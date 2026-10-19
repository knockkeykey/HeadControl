#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
probe_root=$(mktemp -d /tmp/headcontrol-app-controller.XXXXXX)
trap 'rm -rf "$probe_root"' EXIT
xcrun swiftc -D INTERFACE_PROBE -parse-as-library \
  "$task_root/Tests/Platform/SoundFeedbackProbe.swift" \
  "$task_root/Tests/Platform/ApplicationControllerProbe.swift" \
  "$task_root/HeadControl/App/AppController.swift" \
  "$task_root/HeadControl/Platform/ConfigurationStore.swift" \
  "$task_root/HeadControl/Platform/ApplicationSwitcher.swift" \
  "$task_root"/Core/Sources/HeadControlCore/*.swift -o "$probe_root/controller"
"$probe_root/controller"
