#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# One-time cleanup of the 2.0 OwlControl build and data; each step only runs if the old item exists.
legacy_app="$task_root/build/OwlControl.app"
legacy_support="$HOME/Library/Application Support/com.keyknock.OwlControl"
if [[ -d "$legacy_app" ]]; then rm -rf "$legacy_app"; echo "已删除旧应用：$legacy_app"; fi
if [[ -d "$legacy_support" ]]; then rm -rf "$legacy_support"; echo "已删除旧配置：$legacy_support"; fi
for domain in com.keyknock.OwlControl com.keyknock.OwlControl.Debug; do
  if defaults read "$domain" >/dev/null 2>&1; then defaults delete "$domain"; echo "已删除旧偏好设置：$domain"; fi
done
python3 "$task_root/scripts/generate_project.py"
xcodebuild -project "$task_root/HeadControl.xcodeproj" -scheme HeadControl -configuration Release -derivedDataPath "$task_root/build/DerivedData" build
rm -rf "$task_root/build/HeadControl.app"
ditto "$task_root/build/DerivedData/Build/Products/Release/HeadControl.app" "$task_root/build/HeadControl.app"
codesign --verify --deep --strict "$task_root/build/HeadControl.app"
echo "应用：$task_root/build/HeadControl.app"
