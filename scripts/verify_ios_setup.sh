#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  printf 'ERREUR: %s\n' "$1" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "Cette verification doit etre lancee sur macOS."
command -v flutter >/dev/null || fail "Flutter est introuvable."
command -v xcodebuild >/dev/null || fail "Xcode est introuvable."
command -v pod >/dev/null || fail "CocoaPods est introuvable."

FIREBASE_PLIST="ios/Runner/GoogleService-Info.plist"
[[ -f "$FIREBASE_PLIST" ]] || fail "Ajoutez le GoogleService-Info.plist de l'app iOS app.tranviko.mobile."

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$FIREBASE_PLIST" 2>/dev/null || true)"
[[ "$BUNDLE_ID" == "app.tranviko.mobile" ]] || fail "Firebase utilise '$BUNDLE_ID' au lieu de app.tranviko.mobile."
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = app.tranviko.mobile;' ios/Runner.xcodeproj/project.pbxproj ||
  fail "Le Bundle ID Xcode n'est pas app.tranviko.mobile."
grep -q 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;' ios/Runner.xcodeproj/project.pbxproj ||
  fail "Runner.entitlements n'est pas rattache a la cible Xcode."

flutter --version
xcodebuild -version
pod --version
printf 'Configuration statique iOS valide. Verifiez ensuite la Team et le provisioning dans Xcode.\n'
