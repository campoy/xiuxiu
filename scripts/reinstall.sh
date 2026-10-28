#!/bin/bash
# Rebuilds xiuxiu and installs it over the copy on the phone, over Wi-Fi if need be.
#
# A free Personal Team signs with 7-day provisioning profiles, after which the app stops
# launching. Every build under -allowProvisioningUpdates fetches a fresh one, and installing
# over the existing app keeps its entries and the downloaded model, so running this more
# often than weekly keeps the app alive indefinitely.
#
#   scripts/reinstall.sh "<device>"              rebuild and install now
#   scripts/reinstall.sh --schedule "<device>"   do that every night at 03:00 via launchd
#
# <device> is anything devicectl accepts: the name in `xcrun devicectl list devices`, or its
# identifier. Pair the phone by cable once and enable "Connect via network" first.

set -euo pipefail

label=cat.campoy.xiuxiu.reinstall
log="$HOME/Library/Logs/xiuxiu-reinstall.log"
repo="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${1:-}" == "--schedule" ]]; then
  device="${2:?usage: $0 --schedule <device>}"
  plist="$HOME/Library/LaunchAgents/$label.plist"
  mkdir -p "$(dirname "$plist")"
  # launchd starts jobs with a bare PATH that has neither Homebrew nor nix-darwin on it, so
  # xcodegen would not be found. Freezing the current PATH into the job is the simplest fix.
  #
  # StartCalendarInterval runs a missed slot as soon as the Mac wakes, so a Mac asleep at
  # 03:00 still gets its run, just later and with whatever luck the phone's Wi-Fi has then.
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$repo/scripts/reinstall.sh</string>
    <string>$device</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$PATH</string></dict>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$log</string>
  <key>StandardErrorPath</key><string>$log</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  echo "Scheduled nightly at 03:00. Log: $log"
  echo "Run it now with: launchctl kickstart gui/$(id -u)/$label"
  exit 0
fi

device="${1:?usage: $0 <device>}"
cd "$repo"
echo "== $(date '+%F %T') reinstall to $device"

# Check before building: a phone that is asleep or away is the normal case for a nightly
# run, and it should cost a line in the log rather than a full build. "unavailable" has no
# space before "available", so this does not match a device that is out of reach.
if ! xcrun devicectl list devices 2>/dev/null | grep -F -- "$device" | grep -q ' available'; then
  echo "$device is not reachable; trying again next run."
  exit 0
fi

xcodegen --quiet
# generic/platform=iOS rather than the phone's id: xcodebuild wants the hardware UDID while
# devicectl names devices by a different identifier, and the build does not need either.
xcodebuild -quiet -project xiuxiu.xcodeproj -scheme xiuxiu -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device "$device" \
  DerivedData/Build/Products/Debug-iphoneos/xiuxiu.app
echo "Installed."
