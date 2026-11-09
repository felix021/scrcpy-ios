# App Review notes

Remote · scrcpy is a generic full-device screen-mirroring and control client for an Android device owned or authorized by the user. It is not a cloud-hosted app catalog, a game-streaming service or an alternative app marketplace.

## Hardware and setup

An Android device with ADB debugging enabled is required. Android 11 or later with Wireless debugging is recommended. No app account, subscription or demo login is required.

1. Connect the iPhone/iPad and Android to the same local network. On Android, enable Developer options → Wireless debugging.
2. In this iOS app, tap “Pair wireless debugging”. Either scan the QR displayed by iOS using Android’s Wireless debugging → Pair device with QR code, or enter the pairing address, port and six-digit code shown in Android’s “Pair device with pairing code” dialog.
3. After pairing, use the discovered connection port. The connection port differs from the temporary pairing port. Grant iOS Local Network permission.
4. Tap Connect. The app shows the complete Android screen. Touch, Back/Home/Recents and the full keyboard control the authorized Android device.
5. The gear opens runtime settings. Audio playback and microphone forwarding can be enabled independently. Microphone forwarding is off by default and requests permission only when enabled. Audio availability depends on Android version, hardware and capture policies.
6. Rotate the client, or use Rotate left/right in runtime settings. Disconnect requires confirmation.

## Implementation and data

The iOS app uses native SwiftUI, VideoToolbox, AVAudioEngine and a direct ADB connection. It does not execute downloaded Android code on iOS. The bundled, version-pinned scrcpy server and microphone DEX are transferred to the authorized Android device and execute only there under Android’s ADB environment. They are not installed as persistent Android apps. Only this session’s processes and temporary resources are cleaned up.

Screen video, audio, input and optional microphone data travel between the user’s devices. There is no developer relay, analytics service or advertising SDK. Connection preferences are stored locally; the ADB identity is kept in the device-only Keychain. The connection ends when this app moves to the background.

The app contains BoringSSL for TLS 1.3 and the public ADB SPAKE2 pairing protocol. Cryptography and export declarations must match the selected territories and the final uploaded build.

Support: https://scrcpy.oh-my-term.cn/support.html
Privacy: https://scrcpy.oh-my-term.cn/privacy.html
Source: https://github.com/moteng-network/scrcpy-ios

Before submission, attach the final demonstration video or provide its private review URL. Do not invent a test host or credentials. If reviewers need additional hardware access, respond through App Review with the actual available setup.
