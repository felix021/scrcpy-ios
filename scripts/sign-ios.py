#!/usr/bin/env python3
"""Sign an Ad Hoc or App Store IPA using external distribution credentials."""
import argparse
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile


def run(*command):
    return subprocess.run(command, check=True, capture_output=True).stdout


def validate_export_compliance(info, distribution):
    if distribution == 'app-store' and info.get('ITSAppUsesNonExemptEncryption') is True:
        code = info.get('ITSEncryptionExportComplianceCode')
        if not isinstance(code, str) or not code.strip():
            raise ValueError('Non-exempt encryption requires an Apple-issued ITSEncryptionExportComplianceCode before App Store upload')


def sign(args):
    profile_bytes = args.profile.read_bytes()
    profile = plistlib.loads(run('openssl', 'cms', '-verify', '-inform', 'DER', '-in', str(args.profile), '-noverify'))
    permitted = profile.get('Entitlements', {})
    if (profile.get('TeamIdentifier') != [args.team_id]
            or permitted.get('com.apple.developer.team-identifier') != args.team_id):
        raise ValueError('Provisioning profile belongs to a different Apple developer team')
    expiry = profile['ExpirationDate'].replace(tzinfo=timezone.utc)
    if expiry <= datetime.now(timezone.utc):
        raise ValueError('Provisioning profile has expired')
    devices = profile.get('ProvisionedDevices', [])
    if permitted.get('get-task-allow') or profile.get('ProvisionsAllDevices'):
        raise ValueError('A distribution profile is required')
    if args.distribution == 'ad-hoc' and not devices:
        raise ValueError('An Ad Hoc distribution profile is required')
    if args.distribution == 'app-store' and devices:
        raise ValueError('An App Store distribution profile must not contain devices')
    if args.device and args.device not in devices:
        raise ValueError('Target device is absent from the provisioning profile')
    certificate = run('openssl', 'x509', '-in', str(args.signer), '-outform', 'DER')
    if certificate not in profile['DeveloperCertificates']:
        raise ValueError('Signer certificate does not match the profile')
    run('openssl', 'x509', '-in', str(args.signer), '-checkend', '0', '-noout')
    temporary_root = Path.home() / 'tmp' / 'scrcpy-ios-sign'
    temporary_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.TemporaryDirectory(dir=temporary_root) as work:
        root = Path(work)
        with zipfile.ZipFile(args.input) as archive:
            for item in archive.infolist():
                destination = (root / item.filename).resolve()
                if not destination.is_relative_to(root) or stat.S_ISLNK(item.external_attr >> 16):
                    raise ValueError('Unsafe input archive entry')
                archive.extract(item, root)
                mode = stat.S_IMODE(item.external_attr >> 16)
                if mode:
                    destination.chmod(mode)
        apps = list((root / 'Payload').glob('*.app'))
        if len(apps) != 1:
            raise ValueError('Expected exactly one app in Payload')
        app = apps[0]
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        validate_export_compliance(info, args.distribution)
        bundle = info['CFBundleIdentifier']
        prefix = profile['ApplicationIdentifierPrefix'][0]
        identifier = prefix + '.' + bundle
        if permitted.get('application-identifier') != identifier:
            raise ValueError('Profile must match the app bundle identifier exactly')
        team = profile['TeamIdentifier'][0]
        entitlements = {
            'application-identifier': identifier,
            'com.apple.developer.team-identifier': team,
            'get-task-allow': False,
            'keychain-access-groups': [identifier],
        }
        if args.distribution == 'app-store' and permitted.get('beta-reports-active'):
            entitlements['beta-reports-active'] = True
        allowed_groups = permitted.get('keychain-access-groups', [])
        if not any(identifier == group or group.endswith('*') and identifier.startswith(group[:-1]) for group in allowed_groups):
            raise ValueError('Profile does not permit the app Keychain group')
        (app / 'embedded.mobileprovision').write_bytes(profile_bytes)
        entitlement_file = root / 'entitlements.plist'
        entitlement_file.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(['rcodesign', 'sign', '--pem-file', str(args.signer), '--entitlements-xml-file', str(entitlement_file), str(app)], check=True)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        # Stage beside the output so an interrupted signing run never leaves a
        # half-written file at the download path.
        with tempfile.NamedTemporaryFile(dir=args.output.parent, suffix='.partial', delete=False) as staged:
            staged_path = Path(staged.name)
        try:
            with zipfile.ZipFile(staged_path, 'w', zipfile.ZIP_DEFLATED) as archive:
                for file in sorted(app.rglob('*')):
                    if file.is_file():
                        archive.write(file, file.relative_to(root))
            staged_path.replace(args.output)
        finally:
            staged_path.unlink(missing_ok=True)
    print(f'Signed {bundle} {info["CFBundleShortVersionString"]} ({info["CFBundleVersion"]})')
    print(f'Profile expires: {expiry.date()}; target device included: {bool(args.device)}')
    print(f'SHA-256: {hashlib.sha256(args.output.read_bytes()).hexdigest()}')
    print(f'IPA: {args.output}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True, help='Unsigned device IPA')
    parser.add_argument('--profile', type=Path, required=True, help='Private .mobileprovision matching the distribution mode')
    parser.add_argument('--signer', type=Path, required=True, help='Private PEM containing distribution certificate and key')
    parser.add_argument('--team-id', required=True, help='Expected Apple developer Team ID from this project’s private configuration')
    parser.add_argument('--distribution', choices=['ad-hoc', 'app-store'], default='ad-hoc')
    parser.add_argument('--device', help='Require this UDID in the profile; keep it in private local configuration')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Z0-9]{10}', args.team_id):
        parser.error('--team-id must contain exactly 10 uppercase letters or digits')
    if args.distribution == 'app-store' and args.device:
        parser.error('--device is only supported for Ad Hoc signing')
    if args.input.resolve() == args.output.resolve():
        parser.error('Input and output must differ')
    if not shutil.which('rcodesign'):
        parser.error('rcodesign is required (apple-codesign)')
    try:
        sign(args)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Signing failed: {error}\n')


if __name__ == '__main__':
    main()
