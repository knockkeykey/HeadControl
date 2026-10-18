# 头势控制

AirPods Pro 2 的原生 macOS 菜单栏工具：**头势 → 快捷键**。SwiftUI + AppKit + Core Motion，macOS 15.3+、Apple Silicon。

## 使用

1. 打开 `build/HeadControl.app`，在“概览”连接耳机并校准正前方。
2. 在“头势”页为六个头势分别选择点按快捷键、不操作或暂停控制。录入时区分左右修饰键，也可直接选右 Option、Return、Esc、空格。
3. 在“校准测试”开启头势测试，检查动作与预计快捷键；测试模式不发送任何按键。
4. 回到“概览”开启头势控制，切到你要操作的应用。

启动始终默认暂停。修改绑定或识别参数会暂停控制并清空未完成的动作；测试模式中可继续调节。耳机断连、数据中断、左右耳来源改变或重新校准也会暂停控制。

| 头势 | 默认快捷键 |
|---|---|
| 左歪头 | 右 Option 单击 |
| 完整点头 | Return 单击 |
| 右歪头、左右转头、完整摇头 | 不操作 |

所有绑定全局生效。右 Option 是否切换语音、Return 是否发送或换行，取决于当前应用和输入法设置。工具只点按快捷键，不判断录音、文字是否完成或消息是否发送；不区分微信、GPT、Codex，也不读取输入框。可随时改键或禁用任一头势。

每次触发只点按一次，不持续按住、不执行多步骤宏。所有按键（含单独的 Option、Shift、Control、Command）都通过 HID 事件发送，输入法（如微信输入法的右 Option 语音）才能收到，并保留左右键身份。点头和摇头需完整动作；不需要先回正，任何姿势下都能开始做头势；持续歪头不会连续发键，触发后在该方向收回到阈值的 70% 以内并经过冷却才能再次触发。修改设置不会暂停头势控制，新设置从下一个动作开始生效。与实际键盘修饰键冲突时跳过，按下／松开配对执行；若采集到动作后、发键前切换前台应用，本次操作跳过。

## 调节与反馈

头势页为每个头势提供轻柔、标准、稳健三档，可拖动圆弧上的圆点调整动作幅度，并用“慢 ↔ 快”滑块调整动作速度。速度门槛来自耳机角速度：慢慢调整坐姿不会触发；点头和摇头要求下去和回来都够快。测试时会记录你的实际幅度和速度，“采用建议”一次设好两项（取实测值的 70%）。停留、完成时限、点头／摇头的回位范围和冷却时间随档位自动设定，不在界面展示。走路或跑步时自动暂停识别、停下后自动恢复，可在“通用”关闭。悬浮条不抢输入焦点，显示状态、最近发出的快捷键或跳过原因，并提供暂停按钮。提示音、悬浮条、走动暂停与程序坞图标可在“通用”关闭。

## 权限与隐私

头势控制只需要运动与健身、辅助功能／事件发送权限，不需要麦克风。不连接服务器、不读取或保存任何输入文字。

配置保存到 `~/Library/Application Support/com.keyknock.HeadControl/configuration.json`。版本 3 只保存全局绑定、头势参数（含速度门槛）和反馈偏好；版本 2 迁移时保留原有参数，速度按所在档位补默认值，自定义档按标准速度。首次载入旧版本时，先备份原文件，保留头势参数、提示音和悬浮条设置，改用上表的全局预设；旧的应用和语音状态配置不再参与控制。无效／较新版本的配置保留原件，暂停保存并提示备份后重置。

## 使用的耳机数据

- `CMHeadphoneMotionManager` / `CMDeviceMotion`：校准后的转头、点头、歪头角度，以及对应轴的角速度（用于速度门槛）。头势识别接收每个样本，界面只显示小球、圆弧和简单状态，不展示原始数值。
- `CMHeadphoneActivityManager`（macOS 15+）：只用来判断是否在走路或跑步，以便自动暂停；不显示、不保存活动记录。

不接入私有蓝牙协议或未公开的传感器接口。

苹果文档：[耳机运动](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager)、[运动样本](https://developer.apple.com/documentation/coremotion/cmdevicemotion)、[耳机活动](https://developer.apple.com/documentation/coremotion/cmheadphoneactivitymanager)、[音频输入](https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode)。

最终应用标识为 `com.keyknock.HeadControl`；Debug 为独立的 `com.keyknock.HeadControl.Debug`。两者在系统设置里都显示为 “头势控制”，权限应授予最终 `build/HeadControl.app`。应用以 Developer ID 签名，重新构建后权限保持有效。

## 构建与测试

```sh
cd /Users/keyknock/Downloads/cut/HeadControl
./scripts/test.sh
# 需本机已有 Debug 版事件发送权限；会打开专用接收窗口，约 12 秒
./scripts/test-key-delivery.sh
./scripts/build.sh
open build/HeadControl.app
```

Xcode 打开 `HeadControl.xcodeproj`，选择 HeadControl scheme。工程无第三方依赖，脚本仅为当前命令指定 Xcode，不更改全局 xcode-select。Release 2.1.0 (4)，arm64，Developer ID 签名（团队 MR285FSGSG）与 hardened runtime，未公证。

- `Core`：配置迁移、头势识别、全局路由、按键序列规划及自动化测试。
- `HeadControl/Platform`：耳机、按键发送、配置存储、悬浮条。
- `HeadControl/Views`：原生设置、快捷键录入、姿态与动作测试。
- `VALIDATION.md`：已完成的技术检查与真机验证边界。

## 参考与许可

参考 HeadOrbit 的公开运动采集与坐标约定，采用独立结构实现。MIT 许可证及归属保留在 `ThirdPartyNotices/HeadOrbit-LICENSE.txt`。未使用私有背景模糊接口或网络更新功能。
