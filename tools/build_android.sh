#!/usr/bin/env bash
# Builds a signed Android APK you can sideload: build/OutlawsOfSherwood-<version>.apk
#
# Usage: GODOT=/path/to/godot-4.7.1 KEYSTORE=/path/to/outlaws-sideload.keystore tools/build_android.sh
#   KEYSTORE_ALIAS / KEYSTORE_PASS default to the sideload key (alias "outlaws").
#
# No Android SDK is needed: Godot exports an unsigned APK from its prebuilt template (it only checks
# that an SDK folder with apksigner exists, so a stub one is made), then uber-apk-signer aligns and signs it.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
KEYSTORE="${KEYSTORE:?set KEYSTORE to the signing keystore}"
KEYSTORE_ALIAS="${KEYSTORE_ALIAS:-outlaws}"
KEYSTORE_PASS="${KEYSTORE_PASS:-sherwood-sideload}"
GODOT_VERSION="4.7.1"
WORK="${WORK:-$HOME/.cache/outlaws-android}"
TEMPLATES="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
VERSION="$(sed -n 's/^version\/name="\(.*\)"/\1/p' export_presets.cfg)"
mkdir -p "$WORK" build

if [ ! -f "$TEMPLATES/android_release.apk" ]; then
  echo "Downloading Godot $GODOT_VERSION export templates..."
  curl -sSL -o "$WORK/templates.tpz" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
  mkdir -p "$TEMPLATES"
  unzip -o -q -j "$WORK/templates.tpz" 'templates/android_*' 'templates/version.txt' -d "$TEMPLATES"
  rm "$WORK/templates.tpz"
fi
if [ ! -f "$WORK/uber-apk-signer.jar" ]; then
  curl -sSL -o "$WORK/uber-apk-signer.jar" https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar
fi

# Stub SDK so Godot's export check passes; signing happens below.
SDK="$WORK/sdk"
mkdir -p "$SDK/platform-tools" "$SDK/build-tools/35.0.0"
printf '#!/bin/sh\nexit 0\n' > "$SDK/platform-tools/adb"
printf '#!/bin/sh\nexit 0\n' > "$SDK/build-tools/35.0.0/apksigner"
chmod +x "$SDK/platform-tools/adb" "$SDK/build-tools/35.0.0/apksigner"
SETTINGS="$(ls "$HOME"/.config/godot/editor_settings-4*.tres 2>/dev/null | tail -1 || true)"
if [ -z "$SETTINGS" ]; then
  "$GODOT" --headless --path . --quit >/dev/null 2>&1 || true
  SETTINGS="$(ls "$HOME"/.config/godot/editor_settings-4*.tres | tail -1)"
fi
if grep -q '^export/android/android_sdk_path' "$SETTINGS"; then
  sed -i "s|^export/android/android_sdk_path = .*|export/android/android_sdk_path = \"$SDK\"|" "$SETTINGS"
else
  echo "export/android/android_sdk_path = \"$SDK\"" >> "$SETTINGS"
fi

"$GODOT" --headless --path . --import >/dev/null 2>&1
rm -f build/unsigned.apk
"$GODOT" --headless --path . --export-release "Android" build/unsigned.apk
rm -rf build/signed
java -jar "$WORK/uber-apk-signer.jar" --apks build/unsigned.apk --ks "$KEYSTORE" --ksAlias "$KEYSTORE_ALIAS" \
  --ksPass "$KEYSTORE_PASS" --ksKeyPass "$KEYSTORE_PASS" --out build/signed
mv build/signed/unsigned-aligned-signed.apk "build/OutlawsOfSherwood-${VERSION}.apk"
rm -rf build/signed build/unsigned.apk
echo "Built build/OutlawsOfSherwood-${VERSION}.apk"
