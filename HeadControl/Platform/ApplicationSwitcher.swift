import AppKit

enum ApplicationCatalog {
    static func target(at url: URL) -> ApplicationTarget? {
        let url = url.resolvingSymlinksInPath().standardizedFileURL
        guard url.isFileURL, url.pathExtension.lowercased() == "app", FileManager.default.fileExists(atPath: url.path),
              let bundle = Bundle(url: url), bundle.infoDictionary?["CFBundlePackageType"] as? String == "APPL" else { return nil }
        let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String) ??
            (bundle.infoDictionary?["CFBundleDisplayName"] as? String) ??
            (bundle.localizedInfoDictionary?["CFBundleName"] as? String) ??
            (bundle.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let target = ApplicationTarget(name: name, path: url.path, bundleIdentifier: bundle.bundleIdentifier)
        return target.isValid ? target : nil
    }

    static func installed(in roots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Library/CoreServices/Applications")
    ]) -> [ApplicationTarget] {
        var targets: [String: ApplicationTarget] = [:]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                enumerator.skipDescendants()
                if let target = target(at: url) { targets[target.path] = target }
            }
        }
        return targets.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }

    @MainActor static func resolvedURL(for target: ApplicationTarget) -> URL? {
        guard target.isValid else { return nil }
        let saved = URL(fileURLWithPath: target.path)
        if let installed = self.target(at: saved),
           target.bundleIdentifier == nil || installed.bundleIdentifier == target.bundleIdentifier { return saved }
        guard let id = target.bundleIdentifier else { return nil }
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: id).compactMap(\.bundleURL) +
            [NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)].compactMap { $0 }
        return candidates.first { self.target(at: $0)?.bundleIdentifier == id }
    }
}

@MainActor protocol ApplicationSwitching {
    func switchTo(_ target: ApplicationTarget, isAllowed: @escaping @MainActor () -> Bool) async throws
    /// The most recently active regular app other than `frontmost` and HeadControl itself.
    func previousApplication(excluding frontmost: pid_t?) -> ApplicationTarget?
}

enum ApplicationSwitchError: LocalizedError {
    case missing, noPrevious, activationFailed
    var errorDescription: String? {
        switch self {
        case .missing: "找不到目标应用，请在头势设置中重新选择"
        case .noPrevious: "没有可切换的上一个应用"
        case .activationFailed: "应用未能切到前台，请稍后重试"
        }
    }
}

@MainActor final class ApplicationSwitcher: ApplicationSwitching {
    /// Activation order of running apps, most recent first. Only PIDs are kept, never window or content state.
    private var recent: [pid_t] = []
    private var observer: NSObjectProtocol?

    init() {
        if let front = NSWorkspace.shared.frontmostApplication { noteActivated(front) }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.noteActivated(app) }
        }
    }

    private func noteActivated(_ app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier, app.activationPolicy == .regular else { return }
        recent.removeAll { $0 == app.processIdentifier }
        recent.insert(app.processIdentifier, at: 0)
        if recent.count > 32 { recent.removeLast(recent.count - 32) }
    }

    func previousApplication(excluding frontmost: pid_t?) -> ApplicationTarget? {
        let own = ProcessInfo.processInfo.processIdentifier
        for pid in recent where pid != frontmost && pid != own {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                  let url = app.bundleURL, let target = ApplicationCatalog.target(at: url) else { continue }
            return target
        }
        return nil
    }

    func switchTo(_ target: ApplicationTarget, isAllowed: @escaping @MainActor () -> Bool) async throws {
        guard isAllowed() else { throw CancellationError() }
        guard let url = ApplicationCatalog.resolvedURL(for: target) else { throw ApplicationSwitchError.missing }
        if NSWorkspace.shared.frontmostApplication?.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL { return }
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == canonical
        }
        if !running {
            // Recheck authorization after cold launch, before requesting foreground activation.
            let launch = NSWorkspace.OpenConfiguration()
            launch.activates = false; launch.allowsRunningApplicationSubstitution = false
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: launch)
        }
        guard isAllowed() else { throw CancellationError() }
        // Workspace activation works while HeadControl itself is in the background and
        // delivers the native reopen event for hidden/minimized windows.
        let activation = NSWorkspace.OpenConfiguration()
        activation.activates = true; activation.allowsRunningApplicationSubstitution = false
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: activation)
        for _ in 0..<40 {
            guard isAllowed() else { throw CancellationError() }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw ApplicationSwitchError.activationFailed
    }
}
