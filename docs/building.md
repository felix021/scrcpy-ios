# 构建与签名

## 环境与依赖

需要 macOS、Xcode、Python 3、CMake 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。最低部署目标 iOS / iPadOS 16，Swift 5.9 语言模式；首轮构建使用 Xcode 26.6。

```sh
brew install xcodegen cmake
scripts/build-ios.sh simulator
```

脚本还会下载并校验固定版本 BoringSSL 源码，按 macOS、iOS 设备、iOS 模拟器分别生成静态库。产物全部位于 `build/boringssl/`；源码版本和 SHA-256 见 `scripts/prepare-crypto.py`。当前模拟器库和模拟器构建脚本面向 Apple Silicon（arm64），Intel Mac 可扩展构建脚本的架构参数。单独运行 Swift Package 测试前先执行 `scripts/build-crypto.sh macosx`。

构建与远程 UI 测试会持有同一个文件锁，串行执行工程生成和 Xcode 操作，避免同一目录同时生成 `.xcodeproj` 导致拷贝冲突；不同任务需要并行时应使用各自构建目录。

`project.yml` 是工程的唯一来源；修改后重新 `xcodegen generate`，生成的 `.xcodeproj` 不提交。Swift Package 用于核心协议测试和 macOS 探针，不替代完整 iOS 工程。

`prepare-resources.py` 下载并校验：

| 资源 | 版本 / 来源 | SHA-256 |
| --- | --- | --- |
| 官方 scrcpy 服务 | Genymobile / scrcpy 5.0.1 | `764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536` |
| 麦克风服务来源 APK | moteng-network / scrcpy-apk 1.0.0 | `f62ce1dce5dc702d6ce70cbe8288024c7face6172208034400003dec9643584f` |
| 从 APK 提取的 classes.dex | 同上；生成只含 DEX 的 JAR | `3c128d4d004364b61ecf1fd71e1e2a10f23480f774857aaac449fd10ec89c851` |

麦克风资源仍固定为 Android v1.0.0 的 DEX，入口是 `cn.felix021.scrcpy.MicServer`；Android 主应用的新包名不改变这份历史资源。切换到新版本 DEX 时必须一起修改资源版本、哈希和入口类名。

Android JAR 只上传到被控 Android，由 Android 的 `app_process` 加载，不在 iOS 中执行。资源校验失败会中止；不要跳过哈希校验。

## 设备构建

```sh
scripts/build-ios.sh device
```

产物为 `build/Scrcpy.xcarchive` 和 `build/Scrcpy-unsigned.ipa`。**未签名 IPA 不能直接安装**。使用自己的 Apple 开发者账号、证书和与包名匹配的 provisioning profile 签名；包名默认 `cn.oh-my-term.scrcpy`，可在本地修改 `project.yml`。

Bundle ID 已从早期开发版的 `cn.felix021.scrcpy.ios` 调整为 `cn.oh-my-term.scrcpy`。它是独立的应用身份：需要匹配的新 App ID 和描述文件，不能使用旧包的签名配置直接覆盖安装。旧版的连接配置和 Keychain 配对身份不会自动迁移；新包需要重新配置和配对。

也可用 Xcode 打开生成工程，在 Signing & Capabilities 设置自己的 Team，选择已授权设备运行。不要沿用其他项目的 provisioning profile；App ID 与签名权限需匹配。

证书、私钥、描述文件、账号和本机 SSH / 设备信息放私有配置中，不写进工程或文档。工程不内置 Team ID，也不自动上传 App Store Connect。准备 TestFlight / App Store 时另行配置签名、隐私说明、商店信息和审核资料。

## 为已注册设备签名（Ad Hoc）

与构建分开执行，Linux 或 macOS 均可。安装 [apple-codesign](https://github.com/indygreg/apple-platform-rs) 提供的 `rcodesign`；另需 OpenSSL。

先在 Apple 开发者账号中注册目标设备，为本项目包名创建独立的 Ad Hoc 描述文件，选择该设备和已有的有效 Distribution 证书。其他 App 的描述文件不能直接复用。

```sh
python3 scripts/sign-ios.py \
  --input build/Scrcpy-unsigned.ipa \
  --profile /private/path/scrcpy-adhoc.mobileprovision \
  --signer /private/path/distribution-signer.pem \
  --device <target-device-udid> \
  --output build/Scrcpy-adhoc.ipa
```

脚本在签名前检查描述文件有效期、包名、证书及目标设备，写入描述文件和 Keychain 权限，并递归签名内嵌框架。`--device` 建议始终传入，避免生成不包含目标设备的包。输出带 SHA-256，可再在 Mac 上解包并用 `codesign --verify --deep --strict Payload/Scrcpy.app` 校验。

签名 IPA 只供描述文件内的设备安装，不是 TestFlight / App Store 包。描述文件含设备标识，签名包应通过私有下载渠道提供，不上传公开 Release。设备信息、描述文件和密钥路径保存在私有配置仓库；不在公开源码写死账号、证书或 UDID。

## 远程 Mac

可把源码同步到专用构建目录，再通过 SSH 执行上述脚本。排除 `.git`、`.build`、`build`、生成工程；不要覆盖其他项目目录。SSH 别名、路径和模拟器 UUID 由个人配置提供。

跨机器 UI 测试的 ADB 隧道由 `scripts/test-remote.py` 管理。它关闭 SSH 连接复用，确保隧道与测试使用相同生命周期；所有路径和主机名通过参数传入，详见 [验证](testing.md)。
