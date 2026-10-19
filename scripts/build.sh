#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 "$task_root/scripts/generate_project.py"
xcodebuild -project "$task_root/HeadControl.xcodeproj" -scheme HeadControl -configuration Release -derivedDataPath "$task_root/build/DerivedData" "$@" build
rm -rf "$task_root/build/HeadControl.app"
ditto "$task_root/build/DerivedData/Build/Products/Release/HeadControl.app" "$task_root/build/HeadControl.app"
codesign --verify --deep --strict "$task_root/build/HeadControl.app"
echo "应用：$task_root/build/HeadControl.app"
