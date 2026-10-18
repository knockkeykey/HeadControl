# 头势控制

AirPods Pro 2 的原生 macOS 菜单栏工具：**头势 → 快捷键**。SwiftUI + AppKit + Core Motion，macOS 15.3+、Apple Silicon。

## 使用

1. 打开 `build/HeadControl.app`，在“概览”连接耳机并校准正前方。
2. 在“快捷键”为六个头势分别选择点按快捷键、不操作或暂停控制。录入时区分左右修饰键，也可直接选右 Option、Return、Esc、空格。
3. 在“校准测试”开启头势测试，检查动作与预计快捷键；测试模式不发送任何按键。
4. 回到“概览”开启头势控制，切到你要操作的应用。

启动始终默认暂停。修改绑定或识别参数会暂停控制并清空未完成的动作；测试模式中可继续调节。耳机断连、数据中断、左右耳来源改变或重新校准也会暂停控制。

| 头势 | 默认快捷键 |
|---|---|
| 左歪头 | 右 Option 单击 |
| 完整点头 | Return 单击 |
| 右歪头、左右转头、完整摇头 | 不操作 |

所有绑定全局生效。右 Option 是否切换语音、Return 是否发送或换行，取决于当前应用和输入法设置。工具只点按快捷键，不判断录音、文字是否完成或消息是否发送；不区分微信、GPT、Codex，也不读取输入框。可随时改键或禁用任一头势。

每次触发只点按一次，不持续按住、不执行多步骤宏。点头和摇头需完整动作；持续歪头不会连续发键，必须回正并经过冷却。与实际键盘修饰键冲突时跳过，按下／松开配对执行；若采集到动作后、发键前切换前台应用，本次操作跳过。

## 调节与反馈

“头势调节”提供每个头势的轻柔、标准、稳健档位，以及角度、停留时间、完成时限、回正范围和冷却时间。悬浮条不抢输入焦点，显示状态、最近发出的快捷键或跳过原因，并提供暂停按钮。提示音、悬浮条与程序坞图标可在“通用”关闭。

## 权限与隐私

头势控制需要运动与健身、辅助功能／事件发送权限。头势页另有可选的麦克风电平，只有点击“开启电平”才申请麦克风权限；关闭、离开头势页、关闭设置窗口或退出时停止读取。不保存或上传音频，不自行语音识别、不连接服务器、不读取或保存任何输入文字。微信输入法如用于语音，仍由它自行管理麦克风和识别。

配置保存到 `~/Library/Application Support/com.keyknock.HeadControl/configuration.json`。版本 2 只保存全局绑定、头势参数和反馈偏好。首次载入旧版本时，先备份原文件，保留头势参数、提示音和悬浮条设置，改用上表的全局预设；旧的应用和语音状态配置不再参与控制。无效／较新版本的配置保留原件，暂停保存并提示备份后重置。

## 头势页的公开数据

- `CMHeadphoneMotionManager` / `CMDeviceMotion`：三轴角速度（°/s 与 rad/s）、去除重力后的用户加速度（g）、重力（g）、当前运动数据来源耳机、采样时间戳、按时间戳估算的实际采样频率及累计采样数。
- “系统姿态与采集详情”：系统参考系下的 yaw/pitch/roll、四元数、3×3 旋转矩阵、运动授权、运动及连接监听状态、活动服务连接与最近数据时间。这里的系统姿态与校准后的头势角度明确区分。
- `CMHeadphoneActivityManager`（macOS 15+）：静止、步行、跑步等活动分类、置信度与可用的活动开始时间；系统返回缺省时间时显示未提供。依据运行时能力检测显示等待、不支持或错误状态，不将耳机接口尚不支持的骑行／驾车作为有效结果。
- 磁场与航向：只在系统返回有效值时展示；磁场精度为 uncalibrated 时不展示磁场，也不将此时耳机可能返回的默认航向 0 当作有效方向；航向另需处于有效角度范围。
- 可选 `AVAudioEngine` / Core Audio 电平：显示实际输入设备名称、RMS／峰值 dBFS、采样率、声道数。跟随系统输入；只有系统选中 AirPods 输入时才是耳机麦克风数据。dBFS 是数字电平，不是校准后的环境噪声 dBA。

运动数值面板每秒最多刷新 10 次，头势识别仍接收每个姿态样本。停止、数据中断或来源耳机改变时清空采样统计和数值，避免把旧值当作实时值。不接入私有蓝牙协议或未公开的电量、降噪和触控传感器接口；iPhone HealthKit 历史记录不属于此 Mac 页面的实时耳机数据。

苹果文档：[耳机运动](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager)、[运动样本](https://developer.apple.com/documentation/coremotion/cmdevicemotion)、[耳机活动](https://developer.apple.com/documentation/coremotion/cmheadphoneactivitymanager)、[音频输入](https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode)。

最终应用标识为 `com.keyknock.HeadControl`；Debug 为独立的 `com.keyknock.HeadControl.Debug`。两者在系统设置里都显示为 “头势控制”，权限应授予最终 `build/HeadControl.app`。应用以 Developer ID 签名，重新构建后权限保持有效。

## 构建与测试

```sh
cd /Users/keyknock/Downloads/cut/HeadControl
./scripts/test.sh
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
