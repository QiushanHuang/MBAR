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

    private var hidingUnavailable: String? {
        if !model.trusted { return "请先允许辅助功能。" }
        if !model.apiAvailable { return "当前系统无法启用隐藏。" }
        if model.policy.hidden.isEmpty { return "先将应用收入下拉栏或设为始终隐藏。" }
        return nil
    }

    var body: some View {
        let groups = model.groups
        return VStack(alignment: .leading, spacing: 16) {
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

            ScrollView {
                LazyVStack(spacing: 0) {
                    if groups.isEmpty {
                        emptyState
                    }
                    ForEach(Array(groups.enumerated()), id: \.element.bundle) { index, group in
                        if let item = group.items.first {
                            appRow(item, count: group.items.count)
                            if index < groups.count - 1 { Divider().padding(.leading, 54) }
                        }
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: .infinity)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))

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
                Toggle("在下拉栏显示锁定按钮", isOn: Binding(
                    get: { model.shelfLock.showsButton }, set: { model.setShowsShelfLock($0) }))
            }

            if model.trusted, let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
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
            .sheet(isPresented: Binding(get: { model.iconSettingsBundle != nil }, set: { if !$0 { model.iconSettingsBundle = nil } })) {
                if let bundle = model.iconSettingsBundle {
                    IconSettingsView(library: model.iconLibrary, bundle: bundle,
                        name: model.items.first(where: { $0.bundle == bundle })?.name ?? bundle,
                        dismiss: { model.iconSettingsBundle = nil })
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
        }.frame(maxWidth: .infinity, minHeight: 180).padding(24)
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

// Exactly one row. Only the snapshots scroll; the gear always stays at the right.
struct ShelfView: View {
    @ObservedObject var model: AppModel
    let width: CGFloat
    @StateObject private var focus = ShelfFocusCoordinator()
    var body: some View {
        let collected = model.collected
        return HStack(spacing: 2) {
            if !collected.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(collected.enumerated()), id: \.element.id) { index, item in
                            ItemButton(image: model.previews[item.id], name: model.previews[item.id] == nil ? "\(item.name)：请选择图标" : "\(item.name) · \(model.iconLibrary.entry(item.bundle).state.rawValue)",
                                       enabled: !model.capturing, focus: focus, order: index) { right in
                                if model.previews[item.id] == nil { model.configureIcon(item.bundle) }
                                else { model.openItem(item, right: right) }
                            }.frame(width: model.previewWidth(for: item), height: 28)
                        }
                    }.frame(height: 28)
                }.frame(maxWidth: .infinity)
            } else { Spacer(minLength: 0) }
            if model.shelfLock.showsButton {
                ItemButton(image: NSImage(systemSymbolName: model.shelfLock.isLocked ? "lock.fill" : "lock.open", accessibilityDescription: nil),
                           name: model.shelfLock.isLocked ? "解锁下拉栏" : "锁定下拉栏",
                           enabled: true, focus: focus, order: collected.count, allowsRightClick: false) { _ in
                    model.toggleShelfLock()
                }.frame(width: 28, height: 28)
            }
            ItemButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil),
                       name: "MBAR 设置", enabled: true, focus: focus, order: collected.count + 1, allowsRightClick: false) { _ in
                model.showSettings?()
            }.frame(width: 28, height: 28)
        }.padding(.horizontal, 4).frame(width: width, height: ShelfMetrics.height)
    }
}

@MainActor final class ShelfFocusCoordinator: ObservableObject {
    private struct Entry {
        weak var button: ShelfButton?
        var order: Int
    }
    private var entries: [ObjectIdentifier: Entry] = [:]

    func register(_ button: ShelfButton, order: Int) {
        entries[ObjectIdentifier(button)] = Entry(button: button, order: order)
    }
    func unregister(_ button: ShelfButton) { entries.removeValue(forKey: ObjectIdentifier(button)) }
    func moveFocus(from current: ShelfButton, backwards: Bool) {
        let buttons = entries.values.sorted { $0.order < $1.order }.compactMap(\.button).filter(\.isEnabled)
        guard let index = buttons.firstIndex(where: { $0 === current }), !buttons.isEmpty else { return }
        let next = (index + (backwards ? -1 : 1) + buttons.count) % buttons.count
        current.window?.makeFirstResponder(buttons[next])
    }
}

struct ItemButton: NSViewRepresentable {
    let image: NSImage?
    let name: String
    let enabled: Bool
    let focus: ShelfFocusCoordinator
    let order: Int
    var allowsRightClick = true
    let action: (Bool) -> Void
    func makeNSView(context: Context) -> ShelfButton {
        let button = ShelfButton()
        button.isBordered = false; button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly; button.imageScaling = .scaleProportionallyDown
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = button; button.action = #selector(ShelfButton.invoke)
        return button
    }
    func updateNSView(_ button: ShelfButton, context: Context) {
        if let image, let copy = image.copy() as? NSImage {
            let ratio = min(1, 24 / max(1, copy.size.height))
            copy.size = CGSize(width: copy.size.width * ratio, height: copy.size.height * ratio)
            button.image = copy
        } else {
            // Missing artwork opens configuration, never substitutes an application icon.
            button.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "图标待选择")
        }
        button.isEnabled = enabled
        button.toolTip = name.trimmingCharacters(in: .whitespacesAndNewlines)
        button.setAccessibilityLabel(name)
        button.setAccessibilityHelp(name.trimmingCharacters(in: .whitespacesAndNewlines))
        button.callback = action
        button.allowsRightClick = allowsRightClick
        button.focusCoordinator = focus
        focus.register(button, order: order)
    }
    static func dismantleNSView(_ button: ShelfButton, coordinator: ()) { button.focusCoordinator?.unregister(button) }
}
final class ShelfButton: NSButton {
    var callback: ((Bool) -> Void)?
    weak var focusCoordinator: ShelfFocusCoordinator?
    var allowsRightClick = true
    override var acceptsFirstResponder: Bool { isEnabled }
    @objc func invoke() { guard isEnabled else { return }; callback?(NSApp.currentEvent?.type == .rightMouseUp) }
    override func rightMouseDown(with event: NSEvent) { if isEnabled && allowsRightClick { callback?(true) } }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 48, modifiers.subtracting([.shift, .capsLock]).isEmpty, let focusCoordinator {
            focusCoordinator.moveFocus(from: self, backwards: event.modifierFlags.contains(.shift))
        } else { super.keyDown(with: event) }
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { scrollToVisible(bounds) }
        return accepted
    }
}
