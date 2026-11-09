# 项目网站与仓库

## 地址与职责

- iOS 源码：<https://github.com/moteng-network/scrcpy-ios>。
- 项目主页：<https://oh-my-term.cn/scrcpy-ios/>；英文版位于 `en/`，中英文相互链接。
- 隐私政策：<https://oh-my-term.cn/scrcpy-ios/privacy.html>。
- 使用与支持：<https://oh-my-term.cn/scrcpy-ios/support.html>。

`site/` 是独立静态站点，`docs/` 仍是开发文档。网站不依赖编译、外部字体、统计脚本或 Cookie；图标直接复用项目的 SVG。页面上的设备是界面示意，明确标注为非截图。App Store 上架前不放虚假的商店下载链接；当前 iOS 状态和计划售价应与实际发布状态一致。

## 发布与检查

仓库 Settings → Pages 选择 GitHub Actions。主分支的 `site/**` 或 Pages workflow 修改后，由 `.github/workflows/pages.yml` 上传并部署 `site/`；也可手动运行 workflow。权限限定为读取源码、写入 Pages 和获取部署身份。

本地预览：

```sh
python3 -m http.server 8080 --directory site
```

提交前检查中文、英文、隐私和支持页的相对链接；至少查看手机与桌面布局，确认窄屏没有横向溢出，键盘可聚焦链接。不要把构建包、签名材料、测试日志和个人网络信息复制到 `site/`。隐私政策需反映实际行为；新增数据处理或第三方服务时同步更新。

## 仓库迁移

仓库从个人账号转入 `moteng-network` 时沿用 GitHub 的 Transfer 功能，保留提交、标签、Release 和问题记录。旧地址通常会跳转，但本地 `origin`、应用内源码链接和通用文档应改为新地址；不要重新创建同名旧仓库，以免打断跳转。

公司官网由组织首页仓库单独承载，不与 App 源码混合。域名切换前先确认现有源码、网站可用性和 DNS 记录；GitHub 域名验证的 TXT 记录长期保留，网站记录之外的邮件等解析不改。具体域名、旧解析和操作记录放私有部署配置，通用说明不保存账号凭据。

## iOS 应用身份

当前 Bundle ID 为 `cn.oh-my-term.scrcpy`，框架和 UI 测试分别使用 `.core`、`.uitests` 后缀。这个命名只用于 iOS，不改变 Android 的包名及远端麦克风服务类名。旧 Ad Hoc 描述文件不适用于新 ID；安装与配置迁移限制见 [构建与签名](building.md)。
