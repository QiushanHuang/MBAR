# Changelog

## 0.5.0 - 2026-09-26

### Added

- Automatic discovery across app images, compiled `Assets.car` catalogs and Electron ASAR archives, alongside existing verified adapters.
- Per-app icon selection with light/dark previews, original/template rendering, custom PNG/TIFF/JPEG import, recovery to automatic matching and persistent one-step undo.
- User-confirmed native snapshots of currently visible menu icons. Captures carry a timestamp and are invalidated when the target app version changes.
- Bounded background scanning, priority for the app being configured, and finite retries for menu items that appear after application launch.

### Fixed

- Compound names such as `statusicon` and `menubarpinyin` were skipped. Menu-related candidates are now ranked before using the decode budget.
- An outdated negative screen-capture preflight could stop a valid capture request. ScreenCaptureKit now handles actual access for explicit user requests.
- Capture permission failures now offer System Settings, retry and restart actions. Restarting returns to the same icon settings.
- Late discovery results cannot overwrite a newer selection or repopulate an exited application. Changed resource files require revalidation.
- DMG packaging uses macOS 27's `diskutil image create from` command; the deprecated creation path returned `Resource busy` on the release host.

### Behavior and limits

- Only a unique high-confidence candidate is adopted automatically. Ambiguous or incomplete scans remain a user choice.
- Native capture does not reveal hidden items. Empty, faded, clipped or moving targets are rejected.
- All saved images are static, including battery percentages and speed labels. Multiple-item mapping and live status mirroring remain unsupported.
- Resource discovery needs no Screen Recording permission. Optional native capture does; no audio is recorded.

Debug and Release each pass 67 automated tests; one additional live-capture test is skipped unless explicitly requested and was run separately. Installed-app GUI checks confirmed native previews for WeChat and AlDente. See [v0.5.0 notes](docs/releases/v0.5.0.md) for validation and upgrade details.

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

### 0.5.0 - 2026-09-26

#### 新增

- 在现有专用适配之外，自动搜索普通应用图片、`Assets.car` 图像资源库和 Electron ASAR 归档。
- 每应用图标选择：明暗预览、原色/模板显示、自定义 PNG/TIFF/JPEG 导入、恢复自动匹配和持久单步撤销。
- 读取当前可见原生图标，预览确认后保存快照；记录采集时间，目标应用版本变化后要求重新采集。
- 有界后台扫描，优先处理正在配置的应用，并对启动后延迟出现的菜单项目做有限重试。

#### 修复

- 补齐 `statusicon`、`menubarpinyin` 等连写名称，先排序再解码，减少弱候选耗尽名额的情况。
- 旧录屏预检值为否时会直接阻断取图；现在由 ScreenCaptureKit 处理用户主动请求的实际授权。
- 权限失败时提供系统设置、重试和重启入口；重启后返回原图标设置。
- 旧扫描结果不能覆盖新选择或恢复已退出应用；资源变化后重新校验。
- DMG 打包改用 macOS 27 的 `diskutil image create from`；旧创建命令在发行环境报 `Resource busy`。

#### 行为与限制

- 只有唯一高可信候选自动采用；有歧义或扫描不完整时由用户选择。
- 原生采集不会主动展开隐藏项目，空白、淡化、裁切不完整或位置变化的图像会被拒绝。
- 保存内容均为静态图片，包括电量和网速文字；暂不支持多项目逐个映射或实时状态镜像。
- 资源发现无需录屏权限；可选原生采集需要，不录制音频。

Debug 和 Release 各有 67 项自动测试通过；另一个实机采集测试默认跳过，已显式单独运行。安装版 GUI 已确认微信和 AlDente 的原生预览成功。验证与升级说明见 [v0.5.0](docs/releases/v0.5.0.md#中文)。

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
