@echo off
rem One-time setup on Windows, then runs the app. To make an installer use build_windows.bat
cd /d "%~dp0"
call flutter create --org com.orderprinter --project-name order_printer --platforms=windows,android .
call dart run tool/apply_branding.dart
call flutter pub get
call flutter run -d windows
