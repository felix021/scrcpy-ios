# App Store 上架准备

正式版本 **1.0.0 (5)**，iPhone / iPad 通用，一次购买 **US$0.99**，无订阅或 App 内购买。源码继续使用 GPL-3.0；App 条目已创建，中英文资料和截图、定价、初始销售地区已写入。2026-11-12 已核对状态为 `READY_FOR_SALE`，[App Store](https://apps.apple.com/app/id6832577723) 正式在售。

## 当前完成项

- Bundle ID 为 `cn.oh-my-term.scrcpy`；App ID、App Store profile 和签名证书必须归属项目指定的 Apple 开发者团队。描述文件与账号信息仅保存在私有配置。
- TLS / SPAKE2 / AES-GCM 包装改为直接基于 Apache-2.0 AOSP adb 的 C++ 实现，移除 ADBClient-iOS 改编的 C 文件；完整来源和改编范围见 [第三方声明](../THIRD_PARTY_NOTICES.md)。项目整体仍为 GPL-3.0。Android v1.0.0 的麦克风 DEX 保持固定版本和旧入口，不随主应用包名改变。
- `Resources/PrivacyInfo.xcprivacy` 声明不跟踪、不收集数据；UserDefaults 只存本 App 的语言和本机名称，使用 `CA92.1` 原因。没有使用 App Group 或读取其他 App 偏好。客户端本地配置和会话处理见 [隐私政策](https://scrcpy.oh-my-term.cn/privacy.html)。
- 随包有 BoringSSL，真实使用标准 TLS / ADB 配对加密，不能填成只使用 Apple 系统加密。当前发行不含法国，按 Apple 对标准算法、无需上传材料的说明，`ITSAppUsesNonExemptEncryption` 为 `false`；该字段不表示没有加密。增加法国或改变算法前必须重新核对声明。
- [中英文商店草稿](../appstore/README.md)、网站、支持和隐私 URL 已准备。审核备注明确 Android 硬件依赖、开发者选项与授权、二维码方向，以及 Android JAR 仅在 Android 执行。
- build 5 已通过 Apple 上传校验，服务端状态 `VALID`，已关联 iOS 1.0.0 正式版本，并保存中英文测试说明。中英文商店 / TestFlight 文案、16 张截图、US$0.99、Utilities / Productivity 和 4+ 已写入；初始销售范围 173 个地区，暂不含中国大陆与法国，关闭自动增加地区。正式版本使用手动发布。
- 使用 Xcode 26.6；最低 iOS 16。13 项核心测试通过，真实 Android 错误配对码拒绝、正确配对码和 TLS 视频探针通过；iPhone / iPad 的配对 UI 回归以及中英文截图采集均通过，16 张截图与最终包证据留在私有构建目录。

## 账号与 App 条目

注册、创建描述文件、签名与上传前，先从本项目私有配置读取预期 Team ID，并核对 API 凭据可见的已知 App / Bundle ID 所属团队。网页的 Apple Developer 与 App Store Connect 也须选择同一账号 / 团队。参考项目的构建机器与账号可以不同，不能因复用了构建环境就沿用其凭据。

确认团队后再注册本项目的 App ID、创建描述文件。Bundle ID 已注册时，应在「新建 App」的下拉菜单选择它；不要重复进入「注册 App ID」。如果网页与 API 显示不一致，先核对团队与权限，不能直接归因为包名格式或网页缓存。

本项目的 App 条目已由所有者创建。公开 API 不支持 `apps` 的 `CREATE`；以后创建其他 App 时，先确认团队，再在 App Store Connect 点击「＋ → 新建 App」。注册 Bundle ID 不会自动生成 App 条目。仅选择实际支持的平台；如果还创建了 tvOS，App 级隐私资料会额外要求 `privacyPolicyText`，需要填入各语言的完整政策正文，只有 URL 不够。当前资料：

| 字段 | 当前准备值 |
| --- | --- |
| 平台 | iOS |
| 名称 | Remote · scrcpy |
| 主语言 | English (U.S.) |
| Bundle ID | cn.oh-my-term.scrcpy |
| SKU | MOTENG-SCRCPY-IOS |

使用已创建 App 的数字 ID 继续上传构建、应用中英文元数据、设置 US$0.99 和销售范围，并配置 TestFlight。名称和地区仍可按产品决定调整；不要把旧 Bundle ID 的 App 或签名配置套到新包。

## 正式签名与上传

使用自己的 Distribution 证书和新 ID 对应的 `IOS_APP_STORE` 描述文件：

```sh
scripts/build-ios.sh device
python3 scripts/sign-ios.py \
  --team-id "$APPLE_TEAM_ID" \
  --distribution app-store \
  --input build/Scrcpy-unsigned.ipa \
  --profile /private/path/scrcpy-appstore.mobileprovision \
  --signer /private/path/distribution-signer.pem \
  --output build/Scrcpy-AppStore.ipa
```

`APPLE_TEAM_ID` 从已确认的项目私有配置读取；脚本强制要求该参数，并拒绝其他团队的描述文件。App Store profile 不包含个人设备列表，不能当作 Ad Hoc 包安装。脚本还校验包名、证书、有效期与分发类型，并保留 TestFlight 的 `beta-reports-active` 权限。签名后在 Mac 用 `codesign --verify --deep --strict` 检查，再通过 Apple 上传工具验证；本地签名验证不等于 App Store 服务端已经接受。Ad Hoc 默认模式保留，详见 [构建与签名](building.md)。

## 加密、销售与隐私

当前加密仅实现公开的 ADB 连接和配对：TLS 1.3、RSA、SPAKE2、HKDF-SHA256、AES-128-GCM，不提供用户可定制的密码算法。Apple 的材料表规定：随包标准算法在法国销售时需要法国材料；未在法国销售时不需要上传这类材料。Apple 对 `ITSAppUsesNonExemptEncryption` 的定义包含「无需提供合规材料的加密」，因此当前不含法国的发行使用 `false`。这不等于仅用系统加密，也不等于开源自动豁免；美国年度自分类报告等独立义务仍需账号所有者按实际情况核对。

最初 build 4 错把随包加密直接判断为 `true`，Apple 上传返回 `90592`：缺少对应合规编号。API 也明确拒绝为「无私有算法、随包标准算法、不在法国销售」创建材料声明。build 5 根据官方字段定义修正；签名脚本遇到 `true` 却缺少 Apple 签发的 `ITSEncryptionExportComplianceCode` 时会提前中止，不产生待上传签名包。不得编造编号，也不得为获取编号谎报算法或法国销售范围。

若后续需要法国或采用私有算法，先更新销售计划和材料，取得 Apple 编号后再启用 `true`；不要直接复用当前发行标记。

隐私标签草稿为「不收集数据」：无账号、广告、分析 SDK 或开发者中转，画面、声音、输入及自愿开启的麦克风只在用户设备间实时传输。按实际功能完成并发布 App 隐私问卷与年龄分级。付费协议、税务、收款、欧盟商家身份等账号声明由账号所有者核对，不自动代签。

## 审核与发布

使用实际 App 截图和演示。iPhone / iPad 截图尺寸以当前 Apple 规范为准，必须是不透明 PNG / JPEG；截图与录屏不携带个人主机、密钥或设备信息。审核联系人和演示访问资料放私有配置，不在公开仓库保存个人电话或登录信息。

审核说明要让评审能重复操作：需要有权控制的 Android，开启开发者选项与无线调试；iOS 展示 QR，由 Android 扫描，也可使用配对码。没有 App 账号或订阅。屏幕为通用整机镜像，不提供远端 App 商店或云端应用目录；是否接受仍由 Apple 审核判断。

正式构建可在处理完成后关联；提交审核前完成 TestFlight 与真机检查。模拟器结果不等于覆盖所有 Android 厂商、iPhone / iPad 麦克风与扬声器。商店规则、版本、价格、截图和许可都应对应最终上传的源码及二进制。

## 隐私发布与账号资料

公开 OpenAPI 当前没有发布 App Privacy 问卷的端点，API Key 只能处理隐私政策 URL 等已支持字段。可以在 App Store Connect 的「App 隐私」中选择「不收集数据」并发布；也可以用 [fastlane 的隐私上传功能](https://docs.fastlane.tools/uploading-app-privacy-details/)自动上传和发布。后者使用 Apple ID 登录会话，可能需要双重认证，不能直接复用 App Store Connect API Key。没有可用登录会话时，先完成登录或由所有者在网页发布，不能据此断言隐私标签无法自动化。

本次所有者已在网页完成隐私选择，并确认付费协议、税务与收款信息；正式与 TestFlight 审核联系人已按所有者确认设置。补齐两种语言的政策正文后，Apple 已接受 iOS 1.0.0 (5) 提审，当前已正式发布。

声明需对应本项目实际设备直连、无开发者收集的实现；只有隐私政策 URL 和随包隐私清单，不能代表商店标签已经发布。审核联系人需使用所有者确认的真实资料，不能从其他项目未经核对地套用。付费协议、税务、收款、地区材料与最终审核状态仍由账号所有者在网页核对。

## 官方资料

- [审核规则](https://developer.apple.com/app-store/review/guidelines/)：2.1、2.5.2、4.2.7、5.1.1。
- [隐私 API 原因](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。
- [加密声明字段与材料豁免](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)。
- [加密出口材料](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)。
- [截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)。
- [价格计划 API](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-apppriceschedules) 与 [审核提交 API](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-reviewsubmissions)。
