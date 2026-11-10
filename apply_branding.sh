#!/usr/bin/env bash
# Sets the app name shown on Android (home screen), Windows (title bar,
# taskbar, file details) and Linux (window title) to "O'Cha Thai".
# Safe to run more than once.
set -e
cd "$(dirname "$0")"
NAME="O'Cha Thai"

# Android home-screen label
F=android/app/src/main/AndroidManifest.xml
if [ -f "$F" ]; then
  sed -i "s|android:label=\"[^\"]*\"|android:label=\"$NAME\"|" "$F"
  echo "Android: label set"
fi

# Windows window title and file details
F=windows/runner/main.cpp
if [ -f "$F" ]; then
  sed -i "s|window.Create(L\"[^\"]*\"|window.Create(L\"$NAME\"|" "$F"
  echo "Windows: window title set"
fi
F=windows/runner/Runner.rc
if [ -f "$F" ]; then
  sed -i "s|VALUE \"FileDescription\", \"[^\"]*\"|VALUE \"FileDescription\", \"$NAME\"|; \
          s|VALUE \"ProductName\", \"[^\"]*\"|VALUE \"ProductName\", \"$NAME\"|" "$F"
  echo "Windows: product name set"
fi

# Linux window title
F=linux/runner/my_application.cc
[ -f "$F" ] || F=linux/my_application.cc
if [ -f "$F" ]; then
  sed -i "s|_set_title(\([a-z_]*\), \"order_printer\")|_set_title(\1, \"$NAME\")|g" "$F"
  echo "Linux: window title set"
fi
