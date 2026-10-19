import AppKit

@MainActor private final class RecordingApplications: ApplicationSwitching {
    func previousApplication(excluding frontmost: pid_t?) -> ApplicationTarget? { nil }
    var requests = 0
    var activations = 0
    var fails = false
    var delayed = false
    func switchTo(_ target: ApplicationTarget, isAllowed: @escaping @MainActor () -> Bool) async throws {
        guard isAllowed() else { throw CancellationError() }
        requests += 1
        if delayed { try await Task.sleep(for: .milliseconds(80)) }
        guard isAllowed() else { throw CancellationError() }
        if fails { throw ApplicationSwitchError.missing }
        activations += 1
    }
}

@main struct ApplicationControllerProbe {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("headcontrol-app-controller-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = ApplicationTarget(name: "独立目标", path: "/Applications/Probe.app", bundleIdentifier: "example.probe")
        for scenario in 0..<14 {
            let store = ConfigurationStore(directory: directory.appendingPathComponent("\(scenario)"))
            store.configuration.set(.init(.application, shortcut: .rightOption, application: target), for: .tiltLeft)
            let applications = RecordingApplications()
            applications.fails = scenario == 1; applications.delayed = (7...9).contains(scenario)
            let controller = AppController(store: store, applications: applications)
            controller.setPreviewVisible(true, surface: "settings"); controller.setPreviewVisible(true, surface: "gestures")
            if scenario != 2 { controller.setEnabled(true) }
            if scenario == 3 { controller.startTest(.tiltLeft) }
            if scenario == 4 { controller.startJointTest() }
            if scenario == 5 { controller.setSelectingApplication(true) }
            if scenario == 10 { controller.motion.walking = true }
            if scenario == 11 { store.configuration.recognitionEnabled[Gesture.tiltLeft.rawValue] = false }
            if scenario == 12 { store.configuration.bindings[Gesture.tiltLeft.rawValue]?.action = .disabled }
            if scenario == 13 { controller.setEnabled(false) }
            Trace.events = []
            for step in 1...50 {
                controller.motion.onSample?(.init(time: Double(step) * 0.02, roll: step < 15 ? 0 : -30))
            }
            if scenario == 6 { store.configuration.overlay.toggle() }
            if (7...9).contains(scenario) {
                try await Task.sleep(for: .milliseconds(20))
                if scenario == 7 { store.configuration.overlay.toggle() }
                if scenario == 8 { controller.setEnabled(false) }
                if scenario == 9 { controller.setSelectingApplication(true) }
            }
            try await Task.sleep(for: .milliseconds(120))
            let expectedRequests = [0, 1, 7, 8, 9].contains(scenario) ? 1 : 0
            guard applications.requests == expectedRequests, applications.activations == (scenario == 0 ? 1 : 0), !Trace.events.contains("key") else {
                throw failure("scenario \(scenario): unexpected activation, request or key: \(applications.requests), \(applications.activations), \(Trace.events)")
            }
            if scenario == 0 {
                guard controller.lastTrigger?.outcome == .switched, controller.lastTrigger?.application == target,
                      controller.lastTrigger?.caps.isEmpty == true, controller.lastTrigger?.executed == true else { throw failure("missing application success feedback") }
            }
            if scenario == 1 {
                guard controller.lastTrigger?.outcome == .skipped, controller.lastTrigger?.application == target,
                      store.configuration.binding(.tiltLeft).application == target, store.error == nil else { throw failure("failure lost binding or feedback") }
            }
            if [2, 3, 4, 13].contains(scenario) {
                guard controller.lastTrigger?.application == target else { throw failure("preview omitted application target") }
            }
            if scenario == 5 || scenario == 9 {
                controller.setSelectingApplication(false)
                guard controller.enabled else { throw failure("picker changed original enabled state") }
                for step in 1...50 {
                    controller.motion.onSample?(.init(time: 3 + Double(step) * 0.02, roll: step < 15 ? 0 : -30))
                }
                try await Task.sleep(for: .milliseconds(120))
                guard applications.activations == 1 else { throw failure("closing picker did not restore execution") }
            }
            controller.shutdown()
        }
        let reloaded = ConfigurationStore(directory: directory.appendingPathComponent("1"))
        guard reloaded.error == nil, reloaded.configuration.binding(.tiltLeft).application == target else { throw failure("missing app did not survive configuration reload") }
        print("PASS: 14 application controller scenarios: success/failure feedback, previews, practice, joint test, selection suppression/recovery, walking, disabled gestures, queued and in-flight invalidation; no keys; reload preserves missing target")
    }
    static func failure(_ text: String) -> NSError { NSError(domain: text, code: 1) }
}
