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
    @State private var confirmsDismiss = false
    @State private var confirmsUndo = false
    @State private var needsCaptureAuthorization = false
    @State private var resetDetails = ""
    private var entry: IconEntry { library.entry(bundle) }
    private var hasDraft: Bool { selected != nil || imported != nil || native != nil }
    private var preview: NSImage? {
        if let native { return IconLibrary.image(native.prepared.image.png, mode: mode) }
        if let imported { return IconLibrary.image(imported.png, mode: mode) }
        if let selected { return IconLibrary.image(selected.image.png, mode: mode) }
        return entry.image
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("\(name) 的图标").font(.title2.bold()).lineLimit(1)
                Spacer()
                Button("关闭", action: requestDismiss).keyboardShortcut(.cancelAction).disabled(working)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(hasDraft ? "预览 · 未保存" : "当前图标").font(.headline)
                    InfoButton(label: "图标预览说明", detail: "下拉栏使用静态图像，不反映连接状态或实时数值。")
                }
                HStack(spacing: 10) {
                    sample(dark: false)
                    sample(dark: true)
                    Spacer(minLength: 0)
                }
                if hasDraft {
                    HStack {
                        Text("显示方式")
                        Picker("显示方式", selection: $mode) {
                            Text("保留原色").tag(IconDisplayMode.original)
                            Text("随菜单栏着色").tag(IconDisplayMode.template)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 250)
                    }
                }
            }

            HStack {
                Text("候选图标").font(.headline)
                Spacer()
                if entry.scanning {
                    ProgressView().controlSize(.small)
                    Button("取消扫描") { library.stopScan(bundle) }.disabled(working)
                } else {
                    Button { library.scanCandidates(bundle, force: true) } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }.disabled(working)
                }
            }
            HStack(spacing: 8) {
                Button("导入图片…", action: importFile).disabled(working || entry.state == .multiple)
                Button("读取当前原生图标", action: captureNative)
                    .disabled(working || !library.canCaptureNative(bundle))
                InfoButton(label: "读取原生图标说明", detail: "读取系统菜单栏中当前可见的图标，需要屏幕录制权限。保存后使用静态快照。")
                Spacer()
            }
            ScrollView {
                if entry.candidates.isEmpty {
                    Text(entry.scanning ? "正在寻找图标…" : (entry.state == .multiple ? "同一应用的多个菜单图标暂不支持单独适配。" : "没有找到候选图标。可导入图片或读取原生图标。"))
                        .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 110).padding(16)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(entry.candidates) { candidate in
                            Button {
                                selected = candidate; imported = nil; native = nil; mode = candidate.suggestedMode; message = nil
                            } label: {
                                VStack(spacing: 8) {
                                    if let image = IconLibrary.image(candidate.image.png, mode: candidate.suggestedMode) {
                                        Image(nsImage: image).resizable().scaledToFit().frame(width: 36, height: 28)
                                    }
                                    Text(URL(fileURLWithPath: candidate.evidence.path).lastPathComponent)
                                        .font(.caption).lineLimit(2).frame(height: 30)
                                }.frame(maxWidth: .infinity, minHeight: 84).padding(10)
                                    .background(selected?.id == candidate.id ? Color.teal.opacity(0.13) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected?.id == candidate.id ? Color.teal : .clear, lineWidth: 1.5))
                                    .overlay(alignment: .topTrailing) {
                                        HStack(spacing: 4) {
                                            if candidate.evidence.ambiguousVariant {
                                                Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                                            }
                                            if selected?.id == candidate.id {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
                                            }
                                        }.padding(7)
                                    }
                            }.buttonStyle(.plain)
                                .help(candidate.locator.label + (candidate.evidence.ambiguousVariant ? " · 状态或主题变体，请确认" : ""))
                                .accessibilityLabel("选择图标 \(candidate.evidence.path)\(candidate.evidence.ambiguousVariant ? "，状态或主题变体，请确认" : "")")
                                .accessibilityValue(selected?.id == candidate.id ? "已选择" : "未选择")
                                .disabled(working)
                        }
                    }.padding(2)
                }
            }.frame(height: needsCaptureAuthorization ? 110 : 180)
            if !entry.message.isEmpty { Text(entry.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if needsCaptureAuthorization {
                VStack(alignment: .leading, spacing: 8) {
                    Text("允许 MBAR 读取菜单栏画面").font(.subheadline.bold())
                    Text("在系统设置中允许屏幕录制后重试。若已允许但仍失败，请重启 MBAR。")
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
                Text(error).font(.caption).foregroundStyle(error == "已保存" ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if selected != nil || (!hasDraft && (!entry.source.isEmpty || entry.mapping != nil)) {
                DisclosureGroup("来源详情") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected?.locator.label ?? entry.source).textSelection(.enabled)
                        if !hasDraft, let mapping = entry.mapping {
                            Text("选择时应用版本：\(mapping.identity.shortVersion) (\(mapping.identity.version))")
                            Text("\(mapping.origin == .nativeSnapshot ? "采集时间" : "选择时间")：\(mapping.selectedAt.formatted())")
                        }
                        if !hasDraft, entry.mapping?.origin == .automatic {
                            Text("自动匹配依据资源名称与图像特征，尚未验证与原生图标完全一致。")
                        }
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            HStack {
                if library.hasOverride(bundle) || library.canUndo(bundle) {
                    Menu("更多操作") {
                        if library.hasOverride(bundle) {
                            Button("恢复自动匹配…") {
                                working = true
                                Task { @MainActor in
                                    resetDetails = await library.fallbackDescription(bundle)
                                    working = false; confirmsReset = true
                                }
                            }
                        }
                        if library.canUndo(bundle) {
                            Button("撤销上次修改") {
                                if hasDraft { confirmsUndo = true }
                                else { perform { try library.undo(bundle) } }
                            }
                        }
                    }.disabled(working)
                }
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button(native != nil ? "使用原生快照" : (imported == nil ? "使用此图标" : "使用自定义图片"), action: save)
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(working || !hasDraft || library.storageError != nil)
            }
        }.padding(22).frame(width: 600)
            .interactiveDismissDisabled(hasDraft || working)
            .onAppear { library.scanCandidates(bundle) }
            .alert("恢复自动匹配？", isPresented: $confirmsReset) {
                Button("取消", role: .cancel) {}
                Button("恢复") { perform { try library.reset(bundle) } }
            } message: {
                Text(resetDetails + "\n将移除当前保存的选择，可撤销。" + (hasDraft ? "当前未保存的选择也会被放弃。" : ""))
            }
            .alert("放弃未保存的图标？", isPresented: $confirmsDismiss) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃", role: .destructive, action: dismiss)
            } message: {
                Text("当前选择尚未保存，关闭后将丢失。")
            }
            .alert("撤销上次修改？", isPresented: $confirmsUndo) {
                Button("取消", role: .cancel) {}
                Button("撤销") { perform { try library.undo(bundle) } }
            } message: {
                Text("将撤销上次保存的修改，并放弃当前未保存的选择。")
            }
    }
    private func requestDismiss() {
        if hasDraft { confirmsDismiss = true } else { dismiss() }
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
            .accessibilityElement(children: .ignore)
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
                selected = nil; imported = nil; native = nil; message = "已保存"
            } catch { message = error.localizedDescription }
        }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); selected = nil; imported = nil; native = nil; message = nil }
        catch { message = error.localizedDescription }
    }
}
