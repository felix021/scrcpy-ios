# scrcpy-ios

[简体中文](README.md) · [Documentation](docs/README.md) · [Android app](https://github.com/felix021/scrcpy-apk)

View and control an Android phone from an iPhone or iPad. Native SwiftUI interface, direct network ADB, and system VideoToolbox decoding; no relay server required.

**0.1.0 development version**, not yet available on the App Store. Requires iOS / iPadOS 16 or later.

- Multiple connection profiles, including host, port, video quality and control options.
- H.264 / H.265 video, touch, multitouch, Back / Home / Recents.
- Six-row QWERTY keyboard: two control rows, three letter/symbol rows, and a bottom row with Space and Enter. Ctrl / Alt / Shift / Win / Fn; swipe up for symbols, down for capitals.
- Inward edge gestures: either side for Back, bottom for Home, top for Quick Settings. Adaptive landscape layout, optional orientation sync and manual rotation.
- Independent remote audio and local microphone switches. Remote playback defaults on; microphone forwarding defaults off.
- Runtime settings, view-only mode, keep-awake, disconnect confirmation, and English / Simplified Chinese with system-language support.

<img src="docs/assets/keyboard.png" width="260" alt="Six-row keyboard">

<img src="docs/assets/landscape.png" width="700" alt="Landscape remote control">

## Connect

1. Enable USB debugging on Android, run `adb tcpip 5555` from a computer, and put both devices on a trusted network where they can reach each other.
2. Enter the Android IP / hostname and ADB port, then tap **Connect device**.
3. Accept the debugging authorization on Android and the local-network permission on iOS.

The app currently uses classic TCP ADB. **Android 11+ wireless-debugging pairing-code / TLS pairing is not implemented.** Direct USB connection from the Android edition is also unavailable on iOS. Audio and microphone support depend on the Android version and vendor; see [usage and limits](docs/usage.md) (Chinese).

## Build

Install Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) on a Mac, then run:

```sh
scripts/build-ios.sh simulator  # Generate project and build simulator app
scripts/build-ios.sh device     # Build an unsigned device IPA
```

The script downloads pinned Android services and verifies SHA-256. Generated JARs, Xcode projects, build outputs and signing materials stay out of Git. Device installation requires your own Apple signing; see [building](docs/building.md) (Chinese).

## License

The client is licensed under [GPL-3.0](LICENSE). The bundled official scrcpy server is Apache-2.0; the microphone service comes from the GPL-3.0 Android app. See [licenses and corresponding source](docs/licensing.md) for versions and notices.
