import SwiftUI
import AppKit
import MBARCore

private extension ItemCategory {
    var title: String {
        switch self { case .visible: return "常驻菜单栏"; case .automatic: return "自动隐藏"; case .always: return "总是隐藏" }
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "menubar.dock.rectangle").font(.system(size: 30, weight: .light)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MBAR").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("真实图标，一排收好").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            if !model.trusted {
                permissionCard("允许辅助功能", detail: "读取菜单栏项目，并在点击时打开原来的菜单。", button: "打开辅助功能设置", action: model.requestAccessibility)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("自动隐藏").fontWeight(.medium) + Text(" · 点击箭头后在下拉栏显示").foregroundColor(.secondary)
                Text("总是隐藏").fontWeight(.medium) + Text(" · 不进入下拉栏，只在这里临时打开").foregroundColor(.secondary)
            }.font(.caption)
            Toggle("在下拉栏显示锁定按钮", isOn: Binding(
                get: { model.shelfLock.showsButton }, set: { model.setShowsShelfLock($0) }))
                .font(.caption)
            HStack {
                Text("菜单栏应用").font(.headline)
                Spacer()
                if model.refreshing || model.capturing { ProgressView().controlSize(.small) }
                Button { model.refreshContents() } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(model.refreshing)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.groups.isEmpty {
                        Text(model.trusted ? "没有可读取的菜单栏应用" : "辅助功能授权后会显示应用列表")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(25)
                    }
                    ForEach(model.groups, id: \.bundle) { group in
                        if let item = group.items.first {
                            HStack(spacing: 10) {
                                Image(nsImage: model.settingsIcon(for: item)).resizable().scaledToFit().frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    if group.items.count > 1 { Text("\(group.items.count) 个图标一起隐藏").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 4)
                                if model.policy.category(group.bundle) != .visible {
                                    Button { model.openItem(item, right: false, fromSettings: true) } label: { Image(systemName: "arrow.up.forward.square") }
                                        .help("临时打开 \(item.name) 的菜单").accessibilityLabel("临时打开 \(item.name)")
                                }
                                Picker("\(item.name) 的显示方式", selection: Binding(get: { model.policy.category(group.bundle) }, set: { model.setCategory(group.bundle, $0) })) {
                                    ForEach(ItemCategory.allCases, id: \.self) { category in Text(category.title).tag(category) }
                                }.labelsHidden().pickerStyle(.menu).frame(width: 118)
                            }.padding(.horizontal, 12).padding(.vertical, 9)
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }.frame(minHeight: 120, maxHeight: 240).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Toggle("启用隐藏", isOn: Binding(get: { model.hideRequested }, set: { model.enableHiding($0) }))
                    .disabled(!model.trusted || !model.apiAvailable || model.policy.hidden.isEmpty)
                Text("实验功能").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("显示全部（暂停）") { model.restoreAll() }
            }
            Text("macOS 27 的隐藏接口可能暂时影响部分系统附加项或点击时钟打开通知中心。遇到影响时，点“显示全部”恢复。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("原始图标不反映实时连接或运行状态；应用自绘图表未通用支持。Clash 数值在展开时读取一次。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("原始菜单图标 · 静态资源 · 不展开系统栏").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("退出 MBAR") { NSApp.terminate(nil) }
                Button("打开下拉栏") { (NSApp.delegate as? AppDelegate)?.toggleShelf() }.buttonStyle(.borderedProminent).tint(.teal)
            }
        }.padding(24).frame(width: 580).background(Color(nsColor: .windowBackgroundColor))
    }
    private func permissionCard(_ title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(button, action: action).buttonStyle(.borderedProminent).tint(.teal)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// Exactly one row. Only the snapshots scroll; the gear always stays at the right.
struct ShelfView: View {
    @ObservedObject var model: AppModel
    let width: CGFloat
    var body: some View {
        HStack(spacing: 2) {
            if !model.collected.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(model.collected, id: \.id) { item in
                            ItemButton(image: model.previews[item.id], name: item.name,
                                       enabled: model.previews[item.id] != nil && !model.capturing) { right in
                                model.openItem(item, right: right)
                            }.frame(width: model.previewWidth(for: item), height: 28)
                        }
                    }.frame(height: 28)
                }.frame(maxWidth: .infinity)
            } else { Spacer(minLength: 0) }
            if model.shelfLock.showsButton {
                Button { model.toggleShelfLock() } label: {
                    Image(systemName: model.shelfLock.isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 16, weight: .regular)).frame(width: 28, height: 28)
                }.buttonStyle(.plain).focusEffectDisabled()
                    .help(model.shelfLock.isLocked ? "解锁下拉栏" : "锁定下拉栏")
                    .accessibilityLabel(model.shelfLock.isLocked ? "解锁下拉栏" : "锁定下拉栏")
            }
            Button { model.showSettings?() } label: {
                Image(systemName: "gearshape").font(.system(size: 17, weight: .regular)).frame(width: 28, height: 28)
            }.buttonStyle(.plain).focusEffectDisabled().help("MBAR 设置").accessibilityLabel("MBAR 设置")
        }.padding(.horizontal, 4).frame(width: width, height: ShelfMetrics.height)
    }
}
struct ItemButton: NSViewRepresentable {
    let image: NSImage?
    let name: String
    let enabled: Bool
    let action: (Bool) -> Void
    func makeNSView(context: Context) -> ShelfButton {
        let button = ShelfButton()
        button.isBordered = false; button.bezelStyle = .regularSquare
        button.focusRingType = .none
        button.cell?.focusRingType = .none
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
            // Neutral missing-snapshot state, never an application's icon.
            button.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "快照未就绪")
        }
        button.isEnabled = enabled
        button.toolTip = name.trimmingCharacters(in: .whitespacesAndNewlines)
        button.setAccessibilityLabel(name)
        button.setAccessibilityHelp(name.trimmingCharacters(in: .whitespacesAndNewlines))
        button.callback = action
    }
}
final class ShelfButton: NSButton {
    var callback: ((Bool) -> Void)?
    @objc func invoke() { guard isEnabled else { return }; callback?(NSApp.currentEvent?.type == .rightMouseUp) }
    override func rightMouseDown(with event: NSEvent) { if isEnabled { callback?(true) } }
}
