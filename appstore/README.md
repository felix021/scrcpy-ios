# 商店资料

这些文件维护商店文案。当前中英文资料与截图已应用到 App Store Connect，首次版本 `1.0.0 (5)` 已提交审核，状态为 `WAITING_FOR_REVIEW`；一次购买 US$0.99，主语言 en-US，附 zh-Hans 本地化。初始销售范围暂不含中国大陆与法国，审核通过后手动发布；后续实际状态以 App Store Connect 为准。

- `metadata/*.json`：商店标题、副标题、推广文本、描述、关键词和公开 URL。
- `review-notes.en.md`：硬件依赖、配对步骤、Android 服务执行位置、数据处理和审核说明。
- 截图、录屏与上传清单保存在私有构建目录，经隐私检查后上传 App Store Connect，不将原始素材放进公开仓库。

字段映射：名称 / 副标题 / privacyPolicyUrl 属于 `appInfoLocalizations`；description / keywords / supportUrl / marketingUrl / promotionalText 属于版本的 `appStoreVersionLocalizations`。分类建议 Utilities，次分类 Productivity。售价使用美国 USD 0.99 基础价格点，其他地区按商店换算。

隐私标签草稿为“不收集数据”，依据是无账号、统计、广告或开发者中转，实时会话数据由用户设备直接处理。App 隐私问卷和当前年龄分级问卷应按实际功能填写并发布，不照抄其他 App。签名、审核联系人、API 凭据和账号信息仅从私有配置读取。

创建 App 条目需要 App Store Connect 网页；公开 API 返回 apps 不支持 CREATE。Bundle ID 注册和描述文件创建可先完成；App 条目创建后才能上传与关联构建、应用元数据、设置价格及 TestFlight。

正式提交前完成 [上架清单](../docs/app-store.md)，确认新签名包、真实使用演示、隐私发布、付费协议 / 税务 / 收款和销售地区。自动化不会代替账号所有者签署协议，也不发布含个人设备标识的 Ad Hoc 包。
