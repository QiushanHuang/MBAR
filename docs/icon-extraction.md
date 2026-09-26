# 图标提取方法与边界

适用于 v0.5.0（2026-09-26）。

## 已实现的方法

| 方法 | 适用情况 | 处理方式 |
| --- | --- | --- |
| 普通图片资源 | PNG、TIFF、PDF、ICO | 根据名称、尺寸和透明度形成候选；菜单相关资源优先解码 |
| 编译后的 Assets.car | 原生 macOS 应用的图像、模板、矢量字形 | 用系统 assetutil 有界读取索引，用 AppKit 按名称取图；不执行目标应用代码 |
| Electron ASAR | 归档中的菜单图片 | 有界枚举并校验条目，优先处理 tray/status 等候选；不完整扫描不自动采用 |
| 已验证专用来源 | 已有资源路径、系统符号、校验过的内嵌图像 | 保留现有适配优先级；不通用猜测二进制内的图片身份 |
| 当前原生菜单栏快照 | 图标确实可见、位置稳定 | ScreenCaptureKit 只包含菜单栏，再裁切目标项目，预览后由用户保存 |

`statusicon`、`statusbar`、`trayicon`、`menubarpinyin` 等连写名称会被发现。
与应用同名的小尺寸透明图片也可作为手选候选；名称相同本身不足以自动采用。
强名称、模板属性和适宜尺寸可以支持自动匹配，竞争候选与状态/主题变体仍需确认。

Assets.car 的模板属性同时参考索引与 AppKit 实际返回的 `isTemplate`，覆盖矢量字形。
目录候选、归档候选和资源库候选先统一排序，再使用解码预算；不会由目录枚举先后决定优先级。
资源库索引进程有时间、输出大小和名称数量上限。系统缺少 assetutil 或其输出变化时，
该来源会明确报为不完整，其余来源继续可用。

## 使用当前原生图标

1. 让目标图标在系统菜单栏中保持可见。
2. MBAR 设置 → 对应应用的“图标…” → “读取当前原生图标”。
3. 检查明暗背景预览，再点“使用原生快照”。之后可将应用设为自动隐藏。

此功能需要已有的辅助功能及屏幕录制权限。普通资源加载不需要录屏权限。
MBAR 不为取图主动展开系统栏，也不会临时取消其他应用的隐藏。
不可见、被遮挡、位置变化、疑似边缘裁切、空白或明显淡化的图像不会采用。
白色透明字形可转换为模板显示，彩色字形保留原色，用户也可在保存前调整。

保存的是静态图标及采集时间，不是实时图表或当前状态承诺。只在用户确认后保存目标
裁切图，不保存整条菜单栏、桌面或其他窗口。应用版本变化后要求重新采集。
资源库映射还保存 Assets.car 文件摘要；资源库内容发生变化时要求重新确认，防止缓存旧图误用。

## 实测结果与尚存限制

同一批 20 个正在运行的菜单栏应用中，通用扫描找到至少一个候选的数量由 4 个增加到 15 个。
这是候选覆盖率，不是 15 个都自动匹配成功，也不代表候选都与当前原生状态一致。
新增覆盖包括微信、AlDente、Alfred、Bob、LaunchOS、LemonMonitor、讯飞输入法等。
已验证的专用适配独立保留。

在未展开系统栏的情况下，正式采集代码通过了 AlDente、Codex Pulse、LemonMonitor、微信
四个可见项目的测试。AlDente 保留彩色，另三项使用单色模板；隔离 GUI 也验证了
AlDente 原生电池图标的预览和保存。随后在实际安装版中复现并修复授权问题，
微信与 AlDente 的原生预览均成功。验证没有替用户保存新图标选择。

Command X、Creative Cloud 等应用没有在当前搜索范围内暴露合适的原始资源。
它们可在图标自然可见时使用原生快照。多个菜单项目尚未建立稳定的逐项目身份，仍拒绝自动映射。
动态图表可取静帧，不持续同步。隐藏状态下不能保证取得原生像素；本机 ScreenCaptureKit
未列出可单独截取的 MenuBarAgent 项目窗口，未采用旧系统的逐窗口抓取方式。
AX 接口用来核实身份和坐标，不将其当作通用图片数据接口。

## 调查资料

- [Apple：Bundle.image(forResource:)](https://developer.apple.com/documentation/foundation/bundle/image(forresource:))：按资源名读取 AppKit 图像与倍率表示。
- [Apple：SCContentFilter.includeMenuBar](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/includemenubar)：菜单栏过滤；当前 SDK 明确空窗口包含列表不包含桌面和 Dock。
- [Apple：SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)：单帧采集。
- [AssetCatalogTinkerer](https://github.com/insidegui/AssetCatalogTinkerer)：资源库枚举/导出的可行路径；本实现使用系统工具与 AppKit，没有引入其私有 CoreUI 接口。
- [Pelmet 图标缓存源码](https://github.com/fif7y/pelmet/blob/main/Pelmet/Editor/ItemImageCache.swift)：记录了共享菜单栏截图的淡化、刘海和位置映射问题；本实现因此保留拒绝条件和明确的静态快照标签。
- [Thaw macOS 27 跟踪](https://github.com/thaw-app/Thaw/issues/687)：新菜单栏架构的兼容性限制。

## 验证

运行 `swift test`、`swift test -c release` 以及 `scripts/build-app.sh`。
资源库测试使用仓库自制矩形素材，可由 `swift scripts/make-test-catalog.swift` 重建，
不分发第三方图标。实时采集测试默认跳过，显式设置 `MBAR_NATIVE_PROBE_BUNDLES` 后才运行；
它只读取指定的当前可见菜单图标，不操作折叠、分类或系统权限。

## 授权与底层接口补充

安装后若系统录屏开关已开启，旧进程的权限预检仍可能返回否。新版不再把
`CGPreflightScreenCaptureAccess` 的值当作用户请求的硬门槛，而让 ScreenCaptureKit
处理实际授权；拒绝时保留错误类型，提供录屏设置、重试和重启入口。只有用户主动取图
才调用该接口，普通资源发现不会请求录屏。重启后会返回原图标设置。

本机对 MenuBarClientCore / MenuBarClient 的只读检查发现了 `MBMenuBarItemContent.image`
与 `MBMenuBarItemImage.bitmapImage` / `symbolName`。这些是内容对象上的访问器；检查到的
ItemManager 接口负责提交和控制本应用的项目，未找到可供 MBAR 跨应用枚举并获取内容对象的入口。
21 个 AX 菜单项目没有暴露图像属性。上述范围不等于穷尽所有 Swift 私有接口，
但不能把发现内部图像类型直接当作可用的通用提取方案。

直接资源读取与原生画面采集是两条不同路径：静态图标可读 Assets.car/PNG 等资源；
电量数字、网速、波形可能只存在于运行中的绘制结果，没有独立图片文件。
SkyLight 的窗口抓取同样获取渲染像素，不是读取原始 NSImage；Thaw 记录的逐图标离屏窗口路径
主要针对 macOS 26，不能直接替代本机 macOS 27 的共享菜单栏。

参考：[Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)、
[Apple NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar)、
[Thaw 的权限和采集实现](https://github.com/thaw-app/Thaw/blob/development/Thaw/Utilities/ScreenCapture.swift)。
