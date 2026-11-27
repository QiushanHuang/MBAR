# Changelog

## 0.7.7 — 2026-11-27

- The **静透** preset uses the original clear glass in its Settings-focused appearance, including its color transmission and refractive rim. Unlocking the shelf keeps that appearance. All materials share the same outer corners across shelf layouts.

- Choose fixed black, fixed white, system appearance or background-adaptive ink for clear-glass symbols and labels.

- Clear-glass shelf icons and labels share a single glass surface. Automatic foreground ink chooses one color per glyph or label from its background and retains the alpha of fine artwork. Light and dark foreground overrides replace the previous icon backings. Original-color icons keep their artwork.

## 0.7.2 — 2026-11-20

- Clear-glass shelf icons draw the source alpha once, keeping narrow openings and multi-level status indicators visible. Local contrast backgrounds support automatic, light and dark ink treatments in the appearance editor.

## 0.7.1 — 2026-11-20

- Resize shelf app icons from 70% to 150%. At 100%, captured artwork uses its measured point dimensions; artwork without a known native size uses a proportional menu-sized fallback.
- Place the lock and Settings controls on the left or right. The strip, grid and list reserve space for the artwork and keep the controls accessible as items scroll.
- Improved contrast for monochrome and full-color icons on Apple clear glass, including artwork with both light and dark details.

## 0.7.0 — 2026-11-20

- Choose a compact strip, labeled grid or list. Dock the shelf at either side of the display or expand it left, right or centered under its menu-bar entry. Arrow keys navigate items and scroll them into view.
- Choose from seven appearance presets or save your own. **桌面水晶** (Desktop Crystal) combines 35% frosting with 0% tint and native glass refraction at the edges. Frosting, tint and translucent background opacity can be adjusted independently where applicable.
- Optionally refresh visible native icons while the shelf is open. Manual artwork takes priority, and Clash Verge Rev speed text can update when exposed through Accessibility.
- Fixed off-screen placement when the menu-bar entry overflows and icons shifting to the lower left when switching glass materials.

[0.7.0 release notes, upgrade and test details](docs/releases/v0.7.0.md)

## 0.6.0 - 2026-10-28

### Changed

- Reorganized Settings around the app list, clearer visibility choices, a resizable window and contextual help. Permission, error and recovery actions remain visible when needed.
- Simplified icon selection and previews. Rescanning preserves an unsaved choice; closing, undoing or resetting warns before discarding it.
- Added visible keyboard focus and Tab/Shift-Tab navigation across shelf items and controls. Hiding can still be switched off after its last selected app is changed to visible.
- Reconcile menu-bar visibility after startup, wake, display changes and MenuBarAgent replacement; host identity and transition generations prevent stale native work from being treated as current.

Debug and Release each passed 79 tests; one opt-in live capture test was skipped. See [0.6.0 notes](docs/releases/v0.6.0.md) for upgrade details and limits.

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

### 0.7.7 — 2026-11-27

- 「静透玻璃」直接使用原玻璃在设置窗口获得焦点时的材质，解锁后保留相同的透色、磨砂和边缘折射。所有下拉栏材质、布局和外观预览共用同一套外圆角。

- 玻璃前景颜色可选固定黑色、固定白色、跟随系统外观或随背景。

- 苹果液态玻璃上的图标和文字直接显示在同一片玻璃上。每枚图标、每段文字分别按整体背景明暗选色，跨越边界时笔画保持同色，保留细线、镂空与状态读数；也可手选浅色或深色前景。旧的衬底偏好会沿用对应的笔画颜色。

### 0.7.2 — 2026-11-20

- 修正苹果液态玻璃上细线、镂空与半透明图案糊成一团的问题。外观设置中的「图标显示」可以切换自动、浅底深色或深底浅色。

### 0.7.1 — 2026-11-20

- 在设置中将下拉栏应用图标调至 70%–150%，一键恢复 100%。原生快照按实测点尺寸显示，缺少原生尺寸的素材按比例适配。
- 锁定和设置按钮可以一起靠左或靠右；图标放大时，下拉栏会为它们预留空间。
- 改进苹果液态玻璃上单色、双色和彩色图标的对比度。

### 0.7.0 — 2026-11-20

- 新增网格和列表布局，可贴屏幕两侧停靠，或在菜单栏入口下方向左、居中、向右展开。方向键可移动焦点并滚动到相应项目。
- 新增七款外观预设，可保存个人预设。「桌面水晶」默认磨砂 35%、着色 0%，圆角边缘保留原生折射。苹果液态玻璃可单独调磨砂，半透明材质可调背景不透明度。
- 可在下拉栏打开期间刷新可见的原生图标，手选图标优先。Clash Verge Rev 提供辅助功能网速文字时可更新读数。
- 修复入口处于菜单栏溢出区时的窗口定位，以及切换玻璃材质后图标偏向左下的问题。

[0.7.0 更新说明、升级与验证](docs/releases/v0.7.0.md#中文)

### 0.6.0 — 2026-10-28

- 设置页以应用列表为中心，显示方式更直接，窗口可调整大小，次要说明按需查看；保留必要的授权、错误和恢复入口。
- 简化图标预览与选择。重新扫描保留未保存的选择；关闭、撤销或恢复自动匹配前会提示可能丢失的内容。
- 下拉栏增加可见键盘焦点及 Tab / Shift-Tab 导航；最后一个隐藏应用改为常驻后仍可关闭隐藏。
- 调整启动、唤醒、显示器变化和系统菜单栏进程更替时的恢复过程，以进程身份与状态代次隔离过期操作。

Debug 和 Release 各有 79 项测试通过、1 项实机采集测试跳过；升级说明和限制详见 [0.6.0 更新说明](docs/releases/v0.6.0.md#中文)。

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
