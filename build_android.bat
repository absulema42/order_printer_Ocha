@echo off
rem Builds the O'Cha Thai Android app (APK) on a Windows PC.
rem Needs: Flutter and Android Studio (run it once so it installs the Android SDK),
rem then once: flutter doctor --android-licenses
setlocal
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter was not found. See the README for how to install it.
  pause
  exit /b 1
)

echo === Preparing project ===
call flutter create --org com.orderprinter --project-name order_printer --platforms=android .
if errorlevel 1 goto :fail
call dart run tool/apply_branding.dart
if errorlevel 1 goto :fail
call dart run tool/use_signing_key.dart
if errorlevel 1 goto :fail
call flutter pub get
if errorlevel 1 goto :fail

echo === Building ===
call flutter build apk --release
if errorlevel 1 goto :fail

if not exist dist mkdir dist
copy /y build\app\outputs\flutter-apk\app-release.apk dist\OChaThai.apk >nul
echo.
echo Done: dist\OChaThai.apk
echo Copy it to the tablet (USB cable, Google Drive or email) and tap it to install.
pause
exit /b 0

:fail
echo.
echo Build failed - see the messages above.
pause
exit /b 1
