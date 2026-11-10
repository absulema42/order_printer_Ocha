#!/usr/bin/env bash
# Builds the O'Cha Thai Android app (APK) on Linux.
# Needs Flutter and the Android SDK (Android Studio), then once:
#   flutter doctor --android-licenses
set -e
cd "$(dirname "$0")"
flutter create --org com.orderprinter --project-name order_printer --platforms=android .
dart run tool/apply_branding.dart
dart run tool/use_signing_key.dart
flutter pub get
flutter build apk --release
mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk dist/OChaThai.apk
echo "Done: dist/OChaThai.apk"
