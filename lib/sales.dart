import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// One line of a completed sale. Name, category and price are copied at the
/// time of sale so later menu changes don't rewrite history.
class SaleLine {
  final String name;
  final String category;
  final int qty;
  final int unitPence;
  final String note;

  const SaleLine({
    required this.name,
    required this.category,
    required this.qty,
    required this.unitPence,
    this.note = '',
  });

  int get totalPence => unitPence * qty;

  Map<String, dynamic> toJson() => {
        'n': name,
        'c': category,
        'q': qty,
        'p': unitPence,
        if (note.isNotEmpty) 'note': note,
      };

  factory SaleLine.fromJson(Map<String, dynamic> j) => SaleLine(
        name: (j['n'] as String?) ?? '',
        category: (j['c'] as String?) ?? 'Other',
        qty: (j['q'] as num?)?.toInt() ?? 1,
        unitPence: (j['p'] as num?)?.toInt() ?? 0,
        note: (j['note'] as String?) ?? '',
      );
}

/// A printed order, as kept in the sales history.
class SaleRecord {
  final String id;
  final int number;
  final DateTime time;
  final String type;
  final String reference;
  final List<SaleLine> lines;
  String payment;
  bool voided;

  SaleRecord({
    required this.id,
    required this.number,
    required this.time,
    required this.type,
    required this.reference,
    required this.lines,
    required this.payment,
    this.voided = false,
  });

  int get totalPence => lines.fold(0, (s, l) => s + l.totalPence);
  int get itemCount => lines.fold(0, (s, l) => s + l.qty);

  Map<String, dynamic> toJson() => {
        'id': id,
        'no': number,
        't': time.toIso8601String(),
        'type': type,
        'ref': reference,
        'pay': payment,
        'void': voided,
        'lines': lines.map((l) => l.toJson()).toList(),
      };

  factory SaleRecord.fromJson(Map<String, dynamic> j) => SaleRecord(
        id: j['id'] as String,
        number: (j['no'] as num?)?.toInt() ?? 0,
        time: DateTime.parse(j['t'] as String),
        type: (j['type'] as String?) ?? '',
        reference: (j['ref'] as String?) ?? '',
        payment: (j['pay'] as String?) ?? 'Card',
        voided: (j['void'] as bool?) ?? false,
        lines: ((j['lines'] as List?) ?? const [])
            .map((e) => SaleLine.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  factory SaleRecord.fromOrder(Order o) => SaleRecord(
        id: '${o.time.microsecondsSinceEpoch}',
        number: o.number,
        time: o.time,
        type: o.type,
        reference: o.reference.trim(),
        payment: o.payment.isEmpty ? 'Card' : o.payment,
        lines: o.lines
            .map((l) => SaleLine(
                  name: l.item.name,
                  category: l.item.category,
                  qty: l.qty,
                  unitPence: l.unitPence,
                  note: l.note,
                ))
            .toList(),
      );

  /// Rebuilds a printable order (used for reprints).
  Order toOrder() => Order(
        number: number,
        type: type,
        reference: reference,
        time: time,
        payment: payment,
        lines: lines
            .map((l) => OrderLine(
                  MenuItem(
                      id: '',
                      name: l.name,
                      category: l.category,
                      pricePence: l.unitPence),
                  qty: l.qty,
                  note: l.note,
                ))
            .toList(),
      );
}

/// Keeps the sales history on the device, one file per month
/// (e.g. sales/2026-11.jsonl). Each line is one order. Changes (payment
/// method, void) are appended as a new copy of the order and the latest copy
/// wins when reading, so a file is never rewritten and nothing is lost if
/// the device switches off mid-save.
class SalesStore {
  Directory? _dir;
  final Map<String, Future<List<SaleRecord>>> _cache = {};

  Future<Directory> folder() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}sales');
    await d.create(recursive: true);
    _dir = d;
    return d;
  }

  static String _monthKey(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}';

  Future<File> _file(String key) async =>
      File('${(await folder()).path}${Platform.pathSeparator}$key.jsonl');

  /// Reads a month once; later calls (even overlapping ones) share it.
  Future<List<SaleRecord>> _month(String key) =>
      _cache.putIfAbsent(key, () => _readMonth(key));

  Future<List<SaleRecord>> _readMonth(String key) async {
    final f = await _file(key);
    final byId = <String, SaleRecord>{};
    if (await f.exists()) {
      for (final line in await f.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final r =
              SaleRecord.fromJson(jsonDecode(line) as Map<String, dynamic>);
          byId[r.id] = r; // later copies replace earlier ones
        } catch (_) {
          // Skip a damaged line rather than losing the whole month.
        }
      }
    }
    return byId.values.toList();
  }

  Future<void> _append(SaleRecord r) async {
    final f = await _file(_monthKey(r.time));
    await f.writeAsString('${jsonEncode(r.toJson())}\n',
        mode: FileMode.append, flush: true);
  }

  /// Saves a new sale.
  Future<void> add(SaleRecord r) async {
    final month = await _month(_monthKey(r.time));
    await _append(r);
    month.add(r);
  }

  /// Saves a change to an existing sale (payment method or void).
  Future<void> update(SaleRecord r) async {
    final month = await _month(_monthKey(r.time));
    await _append(r);
    final i = month.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      month[i] = r;
    } else {
      month.add(r);
    }
  }

  /// All sales from [from] (inclusive) to [to] (exclusive), oldest first.
  Future<List<SaleRecord>> load(DateTime from, DateTime to) async {
    final out = <SaleRecord>[];
    var m = DateTime(from.year, from.month);
    while (m.isBefore(to)) {
      for (final r in await _month(_monthKey(m))) {
        if (!r.time.isBefore(from) && r.time.isBefore(to)) out.add(r);
      }
      m = DateTime(m.year, m.month + 1);
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }
}
