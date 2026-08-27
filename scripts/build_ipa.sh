#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${MAPBOX_ACCESS_TOKEN:?Definissez MAPBOX_ACCESS_TOKEN avant le build.}"
API_BASE_URL="${API_BASE_URL:-https://tranviko.app/api}"
BUILD_NUMBER="$(sed -nE 's/^version:.*\+([0-9]+)$/\1/p' pubspec.yaml | head -n 1)"
[[ -n "$BUILD_NUMBER" ]] || { echo 'Version Flutter invalide.' >&2; exit 1; }

./scripts/verify_ios_setup.sh
flutter pub get
(
  cd ios
  pod install --repo-update
)

COMMON_ARGS=(
  --release
  "--dart-define=API_BASE_URL=$API_BASE_URL"
  "--dart-define=MAPBOX_ACCESS_TOKEN=$MAPBOX_ACCESS_TOKEN"
)

if [[ "${BUILD_UNSIGNED:-0}" == "1" ]]; then
  flutter build ios "${COMMON_ARGS[@]}" --no-codesign
  echo "Build iOS non signe termine dans build/ios/iphoneos/."
  exit 0
fi

SYMBOLS_DIR="build/symbols/ios/$BUILD_NUMBER"
mkdir -p "$SYMBOLS_DIR"
flutter build ipa "${COMMON_ARGS[@]}" \
  --obfuscate \
  "--split-debug-info=$SYMBOLS_DIR"

echo "IPA generee dans build/ios/ipa/."
echo "Conservez les symboles : $SYMBOLS_DIR"
