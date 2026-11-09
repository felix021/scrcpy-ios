# App Store 上架准备

当前计划为一次购买 **US$0.99**，iPhone / iPad 通用，暂无订阅或 App 内购买。源码继续使用 GPL-3.0。以下是准备清单，不代表已提交审核或已经上架。

## 已有基础

- 原生 SwiftUI 客户端，最低 iOS 16；构建环境使用 Xcode 26.6，符合 Apple 自 2026-04-28 起要求 iOS 上传包使用 iOS 26 SDK 或更高版本的要求。
- 新 Bundle ID：`cn.oh-my-term.scrcpy`。旧开发包的描述文件不能复用；需要独立 App ID 和 App Store 分发描述文件。
- 中英文项目主页、隐私政策与支持页见 [网站发布](publishing.md)。应用设置中可打开隐私政策和源码。
- 没有账号、广告或分析服务；本机麦克风转发默认关闭。隐私标签仍需按最终包的实际行为在 App Store Connect 中填写。

## 提交前必须解决

1. **第三方 GPL 代码与商店分发条件。** `Sources/AdbCrypto/AdbCrypto.c` 的部分证书 / 配对包装来自 GPL-3.0 的 ADBClient-iOS，固定版本见 [第三方声明](../THIRD_PARTY_NOTICES.md)。项目作者可以为自己拥有版权的代码给出额外分发许可，但不能代替第三方授权。应先取得上游许可，或基于 AOSP / BoringSSL 的原始接口独立实现这层包装，再确认 App Store 分发条件。仅将自己的项目标为 GPL-3.0 不能消除第三方代码的许可问题。
2. **隐私清单。** 补全 `PrivacyInfo.xcprivacy`，检查 UserDefaults 等需要声明使用理由的 API，并按最终包验证隐私报告；网页政策不能替代此清单。
3. **加密出口申报。** App 使用自己打包的 BoringSSL 实现 TLS / 配对，不限于系统提供的加密。当前 `ITSAppUsesNonExemptEncryption=false` 需根据 Apple 问卷和实际销售地区重新核实，不能直接沿用早期开发配置。是否在法国等地区销售可能影响所需材料。
4. **签名和真机检查。** 新 App ID、分发签名和描述文件匹配；验证 iPhone / iPad 真机的麦克风、扬声器、旋转与无线配对。现有模拟器通过不等于覆盖所有真机。

## 商店与审核资料

在 App Store Connect 创建 App 记录，设置名称、SKU、主语言、销售地区与基础价格。以美元设置 0.99 后，其他地区由商店价格体系换算，并非每个地区都收取同一个数值。付费协议、税务及收款资料需由账号所有者确认。

准备中英文描述、关键词、支持及隐私 URL、iPhone / iPad 实际截图、年龄分级、内容权利、隐私标签与审核联系方式。不要将个人测试设备信息放进公开文档。

审核备注应明确：本 App 控制用户授权的 Android 实体设备；需要开启开发者选项、无线调试和 ADB 授权；二维码由 iOS 展示、Android 扫描。提供可复现步骤和演示视频，必要时按审核团队要求提供硬件访问方式。被控端 JAR 仅在 Android 上执行，iOS 本机不执行下载的 Android 代码。审核规则对通用屏幕镜像的处理需结合实际功能判断，不能承诺必然获批。

先通过 TestFlight 验证商店签名包，再提交正式审核。不要把 Ad Hoc IPA 当作 App Store 包，也不要把含设备标识的 Ad Hoc 包放到公开 Release。

## 自动化范围

App Store Connect API 可用于 Bundle ID、证书 / 描述文件、构建查询、截图与元数据、价格计划及审核提交。部分步骤仍需要账号所有者操作或网页界面，例如首次创建 App 记录、协议与财务确认。实际 API 权限以账号和密钥角色为准。研究参考中的示例价格或账号参数不能直接照用；密钥、JWT 与签名仅存私有配置，不进入源码。

## 官方资料

- [审核规则](https://developer.apple.com/app-store/review/guidelines/)：特别关注 2.1、2.5.2、4.2.7 和 5.1.1。
- [2026 年 SDK 要求](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)。
- [隐私清单](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)。
- [加密出口材料](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)。
- [价格计划 API](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-apppriceschedules) 与 [审核提交 API](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-reviewsubmissions)。
- [上游固定版本的 GPL-3.0 许可证](https://github.com/lionlggnd/ADBClient-iOS/blob/31057ba6defd0d1a7454503e662f49b05ef21c2a/LICENSE)。
