import 'dart:typed_data';

/// A small ESC/POS command builder for 80mm receipt printers such as the
/// SUNMI NT311 (576 dots wide = 48 characters in the standard font).
class EscPos {
  static const int lineWidth = 48;

  final BytesBuilder _b = BytesBuilder();

  /// Reset the printer and select code page 437, which includes £.
  void init() => _b.add([0x1B, 0x40, 0x1B, 0x74, 0x00]);

  void alignLeft() => _b.add([0x1B, 0x61, 0x00]);
  void alignCenter() => _b.add([0x1B, 0x61, 0x01]);
  void alignRight() => _b.add([0x1B, 0x61, 0x02]);

  void bold(bool on) => _b.add([0x1B, 0x45, on ? 1 : 0]);

  /// Character size multiplier, 1–8 for width and height.
  void size({int width = 1, int height = 1}) {
    final w = (width.clamp(1, 8) - 1) << 4;
    final h = height.clamp(1, 8) - 1;
    _b.add([0x1D, 0x21, w | h]);
  }

  void text(String s) => _b.add(encode(s));

  void line([String s = '']) {
    text(s);
    _b.addByte(0x0A);
  }

  void divider([String ch = '-', int width = lineWidth]) =>
      line(ch * width);

  /// Prints [left] and [right] on one line, padded apart.
  void leftRight(String left, String right, {int width = lineWidth}) {
    final space = width - right.length - 1;
    final wrapped = wrap(left, space < 8 ? width : space);
    for (var i = 0; i < wrapped.length; i++) {
      if (i == 0 && space >= 8) {
        line(wrapped[i].padRight(width - right.length) + right);
      } else {
        line(wrapped[i]);
      }
    }
    if (space < 8) line(right.padLeft(width));
  }

  /// Extra gap of [dots] (about 8 dots per mm).
  void gap(int dots) => _b.add([0x1B, 0x4A, dots.clamp(0, 255)]);

  void feed(int lines) => _b.add([0x1B, 0x64, lines.clamp(0, 255)]);

  /// Full cut.
  void cut() => _b.add([0x1D, 0x56, 0x00]);

  Uint8List bytes() => _b.toBytes();

  /// Wraps text to [width] characters, breaking on spaces where possible.
  static List<String> wrap(String s, int width) {
    final out = <String>[];
    for (final para in s.split('\n')) {
      var current = '';
      for (final word in para.split(' ')) {
        var w = word;
        while (w.length > width) {
          if (current.isNotEmpty) {
            out.add(current);
            current = '';
          }
          out.add(w.substring(0, width));
          w = w.substring(width);
        }
        if (current.isEmpty) {
          current = w;
        } else if (current.length + 1 + w.length <= width) {
          current = '$current $w';
        } else {
          out.add(current);
          current = w;
        }
      }
      out.add(current);
    }
    return out;
  }

  static const Map<String, int> _cp437 = {
    '£': 0x9C, 'é': 0x82, 'è': 0x8A, 'ê': 0x88, 'ë': 0x89, 'à': 0x85,
    'â': 0x83, 'ä': 0x84, 'ç': 0x87, 'î': 0x8C, 'ï': 0x8B, 'ô': 0x93,
    'ö': 0x94, 'ù': 0x97, 'û': 0x96, 'ü': 0x81, 'ñ': 0xA4, 'Ñ': 0xA5,
    'É': 0x90, 'Ä': 0x8E, 'Ö': 0x99, 'Ü': 0x9A, 'ß': 0xE1, '°': 0xF8,
    'á': 0xA0, 'í': 0xA1, 'ó': 0xA2, 'ú': 0xA3, '½': 0xAB, '¼': 0xAC,
  };

  static const Map<String, String> _replacements = {
    '‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-',
    '…': '...', '€': 'EUR', '·': '-', '×': 'x',
  };

  /// Converts text to code page 437 bytes. Characters the printer can't
  /// show are replaced with a close equivalent or '?'.
  static List<int> encode(String s) {
    final out = <int>[];
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      if (rune == 0x0A || (rune >= 0x20 && rune < 0x7F)) {
        out.add(rune);
      } else if (_cp437.containsKey(ch)) {
        out.add(_cp437[ch]!);
      } else if (_replacements.containsKey(ch)) {
        out.addAll(_replacements[ch]!.codeUnits);
      } else {
        out.add(0x3F); // '?'
      }
    }
    return out;
  }
}
