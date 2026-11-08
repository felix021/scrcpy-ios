# 架构与协议

## 数据流

`SwiftUI / CanvasView → AppModel → ScrcpySession → AdbConnection → Android adbd`

视频反向流经 `ScrcpySession → VideoRenderer → VideoToolbox → AVSampleBufferDisplayLayer`；远端声音流经 `AACDecoder → AudioBridge → AVAudioEngine`。麦克风从本机音频引擎采集，转换为 16 kHz 单声道 PCM 后发送给 Android 麦克风服务。

本项目不链接 FFmpeg 或 SDL，不包含 scrcpy-mobile 的代码。无线配对使用固定版本 BoringSSL 提供 TLS 1.3、SPAKE2 和 AES-GCM。C 层使用内存 BIO，Swift 将所有 SSL 操作及输出记录串行执行；网络等待不持有 SSL 锁，因此视频读取不会阻塞控制写入。

网络和协议层也可作为 Swift Package 在 macOS 上运行，使探针与 iOS 客户端复用相同的 ADB、AAC 和会话实现。

## 主要入口

| 文件 | 职责 |
| --- | --- |
| `Sources/Core/AdbIdentity.swift` | Keychain 中的 RSA 2048 身份、Android 公钥格式、AUTH 签名 |
| `Sources/Core/AdbConnection.swift` | NWConnection TCP、握手、校验、逻辑流复用与 ACK 背压 |
| `Sources/Core/ScrcpySession.swift` | 服务上传、视频 / 控制 / 音频 / 麦克风通道、运行时设置 |
| `Sources/Core/RemoteSettings.swift` | 独立 shell 保存并恢复方向 / 唤醒设置，清理会话文件 |
| `Sources/Core/Binary.swift` | 控制消息布局、配置、键码和 Annex B 数据拆分 |
| `Sources/App/AppModel.swift` | 连接状态、配置持久化、权限、UI 回调代际检查 |
| `Sources/App/VideoRenderer.swift` | H.264 / HEVC 参数集、格式变更、原生解码与显示 |
| `Sources/App/AudioBridge.swift` | 播放 / 录音图、AAC 播放、16 kHz PCM 采集 |
| `Sources/App/RemoteCanvas.swift` | 画面缩放坐标、触点、多点与四边手势、硬件键盘 |
| `Sources/App/VirtualKeyboard.swift` | 六行键盘、滑动字符、修饰键、长按重复 |

无线调试配对先通过 TLS 导出 64 字节密钥材料，与配对秘密一起传入 SPAKE2，再交换 AES-GCM 加密的 8192 字节 PeerInfo。本机 RSA Keychain 身份在配对与后续 STLS 中复用。服务发现只浏览声明的 `_adb-tls-pairing._tcp` 和 `_adb-tls-connect._tcp`，二维码只匹配本次随机生成的服务名。

Android 使用自签名服务证书，证书接收规则按 AOSP ADB 实现；Android 端验证本机已配对的 RSA 身份。这里不使用 Web PKI，也不将此验证方式扩展到其他网络请求。

## 会话生命周期

1. 校验配置，加载或生成 ADB 身份，连接并等待 Android 授权。
2. 启动设置 shell，保存原方向与唤醒值；上传固定版本服务。
3. 启动官方 scrcpy 5.0.1，连接视频与控制 socket；音频和麦克风使用独立服务与通道。
4. 读取尺寸、编码参数和视频帧，首个**解码后的像素帧**到达后界面才显示已连接。
5. 运行时切换用独立串行队列与版本号丢弃过期任务；AppModel 用会话 UUID 阻止旧连接更新新界面。
6. 断开先释放触点 / 修饰键、停止音频，再让设置 shell 恢复原值并删去本会话 JAR，最后关闭 ADB。

服务和远端文件使用随机会话标识；不会安装 Android App，不会杀死其他 scrcpy 会话。异常断网也会使 shell 的退出清理生效，但不能保证远端操作系统崩溃时完成恢复。

## 边界与背压

ADB 包最大 1 MiB、视频帧最大 16 MiB、文字最大 64 KiB。流 ACK 随消费推进，视频解码等待异步帧完成，控制队列有上限，麦克风最多排队四段，播放最多排队十二个 buffer。超过实时音频队列容量会丢弃后续音频，防止延迟持续增长。

配置以 JSON 保存在应用 Application Support，原子写入且不参与 iCloud 备份；ADB 私钥独立存 Keychain。配置文件不包含 ADB 私钥。
