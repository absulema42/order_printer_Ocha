// Makes every Android build of O'Cha Thai use the same signing key
// (android_signing/ocha.keystore), so a new version installs over the old
// one on the tablet without losing the menu, settings or sales history.
//
// Flutter signs release APKs with the computer's debug key
// (~/.android/debug.keystore), so this copies ours there. Any different key
// already there is kept as debug.keystore.bak.
//
//   dart run tool/use_signing_key.dart
import 'dart:io';

void main() {
  final ours = File('android_signing/ocha.keystore');
  if (!ours.existsSync()) {
    stderr.writeln('android_signing/ocha.keystore is missing.');
    exit(1);
  }
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '.';
  final sep = Platform.pathSeparator;
  final dir = Directory('$home$sep.android');
  dir.createSync(recursive: true);
  final target = File('${dir.path}${sep}debug.keystore');

  final ourBytes = ours.readAsBytesSync();
  if (target.existsSync()) {
    final existing = target.readAsBytesSync();
    if (_same(existing, ourBytes)) {
      stdout.writeln('Signing key already in place.');
      return;
    }
    target.copySync('${target.path}.bak');
    stdout.writeln('Backed up the previous key to ${target.path}.bak');
  }
  target.writeAsBytesSync(ourBytes);
  stdout.writeln("Using the O'Cha Thai signing key for Android builds.");
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
