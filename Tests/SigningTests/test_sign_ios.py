"""A profile from another account must fail before credentials or IPA are read."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    'sign_ios', Path(__file__).resolve().parents[2] / 'scripts' / 'sign-ios.py')
sign_ios = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sign_ios)


class TeamBoundaryTests(unittest.TestCase):
    def assert_rejected(self, profile):
        temporary_root = Path.home() / 'tmp' / 'scrcpy-ios-sign-tests'
        temporary_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temporary_root) as work:
            path = Path(work) / 'profile.mobileprovision'
            path.write_bytes(b'test profile')
            args = SimpleNamespace(profile=path, team_id='AAAAAAAAAA')
            with patch.object(sign_ios, 'run', return_value=plistlib.dumps(profile)) as run:
                with self.assertRaisesRegex(ValueError, 'different Apple developer team'):
                    sign_ios.sign(args)
                # Only decode the profile; do not read a signer, unzip an IPA or sign.
                self.assertEqual(run.call_count, 1)

    def test_other_team_rejected(self):
        self.assert_rejected({
            'TeamIdentifier': ['BBBBBBBBBB'],
            'Entitlements': {'com.apple.developer.team-identifier': 'BBBBBBBBBB'},
        })

    def test_inconsistent_team_entitlement_rejected(self):
        self.assert_rejected({
            'TeamIdentifier': ['AAAAAAAAAA'],
            'Entitlements': {'com.apple.developer.team-identifier': 'BBBBBBBBBB'},
        })

    def test_missing_team_rejected(self):
        self.assert_rejected({})


class ExportComplianceTests(unittest.TestCase):
    def test_non_exempt_store_build_requires_apple_code(self):
        for code in [None, '', '  ', []]:
            with self.subTest(code=code):
                with self.assertRaisesRegex(ValueError, 'Apple-issued'):
                    sign_ios.validate_export_compliance({
                        'ITSAppUsesNonExemptEncryption': True,
                        'ITSEncryptionExportComplianceCode': code,
                    }, 'app-store')

    def test_apple_code_is_required_only_for_declared_non_exempt_store_builds(self):
        sign_ios.validate_export_compliance({'ITSAppUsesNonExemptEncryption': False}, 'app-store')
        sign_ios.validate_export_compliance({}, 'app-store')
        sign_ios.validate_export_compliance({'ITSAppUsesNonExemptEncryption': True}, 'ad-hoc')
        sign_ios.validate_export_compliance({
            'ITSAppUsesNonExemptEncryption': True,
            'ITSEncryptionExportComplianceCode': 'test-apple-issued-code',
        }, 'app-store')


if __name__ == '__main__':
    unittest.main()
