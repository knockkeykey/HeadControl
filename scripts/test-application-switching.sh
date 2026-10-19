#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
probe_root=$(mktemp -d /tmp/headcontrol-app-switch.XXXXXX)
trap 'rm -rf "$probe_root"' EXIT
for role in Sender Receiver Anchor; do
  mkdir -p "$probe_root/$role.app/Contents/MacOS"
done
xcrun swiftc -parse-as-library "$task_root/Tests/Platform/ApplicationSwitchProbe.swift" \
  "$task_root/HeadControl/Platform/ApplicationSwitcher.swift" \
  "$task_root"/Core/Sources/HeadControlCore/*.swift -o "$probe_root/Sender.app/Contents/MacOS/ApplicationSwitchProbe"
cp "$probe_root/Sender.app/Contents/MacOS/ApplicationSwitchProbe" "$probe_root/Receiver.app/Contents/MacOS/ApplicationSwitchProbe"
cp "$probe_root/Sender.app/Contents/MacOS/ApplicationSwitchProbe" "$probe_root/Anchor.app/Contents/MacOS/ApplicationSwitchProbe"
for role in Sender Receiver Anchor; do
  cat > "$probe_root/$role.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.keyknock.HeadControl.SwitchProbe.$role.${probe_root:t}</string>
<key>CFBundleExecutable</key><string>ApplicationSwitchProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleName</key><string>HeadControlSwitch$role</string>
<key>ProbeStatePath</key><string>$probe_root/${(L)role}-state.txt</string>
</dict></plist>
PLIST
  codesign --force --sign - "$probe_root/$role.app"
done
open -n -a "$probe_root/Sender.app" --args sender "$probe_root/result.txt" "$probe_root/Receiver.app"
for attempt in {1..400}; do
  if [[ -s "$probe_root/result.txt" ]]; then
    cat "$probe_root/result.txt"
    [[ "$(head -c 4 "$probe_root/result.txt")" == PASS ]] && exit 0
    exit 1
  fi
  sleep 0.1
done
echo "FAIL: application switching probe timed out"
exit 1
