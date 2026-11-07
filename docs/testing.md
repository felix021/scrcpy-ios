# 验证

## 基础检查

在 Mac 运行 `xcrun swift test`。覆盖 ADB 包校验、触摸布局、组合键释放、文字字节上限、Annex B 拆分、字符键码、配置兼容默认值及 Android RSA 公钥 / 签名。

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

先把当前源码和生成资源同步到 Mac 并执行 `xcodegen generate`。脚本在前台保持独立 SSH 连接，预检端口，测试结束后只关闭自己的隧道。可加 `--codec h265 --audio` 验证 HEVC 与原生声音播放路径。默认只测真实连接；`--only ScrcpyUITests` 运行整个 UI 套件。

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
- 原生 AAC 探针 12 秒解码 582 个 buffer、595,968 个采样帧，声音非零；Android 录音检测到 997 Hz 注入分量，断开后恢复静音基线。
- Release 设备 archive 和未签名 IPA 构建通过。

上述结果不代表 iPhone 真机录音 / 扬声器 / 蓝牙、所有 iPad 尺寸、所有 Android 厂商或 App Store 审核已通过。后续验证记录应与实际测过的功能一致；失败截图和原始日志保存在私有临时目录，不提交整个结果包。
