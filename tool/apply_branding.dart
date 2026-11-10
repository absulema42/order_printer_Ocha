// Sets the O'Cha Thai name and icon in the generated platform folders.
// Works on Windows, Linux and macOS:  dart run tool/apply_branding.dart
// Safe to run more than once.
import 'dart:io';

const appName = "O'Cha Thai";
const company = 'Korvipong Ltd';

void edit(String path, String Function(String) change) {
  final file = File(path);
  if (!file.existsSync()) return;
  final before = file.readAsStringSync();
  final after = change(before);
  if (after != before) {
    file.writeAsStringSync(after);
    stdout.writeln('Updated $path');
  }
}

void main() {
  // Android: home-screen name and network permission (needed to reach the
  // printer in release builds).
  edit('android/app/src/main/AndroidManifest.xml', (s) {
    s = s.replaceAll(
        RegExp(r'android:label="[^"]*"'), 'android:label="$appName"');
    if (!s.contains('android.permission.INTERNET')) {
      s = s.replaceFirst('<application',
          '<uses-permission android:name="android.permission.INTERNET"/>\n    <application');
    }
    return s;
  });

  // Android: launcher icon.
  for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
    final from = File('assets/android/mipmap-$d/ic_launcher.png');
    final to = File('android/app/src/main/res/mipmap-$d/ic_launcher.png');
    if (from.existsSync() && to.parent.existsSync()) {
      from.copySync(to.path);
    }
  }

  // Windows: window title, file details and icon.
  edit('windows/runner/main.cpp', (s) => s.replaceAll(
      RegExp(r'window\.Create\(L"[^"]*"'), 'window.Create(L"$appName"'));
  edit('windows/runner/Runner.rc', (s) {
    for (final key in ['FileDescription', 'ProductName']) {
      s = s.replaceAll(RegExp('VALUE "$key", "[^"]*"'), 'VALUE "$key", "$appName"');
    }
    return s.replaceAll(
        RegExp(r'VALUE "CompanyName", "[^"]*"'), 'VALUE "CompanyName", "$company"');
  });
  final icon = File('assets/app_icon.ico');
  final winIcon = File('windows/runner/resources/app_icon.ico');
  if (icon.existsSync() && winIcon.parent.existsSync()) {
    icon.copySync(winIcon.path);
    stdout.writeln('Updated ${winIcon.path}');
  }

  // Linux: window title.
  for (final path in [
    'linux/runner/my_application.cc',
    'linux/my_application.cc',
  ]) {
    edit(path, (s) => s.replaceAllMapped(
        RegExp(r'_set_title\((\w+), "[^"]*"\)'),
        (m) => '_set_title(${m[1]}, "$appName")'));
  }
}
