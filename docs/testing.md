# 验证

## 基础检查

在 Mac 先执行 `scripts/build-crypto.sh macosx`，再运行 `xcrun swift test`。覆盖 ADB 包校验、触摸布局、组合键释放、文字字节上限、Annex B 拆分、字符键码、配置兼容默认值及 Android RSA 公钥 / 签名。

完整 UI 测试：

```sh
SCRCPY_SIMULATOR=<owned-simulator-uuid> scripts/build-ios.sh test
```

没有设置 Android 测试地址时，真实连接测试会跳过；配置与语言测试照常执行。UI 测试会清空**当前安装 App**的测试配置，因此使用专用模拟器。不要在个人日用设备运行重置测试。

## 两端模拟器

Android AVD 与 iOS 模拟器均需明确属于当前任务。Android 开启经典 TCP ADB；若 Mac 无法直达，可先在本机为该 Android 建 `adb forward`，由脚本维护 SSH 反向隧道：

```sh
python3 scripts/test-remote.py \
  --mac <private-ssh-alias> \
  --simulator <owned-simulator-uuid> \
  --adb-port <local-forward-port> \
  --rig code/scrcpy-ios-build \
  --output <temporary-artifacts-directory>
```

先把当前源码和生成资源同步到 Mac。脚本会在构建锁内准备加密库、生成工程并运行测试；同一构建目录的任务依次执行。脚本在前台保持独立 SSH 连接，预检端口，测试结束后只关闭自己的隧道。可加 `--codec h265 --audio` 验证 HEVC 与原生声音播放路径。默认只测真实连接；`--only ScrcpyUITests` 运行整个 UI 套件。

测试验证首个实际解码帧、触摸、虚拟键盘、手动旋转、横屏布局和断开确认。截图和 xcresult 放构建目录；截图以屏幕为范围，避免横屏时 App 局部截图被错误裁切。要确认输入抵达 Android，还需用被控端测试 Activity 的事件日志核对，不能只看 iOS 按钮变色。

## 协议与声音探针

```sh
xcrun swift run scrcpy-probe \
  --host <android-host> --port <adb-port> \
  --server Resources/scrcpy-server.jar \
  --microphone Resources/microphone-server.jar \
  --audio --mic-tone --seconds 12
```

`--mic-tone` 发送合成 997 Hz 测试音，不采集 Mac 真实麦克风。被控端运行可播放 / 录音的测试 Activity，检查录音中 997 Hz 分量；`--audio` 使用与 iOS 相同的 AACDecoder 输出样本数和 RMS。静态画面帧数少属于正常现象。可加 `--codec h265` 或 `--touch` 测试其他路径。

探针使用临时 RSA 身份，Android 可能每次要求授权；App 使用 Keychain 长期身份。测试进程不要在日志中输出私钥或个人配置。

## 首轮实测记录

2026-11-08 的开发验证使用 Xcode 26.6、iOS 26.5 iPhone 模拟器、Android 14 AVD：

- 9 项协议单元测试通过。
- 配置 / 语言 / 删除确认 UI 测试通过。
- H.264 / H.265 真实视频解码、触摸、Fn + Menu 到达 Android、手动旋转与断开恢复通过。
- 左右切入滑动触发远端返回；顶部切入展开 Android 快捷设置，画面方向改变后重新计算测试坐标，底部切入返回桌面。截图和 Android 窗口焦点已核对。
- iOS 原生声音播放路径启用后没有错误提示，运行时音频开关保持开启；真机扬声器仍需试听。
- 原生 AAC 探针 12 秒解码 582 个 buffer、595,968 个采样帧，声音非零；Android 录音检测到 997 Hz 注入分量，断开后恢复静音基线。
- Release 设备 archive 和未签名 IPA 构建通过。

上述结果不代表 iPhone 真机录音 / 扬声器 / 蓝牙、所有 iPad 尺寸、所有 Android 厂商或 App Store 审核已通过。后续验证记录应与实际测过的功能一致；失败截图和原始日志保存在私有临时目录，不提交整个结果包。

## 无线配对与 0.2.0 验证

新增测试包括随机 QR 挑战、不含空白分隔符的完整设备名称，以及 iPhone / iPad 上的按钮最大宽度、滚动提示出现 / 到底消失和配对入口。

真实配对测试使用 `testWirelessPairing`，通过 `TEST_RUNNER_PAIRING_MODE=qr|code` 传给 xcodebuild，配对码放 `TEST_RUNNER_PAIRING_CODE`。Xcode 会去掉环境变量的 `TEST_RUNNER_` 前缀，测试同时兼容两种形式；不能因漏读变量而静默当作验收通过。未设置测试环境时该项明确跳过。

`Tests/Fixtures/AdbPairingFixture.java` 仅用于明确归属的 Android AVD：通过系统 IAdbManager 启动与 Settings 相同的配对服务、查询连接端口和设备名称。每次开始前先取消并等待旧配对线程，Android 的原生配对服务只允许一个会话，不能并行启动。不要在未经授权的真机使用此测试辅助程序。

2026-11-08 本轮结果：11 项单元测试通过；错误配对码会被 Android 拒绝，不会误判为成功；iPhone 与 iPad 布局测试通过；Android 16 AVD 的真实六位配对码、TLS 连接和视频流探针通过。二维码测试解码 iOS 实际显示的 QR 图像，把内容交给 Android 系统 QR 配对入口，通过 Bonjour 测试转发发现服务，完成配对与原生画面解码。配对码界面另验证 H.265 和远端音频开关保持开启。AVD 的软件 HEVC 编码器会报告限制并降低分辨率，该提示保留在界面中，iOS 对恢复后的实际视频正常解码。Android 配对列表已核对完整名称 `My_iPad_Client`。最后完整 UI 回归为 3 项通过、1 项无线配对测试因未提供配对环境明确跳过；配对码和二维码另分别运行通过。

跨机器时 AVD 的 mDNS 不会直接穿过 SSH 隧道，因此测试用临时 Bonjour 代理发布其转发端口。代理与隧道随测试进程清理，生产 App 仍直接发现并连接 Android。该验证覆盖二维码内容与完整协议链路，未使用实体 Android 摄像头扫码。

## 1.0.0 上架准备

加密桥接改为基于固定 Apache-2.0 AOSP 版本的 C++17 实现后，13 项核心测试通过，其中两项专门检查无效 DER、非阻塞 TLS ClientHello、未认证时拒绝加密与无效 SPAKE2 消息。真实 Android 16 AVD 的错误配对码被拒绝，正确配对码完成 TLS 视频探针；iPad 13 英寸的实际 QR 解码 / 系统配对 / 视频 UI 链路与 iPhone 大屏的配对码 UI 链路分别通过。

设备 Archive、App Store 签名、Mac `codesign --verify --deep --strict` 和隐私清单语法通过；最终包检查了 Bundle ID、1.0.0 / build 4、加密标记、两种语言目的字符串，以及根目录与随包第三方声明一致性。本地验证不能替代 Apple 上传后的服务端处理。

签名的团队边界另用以下检查验证：

```sh
python3 -m unittest discover -s Tests/SigningTests -v
```

三项测试覆盖其他团队、团队权限不一致和缺少团队的 profile，均在读取 signer 或解包 IPA 前拒绝。另两项测试覆盖非豁免加密缺少 / 空 / 非字符串编号时拒绝，以及编号非空检查、材料豁免和 Ad Hoc 模式的边界；测试不会代替 Apple 核验编号真实性。签名命令必须显式传入私有配置中确认的 `--team-id`。本轮还使用正确账号重新签名，并在 Mac 核对嵌入 profile、App 权限和严格递归签名；错误团队的签名包已隔离，不作为上架候选。

### 可重复的商店截图

`StoreScreenshots/testCaptureProductScreens` 是显式选择的素材采集，不在普通验证中自动连接设备。只在自有模拟器和已授权 Android 上设置以下测试进程环境：

```sh
TEST_RUNNER_STORE_CAPTURE_HOST=<owned-target-host> \
TEST_RUNNER_STORE_CAPTURE_PORT=<forwarded-adb-port> \
TEST_RUNNER_STORE_CAPTURE_LANGUAGE=en \
python3 scripts/with-build-lock.py xcodebuild -project Scrcpy.xcodeproj -scheme Scrcpy \
  -destination 'platform=iOS Simulator,id=<owned-simulator-uuid>' \
  -only-testing:ScrcpyUITests/StoreScreenshots/testCaptureProductScreens \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- test
```

先完成该模拟器的正常配对授权，使用构建锁，并在外层维护独立隧道；没有主机变量时明确跳过。`STORE_CAPTURE_LANGUAGE=zh` 采集中文版。采集配置页面时使用示例地址 `android.local`，真正连接时才使用私有环境地址；发布的远控截图不包含主机地址。

采集连接页、实际远控、完整键盘和运行时设置；用 xcresulttool 导出附件。选用 Apple 接受的 iPhone 大屏与 iPad 13 英寸尺寸，确认 PNG 无 alpha，检查每张图的隐私和实际界面后上传。所有原始截图、录屏和附件清单放私有构建目录，不提交二进制素材。本轮没有重做物理 iPhone / iPad 的完整录音、扬声器和 USB 验收。

本次中英文采集分别在 iPhone 大屏（1320×2868）和 iPad 13 英寸（2064×2752）通过，共 16 张不透明 RGB PNG。素材来自实际 App 和授权 Android AVD，未使用界面示意图替代；是否采用以及最终顺序以商店提交资料为准。

后续 build 5 修正加密材料标记，并重新完成设备 Archive、正确团队签名和 Mac 严格签名 / 权限核验。应用运行时代码未变，使用原先的功能回归与截图证据；不能把签名脚本测试计入 Swift 核心测试数。

build 5 的 Apple 上传工具返回 `UPLOAD SUCCEEDED`，无错误。素材经 App Store Connect 再次查询确认：en-US / zh-Hans，各有 4 张 iPhone 与 4 张 iPad 截图，16 张均为 `COMPLETE`；美国基础定价查询为 USD 0.99，销售范围查询确认法国与中国大陆未启用。上传成功与服务端构建处理、审核通过是不同状态，需分别记录。

Apple 服务端最终将 build 5 标为 `VALID`；已核对其 iOS / 1.0.0 / build 5 和加密标记，关联正式 iOS 版本后再次读取构建关系确认成功，并保存 en-US / zh-Hans 测试说明。尚未邀请测试人员或正式提交审核。
