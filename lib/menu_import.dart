import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'models.dart';

/// What was found in an imported spreadsheet.
class MenuImport {
  final List<MenuItem> items;
  final int skippedRows;
  MenuImport(this.items, this.skippedRows);

  /// Categories in the order they appear, with item counts.
  Map<String, int> get categoryCounts {
    final m = <String, int>{};
    for (final i in items) {
      m[i.category] = (m[i.category] ?? 0) + 1;
    }
    return m;
  }
}

/// Reads an .xlsx or .csv file into menu items.
MenuImport readMenuFile(String fileName, List<int> bytes) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.xls')) {
    throw const FormatException(
        'Old .xls files are not supported. Open it in Excel and use '
        'File > Save As > Excel Workbook (.xlsx).');
  }
  final rows = lower.endsWith('.csv')
      ? readCsvRows(utf8.decode(bytes, allowMalformed: true))
      : readXlsxRows(bytes);
  return parseMenuRows(rows);
}

/// Turns spreadsheet rows into menu items. Two layouts are understood:
///
/// 1. Sections, like the O'Cha menu: a header row such as
///    `Item No | Starters | Price` (or `... | Eat In Price | Take Away Price`)
///    followed by the items in that section. The header's name column gives
///    the category.
/// 2. One table with a header such as
///    `Item No | Name | Category | Price | Take Away Price`.
///
/// A header row is any row with a cell containing "price". Rows without a
/// name are ignored; rows with a name but no valid price are skipped.
MenuImport parseMenuRows(List<List<String>> rows) {
  int? nameCol, priceCol, takeCol, codeCol, catCol;
  var category = 'Other';
  var lastCode = '';
  var skipped = 0;
  var n = 0;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final items = <MenuItem>[];

  for (final raw in rows) {
    final row = raw.map((c) => c.trim()).toList();
    String at(int? i) => (i != null && i < row.length) ? row[i] : '';
    final lower = row.map((c) => c.toLowerCase()).toList();

    final priceCols = [
      for (var i = 0; i < lower.length; i++)
        if (lower[i].contains('price')) i
    ];
    if (priceCols.isNotEmpty) {
      bool isTakeaway(int i) =>
          lower[i].contains('take') || lower[i].contains('away');
      final takeCols = priceCols.where(isTakeaway).toList();
      final mainCols = priceCols.where((i) => !isTakeaway(i)).toList();
      takeCol = takeCols.isEmpty ? null : takeCols.first;
      priceCol = mainCols.isNotEmpty ? mainCols.first : priceCols.first;
      if (priceCol == takeCol) takeCol = null;
      codeCol = _indexWhere(lower, _codeHeaders.contains);
      catCol = _indexWhere(lower, _categoryHeaders.contains);
      final used = {priceCol, takeCol, codeCol, catCol};
      nameCol = null;
      for (var i = 0; i < row.length; i++) {
        if (!used.contains(i) && row[i].isNotEmpty) {
          nameCol = i;
          break;
        }
      }
      if (nameCol == null) {
        for (var i = 0; i <= row.length; i++) {
          if (!used.contains(i)) {
            nameCol = i;
            break;
          }
        }
      }
      final header = at(nameCol);
      if (catCol == null &&
          header.isNotEmpty &&
          !_nameHeaders.contains(header.toLowerCase())) {
        category = header;
      }
      lastCode = '';
      continue;
    }

    final name = at(nameCol);
    if (nameCol == null || priceCol == null) {
      if (row.any((c) => c.isNotEmpty)) skipped++;
      continue;
    }
    if (name.isEmpty) continue;
    final price = importPrice(at(priceCol));
    if (price == null) {
      skipped++;
      continue;
    }
    var code = at(codeCol);
    final asNum = double.tryParse(code);
    if (asNum != null && asNum == asNum.roundToDouble()) {
      code = asNum.toInt().toString();
    }
    if (code.isEmpty) {
      code = lastCode; // variants (e.g. Tom Yum Chicken) share the dish number
    } else {
      lastCode = code;
    }
    final take = takeCol == null ? null : importPrice(at(takeCol));
    final cat = at(catCol).isNotEmpty ? at(catCol) : category;
    items.add(MenuItem(
      id: 'imp${stamp}_${n++}',
      name: name,
      category: cat,
      pricePence: price,
      code: code,
      takeawayPence: take == price ? null : take,
    ));
  }
  return MenuImport(items, skipped);
}

const _codeHeaders = {
  'item no', 'item no.', 'item number', 'item code', 'no', 'no.', 'number',
  'code', '#', 'ref',
};
const _categoryHeaders = {'category', 'section', 'group', 'type'};
const _nameHeaders = {
  'name', 'item', 'items', 'item name', 'product', 'products', 'product name',
  'description', 'dish',
};

int? _indexWhere(List<String> list, bool Function(String) test) {
  for (var i = 0; i < list.length; i++) {
    if (test(list[i])) return i;
  }
  return null;
}

/// Lenient price reader: "6.95", "£6.95", "6.9500000000000002", "7".
/// Anything that isn't a digit or a dot is ignored.
int? importPrice(String s) {
  final cleaned = s.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (cleaned.isEmpty) return null;
  final v = double.tryParse(cleaned);
  if (v == null || v < 0) return null;
  return (v * 100).round();
}

// ---------------------------------------------------------------- xlsx

/// Reads the first worksheet of an .xlsx file as rows of text.
List<List<String>> readXlsxRows(List<int> bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException(
        'This file could not be opened as an Excel (.xlsx) workbook.');
  }

  String? text(String path) {
    final f = archive.findFile(path);
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final shared = <String>[];
  final sst = text('xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in _all(XmlDocument.parse(sst), 'si')) {
      final parts = _all(si, 't').where((t) {
        final parent = t.parent;
        return !(parent is XmlElement && parent.name.local == 'rPh');
      });
      shared.add(parts.map((t) => t.innerText).join());
    }
  }

  final sheet = text(_firstSheetPath(archive, text));
  if (sheet == null) {
    throw const FormatException('No worksheet was found in this file.');
  }

  final rows = <List<String>>[];
  for (final row in _all(XmlDocument.parse(sheet), 'row')) {
    final cells = <String>[];
    var pos = 0;
    for (final c in _kids(row, 'c')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? pos : _columnIndex(ref);
      final type = c.getAttribute('t');
      String value;
      if (type == 'inlineStr') {
        value = _all(c, 't').map((t) => t.innerText).join();
      } else {
        final vs = _kids(c, 'v');
        final v = vs.isEmpty ? '' : vs.first.innerText;
        if (type == 's') {
          final idx = int.tryParse(v);
          value = idx != null && idx >= 0 && idx < shared.length
              ? shared[idx]
              : '';
        } else {
          value = v;
        }
      }
      while (cells.length <= col) {
        cells.add('');
      }
      cells[col] = value;
      pos = col + 1;
    }
    rows.add(cells);
  }
  return rows;
}

/// All elements below [node] with this local name, ignoring any prefix.
Iterable<XmlElement> _all(XmlNode node, String local) => node.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local);

/// Direct child elements with this local name.
Iterable<XmlElement> _kids(XmlElement el, String local) =>
    el.childElements.where((e) => e.name.local == local);

/// "C12" -> 2
int _columnIndex(String ref) {
  var n = 0;
  for (final unit in ref.toUpperCase().codeUnits) {
    if (unit < 65 || unit > 90) break;
    n = n * 26 + (unit - 64);
  }
  return n == 0 ? 0 : n - 1;
}

String _firstSheetPath(Archive archive, String? Function(String) text) {
  try {
    final wb = text('xl/workbook.xml');
    final rels = text('xl/_rels/workbook.xml.rels');
    if (wb != null && rels != null) {
      final sheets = _all(XmlDocument.parse(wb), 'sheet');
      if (sheets.isNotEmpty) {
        String? rid;
        for (final a in sheets.first.attributes) {
          if (a.name.local == 'id') rid = a.value;
        }
        for (final rel
            in _all(XmlDocument.parse(rels), 'Relationship')) {
          if (rid != null && rel.getAttribute('Id') == rid) {
            var target = rel.getAttribute('Target') ?? '';
            target = target.startsWith('/')
                ? target.substring(1)
                : 'xl/$target';
            if (archive.findFile(target) != null) return target;
          }
        }
      }
    }
  } catch (_) {
    // Fall through to the simple lookup below.
  }
  final pattern = RegExp(r'^xl/worksheets/sheet(\d+)\.xml$');
  final names = archive.files
      .map((f) => f.name)
      .where(pattern.hasMatch)
      .toList()
    ..sort((a, b) => int.parse(pattern.firstMatch(a)!.group(1)!)
        .compareTo(int.parse(pattern.firstMatch(b)!.group(1)!)));
  if (names.isEmpty) {
    throw const FormatException('No worksheet was found in this file.');
  }
  return names.first;
}

// ---------------------------------------------------------------- csv

/// Minimal CSV reader (quotes, commas or semicolons, any line endings).
List<List<String>> readCsvRows(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final firstLine = text.split('\n').first;
  final delimiter =
      ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
          ? ';'
          : ',';
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == delimiter) {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}
