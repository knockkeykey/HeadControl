import XCTest
@testable import HeadControlCore

final class GestureTests: XCTestCase {
    var recognizer = GestureRecognizer()
    var time = 0.0
    var tuning = Configuration().tuning
    var seen: [Gesture] = []
    func feed(_ seconds: Double, yaw: Double = 0, pitch: Double = 0, roll: Double = 0) {
        for _ in 0..<Int(seconds / 0.02) {
            time += 0.02
            if let g = recognizer.update(.init(time:time,yaw:yaw,pitch:pitch,roll:roll),tuning:tuning) { seen.append(g) }
        }
    }
    func testNoTriggerBeforeNeutralAndDuringSmallMovement() {
        feed(1,roll:-30); XCTAssertTrue(seen.isEmpty)
        feed(0.3); feed(1,yaw:8,pitch:-6,roll:5); XCTAssertTrue(seen.isEmpty)
    }
    func testDwellIsSingleShotAndRequiresRecenterAndCooldown() {
        feed(0.3); feed(2,roll:-24); XCTAssertEqual(seen,[.tiltLeft])
        feed(0.3); feed(0.5,roll:-24); XCTAssertEqual(seen,[.tiltLeft,.tiltLeft])
    }
    func testShortTiltDoesNotTrigger() { feed(0.3); feed(0.12,roll:-24); feed(0.4); XCTAssertTrue(seen.isEmpty) }
    func testNodMustReturnWithinWindow() {
        feed(0.3); feed(0.24,pitch:-25); XCTAssertTrue(seen.isEmpty); feed(0.1); XCTAssertEqual(seen,[.nod])
    }
    func testLookingDownForLongTimeIsNotNod() { feed(0.3); feed(2.4,pitch:-28); feed(0.4); XCTAssertTrue(seen.isEmpty) }
    func testCompleteShakeAndNotOneWayTurn() {
        feed(0.3); feed(0.16,yaw:-32); feed(0.16,yaw:32); feed(0.2); XCTAssertEqual(seen,[.shake])
    }
    func testHeldTurnIsOneTurnNotShake() { feed(0.3); feed(0.8,yaw:32); feed(0.2); XCTAssertEqual(seen,[.turnRight]) }
    func testDiagonalAndDataGapDoNotFire() {
        feed(0.3); feed(0.6,pitch:-30,roll:-30); XCTAssertTrue(seen.isEmpty)
        feed(0.3); feed(0.2,roll:-24); time += 2; feed(0.3,roll:-24); XCTAssertTrue(seen.isEmpty)
    }
    func testResetDoesNotCompleteOldGesture() { feed(0.3); feed(0.2,pitch:-25); recognizer.reset(); feed(0.2); XCTAssertTrue(seen.isEmpty) }
    func testEveryDirectionAndCustomThreshold() {
        for (g,y,r) in [(Gesture.tiltRight,0.0,30.0),(.tiltLeft,0.0,-30.0),(.turnLeft,-35.0,0.0),(.turnRight,35.0,0.0)] {
            recognizer.reset(); seen=[]; feed(0.3); feed(0.6,yaw:y,roll:r); XCTAssertEqual(seen,[g])
        }
        recognizer.reset(); seen=[]; tuning[Gesture.tiltLeft.rawValue]?.angle = 35; feed(0.3); feed(1,roll:-25); XCTAssertTrue(seen.isEmpty)
    }
    func testPerGestureNeutralRangeIsRespected() {
        tuning[Gesture.nod.rawValue]?.neutral=11
        feed(0.3); feed(0.24,pitch:-25); feed(0.04,pitch:-10)
        XCTAssertEqual(seen,[.nod])
    }
    func testInvalidTimestampAndNaNDiscardPartialGesture() {
        feed(0.3); feed(0.2,pitch:-25)
        XCTAssertNil(recognizer.update(.init(time:time,pitch:.nan),tuning:tuning))
        feed(0.3); XCTAssertTrue(seen.isEmpty)
    }
}

final class ConfigurationTests: XCTestCase {
    func testGlobalRoundTripKeepsSidedAndCustomBindings() throws {
        var c = Configuration()
        c.set(.init(.shortcut,shortcut:.init(keyCode:40,flags:(1<<17)|(1<<18),label:"⌃⇧K")),for:.turnLeft)
        let decoded = try Configuration.decode(c.encoded())
        XCTAssertEqual(decoded,c)
        XCTAssertEqual(decoded.binding(.tiltLeft).shortcut,.rightOption)
        XCTAssertEqual(decoded.binding(.turnLeft).shortcut?.keyCode,40)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:decoded.encoded()) as? [String:Any])
        XCTAssertNil(object["profiles"])
    }
    func testLegacyMigrationKeepsTuningButDiscardsAppStateAssumptions() throws {
        var source=Configuration(); source.sound=false; source.tuning[Gesture.nod.rawValue]?.angle=26
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:source.encoded()) as? [String:Any])
        json["version"]=1; json.removeValue(forKey:"bindings")
        json["profiles"]=[["id":"com.tencent.xinWeChat","bindings":["ready.nod":["action":"submit"]]]]
        let migrated=try Configuration.decode(JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(migrated.version,2); XCTAssertFalse(migrated.sound)
        XCTAssertEqual(migrated.tuning[Gesture.nod.rawValue]?.angle,26)
        XCTAssertEqual(migrated.binding(.nod).shortcut,.returnKey)
    }
    func testInvalidAndNewerConfigurationsRejected() throws {
        var c=Configuration(); c.version=3; XCTAssertThrowsError(try c.encoded())
        c=Configuration(); c.tuning[Gesture.nod.rawValue]?.angle = .nan; XCTAssertThrowsError(try c.encoded())
        c=Configuration(); c.bindings.removeValue(forKey:Gesture.nod.rawValue); XCTAssertFalse(c.isValid)
        c=Configuration(); c.set(.init(.shortcut),for:.shake); XCTAssertFalse(c.isValid)
        c=Configuration(); c.set(.init(.shortcut,shortcut:.init(keyCode:200,label:"invalid")),for:.shake); XCTAssertFalse(c.isValid)
        XCTAssertThrowsError(try Configuration.decode(Data("{}".utf8)))
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Configuration().encoded()) as? [String:Any])
        json["version"]=3
        XCTAssertThrowsError(try Configuration.decode(JSONSerialization.data(withJSONObject:json)))
    }
    func testGlobalPresetHasNoApplicationOrSessionRequirements() {
        let c=Configuration()
        XCTAssertEqual(c.binding(.tiltLeft),.init(.shortcut,shortcut:.rightOption))
        XCTAssertEqual(c.binding(.nod),.init(.shortcut,shortcut:.returnKey))
        for g in [Gesture.tiltRight,.turnLeft,.turnRight,.shake] { XCTAssertEqual(c.binding(g).action,.disabled) }
    }
}

final class RoutingTests: XCTestCase {
    var router=GestureRouter()
    var time=0.0
    var configuration=Configuration()
    func feed(_ seconds: Double, roll: Double=0, pitch: Double=0) -> [GestureRouter.Route] {
        var routes: [GestureRouter.Route]=[]
        for _ in 0..<Int(seconds/0.02) {
            time += 0.02
            if let r=router.update(.init(time:time,pitch:pitch,roll:roll),configuration:configuration) { routes.append(r) }
        }
        return routes
    }
    func testPausedAndPreviewNeverExecuteKeys() {
        XCTAssertTrue(feed(0.3).isEmpty); XCTAssertTrue(feed(0.8,roll:-25).isEmpty)
        XCTAssertNil(router.preview(.nod,configuration:configuration))
        router.setMode(.testing); _=feed(0.3)
        let routes=feed(2,roll:-25)
        XCTAssertEqual(routes.count,1); XCTAssertFalse(routes[0].executes); XCTAssertFalse(router.accepts(routes[0]))
        XCTAssertFalse(router.preview(.nod,configuration:configuration)!.executes)
    }
    func testActiveUsesGlobalShortcutOnceAndRejectsOldWorkAfterPause() throws {
        router.setMode(.active); _=feed(0.3)
        let routes=feed(2,roll:-25); XCTAssertEqual(routes.count,1)
        let route=try XCTUnwrap(routes.first)
        XCTAssertEqual(route.binding.shortcut,.rightOption); XCTAssertTrue(router.accepts(route))
        router.setMode(.paused); XCTAssertFalse(router.accepts(route))
        router.setMode(.active); XCTAssertFalse(router.accepts(route))
        XCTAssertTrue(feed(0.8,roll:-25).isEmpty)
    }
    func testEditingMappingDiscardsPartialGestureAndPausesExecution() {
        router.setMode(.active); _=feed(0.3); _=feed(0.22,pitch:-25)
        configuration.set(.init(.shortcut,shortcut:.init(keyCode:49,label:"空格")),for:.nod)
        router.configurationChanged(); XCTAssertEqual(router.mode,.paused)
        XCTAssertTrue(feed(0.5).isEmpty)
        router.setMode(.active); _=feed(0.3); _=feed(0.24,pitch:-25)
        let routes=feed(0.1); XCTAssertEqual(routes.count,1); XCTAssertEqual(routes[0].binding.shortcut?.keyCode,49)
    }
    func testDisabledNeverAuthorizesAndTestingCanContinueAfterEdit() {
        router.setMode(.active); _=feed(0.3)
        let routes=feed(0.8,roll:25)
        XCTAssertEqual(routes.count,1); XCTAssertFalse(routes[0].executes)
        router.setMode(.testing); router.configurationChanged()
        XCTAssertEqual(router.mode,.testing)
        XCTAssertNotNil(router.preview(.nod,configuration:configuration))
    }
}

final class KeyPlanTests: XCTestCase {
    func testRightOptionIsPairedAndSided() throws {
        let p = try KeyClickPlan.make(.rightOption,physical:0)
        XCTAssertEqual(p.strokes.count,2); XCTAssertEqual(p.strokes.map(\.code),[61,61]); XCTAssertEqual(p.strokes.map(\.down),[true,false])
        XCTAssertTrue(p.strokes.allSatisfy(\.flagsChanged)); XCTAssertEqual(p.strokes[0].flags & 0x60,0x40); XCTAssertEqual(p.strokes[1].flags,0)
    }
    func testPhysicalModifierAbortsAndCapsLockPreserved() throws {
        XCTAssertThrowsError(try KeyClickPlan.make(.rightOption,physical:1<<20))
        let p = try KeyClickPlan.make(.rightOption,physical:1<<16); XCTAssertEqual(p.strokes[1].flags,1<<16)
    }
    func testRightCommandDifferentFromLeftAndOrdinaryChord() throws {
        let right = try KeyClickPlan.make(.init(keyCode:54,label:"右⌘"),physical:0)
        let left = try KeyClickPlan.make(.init(keyCode:55,label:"左⌘"),physical:0)
        XCTAssertNotEqual(right.strokes[0].flags,left.strokes[0].flags)
        let chord = try KeyClickPlan.make(.init(keyCode:36,flags:1<<20,label:"⌘↩"),physical:0)
        XCTAssertFalse(chord.strokes[0].flagsChanged); XCTAssertEqual(chord.strokes[1].flags,0)
    }
    func testReleasePreservesNewPhysicalModifiers() {
        let own: UInt64 = (1<<19)|0x40
        let withShift: UInt64 = own|(1<<17)|0x02
        let released = KeyClickPlan.releaseFlags(owned:own,current:withShift,baseline:0)
        XCTAssertEqual(released,(1<<17)|0x02)
        let oppositeOption: UInt64 = own|0x20
        XCTAssertEqual(KeyClickPlan.releaseFlags(owned:own,current:oppositeOption,baseline:0),(1<<19)|0x20)
    }
}


final class PresentationTests: XCTestCase {
    func testLinkTonesMatchIndicatorColors() {
        XCTAssertEqual(HeadphoneLink.idle.tone, .off)
        XCTAssertEqual(HeadphoneLink.waiting.tone, .off)
        XCTAssertEqual(HeadphoneLink.tracking.tone, .connected)
        for link in [HeadphoneLink.unavailable, .permissionDenied, .interrupted("断开")] { XCTAssertEqual(link.tone, .warning) }
        XCTAssertEqual(HeadphoneLink.interrupted("耳机已断开").detail, "耳机已断开")
    }
    func testTravelMatchesRecognizerDirections() {
        let s = MotionSample(time: 0, yaw: 20, pitch: -15, roll: -30)
        XCTAssertEqual(Gesture.tiltLeft.travel(s), 30); XCTAssertEqual(Gesture.tiltRight.travel(s), -30)
        XCTAssertEqual(Gesture.turnRight.travel(s), 20); XCTAssertEqual(Gesture.turnLeft.travel(s), -20)
        XCTAssertEqual(Gesture.nod.travel(s), 15); XCTAssertEqual(Gesture.shake.travel(s), 20)
    }
    func testSuggestionIsSeventyPercentClampedAboveNeutral() {
        let t = GestureTuning.preset(.standard, for: .tiltLeft)
        XCTAssertEqual(ThresholdAdvisor.suggest(peak: 30, tuning: t), 21)
        XCTAssertEqual(ThresholdAdvisor.suggest(peak: 9, tuning: t), 8)
        XCTAssertEqual(ThresholdAdvisor.suggest(peak: 90, tuning: t), 50)
        XCTAssertNil(ThresholdAdvisor.suggest(peak: .nan, tuning: t))
        var wide = t; wide.neutral = 12
        XCTAssertEqual(ThresholdAdvisor.suggest(peak: 10, tuning: wide), 13)
        XCTAssertTrue({ var x = t; x.angle = ThresholdAdvisor.suggest(peak: 40, tuning: t)!; return x.isValid }())
    }
    func testCapsAndVirtualKeyboardShortcuts() {
        XCTAssertEqual(Shortcut.rightOption.caps, ["右 ⌥"])
        XCTAssertEqual(Shortcut.returnKey.caps, ["↩"])
        let combo = KeyNames.shortcut(key: 40, modifiers: [55, 56])
        XCTAssertEqual(combo.caps, ["⇧", "⌘", "K"]); XCTAssertEqual(combo.label, "⇧⌘K")
        XCTAssertEqual(combo.flags, (1<<20)|0x08|(1<<17)|0x02)
        XCTAssertNoThrow(try KeyClickPlan.make(combo, physical: 0))
        let single = KeyNames.shortcut(key: 61, modifiers: [61])
        XCTAssertEqual(single, .rightOption)
        let esc = KeyNames.shortcut(key: 53, modifiers: [])
        XCTAssertEqual(esc.label, "Esc"); XCTAssertTrue(esc.isValid)
    }
}
