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
    func testConfiguredDwellAppliesToAllFourHeldDirections() {
        for (g, yaw, roll) in [(Gesture.tiltRight, 0.0, 25.0), (.tiltLeft, 0.0, -25.0), (.turnLeft, -30.0, 0.0), (.turnRight, 30.0, 0.0)] {
            recognizer.reset(); time = 0; tuning = Configuration().tuning; seen = []
            tuning[g.rawValue]?.dwell = 0.5
            feed(0.3)
            feed(0.4, yaw:yaw, roll:roll)
            XCTAssertTrue(seen.isEmpty, "\(g) triggered before its configured dwell")
            feed(0.14, yaw:yaw, roll:roll)
            XCTAssertEqual(seen, [g])
        }
    }
    func testLeavingHoldZoneRestartsConfiguredDwell() {
        tuning[Gesture.tiltLeft.rawValue]?.dwell = 0.5
        feed(0.3); feed(0.24, roll:-20); feed(0.02, roll:-12)
        feed(0.3, roll:-20)
        XCTAssertTrue(seen.isEmpty)
        feed(0.24, roll:-20)
        XCTAssertEqual(seen, [.tiltLeft])
    }
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
    func testSequenceGesturesDoNotUseHeldPoseDwell() {
        tuning[Gesture.nod.rawValue]?.dwell = 1.5
        tuning[Gesture.shake.rawValue]?.dwell = 1.5
        feed(0.3); feed(0.24, pitch:-25); feed(0.1)
        XCTAssertEqual(seen, [.nod])

        recognizer.reset(); time += 1; seen = []
        feed(0.3); feed(0.16, yaw:-32); feed(0.16, yaw:32); feed(0.2)
        XCTAssertEqual(seen, [.shake])
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
    func testSpeedSwitchAllowsSlowHeldGesturesAndRemainsIndependent() {
        for (g, pose) in [(Gesture.tiltLeft, (0.0, 0.0, -25.0)), (.tiltRight, (0.0, 0.0, 25.0)), (.turnLeft, (-30.0, 0.0, 0.0)), (.turnRight, (30.0, 0.0, 0.0))] {
            for enabled in [true, false] {
                recognizer.reset(); time = 0; seen = []; tuning = Configuration().tuning
                tuning[g.rawValue]?.speedEnabled = enabled
                hold(0.3, (0, 0, 0)); move(2, from: (0, 0, 0), to: pose); hold(0.6, pose)
                XCTAssertEqual(seen, enabled ? [] : [g], "\(g), speed enabled: \(enabled)")
                if !enabled { XCTAssertNotEqual(recognizer.status[g]?.phase, .tooSlow) }
                XCTAssertTrue(tuning.filter { $0.key != g.rawValue }.values.allSatisfy { !$0.speedEnabled })
            }
        }
    }
    func testDisabledSpeedGateAllowsSlowReturnForNodAndShake() {
        for g in [Gesture.nod, .shake] {
            for enabled in [true, false] {
                recognizer.reset(); time = 0; seen = []; tuning = Configuration().tuning
                tuning[g.rawValue]?.speedEnabled = enabled
                tuning[g.rawValue]?.completion = 2
                tuning[Gesture.turnLeft.rawValue]?.dwell = 1.5
                tuning[Gesture.turnRight.rawValue]?.dwell = 1.5
                hold(0.3, (0, 0, 0))
                if g == .nod {
                    move(0.12, from: (0, 0, 0), to: (0, -25, 0))
                    move(0.6, from: (0, -25, 0), to: (0, 0, 0))
                } else {
                    move(0.12, from: (0, 0, 0), to: (-30, 0, 0))
                    move(1, from: (-30, 0, 0), to: (30, 0, 0))
                    move(0.6, from: (30, 0, 0), to: (0, 0, 0))
                }
                hold(0.1, (0, 0, 0))
                XCTAssertEqual(seen, enabled ? [] : [g], "\(g), speed enabled: \(enabled)")
                if !enabled { XCTAssertNotEqual(recognizer.status[g]?.phase, .tooSlow) }
            }
        }
    }
    func testSlowTiltIsPostureNotGesture() {
        tuning[Gesture.tiltLeft.rawValue]?.speedEnabled = true
        hold(0.3,(0,0,0)); move(2,from:(0,0,0),to:(0,0,-25)); hold(1,(0,0,-25))   // ~12 °/s
        XCTAssertTrue(seen.isEmpty)
    }
    func testBriskTiltPassesSpeedGate() {
        tuning[Gesture.tiltLeft.rawValue]?.speedEnabled = true
        hold(0.3,(0,0,0)); move(0.2,from:(0,0,0),to:(0,0,-25)); hold(0.6,(0,0,-25))  // 125 °/s
        XCTAssertEqual(seen,[.tiltLeft])
    }
    func testSpeedThresholdIsPerGestureAndTunable() {
        tuning[Gesture.tiltLeft.rawValue]?.speedEnabled = true
        tuning[Gesture.tiltLeft.rawValue]?.speed = 200
        hold(0.3,(0,0,0)); move(0.2,from:(0,0,0),to:(0,0,-25)); hold(0.6,(0,0,-25))
        XCTAssertTrue(seen.isEmpty)
    }
    func testNodNeedsBothStrokesFast() {
        tuning[Gesture.nod.rawValue]?.speedEnabled = true
        hold(0.3,(0,0,0)); move(0.12,from:(0,0,0),to:(0,-25,0)); move(0.6,from:(0,-25,0),to:(0,0,0)); hold(0.2,(0,0,0))
        XCTAssertTrue(seen.isEmpty)
        recognizer.reset(); time += 1
        hold(0.3,(0,0,0)); move(0.12,from:(0,0,0),to:(0,-25,0)); move(0.12,from:(0,-25,0),to:(0,0,0)); hold(0.2,(0,0,0))
        XCTAssertEqual(seen,[.nod])
    }
    func testStatusExplainsSlowAndMixedAndRecenter() {
        tuning[Gesture.tiltLeft.rawValue]?.speedEnabled = true
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
    func testSamplesWithoutGyroSkipSpeedGate() { tuning[Gesture.tiltLeft.rawValue]?.speedEnabled = true; feed(0.3); feed(0.6,roll:-24); XCTAssertEqual(seen,[.tiltLeft]) }
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
    func testGestureOrderAndDefaultRecognitionSwitches() {
        let c = Configuration()
        XCTAssertEqual(Gesture.allCases, [.tiltLeft, .tiltRight, .nod, .turnLeft, .turnRight, .shake])
        XCTAssertEqual(c.enabledGestures, [.tiltLeft, .tiltRight, .nod])
        XCTAssertEqual(c.recognitionEnabled.count, 6)
        XCTAssertTrue(c.isEnabled(.tiltRight))
        XCTAssertEqual(c.binding(.tiltRight).action, .disabled)
    }
    func testRecognitionSwitchesRoundTripWithoutChangingBindingsOrTuning() throws {
        var c = Configuration()
        c.recognitionEnabled[Gesture.tiltLeft.rawValue] = false
        c.recognitionEnabled[Gesture.shake.rawValue] = true
        c.set(.init(.shortcut, shortcut: .rightOption), for: .shake)
        c.tuning[Gesture.tiltLeft.rawValue]?.dwell = 0.7
        let decoded = try Configuration.decode(c.encoded())
        XCTAssertEqual(decoded, c)
        XCTAssertFalse(decoded.isEnabled(.tiltLeft))
        XCTAssertTrue(decoded.isEnabled(.shake))
        XCTAssertEqual(decoded.binding(.tiltLeft).shortcut, .rightOption)
        XCTAssertEqual(decoded.tuning[Gesture.tiltLeft.rawValue]?.dwell, 0.7)
        c.recognitionEnabled = c.recognitionEnabled.mapValues { _ in false }
        XCTAssertTrue(c.isValid)
        XCTAssertTrue(try Configuration.decode(c.encoded()).enabledGestures.isEmpty)
    }
    func testVersion4MigrationAddsDefaultSwitchesAndPreservesCustomSettings() throws {
        var source = Configuration()
        source.set(.init(.shortcut, shortcut: .returnKey), for: .turnRight)
        source.sounds[Gesture.tiltLeft.rawValue] = "Submarine"
        source.tuning[Gesture.shake.rawValue]?.speedEnabled = true
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: source.encoded()) as? [String: Any])
        json["version"] = 4
        json.removeValue(forKey: "recognitionEnabled")
        let migrated = try Configuration.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated, source)
        XCTAssertFalse(migrated.isEnabled(.turnRight))
        XCTAssertEqual(migrated.binding(.turnRight).shortcut, .returnKey)
    }
    func testVersion5RequiresExactlySixRecognitionSwitches() throws {
        var c = Configuration()
        c.recognitionEnabled.removeValue(forKey: Gesture.nod.rawValue)
        XCTAssertFalse(c.isValid)
        c = Configuration(); c.recognitionEnabled["unknown"] = true
        XCTAssertThrowsError(try c.encoded())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Configuration().encoded()) as? [String: Any])
        json.removeValue(forKey: "recognitionEnabled")
        XCTAssertThrowsError(try Configuration.decode(JSONSerialization.data(withJSONObject: json)))
    }
    func testAllSixGesturesDefaultSpeedGateOff() {
        let c = Configuration()
        XCTAssertEqual(c.tuning.count, 6)
        for g in Gesture.allCases {
            XCTAssertFalse(GestureTuning.defaults(for: g).speedEnabled)
            XCTAssertEqual(c.tuning[g.rawValue]?.speedEnabled, false)
        }
    }
    func testGlobalRoundTripKeepsSidedAndCustomBindings() throws {
        var c = Configuration()
        c.set(.init(.shortcut,shortcut:.init(keyCode:40,flags:(1<<17)|(1<<18),label:"⌃⇧K")),for:.turnLeft)
        c.tuning[Gesture.tiltLeft.rawValue]?.dwell = 0.45
        c.tuning[Gesture.turnRight.rawValue]?.dwell = 0.85
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
        XCTAssertEqual(migrated.version,5); XCTAssertFalse(migrated.sound)
        XCTAssertEqual(migrated.tuning[Gesture.nod.rawValue]?.angle,26)
        XCTAssertEqual(migrated.binding(.nod).shortcut,.returnKey)
    }
    func testVersion2MigrationAddsPresetSpeedAndKeepsOtherTuning() throws {
        var source=Configuration()
        var steady = GestureTuning.defaults(for: .tiltLeft); steady.angle = 24; steady.dwell = 0.5; steady.neutral = 8; steady.cooldown = 1.1
        source.tuning[Gesture.tiltLeft.rawValue] = steady
        var custom = GestureTuning.defaults(for: .turnLeft); custom.cooldown = 2.2; custom.angle = 30
        source.tuning[Gesture.turnLeft.rawValue] = custom
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:source.encoded()) as? [String:Any])
        json["version"]=2; json.removeValue(forKey:"pauseWhileWalking")
        var tuning=try XCTUnwrap(json["tuning"] as? [String:[String:Any]])
        for key in tuning.keys {
            tuning[key]?.removeValue(forKey:"speed")
            tuning[key]?.removeValue(forKey:"speedEnabled")
            tuning[key]?["preset"] = key == Gesture.tiltLeft.rawValue ? "steady" : "custom"
        }
        json["tuning"]=tuning
        let migrated=try Configuration.decode(JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(migrated.version,5); XCTAssertTrue(migrated.pauseWhileWalking)
        XCTAssertEqual(migrated.tuning[Gesture.tiltLeft.rawValue]?.speed,130)
        XCTAssertEqual(migrated.tuning[Gesture.turnLeft.rawValue]?.speed,110)
        XCTAssertEqual(migrated.tuning[Gesture.turnLeft.rawValue]?.cooldown,2.2)
        XCTAssertEqual(migrated.tuning[Gesture.turnLeft.rawValue]?.angle,30)
        XCTAssertTrue(migrated.tuning.values.allSatisfy { !$0.speedEnabled })
        XCTAssertEqual(migrated.tuning[Gesture.tiltLeft.rawValue]?.dwell, 0.5)
    }
    func testManualTuningValidation() {
        var t = GestureTuning.defaults(for: .nod); t.speed = 10; XCTAssertFalse(t.isValid)
        t = GestureTuning.defaults(for: .tiltLeft); t.dwell = 0.09; XCTAssertFalse(t.isValid)
        t.dwell = 1.51; XCTAssertFalse(t.isValid)
    }
    func testSpeedSwitchRoundTripIsIndependentPerGestureAndKeepsThreshold() throws {
        var c = Configuration()
        c.tuning[Gesture.nod.rawValue]?.speedEnabled = true
        c.tuning[Gesture.nod.rawValue]?.speed = 245
        let decoded = try Configuration.decode(c.encoded())
        XCTAssertEqual(decoded, c)
        XCTAssertEqual(decoded.tuning[Gesture.nod.rawValue]?.speed, 245)
        XCTAssertEqual(decoded.tuning[Gesture.nod.rawValue]?.speedEnabled, true)
        XCTAssertEqual(decoded.tuning[Gesture.shake.rawValue]?.speedEnabled, false)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: decoded.encoded()) as? [String: Any])
        let tuning = try XCTUnwrap(json["tuning"] as? [String: [String: Any]])
        XCTAssertTrue(tuning.values.allSatisfy { $0["preset"] == nil })
    }
    func testVersion3MigrationPreservesNumericValuesAndDefaultsSpeedGatesOff() throws {
        var source = Configuration()
        source.tuning[Gesture.shake.rawValue]?.speed = 175
        source.tuning[Gesture.shake.rawValue]?.completion = 1.65
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: source.encoded()) as? [String: Any])
        json["version"] = 3
        var tuning = try XCTUnwrap(json["tuning"] as? [String: [String: Any]])
        for key in tuning.keys {
            tuning[key]?.removeValue(forKey: "speedEnabled")
            tuning[key]?["preset"] = "custom"
        }
        json["tuning"] = tuning
        let migrated = try Configuration.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated, source)
    }
    func testInvalidAndNewerConfigurationsRejected() throws {
        var c=Configuration(); c.version=6; XCTAssertThrowsError(try c.encoded())
        c=Configuration(); c.tuning[Gesture.nod.rawValue]?.angle = .nan; XCTAssertThrowsError(try c.encoded())
        c=Configuration(); c.bindings.removeValue(forKey:Gesture.nod.rawValue); XCTAssertFalse(c.isValid)
        c=Configuration(); c.set(.init(.shortcut),for:.shake); XCTAssertFalse(c.isValid)
        c=Configuration(); c.set(.init(.shortcut,shortcut:.init(keyCode:200,label:"invalid")),for:.shake); XCTAssertFalse(c.isValid)
        XCTAssertThrowsError(try Configuration.decode(Data("{}".utf8)))
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Configuration().encoded()) as? [String:Any])
        json["version"]=6
        XCTAssertThrowsError(try Configuration.decode(JSONSerialization.data(withJSONObject:json)))
    }
    func testGlobalPresetHasNoApplicationOrSessionRequirements() {
        let c=Configuration()
        XCTAssertEqual(c.binding(.tiltLeft),.init(.shortcut,shortcut:.rightOption))
        XCTAssertEqual(c.binding(.nod),.init(.shortcut,shortcut:.returnKey))
        for g in [Gesture.tiltRight,.turnLeft,.turnRight,.shake] { XCTAssertEqual(c.binding(g).action,.disabled) }
    }
}

final class RecognitionSwitchTests: XCTestCase {
    func trajectory(_ gesture: Gesture) -> [MotionSample] {
        var samples: [MotionSample] = []
        for i in 1...65 {
            let moving = i > 15 && i <= 40
            var s = MotionSample(time: Double(i) * 0.02)
            if moving {
                switch gesture {
                case .tiltLeft: s.roll = -30
                case .tiltRight: s.roll = 30
                case .turnLeft: s.yaw = -32
                case .turnRight: s.yaw = 32
                case .nod: s.pitch = -28
                case .shake: s.yaw = i <= 28 ? -32 : 32
                }
            }
            samples.append(s)
        }
        return samples
    }
    func testEverySwitchStopsRecognitionInActiveTestingAndPausedModes() {
        for mode in [GestureRouter.Mode.active, .testing, .paused] {
            for g in Gesture.allCases {
                var c = Configuration()
                c.recognitionEnabled = c.recognitionEnabled.mapValues { _ in false }
                c.recognitionEnabled[g.rawValue] = true
                var on = GestureRouter(); on.setMode(mode)
                var onRoutes: [GestureRouter.Route] = []
                var onFired = false
                for sample in trajectory(g) {
                    if let route = on.update(sample, configuration: c) { onRoutes.append(route) }
                    onFired = onFired || on.status[g]?.phase == .fired
                }
                XCTAssertTrue(onFired, "enabled \(g) was not recognized in \(mode)")
                XCTAssertEqual(onRoutes.count, mode == .paused ? 0 : 1)
                c.recognitionEnabled[g.rawValue] = false
                var off = GestureRouter(); off.setMode(mode)
                for sample in trajectory(g) {
                    XCTAssertNil(off.update(sample, configuration: c), "disabled \(g) was routed in \(mode)")
                    XCTAssertTrue(off.status.isEmpty)
                }
                XCTAssertNil(off.preview(g, configuration: c))
            }
        }
    }
    func testDisabledTurnDoesNotStealCooldownFromNodOrTilt() {
        for next in [Gesture.nod, .tiltLeft] {
            for turnEnabled in [false, true] {
                var c = Configuration()
                c.recognitionEnabled[Gesture.turnRight.rawValue] = turnEnabled
                var router = GestureRouter(); router.setMode(.active)
                var gestures: [Gesture] = []
                let first = trajectory(.turnRight).filter { $0.time <= 0.9 }
                let second = trajectory(next).map { s in
                    MotionSample(time: s.time + 0.9, yaw: s.yaw, pitch: s.pitch, roll: s.roll)
                }.filter { $0.time <= 1.76 }
                for s in first + second {
                    if let route = router.update(s, configuration: c) { gestures.append(route.gesture) }
                }
                // Same movement: an enabled, unbound turn consumes cooldown; a disabled turn cannot.
                XCTAssertEqual(gestures, turnEnabled ? [.turnRight] : [next])
            }
        }
    }
    func testDisablingPartialNodDiscardsItAndOldRoutesAreRejected() throws {
        var c = Configuration()
        var router = GestureRouter(); router.setMode(.active)
        for sample in trajectory(.nod).filter({ $0.time <= 0.7 }) { _ = router.update(sample, configuration: c) }
        c.recognitionEnabled[Gesture.nod.rawValue] = false
        router.configurationChanged()
        XCTAssertNil(router.update(.init(time: 0.72), configuration: c))
        XCTAssertNil(router.status[.nod])
        c.recognitionEnabled[Gesture.nod.rawValue] = true
        router.configurationChanged()
        let routes = trajectory(.nod).compactMap { router.update($0, configuration: c) }
        let route = try XCTUnwrap(routes.first)
        XCTAssertTrue(router.accepts(route))
        c.recognitionEnabled[Gesture.nod.rawValue] = false
        router.configurationChanged()
        XCTAssertFalse(router.accepts(route))
    }
    func testTargetedTestingIgnoresOtherEnabledGestures() {
        let c = Configuration()
        var router = GestureRouter(); router.setMode(.testing)
        for sample in trajectory(.tiltRight) {
            XCTAssertNil(router.update(sample, configuration: c, testingGesture: .nod))
            XCTAssertNil(router.status[.tiltRight])
        }
        let routes = trajectory(.nod).map { s in
            MotionSample(time: s.time + 1.3, pitch: s.pitch)
        }.compactMap { router.update($0, configuration: c, testingGesture: .nod) }
        XCTAssertEqual(routes.map(\.gesture), [.nod])
        XCTAssertTrue(routes.allSatisfy { !$0.executes })
        XCTAssertNil(router.update(.init(time: 3), configuration: c, testingGesture: .shake))
        XCTAssertTrue(router.status.isEmpty)
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
        let t = GestureTuning.defaults(for: .tiltLeft)
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
