import XCTest
@testable import HeadControlCore

final class ApplicationTests: XCTestCase {
    let target = ApplicationTarget(name: "测试应用", path: "/Applications/Missing.app", bundleIdentifier: "example.missing")

    func testVersion5MigrationPreservesCustomSettingsWithoutApplicationField() throws {
        var source = Configuration()
        source.recognitionEnabled[Gesture.shake.rawValue] = true
        source.tuning[Gesture.nod.rawValue]?.angle = 32
        source.sounds[Gesture.nod.rawValue] = "Hero"
        source.set(.init(.shortcut, shortcut: .rightOption), for: .shake)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: source.encoded()) as? [String: Any])
        json["version"] = 5
        let decoded = try Configuration.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, source)
        XCTAssertEqual(decoded.version, 6)
        XCTAssertTrue(decoded.bindings.values.allSatisfy { $0.application == nil })
    }

    func testApplicationTargetPersistsEvenWhenNotInstalled() throws {
        var configuration = Configuration()
        configuration.set(.init(.application, shortcut: .rightOption, application: target), for: .tiltLeft)
        let decoded = try Configuration.decode(configuration.encoded())
        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(decoded.binding(.tiltLeft).application, target)
        XCTAssertEqual(decoded.binding(.tiltLeft).shortcut, .rightOption)
        XCTAssertEqual(decoded.binding(.nod).shortcut, .returnKey)
    }

    func testApplicationRequiresStructurallyValidTargetButNotExistingFile() throws {
        for invalid in [nil, ApplicationTarget(name: "", path: target.path),
                        ApplicationTarget(name: "App", path: "relative.app"),
                        ApplicationTarget(name: "App", path: "/Applications/file.txt")] {
            var configuration = Configuration()
            configuration.set(.init(.application, application: invalid), for: .nod)
            XCTAssertThrowsError(try configuration.encoded())
        }
        XCTAssertTrue(target.isValid)
    }

    func testApplicationRouteNeverExecutesInTestingOrPausedPreview() throws {
        var configuration = Configuration()
        configuration.set(.init(.application, application: target), for: .tiltLeft)
        for mode in [GestureRouter.Mode.active, .testing, .paused] {
            var router = GestureRouter(); router.setMode(mode)
            let routes = (1...50).compactMap { step in
                router.update(.init(time: Double(step) * 0.02, roll: step < 15 ? 0 : -30),
                              configuration: configuration, feedbackWhenPaused: true)
            }
            let route = try XCTUnwrap(routes.first)
            XCTAssertEqual(route.binding.application, target)
            XCTAssertEqual(route.executes, mode == .active)
            XCTAssertEqual(router.accepts(route), mode == .active)
            router.configurationChanged()
            XCTAssertFalse(router.accepts(route))
        }
    }

    func testPreviousApplicationBindingRoundTripsAndExecutesWithoutTarget() throws {
        var configuration = Configuration()
        configuration.set(.init(.previousApplication), for: .tiltLeft)
        let decoded = try Configuration.decode(configuration.encoded())
        XCTAssertEqual(decoded.binding(.tiltLeft).action, .previousApplication)
        XCTAssertNil(decoded.binding(.tiltLeft).application)
        XCTAssertEqual(ActionKind.previousApplication.title, "切换到上一个应用")
        var router = GestureRouter(); router.setMode(.active)
        let route = try XCTUnwrap((1...50).compactMap { step in
            router.update(.init(time: Double(step) * 0.02, roll: step < 15 ? 0 : -30), configuration: decoded)
        }.first)
        XCTAssertTrue(route.executes)
    }
}
