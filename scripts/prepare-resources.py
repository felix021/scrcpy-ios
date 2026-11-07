#!/usr/bin/env python3
"""Fetch pinned Android-side services; never copy local configuration into the app."""
import hashlib
import io
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / 'Resources'
RESOURCES.mkdir(exist_ok=True)

def fetch(url, expected, destination=None):
    if destination and destination.is_file():
        data = destination.read_bytes()
        if hashlib.sha256(data).hexdigest() == expected:
            return data
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != expected:
        raise SystemExit('Service download SHA-256 mismatch')
    if destination:
        temporary = destination.with_suffix(destination.suffix + '.download')
        temporary.write_bytes(data)
        temporary.replace(destination)
    return data

fetch('https://github.com/Genymobile/scrcpy/releases/download/v5.0.1/scrcpy-server-v5.0.1',
      '764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536', RESOURCES / 'scrcpy-server.jar')
mic = RESOURCES / 'microphone-server.jar'
# A DEX-only archive is loaded by the remote Android shell, never executed on iOS.
dex_sha256 = "3c128d4d004364b61ecf1fd71e1e2a10f23480f774857aaac449fd10ec89c851"
def valid_microphone():
    try:
        with zipfile.ZipFile(mic) as archive:
            return archive.namelist() == ["classes.dex"] and hashlib.sha256(archive.read("classes.dex")).hexdigest() == dex_sha256
    except (OSError, zipfile.BadZipFile, KeyError):
        return False

if not valid_microphone():
    apk = fetch('https://github.com/felix021/scrcpy-apk/releases/download/v1.0.0/scrcpy-apk-1.0.0.apk',
                'f62ce1dce5dc702d6ce70cbe8288024c7face6172208034400003dec9643584f')
    with zipfile.ZipFile(io.BytesIO(apk)) as source:
        dex = source.read('classes.dex')
    if hashlib.sha256(dex).hexdigest() != dex_sha256:
        raise SystemExit('Microphone DEX SHA-256 mismatch')
    temporary = mic.with_suffix('.download')
    with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED) as output:
        output.writestr(zipfile.ZipInfo('classes.dex', date_time=(2026, 1, 1, 0, 0, 0)), dex)
    temporary.replace(mic)
print('Android services ready; binary resources remain ignored by Git.')
