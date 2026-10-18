#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
probe_root="$task_root/build/KeyDeliveryProbe"
sender_source="${HEADCONTROL_KEY_SENDER_SOURCE:-$task_root/HeadControl/Platform/KeySender.swift}"
mkdir -p "$probe_root"
sender_app="$probe_root/Sender.app"
receiver_app="$probe_root/Receiver.app"
for probe_app in "$sender_app" "$receiver_app"; do
  mkdir -p "$probe_app/Contents/MacOS"
done
# Compile the production KeySender, not a duplicate of its event-posting implementation.
xcrun swiftc -parse-as-library "$task_root/Tests/Platform/KeyDeliveryProbe.swift" \
  "$sender_source" "$task_root"/Core/Sources/HeadControlCore/*.swift \
  -o "$sender_app/Contents/MacOS/KeyDeliveryProbe"
cp "$sender_app/Contents/MacOS/KeyDeliveryProbe" "$receiver_app/Contents/MacOS/KeyDeliveryProbe"
for role in Sender Receiver; do
  bundle_id="com.keyknock.HeadControlProbe.Receiver"
  ui_element="false"
  # Same Debug identity and signature as the app already authorized on this Mac.
  if [[ "$role" == Sender ]]; then bundle_id="com.keyknock.HeadControl.Debug"; ui_element="true"; fi
  cat > "$probe_root/$role.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleExecutable</key><string>KeyDeliveryProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleName</key><string>HeadControlKeyDelivery$role</string>
<key>LSUIElement</key><$ui_element/>
</dict></plist>
PLIST
  codesign --force --sign "Developer ID Application" --options runtime "$probe_root/$role.app"
done
runtime_root=$(mktemp -d /tmp/headcontrol-key-delivery.XXXXXX)
result_file="$runtime_root/result.txt"
received_file="$runtime_root/received.csv"
: > "$result_file"
: > "$received_file"
open -n -a "$sender_app" --args sender "$result_file" "$received_file" "$receiver_app"
for attempt in {1..250}; do
  if [[ -s "$result_file" ]]; then
    cat "$result_file"
    [[ "$(head -c 4 "$result_file")" == PASS ]] && exit 0
    exit 1
  fi
  sleep 0.1
done
echo "FAIL: timed out; check $runtime_root"
exit 1
