#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
views_root="${HEADCONTROL_TEST_VIEWS_ROOT:-$task_root/HeadControl/Views}"
probe_root=$(mktemp -d /tmp/headcontrol-interface-probe.XXXXXX)
trap 'rm -rf "$probe_root"' EXIT
output_root="${1:-/tmp/headcontrol-interface}"
mkdir -p "$output_root"
xcrun swiftc -D INTERFACE_PROBE -parse-as-library \
  "$task_root/Tests/Platform/SoundFeedbackProbe.swift" \
  "$task_root/Tests/Platform/InterfaceProbe.swift" \
  "$task_root/HeadControl/App/AppController.swift" \
  "$task_root/HeadControl/Platform/ConfigurationStore.swift" \
  "$task_root/HeadControl/Platform/Snapshot.swift" \
  "$views_root"/*.swift \
  "$task_root"/Core/Sources/HeadControlCore/*.swift -o "$probe_root/interface"
if [[ "${2:-}" == --interactive ]]; then
  app_root="$output_root/HeadControlInterfaceProbe.app"
  mkdir -p "$app_root/Contents/MacOS" "$app_root/Contents/Resources"
  cp "$probe_root/interface" "$app_root/Contents/MacOS/HeadControlInterfaceProbe"
  cat > "$app_root/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.keyknock.HeadControl.InterfaceProbe</string>
<key>CFBundleExecutable</key><string>HeadControlInterfaceProbe</string>
<key>CFBundleName</key><string>HeadControlInterfaceProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
  if [[ -n "${HEADCONTROL_TEST_CONFIGURATION:-}" ]]; then
    cp "$HEADCONTROL_TEST_CONFIGURATION" "$app_root/Contents/Resources/configuration.json"
  fi
  echo "Interface navigation fixture: $app_root (synthetic sensor, no key or audio IO)"
  exit 0
fi
for scenario in practice joint feedback calibration; do
  page=gestures
  if [[ "$scenario" == feedback ]]; then page=status; fi
  snapshot="$probe_root/$scenario.png"
  "$probe_root/interface" "$scenario" "$snapshot" --page "$page"
  [[ -s "$snapshot" ]]
  cp "$snapshot" "$output_root/$scenario.png"
done
echo "PASS: four production-interface scenarios rendered to $output_root (synthetic motion, no key or audio IO)"
