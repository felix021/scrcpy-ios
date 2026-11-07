# 构建与签名

## 环境与依赖

需要 macOS、Xcode、Python 3 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。最低部署目标 iOS / iPadOS 16，Swift 5.9 语言模式；首轮构建使用 Xcode 26.6。

```sh
brew install xcodegen
scripts/build-ios.sh simulator
```

`project.yml` 是工程的唯一来源；修改后重新 `xcodegen generate`，生成的 `.xcodeproj` 不提交。Swift Package 用于核心协议测试和 macOS 探针，不替代完整 iOS 工程。

`prepare-resources.py` 下载并校验：

| 资源 | 版本 / 来源 | SHA-256 |
| --- | --- | --- |
| 官方 scrcpy 服务 | Genymobile / scrcpy 5.0.1 | `764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536` |
| 麦克风服务来源 APK | felix021 / scrcpy-apk 1.0.0 | `f62ce1dce5dc702d6ce70cbe8288024c7face6172208034400003dec9643584f` |
| 从 APK 提取的 classes.dex | 同上；生成只含 DEX 的 JAR | `3c128d4d004364b61ecf1fd71e1e2a10f23480f774857aaac449fd10ec89c851` |

Android JAR 只上传到被控 Android，由 Android 的 `app_process` 加载，不在 iOS 中执行。资源校验失败会中止；不要跳过哈希校验。

## 设备构建

```sh
scripts/build-ios.sh device
```

产物为 `build/Scrcpy.xcarchive` 和 `build/Scrcpy-unsigned.ipa`。**未签名 IPA 不能直接安装**。使用自己的 Apple 开发者账号、证书和与包名匹配的 provisioning profile 签名；包名默认 `cn.felix021.scrcpy.ios`，可在本地修改 `project.yml`。

也可用 Xcode 打开生成工程，在 Signing & Capabilities 设置自己的 Team，选择已授权设备运行。不要沿用其他项目的 provisioning profile；App ID 与签名权限需匹配。

证书、私钥、描述文件、账号和本机 SSH / 设备信息放私有配置中，不写进工程或文档。工程不内置 Team ID，也不自动上传 App Store Connect。准备 TestFlight / App Store 时另行配置签名、隐私说明、商店信息和审核资料。

## 远程 Mac

可把源码同步到专用构建目录，再通过 SSH 执行上述脚本。排除 `.git`、`.build`、`build`、生成工程；不要覆盖其他项目目录。SSH 别名、路径和模拟器 UUID 由个人配置提供。

跨机器 UI 测试的 ADB 隧道由 `scripts/test-remote.py` 管理。它关闭 SSH 连接复用，确保隧道与测试使用相同生命周期；所有路径和主机名通过参数传入，详见 [验证](testing.md)。
