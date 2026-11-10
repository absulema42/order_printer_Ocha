import 'sales.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// A date range for a report. [to] is exclusive (midnight after the last day).
class ReportPeriod {
  final String label;
  final DateTime from;
  final DateTime to;

  const ReportPeriod(this.label, this.from, this.to);

  DateTime get lastDay => DateTime(to.year, to.month, to.day - 1);
  bool get isSingleDay =>
      DateTime(from.year, from.month, from.day + 1) == to;

  String get dates => isSingleDay
      ? formatDate(from)
      : '${formatDate(from)} - ${formatDate(lastDay)}';

  /// Whole days from [start] to [end], both included.
  factory ReportPeriod.range(DateTime start, DateTime end) => ReportPeriod(
        'Custom',
        DateTime(start.year, start.month, start.day),
        DateTime(end.year, end.month, end.day + 1),
      );

  static const presets = {
    'today': 'Today',
    'yesterday': 'Yesterday',
    'week': 'This week',
    'lastWeek': 'Last week',
    'month': 'This month',
    'lastMonth': 'Last month',
  };

  factory ReportPeriod.preset(String key, DateTime now) {
    final d = DateTime(now.year, now.month, now.day);
    final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    final label = presets[key] ?? 'Today';
    switch (key) {
      case 'yesterday':
        return ReportPeriod(label, DateTime(d.year, d.month, d.day - 1), d);
      case 'week':
        return ReportPeriod(label, monday,
            DateTime(monday.year, monday.month, monday.day + 7));
      case 'lastWeek':
        return ReportPeriod(
            label, DateTime(monday.year, monday.month, monday.day - 7), monday);
      case 'month':
        return ReportPeriod(
            label, DateTime(d.year, d.month), DateTime(d.year, d.month + 1));
      case 'lastMonth':
        return ReportPeriod(
            label, DateTime(d.year, d.month - 1), DateTime(d.year, d.month));
      default:
        return ReportPeriod(label, d, DateTime(d.year, d.month, d.day + 1));
    }
  }
}

class Tally {
  int count = 0;
  int pence = 0;
}

class ItemTally {
  final String name;
  final String category;
  int qty = 0;
  int pence = 0;
  ItemTally(this.name, this.category);
}

/// All the numbers for one period. Voided orders are left out of every
/// total and counted separately.
class SalesReport {
  final List<SaleRecord> orders; // everything in the period, incl. voided
  final double vatRate;

  int grossPence = 0;
  int orderCount = 0;
  int itemCount = 0;
  int voidCount = 0;
  int voidPence = 0;

  final Map<String, Tally> byPayment = {};
  final Map<String, Tally> byType = {};
  final Map<String, Tally> byCategory = {}; // count = items sold
  final Map<int, Tally> byHour = {};
  final Map<DateTime, Tally> byDay = {};
  final List<ItemTally> items = [];

  SalesReport(this.orders, {required this.vatRate}) {
    final itemMap = <String, ItemTally>{};
    for (final o in orders) {
      final total = o.totalPence;
      if (o.voided) {
        voidCount++;
        voidPence += total;
        continue;
      }
      grossPence += total;
      orderCount++;
      itemCount += o.itemCount;
      _add(byPayment, o.payment, 1, total);
      _add(byType, o.type, 1, total);
      _add(byHour, o.time.hour, 1, total);
      _add(byDay, DateTime(o.time.year, o.time.month, o.time.day), 1, total);
      for (final l in o.lines) {
        _add(byCategory, l.category, l.qty, l.totalPence);
        final it = itemMap.putIfAbsent(
            '${l.category}|${l.name}', () => ItemTally(l.name, l.category));
        it.qty += l.qty;
        it.pence += l.totalPence;
      }
    }
    items
      ..addAll(itemMap.values)
      ..sort((a, b) => b.pence != a.pence
          ? b.pence.compareTo(a.pence)
          : b.qty.compareTo(a.qty));
  }

  static void _add<K>(Map<K, Tally> m, K key, int count, int pence) {
    final t = m.putIfAbsent(key, Tally.new);
    t.count += count;
    t.pence += pence;
  }

  /// VAT contained in VAT-inclusive prices: gross × rate / (100 + rate).
  int get vatPence =>
      vatRate <= 0 ? 0 : (grossPence * vatRate / (100 + vatRate)).round();
  int get netPence => grossPence - vatPence;
  int get averagePence =>
      orderCount == 0 ? 0 : (grossPence / orderCount).round();

  Tally get unpaid => byPayment['Unpaid'] ?? Tally();

  String get vatLabel =>
      'VAT (${vatRate == vatRate.roundToDouble() ? vatRate.toInt() : vatRate}%)';

  /// Entries sorted by value, biggest first.
  static List<MapEntry<K, Tally>> sorted<K>(Map<K, Tally> m) =>
      m.entries.toList()..sort((a, b) => b.value.pence.compareTo(a.value.pence));
}

String _money(int pence) => (pence / 100).toStringAsFixed(2);

String _csvField(String s) {
  // Stop spreadsheet apps treating typed text as a formula.
  if (s.isNotEmpty && '=+-@'.contains(s[0]) && double.tryParse(s) == null) {
    s = "'$s";
  }
  if (s.contains(RegExp(r'[",\n\r]'))) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _csv(List<List<Object>> rows) =>
    '﻿${rows.map((r) => r.map((c) => _csvField('$c')).join(',')).join('\r\n')}\r\n';

/// One row per order. Opens directly in Excel / Google Sheets.
String ordersCsv(SalesReport r) {
  final rows = <List<Object>>[
    ['Date', 'Time', 'Order', 'Type', 'Table / customer', 'Payment',
      'Status', 'Items', 'Total', 'Net', 'VAT'],
  ];
  for (final o in r.orders) {
    final gross = o.totalPence;
    final vat = r.vatRate <= 0
        ? 0
        : (gross * r.vatRate / (100 + r.vatRate)).round();
    rows.add([
      formatDate(o.time), formatTime(o.time), o.number, o.type, o.reference,
      o.payment, o.voided ? 'Void' : 'OK', o.itemCount,
      _money(gross), _money(gross - vat), _money(vat),
    ]);
  }
  return _csv(rows);
}

/// One row per item line, for detailed analysis (pivot tables etc.).
String itemsCsv(SalesReport r) {
  final rows = <List<Object>>[
    ['Date', 'Time', 'Order', 'Type', 'Payment', 'Status', 'Category',
      'Item', 'Qty', 'Unit price', 'Line total', 'Note'],
  ];
  for (final o in r.orders) {
    for (final l in o.lines) {
      rows.add([
        formatDate(o.time), formatTime(o.time), o.number, o.type, o.payment,
        o.voided ? 'Void' : 'OK', l.category, l.name, l.qty,
        _money(l.unitPence), _money(l.totalPence), l.note,
      ]);
    }
  }
  return _csv(rows);
}

/// Totals only, matching the summary screen.
String summaryCsv(SalesReport r, ReportPeriod p, String restaurant) {
  final rows = <List<Object>>[
    [restaurant, 'Sales summary'],
    ['Period', p.dates],
    [],
    ['Total sales', _money(r.grossPence)],
    ['Net sales', _money(r.netPence)],
    [r.vatLabel, _money(r.vatPence)],
    ['Orders', r.orderCount],
    ['Average order', _money(r.averagePence)],
    ['Items sold', r.itemCount],
    ['Voided orders', r.voidCount],
    ['Voided value', _money(r.voidPence)],
    [],
    ['Payment', 'Orders', 'Amount'],
    for (final e in SalesReport.sorted(r.byPayment))
      [e.key, e.value.count, _money(e.value.pence)],
    [],
    ['Order type', 'Orders', 'Amount'],
    for (final e in SalesReport.sorted(r.byType))
      [e.key, e.value.count, _money(e.value.pence)],
    [],
    ['Category', 'Items', 'Amount'],
    for (final e in SalesReport.sorted(r.byCategory))
      [e.key, e.value.count, _money(e.value.pence)],
    [],
    ['Item', 'Category', 'Qty', 'Amount'],
    for (final i in r.items) [i.name, i.category, i.qty, _money(i.pence)],
  ];
  return _csv(rows);
}
