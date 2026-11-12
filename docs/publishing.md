# 项目网站与仓库

## 地址与职责

- iOS 源码：<https://github.com/moteng-network/scrcpy-ios>。
- 项目主页：<https://scrcpy.oh-my-term.cn/>；中英文在当前页面切换，不跳转到独立的英文主页。旧 `en/` 地址转到首页，保留查询参数和页内锚点。
- App Store：<https://apps.apple.com/app/id6832577723>；首屏及底部均提供入口。iPhone / iPad 可安装，Apple 芯片 Mac（M1 或更新、macOS 13+）也可直接安装同一 iOS 版。Mac 商店分发已开放，完整功能尚未在 Mac 实机验收，不标为原生 macOS 版或已验证兼容。
- 主页提示中国大陆区 App Store 未上架，购买需使用其他已上架地区的 Apple 账号。Android 下载卡显示 Google Play 正式版审核中，并提供可用的 GitHub APK 下载入口；未公开在售前不把 Google Play 状态做成可下载按钮。
- 隐私政策：<https://scrcpy.oh-my-term.cn/privacy.html>。
- 使用与支持：<https://scrcpy.oh-my-term.cn/support.html>。
- 服务条款：<https://scrcpy.oh-my-term.cn/tos.html>；涵盖设备授权、购买与退款、平台限制和开源许可，不额外限制 GPL 权利，不代替商店协议或排除法定消费者权利。

`site/` 是独立静态站点，`docs/` 仍是开发文档。网站不依赖编译、外部字体、统计脚本或 Cookie；图标直接复用项目的 SVG。页面上的设备是界面示意，明确标注为非截图。App Store 上架前不放虚假的商店下载链接；当前 iOS 状态和计划售价应与实际发布状态一致。

首页、隐私、支持和服务条款共用 `assets/language.js`。各页保持同一个 URL，每次只展示一种语言，切换不重载页面。首次按浏览器语言优先列表选择中文或英文，未匹配时用英文；页头可手动切换，选择仅保存在本地 `scrcpy-site-language`，跨页面沿用，不发送到服务器。兼容读取旧隐私页的 `scrcpy-privacy-language` 选择。标题、description / Open Graph、无障碍标签和页脚同时切换；语言存储不可用时仍可切换，禁用 JavaScript 时显示英文正文并隐藏切换按钮。新增翻译使用 `data-language` 包裹正文，属性翻译沿用页面现有 `data-*` 标记，不另建平行页面或复制布局。

应用「设置 → 关于」提供项目主页入口，隐私政策也使用同一域名。公司官网仍为 `https://oh-my-term.cn/`。

## 发布与检查

仓库 Settings → Pages 选择 GitHub Actions，自定义域名设为 `scrcpy.oh-my-term.cn`，DNS CNAME 指向 `moteng-network.github.io`。自定义 workflow 的域名以仓库 Pages 设置为准，不能只提交 CNAME 文件。主分支的 `site/**` 或 Pages workflow 修改后，由 `.github/workflows/pages.yml` 上传并部署 `site/`；也可手动运行 workflow。权限限定为读取源码、写入 Pages 和获取部署身份。

本地预览：

```sh
python3 -m http.server 8080 --directory site
```

提交前检查中文、英文、隐私和支持页的相对链接；至少查看手机与桌面布局，确认窄屏没有横向溢出，键盘可聚焦链接。不要把构建包、签名材料、测试日志和个人网络信息复制到 `site/`。隐私政策需反映实际行为；新增数据处理或第三方服务时同步更新。当前政策覆盖两端商店购买、授权公钥与本机名称的远端保存、剪贴板 / 目标 App 留存，以及 TLS 与传统 TCP 的加密差异；ADB 私钥不会传输。

语言回归覆盖首页、支持、隐私和条款：中文 / 英文浏览器、其他语言回退、浏览器语言优先列表、键盘切换时焦点和 URL 不变、刷新及跨页沿用选择、旧隐私页偏好、禁用本地存储及禁用 JavaScript。旧 `en/` 的跳转保留查询与锚点。检查每页仅显示一个语言版本，标题、元数据及导航同步，并分别核对 App Store 下载、Google Play 状态和 GitHub APK 入口。部署后从正式域名取回 HTML / CSS / JS，与提交内容对比，不只检查 Actions 成功。

## 仓库迁移

仓库从个人账号转入 `moteng-network` 时沿用 GitHub 的 Transfer 功能，保留提交、标签、Release 和问题记录。旧地址通常会跳转，但本地 `origin`、应用内源码链接和通用文档应改为新地址；不要重新创建同名旧仓库，以免打断跳转。

公司官网由组织首页仓库单独承载，不与 App 源码混合。域名切换前先确认现有源码、网站可用性和 DNS 记录；GitHub 域名验证的 TXT 记录长期保留，网站记录之外的邮件等解析不改。具体域名、旧解析和操作记录放私有部署配置，通用说明不保存账号凭据。

## iOS 应用身份

当前 Bundle ID 为 `cn.oh-my-term.scrcpy`，框架和 UI 测试分别使用 `.core`、`.uitests` 后缀。这个命名只用于 iOS，不改变 Android 的包名及远端麦克风服务类名。旧 Ad Hoc 描述文件不适用于新 ID；安装与配置迁移限制见 [构建与签名](building.md)。
