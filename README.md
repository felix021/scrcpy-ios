# scrcpy-ios

[English](README.en.md) · [项目主页](https://scrcpy.oh-my-term.cn/) · [文档](docs/README.md) · [Android 版](https://github.com/moteng-network/scrcpy-apk)

用 iPhone 或 iPad 查看和控制 Android 手机。原生 SwiftUI 界面，通过网络 ADB 连接；视频使用系统 VideoToolbox 解码，无需中转服务器。

当前正式版本 **1.0.0**，已在 [App Store](https://apps.apple.com/app/id6832577723) 发布，一次购买 **US$0.99**。最低 iOS / iPadOS 16。

Apple 芯片 Mac（M1 或更新、macOS 13+）也可从同一 App Store 入口安装此 iOS 版，按 iPad App 运行；Mac 的完整功能尚未实机验收。安装和购买说明见[支持页面](https://scrcpy.oh-my-term.cn/support.html)。

- Android 11+ 无线调试：二维码 / 6 位配对码，配对后通过 TLS 1.3 加密连接；本机名称可自定义。
- 多主机连接配置，保存主机、端口、画质与控制选项。
- H.264 / H.265 视频、触摸、多点触控、返回 / Home / 最近任务。
- 六行 QWERTY 键盘：两行控制键、三行字母及符号、含空格与回车的底行；支持 Ctrl / Alt / Shift / Win / Fn、上滑符号、下滑大写。
- 边缘滑动：左右返回、底部 Home、顶部控制中心；支持横竖屏布局、可选方向同步和手动旋转。
- 远端系统声音播放与本机麦克风转发分别开关；默认播放远端声音，麦克风默认关闭。
- 运行时设置、仅观看、保持唤醒、断开二次确认，中英文界面跟随系统或手动选择。

<img src="docs/assets/keyboard.png" width="260" alt="Six-row keyboard">

<img src="docs/assets/landscape.png" width="700" alt="Landscape remote control">

## 连接

1. Android 11+ 开启开发者选项中的「无线调试」，App 点击「无线调试配对」：让 Android 扫描 iOS 显示的二维码，或输入 Android 配对弹框的地址、端口和 6 位配对码。两台设备需网络互通；二维码发现需要同一局域网。
2. 配对成功后自动发现连接端口；也可填写 Android 无线调试主页面的连接端口，然后点击「连接设备」。连接端口与配对端口不同。
3. iOS 上允许本地网络访问。在「设置」修改本机名称，可让 Android 的已配对设备列表更容易识别本机。

也支持经典 TCP ADB：用电脑执行 `adb tcpip 5555` 后填写设备地址和端口，首次连接在 Android 允许调试。iOS 版暂不提供 USB 直连。详见 [使用说明](docs/usage.md)。

## 构建

在 Mac 安装 Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)，然后：

```sh
scripts/build-ios.sh simulator  # 生成工程并构建模拟器 App
scripts/build-ios.sh device     # 生成未签名设备 IPA
```

脚本下载固定版本的 Android 服务并校验 SHA-256。JAR、Xcode 工程、构建产物及签名材料均不提交。真机安装需自己的 Apple 签名；已注册设备可用 `scripts/sign-ios.py` 生成 Ad Hoc 签名包，见 [构建与签名](docs/building.md)。

## 许可

客户端使用 [GPL-3.0](LICENSE)。随包的官方 scrcpy 服务为 Apache-2.0，麦克风服务来自 GPL-3.0 的 Android 版；具体版本、许可证和源码见 [开源与分发](docs/licensing.md)。
