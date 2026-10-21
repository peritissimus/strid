#!/usr/bin/env bash
# Build Strid for a connected iPhone and install it.
#
#   scripts/install-ios.sh                 # auto-detect team from Xcode accounts, first connected iPhone
#   TEAM_ID=ABCDE12345 scripts/install-ios.sh
#   DEVICE="knox" scripts/install-ios.sh   # pick a device by name (or UDID)
#
# Needs: Xcode 26+ with an Apple ID added (Settings > Accounts), the phone plugged in and trusted,
# Developer Mode on. A free Apple ID works; the profile then lasts 7 days — re-run to renew.
#
# Environment variables (all optional):
#   TEAM_ID       10-character Apple Developer Team ID. Skips auto-detection.
#   DEVICE        Substring of the device name or UDID to target when more
#                 than one iPhone is connected.
#   DERIVED_DATA  Where xcodebuild writes build products. Defaults to a
#                 dedicated Strid-ios folder so it does not collide with
#                 Xcode's own DerivedData for the project.
#
# Flow: resolve team -> wait for a device -> xcodebuild -> devicectl install -> devicectl launch.

# Strict mode: abort on any failing command (-e), on use of an unset variable (-u),
# and make a pipeline fail if any stage fails (-o pipefail), not just the last one.
set -euo pipefail

# Resolve paths relative to this script so it works from any cwd.
# BASH_SOURCE[0] is the script path; ".." climbs from scripts/ to the repo root.
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
proj="$repo/ios/StridApp/StridApp.xcodeproj"
scheme="StridApp_iOS"              # Xcode scheme for the iOS target (see project.yml)
bundle="com.strid.StridApp"        # Bundle identifier, needed to launch the app after install
# Separate DerivedData path keeps this script's builds isolated and makes the
# .app location predictable for the `find` further down.
dd="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Strid-ios}"

# --- Signing team -----------------------------------------------------------
# Code signing for a physical device needs a Team ID. Try, in order:
#   1. TEAM_ID from the environment.
team="${TEAM_ID:-}"
#   2. Xcode's own preferences. IDEProvisioningTeamByIdentifier lists the teams
#      for every Apple ID added in Xcode > Settings > Accounts; grab the first
#      10-char uppercase alphanumeric "teamID" value. `|| true` keeps set -e from
#      aborting when grep finds nothing.
if [[ -z "$team" ]]; then
  team="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | grep -E "teamID" | grep -oE "[A-Z0-9]{10}" | head -1 || true)"
fi
#   3. The keychain. Valid code-signing identities are named like
#      "Apple Development: Name (TEAMID1234)"; extract the parenthesised ID.
if [[ -z "$team" ]]; then
  team="$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '\(([A-Z0-9]{10})\)' | tr -d '()' | head -1 || true)"
fi
# Nothing found: explain how to fix it and stop before wasting a build.
if [[ -z "$team" ]]; then
  cat >&2 <<'MSG'
No signing team found.
  1. Open Xcode > Settings > Accounts and add your Apple ID (a free one is fine).
  2. Re-run this script, or pass TEAM_ID=XXXXXXXXXX explicitly.
MSG
  exit 1
fi
echo "Team: $team"

# --- Device discovery -------------------------------------------------------
# Wait up to 90 s for an available iPhone (it may be rebooting after Developer Mode).
# 18 iterations x 5 s sleep. Each pass:
#   - `devicectl list devices` prints a header (2 lines) then one row per device;
#     `awk 'NR>2'` drops the header, grep keeps iPhones only.
#   - If DEVICE is set, further filter rows by that fixed string (name or UDID).
#   - Keep only rows whose state is "available"/"connected", then drop any row
#     mentioning "unavailable" as cheap insurance against wording changes in
#     devicectl's output. Take the first match.
dev_line=""
for _ in $(seq 1 18); do
  # Newer devicectl also lists booted simulators ("simulated"); only real phones qualify.
  list="$(xcrun devicectl list devices 2>/dev/null | awk 'NR>2' | grep -iE 'iphone' | grep -iE 'physical')"
  if [[ -n "${DEVICE:-}" ]]; then list="$(echo "$list" | grep -iF "$DEVICE" || true)"; fi
  dev_line="$(echo "$list" | grep -iE '\b(available|connected)\b' | grep -viE 'unavailable' | head -1 || true)"
  [[ -n "$dev_line" ]] && break
  echo "Waiting for iPhone..."; sleep 5
done
# Timed out: tell the user the usual causes and dump the raw device list to help debugging.
if [[ -z "$dev_line" ]]; then
  echo "No available iPhone found. Plug it in, unlock it, tap Trust, enable Developer Mode, then retry." >&2
  xcrun devicectl list devices 2>/dev/null || true
  exit 1
fi
# devicectl identifiers look like "00008030-001A2B3C4D5E6F7G" (8 hex, dash, 16 hex).
# The device name is the first whitespace-delimited column of the row.
dev_id="$(echo "$dev_line" | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)"
dev_name="$(echo "$dev_line" | awk '{print $1}')"
echo "Device: $dev_name ($dev_id)"

# --- Build ------------------------------------------------------------------
echo "Building..."
# xcodebuild is extremely chatty, so its output is piped through grep to show
# only errors, BUILD SUCCEEDED/FAILED lines and provisioning/signing messages,
# deduplicated with sort -u. With pipefail on, grep returning 1 (no matches) or
# xcodebuild failing would abort the script here; set +e disables that so we
# can instead check for the produced .app below and give a clearer message.
#
# Flags:
#   -destination "id=$dev_id"            build for the specific connected phone
#   -derivedDataPath "$dd"               predictable output location
#   -allowProvisioningUpdates            let xcodebuild create/refresh the
#                                        provisioning profile automatically
#   -allowProvisioningDeviceRegistration register this iPhone with the team if
#                                        it is not yet in the developer portal
#   DEVELOPMENT_TEAM / CODE_SIGN_STYLE   override signing settings so the project
#                                        does not need a hard-coded team.
set +e
xcodebuild -project "$proj" -scheme "$scheme" -configuration Debug \
  -destination "id=$dev_id" -derivedDataPath "$dd" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic \
  build 2>&1 | grep -E "error:|error |BUILD|Provisioning|Signing" | sort -u
set -e

# Success is judged by whether the .app bundle exists, since the exit status of
# the pipeline above was intentionally ignored. Debug-iphoneos is the products
# folder for a Debug build targeting a physical device.
app="$(find "$dd/Build/Products/Debug-iphoneos" -maxdepth 1 -name 'StridApp.app' 2>/dev/null | head -1)"
[[ -n "$app" ]] || { echo "Build failed: StridApp.app not produced." >&2; exit 1; }

# --- Install & launch -------------------------------------------------------
echo "Installing..."
# Copies the signed .app onto the phone (replaces an existing install). This
# runs under set -e, so a failed install aborts the script.
xcrun devicectl device install app --device "$dev_id" "$app"
echo "Launching..."
# Launch is best-effort (`|| true`): on a free Apple ID the very first launch
# fails until the user trusts the developer certificate on the phone, and that
# should not be reported as a script failure.
xcrun devicectl device process launch --device "$dev_id" "$bundle" || true
echo "Done. First launch may ask you to trust the developer: Settings > General > VPN & Device Management."
