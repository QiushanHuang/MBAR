import AppKit
import MBARCore
import SwiftUI

private extension ShelfMaterial {
    var title: String {
        switch self {
        case .translucent: return "半透明"
        case .frosted: return "毛玻璃"
        case .liquid: return "柔光玻璃"
        case .appleGlass: return "苹果液态玻璃"
        case .quietGlass: return "静透玻璃"
        }
    }
}

private extension ShelfTint {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    init?(color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }
}

struct ShelfAppearanceSettings: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var namingCopy = false
    @State private var deletingPreset: ShelfAppearancePreset?

    private var activePreset: ShelfAppearancePreset? {
        model.shelfPresets.first { $0.id == model.selectedShelfPresetID }
    }
    private var isModified: Bool { activePreset?.appearance != model.shelfAppearance }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("下拉栏外观").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            preview
            presetSection
            Divider()
            controls
        }
        .padding(22)
        .frame(width: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("删除这个预设？", isPresented: Binding(get: { deletingPreset != nil }, set: { if !$0 { deletingPreset = nil } }),
               presenting: deletingPreset) { preset in
            Button("删除", role: .destructive) { model.deleteShelfPreset(preset.id) }
            Button("取消", role: .cancel) {}
        } message: { preset in
            Text("将从我的预设中移除「\(preset.name)」。")
        }
    }

    private var preview: some View {
        ZStack {
            // Sharp tonal boundaries behind the sampler make the difference between tint and blur visible.
            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size)
                context.fill(Path(bounds), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.24, green: 0.32, blue: 0.43), Color(red: 0.67, green: 0.79, blue: 0.77)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                var ridge = Path()
                ridge.move(to: CGPoint(x: 0, y: size.height * 0.86))
                ridge.addQuadCurve(to: CGPoint(x: size.width, y: size.height * 0.14),
                                   control: CGPoint(x: size.width * 0.46, y: size.height * 0.58))
                ridge.addLine(to: CGPoint(x: size.width, y: size.height))
                ridge.addLine(to: CGPoint(x: 0, y: size.height))
                ridge.closeSubpath()
                context.fill(ridge, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.73, green: 0.65, blue: 0.54), Color(red: 0.30, green: 0.44, blue: 0.52)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                // Small silhouetted branches provide detail to refract through clear glass.
                let pine = Color(red: 0.16, green: 0.27, blue: 0.31)
                var hillside = Path()
                hillside.move(to: CGPoint(x: 0, y: size.height))
                for i in 0..<36 {
                    let x = size.width * CGFloat(i) / 35
                    let ground = size.height * (0.76 + 0.07 * sin(Double(i) * 0.14) - 0.08 * cos(Double(i) * 0.11))
                    hillside.addLine(to: CGPoint(x: x, y: ground))
                    let height = size.height * (0.37 + 0.14 * cos(Double(i) * 1.87))
                    let slope = ground - height * 0.80
                    var tree = Path()
                    for tier in 1...3 {
                        let top = slope + height * CGFloat(tier - 1) * 0.15
                        let base = top + height * 0.54
                        let halfWidth = height * CGFloat(tier + 1) * 0.06
                        tree.move(to: CGPoint(x: x, y: top))
                        tree.addLine(to: CGPoint(x: x - halfWidth, y: base))
                        tree.addLine(to: CGPoint(x: x + halfWidth, y: base))
                        tree.closeSubpath()
                    }
                    context.fill(tree, with: .color(pine))
                }
                hillside.addLine(to: CGPoint(x: size.width, y: size.height))
                hillside.closeSubpath()
                context.fill(hillside, with: .color(pine))
            }
            let sample = ShelfMaterialSample(model: model)
            sample.frame(width: sample.size.width, height: sample.size.height)
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("下拉栏材质预览")
        .accessibilityValue(model.shelfAppearance.material.title)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("预设").font(.headline)
                if isModified { Text("已调整").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if let preset = activePreset, preset.isCustom {
                    Button("更新此预设") { model.updateShelfPreset(preset.id) }
                        .disabled(!isModified)
                    Button { deletingPreset = preset } label: {
                        Image(systemName: "trash")
                    }
                    .help("删除当前预设")
                    .accessibilityLabel("删除当前预设")
                }
                Button("存为新预设…") { namingCopy = true }
                    .popover(isPresented: $namingCopy, arrowEdge: .bottom) {
                        PresetNameEditor(name: suggestedCopyName, existingNames: model.shelfPresets.map(\.name),
                                         cancel: { namingCopy = false }, save: { name in
                            model.saveShelfPreset(named: name)
                            namingCopy = false
                        })
                    }
            }
            .controlSize(.small)

            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(model.shelfPresets, id: \.id) { preset in
                            let selected = model.selectedShelfPresetID == preset.id
                            Button {
                                model.selectShelfPreset(preset.id)
                            } label: {
                                HStack(spacing: 7) {
                                    Circle().fill(preset.appearance.tint.color)
                                        .overlay(Circle().strokeBorder(.primary.opacity(0.22), lineWidth: 1))
                                        .frame(width: 14, height: 14)
                                    Text(preset.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if selected { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Color.accentColor) }
                                }
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045),
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(preset.name + " · " + preset.appearance.material.title)
                            .accessibilityLabel(preset.name)
                            .accessibilityValue(preset.appearance.material.title)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(2)
                }
                .frame(height: CGFloat(min(3, (model.shelfPresets.count + 2) / 3)) * 34)
                .onChange(of: model.selectedShelfPresetID) { _, id in reader.scrollTo(id) }
                .onAppear { reader.scrollTo(model.selectedShelfPresetID) }
            }
        }
    }

    private var suggestedCopyName: String {
        let base = (activePreset?.name ?? "外观") + " 副本"
        let names = Set(model.shelfPresets.map(\.name))
        var candidate = base
        var suffix = 2
        while names.contains(candidate) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private var controls: some View {
        let current = model.shelfAppearance
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                Text("材质")
                Picker("材质", selection: Binding(get: { model.shelfAppearance.material }, set: { material in
                    var appearance = model.shelfAppearance
                    appearance.material = material
                    model.setShelfAppearance(appearance)
                })) {
                    ForEach(ShelfMaterial.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            GridRow {
                Text("颜色")
                HStack(spacing: 8) {
                    ColorPicker("选择着色颜色", selection: Binding(get: { model.shelfAppearance.tint.color }, set: { color in
                        guard let tint = ShelfTint(color: color) else { return }
                        var appearance = model.shelfAppearance
                        appearance.tint = tint
                        if appearance.intensity == 0 { appearance.intensity = 0.35 }
                        model.setShelfAppearance(appearance)
                    }), supportsOpacity: false)
                    .labelsHidden()
                    Spacer()
                    if isModified {
                        Button("还原为预设") { model.selectShelfPreset(model.selectedShelfPresetID) }.controlSize(.small)
                    }
                }
            }
            adjustment("着色强度", value: \.intensity, range: 0...1)
            if current.material.usesGlassForeground {
                adjustment("磨砂强度", value: \.frostAmount, range: 0...1)
                GridRow {
                    Text("前景颜色")
                    Picker("前景颜色", selection: Binding(get: { model.shelfAppearance.iconTreatment }, set: { treatment in
                        var appearance = model.shelfAppearance
                        appearance.iconTreatment = treatment
                        model.setShelfAppearance(appearance)
                    })) {
                        Text("随背景").tag(ShelfIconTreatment.automatic)
                        Text("跟随系统").tag(ShelfIconTreatment.system)
                        Text("固定黑色").tag(ShelfIconTreatment.darkInk)
                        Text("固定白色").tag(ShelfIconTreatment.lightInk)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .help("随背景按每个项目下方的明暗选色。跟随系统在浅色外观用黑色、深色外观用白色。彩色原图保留原色。")
                }
            }
            if current.material == .translucent {
                adjustment("背景不透明度", value: \.opacity, range: 0.25...1)
            }
        }
    }
    private func adjustment(_ label: String, value key: WritableKeyPath<ShelfAppearance, Double>,
                            range: ClosedRange<Double>) -> some View {
        let percent = model.shelfAppearance[keyPath: key].formatted(.percent)
        return GridRow {
            Text(label)
            HStack {
                ShelfValueSlider(label: label, range: range, value: model.shelfAppearance[keyPath: key]) { value in
                    var appearance = model.shelfAppearance
                    appearance[keyPath: key] = (value * 100).rounded() / 100
                    model.setShelfAppearance(appearance)
                }
                .frame(maxWidth: .infinity)
                Text(percent)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

private struct PresetNameEditor: View {
    @State var name: String
    let existingNames: [String]
    let cancel: () -> Void
    let save: (String) -> Void
    @FocusState private var nameHasFocus: Bool

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let duplicate = existingNames.contains { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        let canSave = !trimmed.isEmpty && !duplicate
        return VStack(alignment: .leading, spacing: 10) {
            Text("新预设名称").font(.headline)
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameHasFocus)
                .onSubmit { if canSave { save(trimmed) } }
            if duplicate { Text("该名称已被使用").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("保存") { save(trimmed) }.keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(14)
        .frame(width: 230)
        .onAppear { nameHasFocus = true }
    }

}

/// Programmatic value updates only move the thumb. AppKit sends actions for user edits.
struct ShelfValueSlider: NSViewRepresentable {
    let label: String
    let range: ClosedRange<Double>
    let value: Double
    var keyboardStep: Double = 0.01
    let changed: (Double) -> Void

    final class Coordinator: NSObject {
        var changed: ((Double) -> Void)?
        @objc func slide(_ sender: NSSlider) { changed?(sender.doubleValue) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSSlider {
        let slider = ShelfAdjustmentSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: context.coordinator, action: #selector(Coordinator.slide))
        slider.keyboardStep = keyboardStep
        slider.isContinuous = true
        slider.setAccessibilityLabel(label)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.changed = changed
        slider.doubleValue = value
        slider.setAccessibilityValueDescription(value.formatted(.percent))
    }
}

private final class ShelfAdjustmentSlider: NSSlider {
    var keyboardStep = 0.01
    override func keyDown(with event: NSEvent) {
        let direction: Double
        switch event.keyCode {
        case 123, 125: direction = -1
        case 124, 126: direction = 1
        default: super.keyDown(with: event); return
        }
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        guard flags.isEmpty else { super.keyDown(with: event); return }
        let step = event.modifierFlags.contains(.shift) ? max(0.10, keyboardStep) : keyboardStep
        doubleValue = min(maxValue, max(minValue, doubleValue + direction * step))
        sendAction(action, to: target)
    }
}

private struct ShelfMaterialSample: NSViewRepresentable {
    @ObservedObject var model: AppModel

    private static let symbols = ["moon.fill", "waveform", "headphones", "display"]
    private static let artwork = CGSize(width: ShelfMetrics.referenceIconHeight, height: ShelfMetrics.referenceIconHeight)
    var size: CGSize {
        let cellWidth = ShelfMetrics.itemWidth(Self.artwork, scale: model.shelfIconScale)
        return ShelfMetrics.size(style: .strip, itemWidths: Array(repeating: cellWidth, count: Self.symbols.count),
                                 available: CGSize(width: 420, height: 80), showsLock: model.shelfLock.showsButton,
                                 scale: model.shelfIconScale, tallestGlyphHeight: Self.artwork.height * model.shelfIconScale)
    }

    func makeNSView(context: Context) -> ShelfBackdrop {
        let content = NSHostingView(rootView: SampleIcons(model: model))
        return ShelfBackdrop(frame: .zero, configuration: model.shelfAppearance, content: content, blendingMode: .withinWindow)
    }

    func updateNSView(_ backdrop: ShelfBackdrop, context: Context) {
        backdrop.apply(model.shelfAppearance)
    }

    private struct SampleIcons: View {
        @ObservedObject var model: AppModel
        private var glass: Bool { model.shelfAppearance.material.usesGlassForeground }

        var body: some View {
            let glyph = ShelfMetrics.glyphSize(ShelfMaterialSample.artwork, scale: model.shelfIconScale)
            let cellWidth = ShelfMetrics.itemWidth(ShelfMaterialSample.artwork, scale: model.shelfIconScale)
            HStack(spacing: 2) {
                if model.shelfToolsSide == .left {
                    tools
                    Divider().frame(height: 16)
                }
                HStack(spacing: 4) {
                    ForEach(ShelfMaterialSample.symbols, id: \.self) { symbol in
                        ShelfGlyph(systemName: symbol, onClearGlass: glass, treatment: model.shelfAppearance.iconTreatment)
                            .frame(width: glyph.width, height: glyph.height)
                            .frame(width: cellWidth)
                    }
                }
                .frame(maxWidth: .infinity)
                if model.shelfToolsSide == .right {
                    Divider().frame(height: 16)
                    tools
                }
            }
            .padding(.horizontal, ShelfMetrics.stripInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .shelfInkSurface(clearGlass: glass, treatment: model.shelfAppearance.iconTreatment)
        }

        @ViewBuilder var tools: some View {
            if model.shelfLock.showsButton {
                ShelfGlyph(systemName: "lock.open", onClearGlass: glass, treatment: model.shelfAppearance.iconTreatment)
                    .frame(width: 14, height: 14).frame(width: 28, height: 28)
            }
            ShelfGlyph(systemName: "gearshape", onClearGlass: glass, treatment: model.shelfAppearance.iconTreatment)
                .frame(width: 14, height: 14).frame(width: 28, height: 28)
        }
    }
}
