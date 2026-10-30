#!/usr/bin/env bash
# Build xiuxiu for a device and install it on the paired iPhone, cable or Wi-Fi.
# The by-hand equivalent of ⌘R, and what re-signs the app before the free
# account's 7-day profile runs out. The dotfiles repo runs it daily on the mini.
#
# Reinstalling over the app keeps its data, so entries and the model survive.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen --quiet

# -allowProvisioningUpdates is what fetches a fresh profile once the old one
# expires. It needs the Apple ID signed in to Xcode on this Mac and the login
# keychain unlocked, so this has to run inside a logged-in session.
xcodebuild -quiet -project xiuxiu.xcodeproj -scheme xiuxiu \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData \
  -allowProvisioningUpdates build

# The phone shows up over the local network once it has been paired with this
# Mac by cable. The Apple Watch is paired too, hence the platform filter.
devices=$(mktemp)
trap 'rm -f "$devices"' EXIT
xcrun devicectl list devices --quiet --json-output "$devices"
phone=$(jq -r 'first(.result.devices[]
  | select(.hardwareProperties.reality == "physical"
       and .hardwareProperties.platform == "iOS"
       and .connectionProperties.pairingState == "paired")
  | .identifier) // empty' "$devices")
if [[ -z "$phone" ]]; then
  echo "no paired iPhone; plug it into this Mac once and tap Trust" >&2
  exit 1
fi

xcrun devicectl device install app --device "$phone" \
  DerivedData/Build/Products/Debug-iphoneos/xiuxiu.app
