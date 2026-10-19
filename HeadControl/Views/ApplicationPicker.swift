import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ApplicationTargetLabel: View {
    let target: ApplicationTarget
    var size: CGFloat = 16
    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: target.path)).resizable().frame(width: size, height: size)
            Text(target.name).fixedSize(horizontal: false, vertical: true)
        }
        .help(target.path)
        .accessibilityElement(children: .combine)
    }
}

struct ApplicationPicker: View {
    let gesture: Gesture
    var initialTarget: ApplicationTarget?
    var select: (ApplicationTarget) -> Void
    var cancel: () -> Void
    @State private var applications: [ApplicationTarget] = []
    @State private var query = ""
    @State private var selected: ApplicationTarget?
    @State private var loading = true
    @State private var error: String?
    @State private var panel: NSOpenPanel?
    @FocusState private var searchFocused: Bool

    private var filtered: [ApplicationTarget] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? applications : applications.filter {
            $0.name.localizedStandardContains(text) || ($0.bundleIdentifier?.localizedStandardContains(text) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("选择应用").font(.headline)
                Text("\(gesture.title) → 切换到应用").font(.callout).foregroundStyle(.secondary)
            }
            TextField("搜索已安装应用", text: $query).textFieldStyle(.roundedBorder)
                .focused($searchFocused).accessibilityLabel("搜索已安装应用")
            Group {
                if loading {
                    ProgressView("正在查找应用…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(selection: Binding(get: { selected?.id }, set: { id in selected = applications.first { $0.id == id } })) {
                        ForEach(filtered) { target in
                            VStack(alignment: .leading, spacing: 3) {
                                ApplicationTargetLabel(target: target, size: 24).font(.body)
                                if applications.contains(where: { $0.name == target.name && $0.id != target.id }) {
                                    Text(target.path).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(2).truncationMode(.middle).padding(.leading, 29)
                                }
                            }
                            .padding(.vertical, 3).tag(target.id)
                        }
                    }
                    .listStyle(.inset).accessibilityLabel("已安装应用")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            if let error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Text("选择期间暂停头势执行，关闭后恢复原状态。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("选择其他应用…", action: chooseOther)
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("选择") { if let selected { select(selected) } }
                    .keyboardShortcut(.defaultAction).disabled(selected == nil || !filtered.contains(where: { $0.id == selected?.id }))
            }
        }
        .padding(20).frame(width: 480, height: 510)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            selected = initialTarget
            let task = Task.detached(priority: .userInitiated) { ApplicationCatalog.installed() }
            let installed = await task.value
            guard !Task.isCancelled else { return }
            applications = installed
            if let initialTarget, !applications.contains(where: { $0.id == initialTarget.id }),
               let current = ApplicationCatalog.target(at: URL(fileURLWithPath: initialTarget.path)) {
                applications.insert(current, at: 0)
            }
            loading = false; searchFocused = true
        }
        .onDisappear { panel?.cancel(nil); panel = nil }
    }

    private func chooseOther() {
        let picker = NSOpenPanel()
        picker.title = "选择应用"
        picker.allowedContentTypes = [.applicationBundle]
        picker.canChooseDirectories = false; picker.canChooseFiles = true
        picker.allowsMultipleSelection = false; picker.treatsFilePackagesAsDirectories = false
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        panel = picker
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            defer { panel = nil }
            guard response == .OK, let url = picker.url else { return }
            guard let target = ApplicationCatalog.target(at: url) else {
                error = "请选择有效的 macOS 应用（.app）"; return
            }
            select(target)
        }
        if let window = NSApp.keyWindow { picker.beginSheetModal(for: window, completionHandler: completion) }
        else { picker.begin(completionHandler: completion) }
    }
}
