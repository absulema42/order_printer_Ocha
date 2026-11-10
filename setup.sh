#!/usr/bin/env bash
# One-time setup: generates the Android, Windows and Linux platform folders
# and gives the Android app permission to use the network (needed to reach
# the printer in release builds).
set -e
cd "$(dirname "$0")"

flutter create --org com.orderprinter --project-name order_printer \
  --platforms=android,windows,linux .


dart run tool/apply_branding.dart
flutter pub get
echo "Setup done. Run: flutter run -d linux"
