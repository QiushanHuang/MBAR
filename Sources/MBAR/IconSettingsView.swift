import SwiftUI
import UniformTypeIdentifiers
import MBARCore

struct IconSettingsView: View {
    @ObservedObject var library: IconLibrary
    let bundle: String
    let name: String
    let dismiss: () -> Void
    @State private var selected: IconCandidate?
    @State private var imported: IconDecodedImage?
    @State private var native: NativeIconPreview?
    @State private var mode: IconDisplayMode = .original
    @State private var working = false
    @State private var message: String?
    @State private var confirmsReset = false
    @State private var needsCaptureAuthorization = false
    @State private var resetDetails = ""
    private var entry: IconEntry { library.entry(bundle) }
    private var preview: NSImage? {
        if let native { return IconLibrary.image(native.prepared.image.png, mode: mode) }
        if let imported { return IconLibrary.image(imported.png, mode: mode) }
        if let selected { return IconLibrary.image(selected.image.png, mode: mode) }
        return entry.image
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(name) 的菜单图标").font(.title3.bold())
                    Text(entry.state.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成", action: dismiss).keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 12) {
                sample(dark: false)
                sample(dark: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(native != nil ? "原生图标预览" : (imported != nil ? "自定义图片预览" : (selected != nil ? "候选预览" : "当前图标"))).font(.subheadline)
                    Text("静态图片；不代表应用实时状态。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if selected != nil || imported != nil || native != nil {
                Picker("显示方式", selection: $mode) {
                    Text("保留原色").tag(IconDisplayMode.original)
                    Text("随菜单栏着色").tag(IconDisplayMode.template)
                }.pickerStyle(.segmented)
            }
            HStack {
                Text("可用候选").font(.headline)
                Spacer()
                Button("读取当前原生图标", action: captureNative)
                    .disabled(working || !library.canCaptureNative(bundle))
                    .help("仅读取已经可见的菜单图标，不展开系统栏。需要屏幕录制权限。")
                if entry.scanning {
                    ProgressView().controlSize(.small)
                    Button("取消扫描") { library.stopScan(bundle) }
                } else {
                    Button("重新扫描") { selected = nil; imported = nil; native = nil; library.scanCandidates(bundle, force: true) }
                }
            }
            Text("原生取图会采集当前可见菜单图标的画面；预览并保存后，折叠时可继续显示这张静态快照。")
                .font(.caption2).foregroundStyle(.secondary)
            ScrollView {
                if entry.candidates.isEmpty {
                    Text(entry.scanning ? "正在应用资源中寻找菜单图标…" : (entry.state == .multiple ? "多个菜单项目暂不支持自动匹配。" : "没有找到可用候选，可以导入图片或继续常驻菜单栏。"))
                        .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 144), spacing: 8)], spacing: 8) {
                        ForEach(entry.candidates) { candidate in
                            Button {
                                selected = candidate; imported = nil; native = nil; mode = candidate.suggestedMode; message = nil
                            } label: {
                                VStack(spacing: 7) {
                                    if let image = IconLibrary.image(candidate.image.png, mode: candidate.suggestedMode) {
                                        Image(nsImage: image).resizable().scaledToFit().frame(width: 36, height: 28)
                                    }
                                    Text(URL(fileURLWithPath: candidate.evidence.path).lastPathComponent)
                                        .font(.caption).lineLimit(2).frame(height: 30)
                                    Text("\(candidate.image.width) × \(candidate.image.height)").font(.caption2).foregroundStyle(.secondary)
                                    Text(candidate.evidence.ambiguousVariant ? "状态或主题变体 · 请确认" : (candidate.evidence.strongName ? "名称与菜单图标相关" : "需手动确认"))
                                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth: .infinity).padding(10)
                                    .background(selected?.id == candidate.id ? Color.teal.opacity(0.13) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected?.id == candidate.id ? Color.teal : .clear, lineWidth: 1.5))
                            }.buttonStyle(.plain).help(candidate.locator.label)
                                .accessibilityLabel("选择图标 \(candidate.evidence.path)")
                                .accessibilityValue(selected?.id == candidate.id ? "已选择" : "未选择")
                                .disabled(working)
                        }
                    }.padding(2)
                }
            }.frame(height: needsCaptureAuthorization ? 125 : 218)
            if !entry.message.isEmpty { Text(entry.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if needsCaptureAuthorization {
                VStack(alignment: .leading, spacing: 8) {
                    Text("允许 MBAR 读取菜单栏画面").font(.subheadline.bold())
                    Text("在系统设置的“屏幕与系统音频录制”中开启 MBAR，然后重新读取。若开关已开但仍失败，请重启 MBAR。资源图标读取不需要此权限。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("打开屏幕录制设置") { ScreenCaptureAccess.shared.openSettings() }
                        Button("重新检查并读取", action: captureNative).disabled(working)
                        if AppRelauncher.available {
                            Button("重启 MBAR") {
                                do { try AppRelauncher.restart(iconBundle: bundle) }
                                catch { message = error.localizedDescription }
                            }.disabled(working)
                        }
                    }
                }.padding(12).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
            if !needsCaptureAuthorization, let error = message ?? library.storageError {
                Text(error).font(.caption).foregroundStyle(error == "已保存，可撤销上次修改。" ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("来源详情") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected?.locator.label ?? entry.source).textSelection(.enabled)
                    if let mapping = entry.mapping {
                        Text("选择时应用版本：\(mapping.identity.shortVersion) (\(mapping.identity.version))")
                        Text("\(mapping.origin == .nativeSnapshot ? "采集时间" : "选择时间")：\(mapping.selectedAt.formatted())")
                    }
                    Text("自动匹配依据资源名称与图像特征，尚未验证与原生图标完全一致。")
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("导入图片…", action: importFile).disabled(working || entry.state == .multiple)
                if library.hasOverride(bundle) {
                    Button("恢复自动匹配…") {
                        working = true
                        Task { @MainActor in
                            resetDetails = await library.fallbackDescription(bundle)
                            working = false; confirmsReset = true
                        }
                    }.disabled(working)
                }
                if library.canUndo(bundle) {
                    Button("撤销上次修改") { perform { try library.undo(bundle) } }.disabled(working)
                }
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button(native != nil ? "使用原生快照" : (imported == nil ? "使用此图标" : "使用自定义图片"), action: save)
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(working || (selected == nil && imported == nil && native == nil) || library.storageError != nil)
            }
        }.padding(22).frame(width: 570)
            .onAppear { library.scanCandidates(bundle) }
            .alert("恢复自动匹配？", isPresented: $confirmsReset) {
                Button("取消", role: .cancel) {}
                Button("恢复") { perform { try library.reset(bundle) } }
            } message: {
                Text(resetDetails + "\n将移除当前用户选择，保存后可撤销。")
            }
    }
    private func sample(dark: Bool) -> some View {
        HStack(spacing: 16) {
            if let preview {
                Image(nsImage: preview).frame(width: 30, height: 28)
                Image(nsImage: preview).resizable().scaledToFit().frame(width: 48, height: 44)
            } else { Image(systemName: "circle.dotted").frame(width: 94, height: 44) }
        }.foregroundStyle(dark ? .white : .black).padding(10)
            .background(dark ? Color(white: 0.14) : Color(white: 0.94), in: RoundedRectangle(cornerRadius: 9))
            .environment(\.colorScheme, dark ? .dark : .light)
            .accessibilityLabel(dark ? "深色背景图标预览" : "浅色背景图标预览")
    }
    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .tiff, .jpeg]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            working = true; message = nil
            Task { @MainActor in
                defer { working = false }
                do { imported = try await library.importImage(url); selected = nil; native = nil; mode = .original }
                catch { message = error.localizedDescription }
            }
        }
    }
    private func captureNative() {
        working = true; message = nil
        Task { @MainActor in
            defer { working = false }
            do {
                let result = try await library.nativePreview(bundle)
                native = result; selected = nil; imported = nil; mode = result.prepared.mode; needsCaptureAuthorization = false
            } catch {
                needsCaptureAuthorization = ScreenCaptureAccess.isPermissionDenied(error)
                message = needsCaptureAuthorization ? "macOS 尚未允许当前 MBAR 进程采集菜单栏画面。" : error.localizedDescription
            }
        }
    }
    private func save() {
        working = true; message = nil
        Task { @MainActor in
            defer { working = false }
            do {
                if let native { try library.saveNative(native, mode: mode, bundle: bundle) }
                else if let imported { try library.saveImport(imported, mode: mode, bundle: bundle) }
                else if let selected { try await library.choose(selected, mode: mode, bundle: bundle) }
                selected = nil; imported = nil; native = nil; message = "已保存，可撤销上次修改。"
            } catch { message = error.localizedDescription }
        }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); selected = nil; imported = nil; native = nil; message = nil }
        catch { message = error.localizedDescription }
    }
}
