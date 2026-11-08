# scrcpy-ios 协作入口

本项目是 iPhone / iPad 控制 Android 的原生客户端，GPL-3.0。先看 [README](README.md) 和 [文档索引](docs/README.md)。

## 目录与职责

- `Sources/AdbCrypto/`：BoringSSL 内存 BIO、SPAKE2 / AES-GCM 包装；来源与许可见 `THIRD_PARTY_NOTICES.md`，生成库和下载源码只放 `build/`。
- `Sources/Core/`：ADB 身份、连接与流复用、scrcpy 协议、远端服务生命周期、声音解码；同时用于 macOS 协议探针。
- `Sources/App/`：SwiftUI 配置与远控界面、VideoToolbox 视频、AVAudioEngine 声音、触摸与键盘。
- `Sources/Probe/`：macOS 命令行端到端探针，只操作明确指定的测试 Android。
- `Tests/CoreTests/`、`Tests/UITests/`：协议边界和界面验收。
- `Resources/`：许可文本与下载后生成的 Android 服务；JAR 不进 Git。
- `project.yml`、`Package.swift`、`scripts/`：工程生成、构建、Ad Hoc 签名与验证。生成的 Xcode 工程不进 Git。
- `docs/`：分主题说明；本机配置、SSH 别名、设备编号和签名只放私有配置仓库。

## 修改规则

1. 开始代码修改前创建或切换到专用 worktree，保留其他任务的修改。
2. 不把凭据、个人设备信息、局域网地址、签名证书、构建产物和临时文件提交到源码；不添加 AI coauthor。
3. 只操作明确属于本任务的模拟器或授权真机。测试隧道使用独立 SSH 连接，并在 `finally` 清理；不依赖共享 SSH master 的存活时间。
4. 修改输入协议时核对字节布局、修饰键按下/释放顺序与大小限制；断开、旋转、隐藏键盘时释放触点和修饰键。
5. 网络与编解码在后台执行；UI 更新在主线程。远端进程、文件都带会话标识，禁止全局 `pkill` 或清理其他会话。
6. 用户启用前不申请录音或转发麦克风；仅观看禁止输入、麦克风和方向控制。恢复本会话改过的远端设置。
7. 服务版本、下载 URL、SHA-256 和对应源码一起更新。任何能力的验收结论必须说明实际测试环境，不把模拟器结果等同于真机通过。
8. 配对密码只驻留当前页面；手工取消须终止网络 I/O。二维码必须使用 Android Studio 的 `WIFI:T:ADB` 方向（iOS 展示、Android 扫码），不能把普通扫码页面当作 ADB 配对。
9. 按改动运行相关检查，见 [验证](docs/testing.md)；改功能同步更新相关文档，中英文 README 互相链接。
