<a id="english"></a>

<p align="center">
  <img src="docs/images/mbar-icon.png" alt="MBAR menu-bar shelf" width="144">
</p>
<h1 align="center">MBAR</h1>
<p align="center"><strong>Your menu-bar tools, together in one row.</strong></p>
<p align="center">
  <a href="#english"><img src="https://img.shields.io/badge/Language-English-24292f" alt="English"></a>
  <a href="#中文"><img src="https://img.shields.io/badge/语言-简体中文-1677ff" alt="简体中文"></a>
</p>
<p align="center">
  <a href="https://github.com/QiushanHuang/MBAR/releases/latest"><img src="https://img.shields.io/github/v/release/QiushanHuang/MBAR" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-27-111827" alt="macOS 27">
  <img src="https://img.shields.io/badge/Apple_Silicon-arm64-0d9488" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-AppKit_%2B_SwiftUI-f05138" alt="Swift, AppKit and SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-blue" alt="GPL-3.0"></a>
</p>

MBAR gathers menu-bar icons into a compact dropdown below its entry on macOS 27.
Choose which apps stay visible, which go into the shelf, and which remain hidden.
Open the shelf, then click a tool to reach its original menu.

[**Download v0.5.0**](https://github.com/QiushanHuang/MBAR/releases/tag/v0.5.0) ·
[Install](#install) · [Choose an icon](#choose-an-icon) ·
[What's new](docs/releases/v0.5.0.md) · [Report an issue](https://github.com/QiushanHuang/MBAR/issues)

## What MBAR does

- Keeps frequently used tools in one row near the point where you click. Wide collections scroll horizontally.
- Reads original menu-icon resources from supported apps. Automatic discovery also searches ordinary images, compiled `Assets.car` catalogs and Electron ASAR archives.
- Lets you compare uncertain candidates, import your own image, or capture a currently visible native icon.
- Keeps the shelf open with an optional lock, forwards left/right clicks, and provides a Show all recovery action.

**v0.5.0 adds broader icon discovery, per-app icon selection, optional native snapshots and a fix for screen-capture permission checks.**
The UI is currently in Simplified Chinese; English instructions below use the actual button labels.

Hiding uses a private macOS 27 interface and remains experimental. Artwork is static.
A saved battery percentage, speed value or graph does not continue updating.

<a id="install"></a>

## Install

Requires **macOS 27 and an Apple Silicon Mac**. Downloads are ad-hoc signed,
without Developer ID signing or Apple notarization. There is no Intel build.

1. Download `MBAR-0.5.0-macos-arm64.dmg` from [Releases](https://github.com/QiushanHuang/MBAR/releases/tag/v0.5.0).
2. Open the DMG and drag **MBAR** to **Applications**, then eject it. The ZIP is an alternative: extract it and move `MBAR.app` to Applications.
3. Launch `/Applications/MBAR.app`. MBAR runs in the menu bar, without a Dock icon.
4. If macOS blocks opening, review the download and use **System Settings → Privacy & Security → Open Anyway**. Keep Gatekeeper enabled.
5. Click **打开辅助功能设置**, enable MBAR, return and click **刷新**. On macOS 27 the system pane may be called **Device Control and Data Access**.

Keep target apps enabled in **System Settings → Menu Bar → Allow in Menu Bar**.
Turning them off there removes their menu items instead of collecting them in MBAR.

To verify a downloaded archive, put it beside the release's `SHA256SUMS.txt` and compare its digest:

```sh
shasum -a 256 MBAR-0.5.0-macos-arm64.dmg
```

## Start here

1. Launch the apps you want to organize, then click **刷新** in MBAR.
2. Leave new apps visible while checking **图标…** and preparing any native snapshot.
3. Choose a category:

| UI label | Behavior |
| --- | --- |
| 常驻菜单栏 | Stays visible in the system menu bar |
| 自动隐藏 | Appears in MBAR's dropdown when you open it |
| 总是隐藏 | Stays out of the dropdown; use its Settings arrow to open it temporarily |

4. Click **打开下拉栏** to check the row, then enable **启用隐藏**.

A fresh installation starts with hiding off. New apps default to Visible.
Categories and the enabled preference survive normal restarts; the shelf's locked state does not.

<a id="choose-an-icon"></a>

## Choose an icon

Open **Settings → 图标…** beside an app. MBAR uses these sources:

| Source | How it works | Screen Recording |
| --- | --- | --- |
| Verified adapter | Reads a known menu resource or symbol | Not needed |
| Automatic discovery | Uses a unique high-confidence candidate; otherwise asks you to choose | Not needed |
| Custom image | Previews and copies a PNG, TIFF or JPEG you select | Not needed |
| Native snapshot | Captures the icon as currently drawn in the visible menu bar | Required |

An explicit saved choice takes priority over automatic matching. Compare the light/dark previews,
choose original colors or template coloring, then click **使用此图标**.
**恢复自动匹配…** removes your override; **撤销上次修改** restores the previous saved choice.

Incomplete scans and ambiguous candidates never trigger automatic adoption. If a saved resource
changes after an app update, MBAR asks you to choose again. A missing shelf icon opens its icon settings.

### Capture a native icon

1. Keep the target icon visible in the system menu bar.
2. Open its **图标…** panel and click **读取当前原生图标**.
3. Allow MBAR in **Screen & System Audio Recording** if requested. Resource loading needs no such permission.
4. Check the preview and click **使用原生快照**. You can then move the app into Auto-hide.

This is a single-frame capture of the menu bar's rendered content. MBAR does not reveal hidden
icons to get a picture. It checks positions before and after capture and rejects empty, faded,
clipped or ambiguous results. Only the confirmed icon crop is saved, with its capture time.

If permission fails, the panel provides **打开屏幕录制设置**, **重新检查并读取** and **重启 MBAR**.
The restart returns to the same icon settings. v0.5.0 lets ScreenCaptureKit determine actual
access instead of blocking the request on an outdated preflight result.

A snapshot is static, including any numbers in it. Capture again to refresh it.
An app version change invalidates the old native snapshot.

### Compatibility

Existing verified adapters cover KeepingYouAwake, MonitorControl, Tailscale, BuhoNTFS Menu,
UU Remote, Codex, ScreenPilot, Docker Desktop, UGREEN NAS, Macs Fan Control and Clash Verge Rev.
Upstream resource changes can still require adapter updates. Clash's exposed speed text is read
once on opening, when available.

Automatic discovery extends beyond that list. In a local comparison of the same 20 running apps,
apps with at least one candidate increased from **4 to 15**. This measures candidate coverage,
not automatic matching accuracy or agreement with every app's current native state.

Apps with several menu items cannot yet be mapped individually. Custom charts and dynamically
drawn icons may have no standalone image resource; use a visible native snapshot when available.
See [extraction methods, evidence and limits](docs/icon-extraction.md) for the technical details.

## Everyday controls

| Action | Control |
| --- | --- |
| Open/close the shelf | Left-click MBAR's arrow |
| Open the original menu | Left-click an available shelf icon |
| Forward a right-click | Right-click the icon; behavior depends on the target app |
| Open Settings | Shelf gear, or right-click MBAR → 设置… |
| Keep the shelf open | Click the lock; click again to unlock |
| Close an unlocked shelf | Click outside, press Escape, or click MBAR again |
| Temporarily open an Always-hide item | Arrow button beside the app in Settings |
| Restore all icons and pause hiding | 显示全部（暂停） in Settings, or 显示全部图标 in MBAR's context menu |
| Quit | 退出 MBAR |

A locked shelf ignores normal dismissal, including Escape and item clicks. Unlock it to close it
normally; recovery actions can also close it. Clicking a tool may temporarily reveal its native
item, and the original menu may open at the system bar rather than below the shelf.

## Permissions and local data

Accessibility is required to discover menu items and forward interaction. Screen Recording is
optional and used only for an explicit native capture request. MBAR records no audio.

Resource loading reads installed app files without executing their binaries. Third-party artwork
is not included in MBAR's downloads. There is no account, telemetry or network backend.

| Data | Location |
| --- | --- |
| Categories, hiding preference, recent diagnostics | macOS UserDefaults, `local.qiushan.MBAR` |
| Saved icon mappings and one-step undo | `~/Library/Application Support/MBAR/IconMappings.json` |
| Imported images and confirmed native crops | `~/Library/Application Support/MBAR/ImportedIcons/` |
| Unconfirmed candidates | Memory only |

No full desktop or menu-bar screenshot is saved. Private hiding APIs can affect system extras
or the clock/Notification Center. If that happens, use **显示全部（暂停）**. Display arrangements,
Spaces and third-party menu behavior still need checking on your own setup.

## Troubleshooting and updates

| Problem | What to try |
| --- | --- |
| No apps appear | Check Accessibility, launch the target app, then Refresh |
| Accessibility is on but still rejected | Refresh only MBAR's entry for `/Applications/MBAR.app`, then reopen MBAR |
| Screen Recording is on but capture fails | Use the icon panel's settings/retry buttons; restart MBAR if the current process still lacks access |
| Native icon is hidden or moving | Keep it visible and wait for the bar to settle, then capture again |
| No useful resource candidate | Choose another candidate, import an image, or capture the visible native icon |
| A menu will not open | Show all and use the native icon; not all apps expose working Accessibility actions |
| The shelf will not close | Unlock it; Show all also resets the lock |

Before updating, quit MBAR and back up its preferences and Application Support directory if you
need a rollback. Replace the app in Applications and reopen it. Categories and saved choices
are retained. A changed ad-hoc signature can require macOS to reauthorize the new build.
When rolling back to an older version, restore its matching icon-data backup as well.

To uninstall, Show all, quit and move MBAR to Trash. Remove its system permission entries if desired.
Deleting `local.qiushan.MBAR` preferences resets categories; deleting the Application Support directory
also removes saved icon choices, imported images and undo history. These are separate cleanup steps.

## Build and diagnose

Use macOS 27 with Xcode's Swift 6 toolchain. Release validation uses Swift 6.4 and the macOS 27 SDK.

```sh
git clone https://github.com/QiushanHuang/MBAR.git
cd MBAR
git checkout v0.5.0
swift test
swift test -c release
./scripts/build-app.sh
./dist/MBAR.app/Contents/MacOS/MBAR --diagnostics
```

Use `main` instead of the release tag for current development. The build script signs
`dist/MBAR.app` and does not install or launch it. `SIGNING_IDENTITY` selects an existing signing
identity; the default is ad-hoc. `MBAR_APP_DIR` accepts an absolute output path.
Do not overwrite a running bundle. `./scripts/package-release.sh` produces DMG, ZIP and checksums
in a new output directory.

Diagnostics with `--items` include app identifiers and menu geometry; review them before sharing.
Terminal permission results do not prove that the GUI app is authorized. Unit tests cover policy,
parsing and lifecycle behavior; installed-app capture and physical-display checks are separate.

[Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md) ·
[Release notes and validation](docs/releases/v0.5.0.md)

Created and maintained by **[Qiushan (QiushanHuang)](https://github.com/QiushanHuang)**.
[Contributors](CONTRIBUTORS.md) · [GPL-3.0](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)

[↓ 简体中文](#中文)

---

<a id="中文"></a>

## 中文

<p align="center">
  <img src="docs/images/mbar-icon.png" alt="MBAR 菜单栏收纳工具" width="144">
</p>
<p align="center"><strong>常用菜单栏工具，一排收好。</strong></p>
<p align="center">
  <a href="#english"><img src="https://img.shields.io/badge/Language-English-24292f" alt="English"></a>
  <a href="#中文"><img src="https://img.shields.io/badge/语言-简体中文-1677ff" alt="简体中文"></a>
</p>

MBAR 将 macOS 27 的菜单栏图标收进入口下方的紧凑下拉栏。
你可以决定哪些应用常驻、哪些收入下拉栏、哪些一直隐藏，再从同一排图标打开它们的原菜单。

[**下载 v0.5.0**](https://github.com/QiushanHuang/MBAR/releases/tag/v0.5.0) ·
[安装](#安装) · [选择图标](#选择图标) · [更新说明](docs/releases/v0.5.0.md#中文) ·
[反馈问题](https://github.com/QiushanHuang/MBAR/issues)

### 主要功能

- 常用工具集中在入口下方；图标较多时横向滚动。
- 读取已适配应用的原始菜单图标，也会自动搜索普通图片、`Assets.car` 图像资源库和 Electron ASAR 归档。
- 候选不明确时手动选择，也支持导入图片、读取当前可见的原生图标。
- 可锁定下拉栏，转发左右键操作，并随时显示全部图标、暂停隐藏。

**v0.5.0 扩展了图标识别，加入每应用图标选择和可选原生快照，并修复了录屏权限预检阻断取图的问题。**
界面目前为简体中文。隐藏依赖 macOS 27 私有接口，仍属实验功能。
图标和快照都是静态内容，保存的电量、网速或波形不会持续刷新。

<a id="安装"></a>

### 安装

需要 **macOS 27 和 Apple Silicon Mac**。下载包采用 ad-hoc 签名，
未经 Developer ID 签名或 Apple 公证，未提供 Intel 版本。

1. 在[发行页](https://github.com/QiushanHuang/MBAR/releases/tag/v0.5.0)下载 `MBAR-0.5.0-macos-arm64.dmg`。
2. 打开 DMG，将 **MBAR** 拖到 **Applications（应用程序）**，然后推出映像。也可解压 ZIP 后移动 `MBAR.app`。
3. 从 `/Applications/MBAR.app` 启动。MBAR 只驻留菜单栏，不显示 Dock 图标。
4. 若 macOS 阻止打开，确认下载来源后，在**系统设置 → 隐私与安全性 → 仍要打开**中放行，保持 Gatekeeper 开启。
5. 点击 **打开辅助功能设置**，启用 MBAR，返回后点击 **刷新**。macOS 27 英文系统可能将该权限称为 **Device Control and Data Access**。

请在系统的**菜单栏 → 允许在菜单栏中**保持目标应用开启；在那里关闭会移除菜单项目，而不是由 MBAR 收纳。

发行页提供 `SHA256SUMS.txt`，可将以下结果与其中对应行核对：

```sh
shasum -a 256 MBAR-0.5.0-macos-arm64.dmg
```

### 快速开始

1. 启动需要收纳的应用，在 MBAR 中点击 **刷新**。
2. 新应用先保持常驻，在 **图标…** 中检查来源，必要时先采集原生图标。
3. 为应用选择分类：

| 分类 | 行为 |
| --- | --- |
| 常驻菜单栏 | 保留在系统顶栏 |
| 自动隐藏 | 点击 MBAR 后在下拉栏显示 |
| 总是隐藏 | 不进入下拉栏，仅从设置临时打开 |

4. 点击 **打开下拉栏** 检查效果，然后开启 **启用隐藏**。

全新安装默认不隐藏，新发现的应用默认常驻。分类与隐藏开关会在正常重启后保留；下拉栏的锁定状态不跨重启保存。

<a id="选择图标"></a>

### 选择图标

在设置中点击应用旁的 **图标…**。可用来源如下：

| 来源 | 工作方式 | 录屏权限 |
| --- | --- | --- |
| 已验证适配 | 读取已知菜单资源或系统符号 | 不需要 |
| 自动发现 | 唯一高可信候选自动采用，有歧义则手动选择 | 不需要 |
| 自定义图片 | 预览并保存选中的 PNG、TIFF 或 JPEG | 不需要 |
| 原生快照 | 采集当前可见菜单图标的实际画面 | 需要 |

手动保存的选择优先于自动匹配。比较明暗背景预览，选择保留原色或随菜单栏着色，再点 **使用此图标**。
**恢复自动匹配…** 可撤销手动覆盖，**撤销上次修改** 可恢复上一次保存的选择。

扫描不完整或候选有歧义时不会自动采用。应用更新后，若保存的图标来源发生变化，会要求重新选择。
下拉栏中的缺失图标入口会打开对应应用的图标设置。

#### 读取原生图标

1. 让目标图标在系统菜单栏中保持可见。
2. 打开该应用的 **图标…**，点击 **读取当前原生图标**。
3. 如系统提示，在**屏幕与系统音频录制**中允许 MBAR。普通资源读取不需要这项权限。
4. 检查预览，点击 **使用原生快照**，之后可将应用设为自动隐藏。

这是对系统菜单栏画面的单帧采集。MBAR 不会为了取图展开隐藏项目，采集前后会核对位置，
并拒绝空白、明显淡化、裁切不完整或身份不明确的结果。确认后只保存目标图标及采集时间。

权限失败时，面板提供 **打开屏幕录制设置**、**重新检查并读取** 和 **重启 MBAR**。
重启会返回原图标设置。v0.5.0 以 ScreenCaptureKit 的实际结果判定访问权限，
避免旧的预检值为否时直接拦住取图。

快照内的数字也是静态的，需要重新采集才会更新。目标应用版本变化后，旧原生快照会失效。

#### 兼容范围

已有专用适配覆盖 KeepingYouAwake、MonitorControl、Tailscale、BuhoNTFS Menu、UU Remote、
Codex、ScreenPilot、Docker Desktop、绿联 NAS、Macs Fan Control 和 Clash Verge Rev。
上游资源改变仍可能需要更新适配。Clash 暴露的速度文字仅在展开时读取一次。

自动发现也会处理列表之外的应用。在同一批 20 个运行中应用的本地对照中，
找到至少一个候选的应用从 **4 个增加到 15 个**。这是候选覆盖率，不代表 15 个均自动匹配成功，
也不保证与每个应用的当前原生状态一致。

同一应用的多个菜单项目暂不支持逐个映射。自绘图表可能没有独立图片资源，可在图标可见时采集原生快照。
技术路径和证据见[提取方法与限制](docs/icon-extraction.md)。

### 日常操作

| 操作 | 方法 |
| --- | --- |
| 展开或收起下拉栏 | 左键点击 MBAR 箭头 |
| 打开原应用菜单 | 左键点击可用图标 |
| 转发右键 | 右键点击图标，实际行为由目标应用决定 |
| 打开设置 | 下拉栏齿轮，或右键 MBAR → 设置… |
| 保持下拉栏打开 | 点击锁定按钮，再次点击解锁 |
| 收起未锁定的下拉栏 | 点击外部、按 Escape 或再次点击 MBAR |
| 临时打开总是隐藏的项目 | 设置列表中对应行的箭头按钮 |
| 恢复全部并暂停隐藏 | 设置中的 显示全部（暂停），或 MBAR 右键菜单的 显示全部图标 |
| 退出 | 退出 MBAR |

锁定后会忽略普通收起操作，包括 Escape 和图标点击；需要正常收起时先解锁，恢复操作也可关闭面板。
点击工具时可能临时显示其原生图标，原菜单也可能出现在系统顶栏，而不是下拉栏下方。

### 权限与本地数据

辅助功能用于发现菜单项目和转发操作。录屏权限是可选的，只在主动读取原生图标时使用，MBAR 不录制音频。

资源读取不会执行其他应用的二进制，下载包也不附带第三方图标。MBAR 没有账号、遥测或网络后端。

| 数据 | 位置 |
| --- | --- |
| 分类、隐藏偏好、最近诊断 | macOS UserDefaults，`local.qiushan.MBAR` |
| 图标映射与单步撤销 | `~/Library/Application Support/MBAR/IconMappings.json` |
| 导入图片与确认的原生裁切图 | `~/Library/Application Support/MBAR/ImportedIcons/` |
| 未确认的候选 | 仅内存 |

不保存整屏或整条菜单栏截图。私有隐藏接口可能影响系统附加项，以及点击时钟打开通知中心。
遇到影响时用 **显示全部（暂停）** 恢复；多屏、Spaces 和第三方菜单行为仍需在自己的环境中确认。

### 排障与更新

| 问题 | 处理方法 |
| --- | --- |
| 应用列表为空 | 检查辅助功能，启动目标应用并刷新 |
| 辅助功能已开但仍提示未授权 | 只刷新 `/Applications/MBAR.app` 的授权条目，再重新打开 MBAR |
| 录屏已开但原生取图失败 | 使用图标面板中的设置和重试按钮；当前进程仍无权限时重启 MBAR |
| 原生图标隐藏或位置变化 | 先保持可见，等菜单栏稳定后再读取 |
| 没有合适的资源候选 | 选择其他候选、导入图片，或读取当前可见原生图标 |
| 原菜单打不开 | 显示全部后使用原生图标，部分应用不支持可用的辅助功能动作 |
| 面板无法收起 | 先解锁；显示全部也会解除锁定 |

更新前退出 MBAR。需要回退时，先备份偏好设置与 Application Support 目录，再替换“应用程序”中的包并重开。
分类与保存的选择会保留；ad-hoc 签名变化后，macOS 可能要求重新授权。
回退到旧版本时，也应恢复与旧版匹配的图标数据备份。

卸载时先显示全部并退出，再将 MBAR 移入废纸篓，可按需移除其系统授权。
删除 `local.qiushan.MBAR` 偏好会重置分类；删除 Application Support 目录还会清除图标选择、图片及撤销历史。
两者是独立的清理步骤。

### 构建与诊断

使用 macOS 27 和 Xcode 的 Swift 6 工具链；发行验证使用 Swift 6.4 / macOS 27 SDK。

```sh
git clone https://github.com/QiushanHuang/MBAR.git
cd MBAR
git checkout v0.5.0
swift test
swift test -c release
./scripts/build-app.sh
./dist/MBAR.app/Contents/MacOS/MBAR --diagnostics
```

开发时可使用 `main` 分支。构建脚本生成并签名 `dist/MBAR.app`，不会自动安装或启动。
`SIGNING_IDENTITY` 可指定已有签名身份，默认 ad-hoc；`MBAR_APP_DIR` 可指定绝对输出路径。
不要覆盖正在运行的包。`./scripts/package-release.sh` 会在新的输出目录生成 DMG、ZIP 和校验文件。

诊断加上 `--items` 会输出应用标识和坐标，分享前请检查内容。终端权限不代表 GUI 应用已授权。
单元测试覆盖策略、解析与生命周期；安装版采集和多屏实机验收分别记录。

[贡献指南](CONTRIBUTING.md) · [更新记录](CHANGELOG.md) · [版本说明与验证](docs/releases/v0.5.0.md#中文)

作者与维护者：**[Qiushan（QiushanHuang）](https://github.com/QiushanHuang)**。
[贡献署名](CONTRIBUTORS.md) · [GPL-3.0 许可](LICENSE) · [第三方声明](THIRD_PARTY_NOTICES.md)

[↑ Back to English](#english)
