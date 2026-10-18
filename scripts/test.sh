#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift test --package-path "$task_root/Core"
