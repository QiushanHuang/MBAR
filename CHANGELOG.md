# Changelog

## Unreleased

- Discover static menu-icon candidates from application resources and packed Electron ASAR files.
- Automatically use only a unique high-confidence candidate; incomplete scans, competing
  artwork, theme/state variants and unsupported multiple-item apps require explicit handling.
- Add per-app icon settings with light/dark previews, original/template colors, candidate
  selection, custom image import, automatic-matching recovery and persistent one-step undo.
- Revalidate saved resource choices after updates without silently replacing user-selected artwork.
- Keep discovery bounded and asynchronous, prioritize the app being configured, and reject late
  results after application exit or a newer selection. Retry delayed menu-item creation a bounded number of times.
- Add parser, ranking, persistence and lifecycle coverage; 50 tests pass in both debug and release.

These changes are available in `main`; the v0.4.0 downloadable packages are unchanged.

## 0.4.0 — 2026-09-20

First public GitHub distribution of MBAR for macOS 27 on Apple Silicon.

- Compact single-row shelf with original menu-icon resource adapters.
- Per-app Visible, Auto-hide and Always-hide categories.
- Left/right interaction forwarding and an optional shelf lock.
- Show-all recovery, persistent category preferences and experimental native hiding.
- Teal menu-bar/shelf identity shared by the app icon and documentation.
- English and Simplified Chinese documentation in one README, installation guide,
  contributor attribution, source build instructions, DMG/ZIP packaging and SHA-256 checksums.
- Diagnostic version now follows the application bundle metadata.

This is an ad-hoc-signed, unnotarized early release. Private API hiding, static
artwork, limited adapters and physical-display compatibility limits are documented
in the README. Local prototype versions before 0.4.0 were not GitHub releases.

## 中文

### 尚未发行

- 自动搜索应用资源及 Electron ASAR 中的静态菜单图标，只有唯一高可信候选才自动采用。
- 扫描不完整、候选竞争、主题/状态变体或多个菜单项目时，不猜测对应图标。
- 新增每应用图标设置：明暗预览、原色/模板着色、候选选择、自定义图片导入、恢复自动匹配和持久撤销。
- 应用更新后重新校验图标来源；用户选过的图片发生变化时要求重新选择。
- 后台扫描有时间及数量边界，优先处理正在配置的应用；退出或新选择之后的旧结果不能覆盖当前状态。
- 对启动后延迟出现的菜单项目进行有限重试；新增解析、排名、持久化及生命周期测试。
- debug 与 release 下各有 50 项测试通过。

上述变更已进入 `main`，现有 v0.4.0 下载包未变更。

### 0.4.0 — 2026-09-20

首次 GitHub 公开发行，面向 macOS 27 / Apple Silicon。

- 单行下拉栏与原始菜单图标资源适配。
- 常驻、自动隐藏、总是隐藏三种分类。
- 左右键转发、可选锁定按钮、显示全部恢复与分类保存。
- 统一应用与文档 Logo，同页中英文 README、安装操作说明与贡献署名。
- DMG / ZIP 打包、SHA-256 校验，诊断版本改为读取应用包元数据。

发行包为 ad-hoc 签名、未经 Apple 公证的早期版本。
私有隐藏接口、静态图标、适配范围及实机兼容边界见 README。
0.4.0 之前的本地原型并非 GitHub 发行版。
