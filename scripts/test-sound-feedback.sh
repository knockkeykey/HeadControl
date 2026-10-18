#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
probe_root=$(mktemp -d /tmp/headcontrol-feedback-probe.XXXXXX)
trap 'rm -rf "$probe_root"' EXIT
controller_source="${HEADCONTROL_CONTROLLER_SOURCE:-$task_root/HeadControl/App/AppController.swift}"
xcrun swiftc -parse-as-library "$task_root/Tests/Platform/SoundFeedbackProbe.swift" \
  "$controller_source" "$task_root/HeadControl/Platform/ConfigurationStore.swift" \
  "$task_root"/Core/Sources/HeadControlCore/*.swift -o "$probe_root/controller"
"$probe_root/controller"
xcrun swiftc -parse-as-library "$task_root/Tests/Platform/SoundRecoveryProbe.swift" \
  "$task_root/HeadControl/Platform/SoundFeedback.swift" \
  "$task_root"/Core/Sources/HeadControlCore/*.swift -o "$probe_root/recovery"
"$probe_root/recovery"
if [[ "${HEADCONTROL_SKIP_PLAYBACK:-0}" != 1 ]]; then
  xcrun swiftc -parse-as-library "$task_root/Tests/Platform/SoundPlaybackProbe.swift" \
    "$task_root/HeadControl/Platform/SoundFeedback.swift" \
    "$task_root"/Core/Sources/HeadControlCore/*.swift -o "$probe_root/playback"
  "$probe_root/playback"
fi
