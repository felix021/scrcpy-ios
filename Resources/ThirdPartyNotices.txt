# Third-party notices

## BoringSSL

The app statically links BoringSSL, pinned to commit
`0131ae9d78e42fcc2c1811315e62410ad96d8230` from
https://github.com/google/boringssl. Its Apache-2.0 license is included in
`Resources/BoringSSL-LICENSE.txt`. The source archive SHA-256 is checked by
`scripts/prepare-crypto.py`; generated sources and libraries stay under `build/`.

## Android Open Source Project (AOSP)

The ADB TLS certificate, exporter, SPAKE2 identity and AES-GCM record operations
in `Sources/AdbCrypto/AdbCrypto.cpp` are ported from Apache-2.0 AOSP adb at
`android-14.0.0_r1`:

- `crypto/x509_generator.cpp` and `tls/tls_connection.cpp` (Copyright 2019 AOSP)
- `pairing_auth/pairing_auth.cpp` and `pairing_auth/aes_128_gcm.cpp` (Copyright 2020 AOSP)

Source: https://android.googlesource.com/platform/packages/modules/adb/+/refs/tags/android-14.0.0_r1/

This port replaces AOSP's Android-specific sockets/logging with a nonblocking
memory-BIO C interface for Swift. It retains protocol constants, little-endian
nonces and the original copyright notices. The Apache-2.0 license is bundled in
`Resources/AOSP-LICENSE.txt`. The earlier ADBClient-iOS-derived C bridge has been
removed from the build; its provenance remains in Git history.

## Android components

Official scrcpy-server: Apache-2.0, version 5.0.1, see
`Resources/scrcpy-LICENSE.txt`. The microphone service is from scrcpy-apk 1.0.0
(GPL-3.0) and also carries the adblib BSD notice. Corresponding source URLs are
included in `Resources/CorrespondingSource.txt`.
