# 开源与分发

## 客户端

本项目选择 [GNU GPL version 3](../LICENSE)。修改、分发与收费遵循许可证条款；分发二进制时也需提供相应源码和许可声明。开源本身不禁止收费，收到 GPL 版本的人也获得许可证赋予的再分发与修改权。

自己拥有版权的原创部分仍可由版权所有者决定其他授权方式；引入他人贡献或第三方代码后，需要分别确认其授权。当前项目统一按 GPL-3.0 维护，不把“收费”解释为“可以省略源码与许可义务”。

新增 TLS / SPAKE2 功能静态链接 Apache-2.0 的 BoringSSL，少量证书与配对原语改编自 GPL-3.0 的 ADBClient-iOS。具体固定版本、改编范围和许可见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)，声明随 App 打包。

## Android 服务与随包声明

| 组件 | 版本 | 许可 / 源码 |
| --- | --- | --- |
| scrcpy-server | 5.0.1 | [Apache-2.0；官方源码](https://github.com/Genymobile/scrcpy/tree/v5.0.1) |
| MicServer | scrcpy-apk 1.0.0 | [GPL-3.0；对应源码](https://github.com/moteng-network/scrcpy-apk/tree/v1.0.0) |
| APK DEX 中未使用的 adblib 类 | 同上 | BSD-3-Clause；随包保留版权和许可 |

`Resources/` 保留 GPL、scrcpy 和 adblib 许可文本及 `CorrespondingSource.txt`。当前麦克风构建复用固定 APK 中的整个 DEX，因此即使 adblib 不会被调用，也保留其声明。服务版本变更时同步更新 URL、哈希、声明和对应源码版本。

图标沿用本项目 Android 版的手机控制图形。iOS 客户端使用系统框架，无 FFmpeg、SDL 或 scrcpy-mobile 代码依赖。

## 商店发布

当前仓库提供开发版源码与构建方式，不表示已获 App Store 审核通过。上架前需核对 GPL 分发义务、Apple 的商店协议、隐私信息及下载后执行代码等相关审核要求；本项目不会自动提交或收费上架。
