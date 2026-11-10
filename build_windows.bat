@echo off
rem Builds the O'Cha Thai Windows program on a Windows PC.
rem Needs: Flutter (flutter.dev) and Visual Studio 2022 with
rem "Desktop development with C++". Inno Setup 6 is optional (for Setup.exe).
setlocal
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter was not found. Install it from https://docs.flutter.dev/get-started/install/windows
  pause
  exit /b 1
)

echo === Preparing project ===
call flutter create --org com.orderprinter --project-name order_printer --platforms=windows,android .
if errorlevel 1 goto :fail
call dart run tool/apply_branding.dart
if errorlevel 1 goto :fail
call flutter pub get
if errorlevel 1 goto :fail

echo === Building ===
call flutter build windows --release
if errorlevel 1 goto :fail

set "OUT=build\windows\x64\runner\Release"
rem Include the Visual C++ runtime so the program runs on PCs without it.
for %%F in (msvcp140.dll vcruntime140.dll vcruntime140_1.dll) do (
  if exist "%WINDIR%\System32\%%F" copy /y "%WINDIR%\System32\%%F" "%OUT%\" >nul
)

if not exist dist mkdir dist
powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath 'dist\OChaThai-Windows-Portable.zip' -Force"

set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ISCC%" (
  echo === Making installer ===
  "%ISCC%" windows_installer.iss
  if errorlevel 1 goto :fail
  echo.
  echo Done. Installer: dist\OChaThai-Setup.exe
) else (
  echo.
  echo Done. Install Inno Setup 6 to also get dist\OChaThai-Setup.exe
)
echo Portable version: dist\OChaThai-Windows-Portable.zip
echo Or run it now:    %OUT%\order_printer.exe
pause
exit /b 0

:fail
echo.
echo Build failed - see the messages above.
pause
exit /b 1
