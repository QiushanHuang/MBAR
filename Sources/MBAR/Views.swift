import SwiftUI
import AppKit
import MBARCore

private extension ItemCategory {
    var title: String {
        switch self {
        case .visible: return "常驻菜单栏"
        case .automatic: return "收入下拉栏"
        case .always: return "始终隐藏"
        }
    }
}

extension ShelfStyle {
    var title: String {
        switch self {
        case .strip: return "图标条"
        case .grid: return "网格"
        case .list: return "列表"
        }
    }
}

extension ShelfPlacement {
    var title: String {
        switch self {
        case .left: return "屏幕左侧"
        case .anchor: return "入口下方"
        case .right: return "屏幕右侧"
        }
    }
}

extension ShelfAlignment {
    var title: String {
        switch self {
        case .left: return "向左展开"
        case .center: return "居中展开"
        case .right: return "向右展开"
        }
    }
}

struct InfoButton: View {
    let label: String
    let detail: String
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(detail)
        .accessibilityLabel(label)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(detail).font(.callout).fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading).padding(16)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var showsAppearance = false

    private var hidingUnavailable: String? {
        if !model.trusted { return "请先允许辅助功能。" }
        if !model.apiAvailable { return "当前系统无法启用隐藏。" }
        if model.policy.hidden.isEmpty { return "先将应用收入下拉栏或设为始终隐藏。" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "menubar.dock.rectangle")
                    .font(.system(size: 23, weight: .medium)).foregroundStyle(.teal)
                    .accessibilityHidden(true)
                Text("菜单栏应用").font(.title2.bold())
                InfoButton(label: "显示方式说明", detail: "收入下拉栏的应用可从 MBAR 打开；始终隐藏的应用不在下拉栏中，可从设置临时打开。")
                Spacer()
                if model.refreshing || model.capturing { ProgressView().controlSize(.small) }
                Button { model.refreshContents() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .disabled(model.refreshing || !model.trusted)
            }

            ViewThatFits(in: .vertical) {
                VStack(spacing: 16) {
                    appList
                    options.fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 12) {
                    appList.frame(height: 110)
                    ScrollView { options.padding(2) }
                }
            }
            HStack {
                Button("退出 MBAR") { NSApp.terminate(nil) }
                Spacer()
                Button("打开下拉栏") { (NSApp.delegate as? AppDelegate)?.toggleShelf() }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(!model.trusted)
                    .help(model.trusted ? "打开 MBAR 下拉栏。" : "请先允许辅助功能。")
            }
        }.padding(24).frame(minWidth: 580, minHeight: 500)
            .background(Color(nsColor: .windowBackgroundColor))
            .sheet(isPresented: $showsAppearance) { ShelfAppearanceSettings(model: model) }
            .sheet(isPresented: Binding(get: { model.iconSettingsBundle != nil }, set: { if !$0 { model.iconSettingsBundle = nil } })) {
                if let bundle = model.iconSettingsBundle {
                    IconSettingsView(library: model.iconLibrary, bundle: bundle,
                        name: model.items.first(where: { $0.bundle == bundle })?.name ?? bundle,
                        dismiss: { model.iconSettingsBundle = nil })
                }
            }
    }

    private var appList: some View {
        let groups = model.groups
        return Group {
            if groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.bundle) { index, group in
                            if let item = group.items.first {
                                appRow(item, count: group.items.count)
                                if index < groups.count - 1 { Divider().padding(.leading, 54) }
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: 110, idealHeight: 110, maxHeight: .infinity)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Toggle("启用隐藏", isOn: Binding(get: { model.hideRequested }, set: { model.enableHiding($0) }))
                        .disabled(!model.hideRequested && hidingUnavailable != nil)
                        .help(model.hideRequested ? "关闭后显示全部图标并暂停隐藏。" : (hidingUnavailable ?? "按应用的显示方式隐藏菜单栏图标。"))
                    InfoButton(label: "隐藏功能说明", detail: "隐藏功能使用系统接口，可能影响部分系统菜单项或通知中心。若出现异常，选择“显示全部（暂停）”恢复。")
                    Spacer()
                    Button("显示全部（暂停）") { model.restoreAll() }
                }
                if model.trusted, !model.hideRequested, let reason = hidingUnavailable {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                if model.hideRequested {
                    Label("菜单栏出现异常时，可显示全部并暂停。", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if model.trusted, let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            shelfSettings
        }
    }

    private var shelfSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("下拉栏").font(.headline)
                Spacer()
                Button { showsAppearance = true } label: {
                    Label("外观…", systemImage: "paintpalette")
                }
                .controlSize(.small)
                .accessibilityLabel("下拉栏外观")
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("样式")
                    Picker("下拉栏样式", selection: $model.shelfStyle) {
                        ForEach(ShelfStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                GridRow {
                    Text("位置")
                    Picker("下拉栏位置", selection: $model.shelfPlacement) {
                        ForEach([ShelfPlacement.left, .anchor, .right], id: \.self) { Text($0.title).tag($0) }
                    }
                }
                if model.shelfPlacement == .anchor {
                    GridRow {
                        Text("展开方向")
                        Picker("入口下方展开方向", selection: $model.shelfAlignment) {
                            ForEach(ShelfAlignment.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .help("选择相对 MBAR 入口的展开方向。靠近屏幕边缘时，下拉栏会移入可见区域。")
                    }
                }
                GridRow {
                    Text("图标大小")
                    HStack(spacing: 8) {
                        ShelfValueSlider(label: "图标大小", range: ShelfIconScale.range, value: model.shelfIconScale,
                                         keyboardStep: ShelfIconScale.step) { model.shelfIconScale = $0 }
                            .frame(maxWidth: .infinity)
                        Text(model.shelfIconScale.formatted(.percent))
                            .monospacedDigit().frame(width: 40, alignment: .trailing)
                        Button("还原") { model.shelfIconScale = 1 }
                            .controlSize(.small)
                            .disabled(model.shelfIconScale == 1)
                            .accessibilityLabel("还原图标大小至 100%")
                    }
                }
                GridRow {
                    Text("锁定与设置")
                    Picker("锁定和设置按钮的位置", selection: $model.shelfToolsSide) {
                        Text("左侧").tag(ShelfToolsSide.left)
                        Text("右侧").tag(ShelfToolsSide.right)
                    }
                    .help("将锁定和设置按钮一起放在下拉栏左侧或右侧。")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 6) {
                Toggle("显示锁定按钮", isOn: Binding(
                    get: { model.shelfLock.showsButton }, set: { model.setShowsShelfLock($0) }))
                    .help("锁定后，点按其他窗口时保持下拉栏打开。")
                    .padding(.trailing, 14)
                Toggle("刷新可见的原生图标", isOn: $model.shelfLiveIcons)
                InfoButton(label: "原生图标刷新说明", detail: "下拉栏打开期间，MBAR 使用屏幕录制权限读取菜单栏中可见的图标。手选和导入的图标优先。隐藏项目沿用静态图标，Clash 可在提供网速文字时更新数值。")
            }
            if model.shelfLiveIcons, let notice = model.shelfLiveNotice {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(notice, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.shelfLivePermissionDenied {
                        Button("屏幕录制设置") { ScreenCaptureAccess.shared.openSettings() }
                            .controlSize(.small).fixedSize()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if model.refreshing {
                ProgressView()
                Text("正在读取菜单栏…").foregroundStyle(.secondary)
            } else if !model.trusted {
                Image(systemName: "hand.raised").font(.title2).foregroundStyle(.secondary)
                Text("允许辅助功能后管理菜单栏应用").font(.headline)
                Button("打开辅助功能设置", action: model.requestAccessibility)
                    .buttonStyle(.borderedProminent).tint(.teal)
            } else {
                Image(systemName: "menubar.rectangle").font(.title2).foregroundStyle(.secondary)
                Text("没有可读取的菜单栏应用").foregroundStyle(.secondary)
                Button("刷新", action: model.refreshContents)
            }
        }.frame(maxWidth: .infinity).padding(6)
    }

    private func appRow(_ item: MenuItem, count: Int) -> some View {
        let category = model.policy.category(item.bundle)
        let entry = model.iconLibrary.entry(item.bundle)
        let needsIcon = entry.state == .needsSelection || entry.state == .missing || entry.state == .stale || entry.state == .failed
        return HStack(spacing: 12) {
            Image(nsImage: model.settingsIcon(for: item)).resizable().scaledToFit().frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text(item.name).fontWeight(.medium).lineLimit(1)
            if count > 1 {
                Text("\(count) 个图标").font(.caption).foregroundStyle(.secondary)
                    .help("此应用的菜单栏图标一起设置。")
            }
            Spacer(minLength: 8)
            Button(needsIcon && category == .automatic ? "选择图标…" : "图标…") { model.configureIcon(item.bundle) }
                .help(entry.state.rawValue)
                .accessibilityLabel("\(item.name) 图标设置，\(entry.state.rawValue)")
            if category != .visible {
                Button { model.openItem(item, right: false, fromSettings: true) } label: {
                    Image(systemName: "arrow.up.forward.square")
                }.help("临时打开 \(item.name) 的菜单").accessibilityLabel("临时打开 \(item.name) 的菜单")
            }
            Picker("\(item.name) 的显示方式", selection: Binding(get: { model.policy.category(item.bundle) }, set: { model.setCategory(item.bundle, $0) })) {
                ForEach(ItemCategory.allCases, id: \.self) { category in Text(category.title).tag(category) }
            }.labelsHidden().pickerStyle(.menu).frame(width: 132)
        }.padding(.horizontal, 16).padding(.vertical, 11)
    }
}

struct ShelfView: View {
    @ObservedObject var model: AppModel
    let width: CGFloat
    var height: CGFloat = ShelfMetrics.height
    @StateObject private var focus = ShelfFocusCoordinator()

    var body: some View {
        let items = model.collected
        let tallest = model.shelfMaxGlyphHeight
        Group {
            if model.shelfStyle == .strip {
                let itemHeight = ShelfMetrics.stripItemHeight(scale: model.shelfIconScale, tallestGlyphHeight: tallest)
                HStack(spacing: 2) {
                    if toolsOnLeft {
                        tools(itemCount: items.count, columns: max(1, items.count))
                        Divider().frame(height: 16)
                    }
                    if items.isEmpty {
                        emptyState
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    itemControl(item, index: index, columns: items.count)
                                        .frame(width: model.previewWidth(for: item),
                                               height: itemHeight)
                                }
                            }
                        }
                        .frame(height: itemHeight)
                        .clipped()
                    }
                    if !toolsOnLeft {
                        Divider().frame(height: 16)
                        tools(itemCount: items.count, columns: max(1, items.count))
                    }
                }
                .padding(.horizontal, ShelfMetrics.stripInset)
            } else {
                let columns = model.shelfStyle == .grid ? ShelfMetrics.gridColumns(for: width, itemCount: items.count) : 1
                VStack(spacing: 0) {
                    if items.isEmpty {
                        emptyState
                    } else {
                        let rowHeight = model.shelfStyle == .grid
                            ? ShelfMetrics.tileHeight(scale: model.shelfIconScale, tallestGlyphHeight: tallest)
                            : ShelfMetrics.listRowHeight(scale: model.shelfIconScale, tallestGlyphHeight: tallest)
                        ScrollView(.vertical) {
                            // Keep offscreen buttons registered so keyboard navigation can reach every row.
                            VStack(spacing: ShelfMetrics.rowSpacing) {
                                ForEach(0..<((items.count + columns - 1) / columns), id: \.self) { row in
                                    HStack(spacing: ShelfMetrics.rowSpacing) {
                                        ForEach(0..<columns, id: \.self) { column in
                                            let index = row * columns + column
                                            if index < items.count {
                                                itemControl(items[index], index: index, columns: columns)
                                            } else {
                                                Color.clear.accessibilityHidden(true)
                                            }
                                        }
                                    }
                                    .frame(height: rowHeight)
                                }
                            }
                        }
                        .clipped()
                        .padding(ShelfMetrics.bodyInset)
                    }
                    HStack(spacing: 2) {
                        if toolsOnLeft {
                            tools(itemCount: items.count, columns: columns)
                            Spacer(minLength: 0)
                        }
                        if !items.isEmpty {
                            Text("\(items.count) 个项目")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .modifier(ShelfTextContrast(clearGlass: clearGlass))
                                .padding(toolsOnLeft ? .trailing : .leading, 6)
                        }
                        if !toolsOnLeft {
                            Spacer(minLength: 0)
                            tools(itemCount: items.count, columns: columns)
                        }
                    }
                    .padding(.horizontal, ShelfMetrics.bodyInset)
                    .frame(height: ShelfMetrics.footerHeight)
                    .overlay(alignment: .top) { Divider() }
                }
            }
        }
        .frame(width: width, height: height)
    }

    private var toolsOnLeft: Bool { model.shelfToolsSide == .left }
    private var toolCount: Int { model.shelfLock.showsButton ? 2 : 1 }
    private var clearGlass: Bool { model.shelfAppearance.material == .appleGlass }

    private var emptyState: some View {
        Label("尚未收入应用", systemImage: "tray")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .modifier(ShelfTextContrast(clearGlass: clearGlass))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func itemControl(_ item: MenuItem, index: Int, columns: Int) -> some View {
        let image = model.shelfImage(for: item)
        let help = image == nil ? "选择此项目的图标" : model.shelfIconDescription(for: item)
        let itemName = model.shelfItemLabel(for: item)
        let glyphSize = model.shelfGlyphSize(for: item)
        let icon = ShelfGlyph(image: image, onClearGlass: clearGlass, treatment: model.shelfAppearance.iconTreatment,
                              preservesOriginalInk: model.iconLibrary.hasOverride(item.bundle))
            .frame(maxWidth: glyphSize.width, maxHeight: glyphSize.height)
        let leadingTools = model.shelfStyle == .strip && toolsOnLeft ? toolCount : 0
        return ZStack {
            Group {
                switch model.shelfStyle {
                case .strip:
                    icon.padding(.horizontal, 2)
                case .grid:
                    VStack(spacing: 4) {
                        icon
                        Text(item.name).font(.caption).lineLimit(1)
                            .modifier(ShelfTextContrast(clearGlass: clearGlass))
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 7))
                case .list:
                    HStack(spacing: 9) {
                        icon.frame(width: min(max(38, glyphSize.width), width * 0.42))
                        Text(item.name).font(.body).lineLimit(1)
                            .modifier(ShelfTextContrast(clearGlass: clearGlass))
                        Spacer(minLength: 2)
                        Image(systemName: image == nil ? "slider.horizontal.3" : "chevron.forward")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .opacity(model.capturing ? 0.5 : 1)
            ShelfTarget(label: itemName, help: help, enabled: !model.capturing,
                        focus: focus, order: index + leadingTools, row: index / columns,
                        column: index % columns + leadingTools,
                        allowsRightClick: image != nil) { right in
                if image == nil { model.configureIcon(item.bundle) }
                else { model.openItem(item, right: right) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func tools(itemCount: Int, columns: Int) -> some View {
        let strip = model.shelfStyle == .strip
        let row = strip ? 0 : (itemCount + columns - 1) / columns
        let firstOrder = strip && toolsOnLeft ? 0 : itemCount
        let firstColumn = toolsOnLeft ? 0 : (strip ? itemCount : max(0, columns - toolCount))
        if model.shelfLock.showsButton {
            let locked = model.shelfLock.isLocked
            tool(symbol: locked ? "lock.fill" : "lock.open", label: locked ? "解锁下拉栏" : "锁定下拉栏",
                 selected: locked, order: firstOrder, row: row, column: firstColumn) {
                model.toggleShelfLock()
            }
        }
        tool(symbol: "gearshape", label: "MBAR 设置", selected: false, order: firstOrder + toolCount - 1,
             row: row, column: firstColumn + toolCount - 1) {
            model.showSettings?()
        }
    }

    private func tool(symbol: String, label: String, selected: Bool, order: Int, row: Int, column: Int,
                      action: @escaping () -> Void) -> some View {
        ZStack {
            ShelfGlyph(systemName: symbol, onClearGlass: clearGlass, treatment: model.shelfAppearance.iconTreatment, selected: selected)
                .frame(width: 14, height: 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            ShelfTarget(label: label, help: "", enabled: true, focus: focus, order: order,
                        row: row, column: column, allowsRightClick: false) { _ in action() }
        }
        .frame(width: 28, height: 28)
    }
}

/// Only labels receive a text shadow. Icon transparency already has a local backing.
private struct ShelfTextContrast: ViewModifier {
    let clearGlass: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if clearGlass && !reduceTransparency {
            content.foregroundStyle(.white).shadow(color: .black, radius: 1, y: 0.5)
        } else {
            content
        }
    }
}

/// The panel focuses its host on opening so no menu item looks preselected.
final class ShelfHostingView: NSHostingView<ShelfView> {
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.shift, .capsLock])
        if window?.firstResponder === self, event.keyCode == 48, modifiers.isEmpty,
           let coordinator = coordinator(in: self) {
            coordinator.enter(backwards: event.modifierFlags.contains(.shift))
        } else {
            super.keyDown(with: event)
        }
    }

    private func coordinator(in view: NSView) -> ShelfFocusCoordinator? {
        if let button = view as? ShelfButton { return button.focusCoordinator }
        for child in view.subviews {
            if let focus = coordinator(in: child) { return focus }
        }
        return nil
    }
}

@MainActor final class ShelfFocusCoordinator: ObservableObject {
    private struct Entry {
        weak var button: ShelfButton?
        let order: Int
        let row: Int
        let column: Int
    }
    private var entries: [ObjectIdentifier: Entry] = [:]

    func register(_ button: ShelfButton, order: Int, row: Int = 0, column: Int? = nil) {
        entries[ObjectIdentifier(button)] = Entry(button: button, order: order, row: row, column: column ?? order)
    }
    func unregister(_ button: ShelfButton) { entries.removeValue(forKey: ObjectIdentifier(button)) }

    private var available: [Entry] {
        entries.values.filter { $0.button?.isEnabled == true }.sorted { $0.order < $1.order }
    }

    func enter(backwards: Bool) {
        let entries = available
        guard let button = (backwards ? entries.last : entries.first)?.button else { return }
        button.window?.makeFirstResponder(button)
    }
    func moveFocus(from current: ShelfButton, backwards: Bool) {
        let buttons = available.compactMap(\.button)
        guard let index = buttons.firstIndex(where: { $0 === current }) else { return }
        let next = (index + (backwards ? -1 : 1) + buttons.count) % buttons.count
        current.window?.makeFirstResponder(buttons[next])
    }

    func moveFocus(from current: ShelfButton, horizontal: Int, vertical: Int) {
        guard let origin = entries[ObjectIdentifier(current)] else { return }
        let target: Entry?
        if vertical == 0 {
            target = available.filter { $0.row == origin.row && ($0.column - origin.column) * horizontal > 0 }
                .min { abs($0.column - origin.column) < abs($1.column - origin.column) }
        } else {
            target = available.filter { ($0.row - origin.row) * vertical > 0 }.min {
                (abs($0.row - origin.row), abs($0.column - origin.column)) <
                (abs($1.row - origin.row), abs($1.column - origin.column))
            }
        }
        if let button = target?.button { current.window?.makeFirstResponder(button) }
    }
}

/// Native input over the SwiftUI label retains first-click, right-click and VoiceOver button behavior.
private struct ShelfTarget: NSViewRepresentable {
    let label: String
    let help: String
    let enabled: Bool
    let focus: ShelfFocusCoordinator
    let order: Int
    let row: Int
    let column: Int
    let allowsRightClick: Bool
    let action: (Bool) -> Void

    func makeNSView(context: Context) -> ShelfButton {
        let button = ShelfButton()
        button.isBordered = false
        button.title = ""
        button.focusRingType = .none
        button.target = button
        button.action = #selector(ShelfButton.invoke)
        return button
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShelfButton, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 28, height: 28))
    }
    func updateNSView(_ button: ShelfButton, context: Context) {
        button.isEnabled = enabled
        button.toolTip = help.isEmpty ? label : "\(label)\n\(help)"
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp(help)
        button.callback = action
        button.allowsRightClick = allowsRightClick
        button.focusCoordinator = focus
        focus.register(button, order: order, row: row, column: column)
    }
    static func dismantleNSView(_ button: ShelfButton, coordinator: ()) { button.focusCoordinator?.unregister(button) }
}

final class ShelfButton: NSButton {
    var callback: ((Bool) -> Void)?
    weak var focusCoordinator: ShelfFocusCoordinator?
    var allowsRightClick = true
    private var hoverArea: NSTrackingArea?
    private var hovered = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { isEnabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc func invoke() { if isEnabled { callback?(false) } }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), allowsRightClick {
            if isEnabled { callback?(true) }
        } else { super.mouseDown(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) { if isEnabled && allowsRightClick { callback?(true) } }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if event.keyCode == 48, modifiers.subtracting(.shift).isEmpty, let focusCoordinator {
            focusCoordinator.moveFocus(from: self, backwards: modifiers.contains(.shift))
            return
        }
        guard modifiers.isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 123: focusCoordinator?.moveFocus(from: self, horizontal: -1, vertical: 0)
        case 124: focusCoordinator?.moveFocus(from: self, horizontal: 1, vertical: 0)
        case 125: focusCoordinator?.moveFocus(from: self, horizontal: 0, vertical: 1)
        case 126: focusCoordinator?.moveFocus(from: self, horizontal: 0, vertical: -1)
        case 36, 49, 76: if !event.isARepeat { invoke() }
        default: super.keyDown(with: event)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        if let window {
            hovered = visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 6, yRadius: 6)
        if isEnabled && (isHighlighted || hovered) {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.18 : 0.08).setFill()
            path.fill()
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { scrollToVisible(bounds); needsDisplay = true }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }
}
