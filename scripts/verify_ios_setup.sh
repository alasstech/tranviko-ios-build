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

plutil -lint ios/Runner/Info.plist >/dev/null || fail "Info.plist est invalide."
plutil -lint ios/Runner/Runner.entitlements >/dev/null || fail "Runner.entitlements est invalide."
plutil -lint "$FIREBASE_PLIST" >/dev/null || fail "GoogleService-Info.plist est invalide."

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$FIREBASE_PLIST" 2>/dev/null || true)"
[[ "$BUNDLE_ID" == "app.tranviko.mobile" ]] || fail "Firebase utilise '$BUNDLE_ID' au lieu de app.tranviko.mobile."
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = app.tranviko.mobile;' ios/Runner.xcodeproj/project.pbxproj ||
  fail "Le Bundle ID Xcode n'est pas app.tranviko.mobile."
grep -q 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;' ios/Runner.xcodeproj/project.pbxproj ||
  fail "Runner.entitlements n'est pas rattache a la cible Xcode."
grep -q '<string>voip</string>' ios/Runner/Info.plist ||
  fail "Le Background Mode VoIP manque dans Info.plist."
grep -q '<string>remote-notification</string>' ios/Runner/Info.plist ||
  fail "Le Background Mode Remote notifications manque dans Info.plist."
grep -q '<key>aps-environment</key>' ios/Runner/Runner.entitlements ||
  fail "L'entitlement APNs manque."
grep -q 'PKPushRegistryDelegate' ios/Runner/AppDelegate.swift ||
  fail "L'enregistrement PushKit manque dans AppDelegate.swift."
grep -q 'fromPushKit: true' ios/Runner/AppDelegate.swift ||
  fail "Le signalement immediat a CallKit manque dans AppDelegate.swift."

if find . -type f \( -name '*.p8' -o -name '*.p12' -o -name '*.mobileprovision' \) -print -quit | grep -q .; then
  fail "Un secret Apple interdit est present dans le depot."
fi

flutter --version
xcodebuild -version
pod --version
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -list >/dev/null
printf 'Configuration statique iOS valide. Verifiez ensuite la Team et le provisioning dans Xcode.\n'
