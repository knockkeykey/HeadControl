import CoreMotion
import Foundation

enum PublicDataState: Equatable {
    case stopped, waiting, receiving, unsupported, denied, failed(String)

    var title: String {
        switch self {
        case .stopped: "未开始"
        case .waiting: "等待系统数据"
        case .receiving: "正在接收"
        case .unsupported: "当前设备不支持"
        case .denied: "运动权限不可用"
        case .failed(let message): message
        }
    }
}

struct HeadphoneTelemetry {
    let timestamp: Double
    let receivedAt: Date
    let frequency: Double?
    let sampleCount: Int
    let rotationRate: SensorVector
    let acceleration: SensorVector
    let gravity: SensorVector
    let attitude: MotionSample
    let quaternion: [Double]
    let rotationMatrix: [Double]
    let heading: Double?
    let magneticField: SensorVector?
    let magneticAccuracy: String?

    init(motion: CMDeviceMotion, cadence: MotionCadence) {
        timestamp = motion.timestamp; receivedAt = Date()
        frequency = cadence.frequency; sampleCount = cadence.sampleCount
        rotationRate = .init(x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z)
        acceleration = .init(x: motion.userAcceleration.x, y: motion.userAcceleration.y, z: motion.userAcceleration.z)
        gravity = .init(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z)
        let degrees = 180.0 / Double.pi
        attitude = .init(time: motion.timestamp, yaw: motion.attitude.yaw * degrees,
                         pitch: motion.attitude.pitch * degrees, roll: motion.attitude.roll * degrees)
        let q = motion.attitude.quaternion
        quaternion = [q.x, q.y, q.z, q.w]
        let m = motion.attitude.rotationMatrix
        rotationMatrix = [m.m11, m.m12, m.m13, m.m21, m.m22, m.m23, m.m31, m.m32, m.m33]
        // These fields also exist on CMDeviceMotion for other Apple devices. Do not show
        // a default zero as a valid compass or magnetometer reading from headphones.
        let magnetic = motion.magneticField
        let vector = SensorVector(x: magnetic.field.x, y: magnetic.field.y, z: magnetic.field.z)
        if magnetic.accuracy != .uncalibrated && vector.isFinite {
            magneticField = vector
            // Headphones can return a default heading of zero even without a north
            // reference. Never accept it without a usable calibrated magnetic field.
            heading = motion.heading.isFinite && (0...360).contains(motion.heading) ? motion.heading : nil
            switch magnetic.accuracy {
            case .low: magneticAccuracy = "低"
            case .medium: magneticAccuracy = "中"
            case .high: magneticAccuracy = "高"
            default: magneticAccuracy = nil
            }
        } else { magneticField = nil; magneticAccuracy = nil; heading = nil }
    }
}

struct HeadphoneActivityReading {
    let title: String
    let confidence: String?
    let startedAt: Date?

    init(_ activity: CMMotionActivity) {
        var types: [String] = []
        if activity.stationary { types.append("静止") }
        if activity.walking { types.append("步行") }
        if activity.running { types.append("跑步") }
        if activity.unknown { types.append("未知活动") }
        title = types.isEmpty ? "未分类" : types.joined(separator: "、")
        if types.isEmpty { confidence = nil }
        else {
            switch activity.confidence {
            case .low: confidence = "低"
            case .medium: confidence = "中"
            case .high: confidence = "高"
            @unknown default: confidence = "未知"
            }
        }
        // Some headphone updates supply an epoch/default date instead of an activity time.
        let date = activity.startDate
        let validDate = date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 != 0
            && date.timeIntervalSinceReferenceDate != 0 && date <= Date().addingTimeInterval(1)
        startedAt = validDate ? date : nil
    }
}
