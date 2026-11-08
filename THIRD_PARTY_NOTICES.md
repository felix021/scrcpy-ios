# Third-party notices

## BoringSSL

The app statically links BoringSSL, pinned to commit
`0131ae9d78e42fcc2c1811315e62410ad96d8230` from
https://github.com/google/boringssl. Its Apache-2.0 license is included in
`Resources/BoringSSL-LICENSE.txt`. The source archive SHA-256 is checked by
`scripts/prepare-crypto.py`; generated sources and libraries stay under `build/`.

## ADBClient-iOS

The certificate generation and SPAKE2 / HKDF / AES-GCM primitives in
`Sources/AdbCrypto/AdbCrypto.c` are adapted from `AdbNative.c` in
https://github.com/lionlggnd/ADBClient-iOS at commit
`31057ba6defd0d1a7454503e662f49b05ef21c2a` (GPL-3.0, see `LICENSE`).
The implementation here uses memory BIOs and the existing Swift Network transport
instead of that project's sockets and blocking SSL read/write implementation.

## Android components

Official scrcpy-server: Apache-2.0, version 5.0.1, see
`Resources/scrcpy-LICENSE.txt`. The microphone service is from scrcpy-apk 1.0.0
(GPL-3.0) and also carries the adblib BSD notice. Corresponding source URLs are
included in `Resources/CorrespondingSource.txt`.
