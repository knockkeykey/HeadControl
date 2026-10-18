import CoreMotion
import SwiftUI

struct MotionDataPanel: View {
    @ObservedObject var motion: MotionService
    @ObservedObject var microphone: MicrophoneService
    @State private var details = false

    private var data: HeadphoneTelemetry? { motion.telemetry }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 22, alignment: .top), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionTitle(title: "耳机实时数据")
                        Spacer()
                        Label(motion.tracking ? "正在接收 · \(motion.sensor)" : "等待运动数据",
                              systemImage: motion.tracking ? "waveform.path" : "pause.circle")
                            .font(.caption).foregroundStyle(motion.tracking ? .green : .secondary)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        vector("角速度", symbol: "rotate.3d", value: data?.rotationRate.scaled(by: 180 / .pi), unit: "°/s", digits: 1)
                        vector("用户加速度", symbol: "waveform.path", value: data?.acceleration, unit: "g", digits: 3)
                        vector("重力", symbol: "arrow.down", value: data?.gravity, unit: "g", digits: 3)
                    }
                    Text("三轴以耳机坐标系为准。用户加速度已去除重力，1 g 约为 9.81 m/s²。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    activityReadout
                    Divider()
                    HStack(spacing: 24) {
                        compactValue("采样频率", value: data?.frequency.map { "\(number($0, digits: 1)) Hz" } ?? (data == nil ? "等待数据" : "测量中"))
                        compactValue("采样时间戳", value: data.map { "\(number($0.timestamp, digits: 3)) s" } ?? "等待数据")
                        compactValue("累计采样", value: data.map { "\($0.sampleCount) 次" } ?? "等待数据")
                    }
                    DisclosureGroup("系统姿态与采集详情", isExpanded: $details) {
                        systemDetails.padding(.top, 14)
                    }
                    .font(.callout)
                }
            }
            MicrophoneDataCard(microphone: microphone)
        }
    }

    private var activityReadout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("活动", systemImage: "figure.walk").font(.callout.weight(.medium))
                Spacer()
                Text(motion.activity?.title ?? motion.activityState.title)
                    .font(.callout.weight(.medium)).multilineTextAlignment(.trailing)
                    .foregroundStyle(motion.activityState == .receiving ? Color.primary : Color.secondary)
            }
            if let activity = motion.activity {
                HStack {
                    if let confidence = activity.confidence { Text("置信度：\(confidence)") }
                    Spacer()
                    if let date = activity.startedAt { Text("开始于 \(date.formatted(date: .omitted, time: .standard))") }
                    else { Text("系统未提供开始时间") }
                }.font(.caption).foregroundStyle(.secondary)
            } else {
                Text("由系统识别静止、步行和跑步；不支持或尚未返回时会显示状态。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var systemDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("系统参考姿态").font(.callout.weight(.medium))
                HStack(spacing: 24) {
                    compactValue("Yaw", value: angle(data?.attitude.yaw))
                    compactValue("Pitch", value: angle(data?.attitude.pitch))
                    compactValue("Roll", value: angle(data?.attitude.roll))
                }
                Text("这里保留系统参考系。上方小球和头势角度使用你校准的正前方。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("四元数").font(.callout.weight(.medium))
                HStack(alignment: .top, spacing: 28) {
                    ForEach(Array(["x", "y", "z", "w"].enumerated()), id: \.offset) { index, label in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label).font(.caption).foregroundStyle(.secondary)
                            Text(number(data?.quaternion[index], digits: 4))
                                .font(.system(.callout, design: .monospaced)).monospacedDigit()
                        }
                    }
                }.textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("旋转矩阵").font(.callout.weight(.medium))
                Text(matrixText)
                    .font(.system(.callout, design: .monospaced)).monospacedDigit()
                    .lineSpacing(6).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                vector("角速度原始单位", symbol: "rotate.3d", value: data?.rotationRate, unit: "rad/s", digits: 3)
                vector("有效磁场", symbol: "safari", value: data?.magneticField, unit: "µT", digits: 2,
                       empty: data == nil ? "等待数据" : "系统未提供有效值")
                VStack(alignment: .leading, spacing: 10) {
                    Label("有效航向", systemImage: "location.north").font(.callout.weight(.medium))
                    Text(data?.heading.map { "\(number($0, digits: 1))°" } ?? (data == nil ? "等待数据" : "系统未提供有效值"))
                        .font(.callout).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    if let accuracy = data?.magneticAccuracy { Text("磁场精度：\(accuracy)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Text("磁场需有效校准，航向还需北向参考系。耳机未提供时不会将默认的 0 当作有效方向。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(spacing: 9) {
                field("运动权限", value: authorizationTitle)
                field("运动采集", value: motion.deviceMotionActive ? "已启动" : "未启动")
                field("运动连接监听", value: motion.connectionUpdatesActive ? "已启动" : "未启动")
                field("活动连接事件", value: motion.activityConnection)
                field("活动采集", value: motion.activityState.title)
                field("最近收到数据", value: data?.receivedAt.formatted(date: .omitted, time: .standard) ?? "暂无")
            }
            Text("数据来自苹果公开的 Core Motion 接口。连接状态表示数据服务连接，不等同于每只耳机的佩戴检测。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var authorizationTitle: String {
        switch motion.authorization {
        case .authorized: "已授权"
        case .notDetermined: "尚未请求"
        case .denied: "未授予"
        case .restricted: "系统限制"
        @unknown default: "未知"
        }
    }

    private var matrixText: String {
        guard let values = data?.rotationMatrix else { return "等待数据" }
        return (0..<3).map { row in
            (0..<3).map { column in
                String(format: "%8.4f", values[row * 3 + column])
            }.joined(separator: "    ")
        }.joined(separator: "\n")
    }

    private func vector(_ title: String, symbol: String, value: SensorVector?, unit: String, digits: Int, empty: String = "等待数据") -> some View {
        let valid = value.flatMap { $0.isFinite ? $0 : nil }
        return VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol).font(.callout.weight(.medium))
            if let valid {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(number(valid.magnitude, digits: digits)).font(.system(.title3, design: .rounded).weight(.medium)).monospacedDigit()
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array([valid.x, valid.y, valid.z].enumerated()), id: \.offset) { index, value in
                    HStack {
                        Text(["X", "Y", "Z"][index]).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(number(value, digits: digits)).monospacedDigit()
                    }.font(.system(.caption, design: .monospaced))
                }
            } else {
                Text(empty).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .textSelection(.enabled).accessibilityElement(children: .combine)
    }

    private func compactValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).monospacedDigit().textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.callout)
    }

    private func number(_ value: Double?, digits: Int) -> String {
        guard let value, value.isFinite else { return "暂无" }
        let rounded = abs(value) < pow(10, -Double(digits)) / 2 ? 0 : value
        return String(format: "%.*f", digits, rounded)
    }
    private func angle(_ value: Double?) -> String { value.map { "\(number($0, digits: 1))°" } ?? "等待数据" }
}

private struct MicrophoneDataCard: View {
    @ObservedObject var microphone: MicrophoneService

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("麦克风电平", systemImage: "mic").font(.headline)
                    Spacer()
                    if microphone.state == .denied {
                        Button("去授权") { microphone.openSettings() }
                    } else {
                        Button(microphone.isStarted ? "停止读取" : "开启电平") {
                            if microphone.isStarted { microphone.stop() } else { microphone.start() }
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(microphone.inputName).font(.callout.weight(.medium)).textSelection(.enabled)
                    Spacer()
                    Text(microphone.state.title).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                Text("跟随系统的声音输入设备；选择 AirPods 时，这里才是耳机麦克风的数据。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let level = microphone.level {
                    ProgressView(value: level.meterFraction).tint(.green)
                        .accessibilityLabel("麦克风电平").accessibilityValue("\(Int(level.rmsDecibels)) dBFS")
                    HStack(spacing: 20) {
                        Text("平均 \(level.rmsDecibels, specifier: "%.1f") dBFS")
                        Text("峰值 \(level.peakDecibels, specifier: "%.1f") dBFS")
                        Spacer(minLength: 0)
                    }.font(.callout).monospacedDigit()
                    HStack {
                        if let rate = microphone.sampleRate { Text("\(rate / 1000, specifier: "%.1f") kHz") }
                        if let channels = microphone.channelCount { Text("\(channels) 声道") }
                    }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Text("开启时才申请麦克风权限，不保存或上传音频。电平为 dBFS，不能当作环境噪声 dBA。离开头势页会停止读取。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { microphone.refreshInputStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphone.refreshInputStatus()
        }
    }
}
