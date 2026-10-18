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
    func testNoFullRecenterNeeded() {
        // Starting off-center on other axes (drifted yaw, slight head-down) still fires.
        feed(0.3,yaw:10,pitch:-8); feed(0.6,yaw:10,pitch:-8,roll:-30); XCTAssertEqual(seen,[.tiltLeft])
        // Easing back only part way (below 70% of the trigger angle) re-allows it.
        feed(1,roll:-11); feed(0.6,roll:-24); XCTAssertEqual(seen,[.tiltLeft,.tiltLeft])
        // Staying past the release point does not repeat.
        feed(0.3,roll:-17); feed(1,roll:-26); XCTAssertEqual(seen,[.tiltLeft,.tiltLeft])
    }
    func testShortTiltDoesNotTrigger() { feed(0.3); feed(0.12,roll:-24); feed(0.4); XCTAssertTrue(seen.isEmpty) }
    func testJitterAroundTriggerAngleKeepsHolding() {
        // Hovering at the dot (18°) dips just below it every other sample; the hold must not restart.
        feed(0.3)
        for i in 0..<20 { feed(0.02, roll: i % 2 == 0 ? -18.5 : -16) }
        XCTAssertEqual(seen,[.tiltLeft])
    }
    func testOtherAxisCreepDuringHoldStillFires() {
        // Entering cleanly, then a little head-down creeps in while holding.
        feed(0.3); feed(0.06,roll:-20); feed(0.4,pitch:-17,roll:-20); XCTAssertEqual(seen,[.tiltLeft])
    }
    func testLeavingTheHoldZoneStillCancels() {
        feed(0.3); feed(0.2,roll:-20); feed(0.04,roll:-12); feed(0.2,roll:-20); XCTAssertTrue(seen.isEmpty)
    }
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
    /// Feed angles with a matching gyro rate: rate is the per-step change in degrees per second.
    func move(_ seconds: Double, from a: (Double,Double,Double), to b: (Double,Double,Double)) {
        let steps = max(1, Int(seconds / 0.02))
        for i in 1...steps {
            time += 0.02
            let f = Double(i) / Double(steps)
            let rate = AxisRates(yaw:(b.0-a.0)/seconds, pitch:(b.1-a.1)/seconds, roll:(b.2-a.2)/seconds)
            let s = MotionSample(time:time, yaw:a.0+(b.0-a.0)*f, pitch:a.1+(b.1-a.1)*f, roll:a.2+(b.2-a.2)*f, rate:rate)
            if let g = recognizer.update(s,tuning:tuning) { seen.append(g) }
        }
    }
    func hold(_ seconds: Double, _ p: (Double,Double,Double)) { move(seconds, from:p, to:p) }
    func testSlowTiltIsPostureNotGesture() {
        hold(0.3,(0,0,0)); move(2,from:(0,0,0),to:(0,0,-25)); hold(1,(0,0,-25))   // ~12 °/s
        XCTAssertTrue(seen.isEmpty)
    }
    func testBriskTiltPassesSpeedGate() {
        hold(0.3,(0,0,0)); move(0.2,from:(0,0,0),to:(0,0,-25)); hold(0.6,(0,0,-25))  // 125 °/s
        XCTAssertEqual(seen,[.tiltLeft])
    }
    func testSpeedThresholdIsPerGestureAndTunable() {
        tuning[Gesture.tiltLeft.rawValue]?.speed = 200
        hold(0.3,(0,0,0)); move(0.2,from:(0,0,0),to:(0,0,-25)); hold(0.6,(0,0,-25))
        XCTAssertTrue(seen.isEmpty)
    }
    func testNodNeedsBothStrokesFast() {
        hold(0.3,(0,0,0)); move(0.12,from:(0,0,0),to:(0,-25,0)); move(0.6,from:(0,-25,0),to:(0,0,0)); hold(0.2,(0,0,0))
        XCTAssertTrue(seen.isEmpty)
        recognizer.reset(); time += 1
        hold(0.3,(0,0,0)); move(0.12,from:(0,0,0),to:(0,-25,0)); move(0.12,from:(0,-25,0),to:(0,0,0)); hold(0.2,(0,0,0))
        XCTAssertEqual(seen,[.nod])
    }
    func testStatusExplainsSlowAndMixedAndRecenter() {
        tuning[Gesture.tiltLeft.rawValue]?.speed = 200
        hold(0.3,(0,0,0)); move(0.2,from:(0,0,0),to:(0,0,-25)); hold(0.6,(0,0,-25))
        XCTAssertEqual(recognizer.status[.tiltLeft]?.phase, .tooSlow)
        recognizer.reset(); time += 1
        feed(0.3); feed(0.2,yaw:22,roll:-24)
        XCTAssertEqual(recognizer.status[.tiltLeft]?.phase, .mixed)
        recognizer.reset(); time += 1
        feed(0.5,roll:-30)
        XCTAssertEqual(recognizer.status[.tiltLeft]?.phase, .release)
    }
    func testStatusFiredMatchesEmittedGesture() {
        feed(0.3); feed(0.6,roll:-24)
        XCTAssertEqual(seen,[.tiltLeft])
        XCTAssertNotEqual(recognizer.status[.tiltLeft]?.phase, .tooSlow)
    }
    func testSamplesWithoutGyroSkipSpeedGate() { feed(0.3); feed(0.6,roll:-24); XCTAssertEqual(seen,[.tiltLeft]) }
    func testNaNRateDiscardsSample() {
        XCTAssertFalse(MotionSample(time:1, rate:.init(yaw:.nan)).finite)
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
    func testPerGestureSoundsRoundTripAndDefaultForOlderFiles() throws {
        XCTAssertEqual(Set(Gesture.allCases.map(\.defaultSound)).count, Gesture.allCases.count)
        var c=Configuration(); c.sounds[Gesture.nod.rawValue]="Hero"; c.sounds[Gesture.shake.rawValue]=""
        let decoded=try Configuration.decode(c.encoded())
        XCTAssertEqual(decoded.sound(.nod),"Hero"); XCTAssertEqual(decoded.sound(.shake),"")
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:c.encoded()) as? [String:Any])
        json.removeValue(forKey:"sounds")
        let old=try Configuration.decode(JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(old.sound(.tiltLeft),"Tink"); XCTAssertEqual(old.sounds,Configuration.defaultSounds)
        c.sounds[Gesture.nod.rawValue]="../evil"; XCTAssertFalse(c.isValid)
    }
    func testLegacyMigrationKeepsTuningButDiscardsAppStateAssumptions() throws {
        var source=Configuration(); source.sound=false; source.tuning[Gesture.nod.rawValue]?.angle=26
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:source.encoded()) as? [String:Any])
        json["version"]=1; json.removeValue(forKey:"bindings")
        json["profiles"]=[["id":"com.tencent.xinWeChat","bindings":["ready.nod":["action":"submit"]]]]
        let migrated=try Configuration.decode(JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(migrated.version,3); XCTAssertFalse(migrated.sound)
        XCTAssertEqual(migrated.tuning[Gesture.nod.rawValue]?.angle,26)
        XCTAssertEqual(migrated.binding(.nod).shortcut,.returnKey)
    }
    func testVersion2MigrationAddsPresetSpeedAndKeepsOtherTuning() throws {
        var source=Configuration()
        source.tuning[Gesture.tiltLeft.rawValue] = .preset(.steady, for:.tiltLeft)
        var custom = GestureTuning.preset(.standard, for:.turnLeft); custom.preset = .custom; custom.cooldown = 2.2; custom.angle = 30
        source.tuning[Gesture.turnLeft.rawValue] = custom
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:source.encoded()) as? [String:Any])
        json["version"]=2; json.removeValue(forKey:"pauseWhileWalking")
        var tuning=try XCTUnwrap(json["tuning"] as? [String:[String:Any]])
        for key in tuning.keys { tuning[key]?.removeValue(forKey:"speed") }
        json["tuning"]=tuning
        let migrated=try Configuration.decode(JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(migrated.version,3); XCTAssertTrue(migrated.pauseWhileWalking)
        XCTAssertEqual(migrated.tuning[Gesture.tiltLeft.rawValue]?.speed,130)
        XCTAssertEqual(migrated.tuning[Gesture.turnLeft.rawValue]?.speed,110)
        XCTAssertEqual(migrated.tuning[Gesture.turnLeft.rawValue]?.cooldown,2.2)
        XCTAssertEqual(migrated.tuning[Gesture.turnLeft.rawValue]?.angle,30)
        XCTAssertEqual(migrated.tuning[Gesture.turnLeft.rawValue]?.preset,.custom)
    }
    func testPresetSpeeds() {
        XCTAssertEqual(GestureTuning.preset(.gentle, for:.tiltLeft).speed,60)
        XCTAssertEqual(GestureTuning.preset(.standard, for:.nod).speed,90)
        XCTAssertEqual(GestureTuning.preset(.steady, for:.shake).speed,150)
        var t=GestureTuning.preset(.standard, for:.nod); t.speed=10; XCTAssertFalse(t.isValid)
    }
    func testInvalidAndNewerConfigurationsRejected() throws {
        var c=Configuration(); c.version=4; XCTAssertThrowsError(try c.encoded())
        c=Configuration(); c.tuning[Gesture.nod.rawValue]?.angle = .nan; XCTAssertThrowsError(try c.encoded())
        c=Configuration(); c.bindings.removeValue(forKey:Gesture.nod.rawValue); XCTAssertFalse(c.isValid)
        c=Configuration(); c.set(.init(.shortcut),for:.shake); XCTAssertFalse(c.isValid)
        c=Configuration(); c.set(.init(.shortcut,shortcut:.init(keyCode:200,label:"invalid")),for:.shake); XCTAssertFalse(c.isValid)
        XCTAssertThrowsError(try Configuration.decode(Data("{}".utf8)))
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Configuration().encoded()) as? [String:Any])
        json["version"]=4
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
    func testEditingMappingDiscardsPartialGestureButKeepsControlOn() {
        router.setMode(.active); _=feed(0.3); _=feed(0.22,pitch:-25)
        let old=router.revision
        configuration.set(.init(.shortcut,shortcut:.init(keyCode:49,label:"空格")),for:.nod)
        router.configurationChanged(); XCTAssertEqual(router.mode,.active); XCTAssertNotEqual(router.revision,old)
        XCTAssertTrue(feed(0.5).isEmpty)
        _=feed(0.3); _=feed(0.24,pitch:-25)
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
    func testSpeedSuggestionAndPeakDirections() {
        XCTAssertEqual(ThresholdAdvisor.suggestSpeed(peak: 200), 140)
        XCTAssertEqual(ThresholdAdvisor.suggestSpeed(peak: 10), 20)
        XCTAssertEqual(ThresholdAdvisor.suggestSpeed(peak: 900), 300)
        XCTAssertNil(ThresholdAdvisor.suggestSpeed(peak: .nan))
        var p = SpeedPeak(); p.record(150); p.record(-60); p.record(.nan)
        XCTAssertEqual(p.effective(sequence: false), 150); XCTAssertEqual(p.effective(sequence: true), 60)
        XCTAssertEqual(Gesture.tiltLeft.rate(.init(yaw: 1, pitch: 2, roll: 3)), 3)
        XCTAssertEqual(Gesture.shake.rate(.init(yaw: 1, pitch: 2, roll: 3)), 1)
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
