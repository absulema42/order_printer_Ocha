import 'dart:typed_data';

import 'escpos.dart';
import 'models.dart';
import 'reports.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Builds the kitchen slip for an order.
Uint8List buildOrderTicket(Order order, AppSettings settings,
    {bool reprint = false}) {
  final p = EscPos()..init();
  const w = EscPos.lineWidth;
  final t = order.time;

  // Header
  p.alignCenter();
  if (reprint) {
    p.bold(true);
    p.line('*** REPRINT ***');
    p.bold(false);
  }
  if (settings.restaurantName.trim().isNotEmpty) {
    p.size(width: 2, height: 2);
    p.bold(true);
    for (final l in EscPos.wrap(settings.restaurantName.trim(), w ~/ 2)) {
      p.line(l);
    }
    p.bold(false);
    p.size();
    p.divider();
  }
  p.size(width: 2, height: 2);
  p.bold(true);
  p.line('ORDER #${order.number}');
  p.line(order.type.toUpperCase());
  if (order.reference.trim().isNotEmpty) {
    for (final l in EscPos.wrap(order.reference.trim(), w ~/ 2)) {
      p.line(l);
    }
  }
  p.bold(false);
  p.size();
  p.line('${_two(t.hour)}:${_two(t.minute)}  '
      '${_two(t.day)}/${_two(t.month)}/${t.year}');
  if (order.payment.isNotEmpty) {
    p.bold(true);
    p.line(order.payment == 'Unpaid'
        ? 'NOT PAID'
        : 'PAID - ${order.payment.toUpperCase()}');
    p.bold(false);
  }
  p.alignLeft();
  p.divider('=');

  // Items: double height so the kitchen can read them at a glance.
  for (final l in order.lines) {
    p.size(height: 2);
    p.bold(true);
    final label = '${l.qty} x ${l.item.name}';
    if (settings.showPrices) {
      p.leftRight(label, formatPrice(l.totalPence));
    } else {
      for (final s in EscPos.wrap(label, w)) {
        p.line(s);
      }
    }
    p.bold(false);
    p.size();
    if (l.note.trim().isNotEmpty) {
      for (final s in EscPos.wrap('>> ${l.note.trim()}', w - 4)) {
        p.line('    $s');
      }
    }
  }

  // Footer
  p.divider('=');
  final items = '${order.itemCount} item${order.itemCount == 1 ? '' : 's'}';
  if (settings.showPrices) {
    p.bold(true);
    p.size(height: 2);
    p.leftRight(items, 'TOTAL ${formatPrice(order.totalPence)}');
    p.size();
    p.bold(false);
  } else {
    p.line(items);
  }
  p.feed(4);
  p.cut();
  return p.bytes();
}

/// Customer receipt, laid out like the restaurant's till receipt.
/// Prices include VAT; the VAT contained in the total is shown at the end.
Uint8List buildReceipt(Order order, AppSettings settings,
    {bool reprint = false}) {
  final p = EscPos()..init();
  const w = EscPos.lineWidth; // 48
  const priceW = 12, qtyW = 5, totalW = 12;
  const nameW = w - priceW - qtyW - totalW; // 25
  final t = order.time;

  // Header
  p.alignCenter();
  if (reprint) {
    p.bold(true);
    p.line('*** REPRINT ***');
    p.bold(false);
  }
  final name = settings.restaurantName.trim();
  if (name.isNotEmpty) {
    p.size(width: 2, height: 2);
    p.bold(true);
    for (final l in EscPos.wrap(name, w ~/ 2)) {
      p.line(l);
    }
    p.bold(false);
    p.size();
  }
  for (final extra in [settings.businessLine, settings.email]) {
    if (extra.trim().isNotEmpty) {
      for (final l in EscPos.wrap(extra.trim(), w)) {
        p.line(l);
      }
    }
  }
  p.alignLeft();
  p.divider();

  // Order details
  p.bold(true);
  p.leftRight('Order Details (Inc Tax)',
      '${_two(t.day)}/${_two(t.month)}/${t.year}');
  p.bold(false);
  p.leftRight('', '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}');
  p.leftRight('Order No.', '#${order.number}');
  p.leftRight('Type', order.type);
  if (order.reference.trim().isNotEmpty) {
    p.leftRight(order.type == 'Eat in' ? 'Table' : 'Customer',
        order.reference.trim());
  }
  if (settings.staffName.trim().isNotEmpty) {
    p.leftRight('Staff', settings.staffName.trim());
  }
  if (settings.deviceName.trim().isNotEmpty) {
    p.leftRight('Device', settings.deviceName.trim());
  }
  if (order.payment.isNotEmpty) {
    p.leftRight('Payment', order.payment == 'Unpaid' ? 'Not paid' : order.payment);
  }
  p.divider();

  // Products. 'wide', 'tall' and 'large' print bigger, bold, well-spaced
  // rows so they can be read from further away.
  final size = settings.itemSize;
  const rowGap = 14; // dots of extra space between rows (~1.75 mm)
  void note(OrderLine l) {
    if (l.note.trim().isEmpty) return;
    p.size();
    p.bold(false);
    for (final s in EscPos.wrap('>> ${l.note.trim()}', w - 2)) {
      p.line('  $s');
    }
  }

  if (size == 'large' || size == 'wide') {
    // Double width: 24 columns. Name on one line, "qty x price" and the
    // line total underneath. 'wide' keeps normal height (short, broad
    // letters); 'large' is double height as well.
    const lw = w ~/ 2;
    final h = size == 'large' ? 2 : 1;
    p.size(width: 2, height: h);
    p.bold(true);
    p.leftRight('PRODUCT', 'TOTAL', width: lw);
    p.size();
    p.divider();
    for (final l in order.lines) {
      p.size(width: 2, height: h);
      p.bold(true);
      for (final s in EscPos.wrap(l.item.name, lw)) {
        p.line(s);
      }
      p.leftRight('${l.qty} x ${formatPrice(l.unitPence)}',
          formatPrice(l.totalPence),
          width: lw);
      note(l);
      p.gap(rowGap);
    }
    p.size(width: 2, height: h);
    p.bold(true);
    p.leftRight('Total Qty', '${order.itemCount}', width: lw);
  } else {
    final tall = size == 'tall';
    p.bold(true);
    p.line('PRODUCT'.padRight(nameW) +
        'PRICE'.padLeft(priceW) +
        'QTY'.padLeft(qtyW) +
        'TOTAL'.padLeft(totalW));
    if (tall) p.gap(rowGap);
    for (final l in order.lines) {
      if (tall) {
        p.size(height: 2);
        p.bold(true);
      } else {
        p.bold(false);
      }
      final nameLines = EscPos.wrap(l.item.name, nameW);
      p.line(nameLines.first.padRight(nameW) +
          formatPrice(l.unitPence).padLeft(priceW) +
          '${l.qty}'.padLeft(qtyW) +
          formatPrice(l.totalPence).padLeft(totalW));
      for (final extra in nameLines.skip(1)) {
        p.line(extra);
      }
      note(l);
      if (tall) p.gap(rowGap);
    }
    if (tall) p.size(height: 2);
    p.bold(true);
    p.line(''.padRight(nameW) +
        'Total Qty'.padLeft(priceW) +
        '${order.itemCount}'.padLeft(qtyW));
  }
  p.size();
  p.bold(false);
  p.divider();

  // Totals
  final total = formatPrice(order.totalPence);
  p.leftRight('Sub Total', total);
  p.leftRight('Total', total);
  // "Amount Due" in normal text with the amount in large text on the
  // same line. Large characters take two columns each.
  p.text('Amount Due'.padRight(w - total.length * 2));
  p.size(width: 2, height: 2);
  p.bold(true);
  p.line(total);
  p.bold(false);
  p.size();

  // VAT
  if (settings.vatRate > 0) {
    final rate = settings.vatRate;
    final vat = (order.totalPence * rate / (100 + rate)).round();
    final rateLabel = rate == rate.roundToDouble()
        ? '${rate.toInt()}VAT'
        : '${rate}VAT';
    const col = w ~/ 3; // 16
    p.line();
    p.bold(true);
    p.line('TAX RATE'.padRight(col) +
        _centre('PERCENTAGE', col) +
        'TAX'.padLeft(col));
    p.bold(false);
    p.line(rateLabel.padRight(col) +
        _centre('${rate.toStringAsFixed(2)}%', col) +
        formatPrice(vat).padLeft(col));
    if (settings.vatNumber.trim().isNotEmpty) {
      p.alignCenter();
      p.line('VAT Number: ${settings.vatNumber.trim()}');
      p.alignLeft();
    }
  }

  // Footer
  if (settings.footer.trim().isNotEmpty) {
    p.divider();
    p.alignCenter();
    p.bold(true);
    for (final l in EscPos.wrap(settings.footer.trim(), w)) {
      p.line(l);
    }
    p.bold(false);
    p.alignLeft();
  }
  p.feed(4);
  p.cut();
  return p.bytes();
}

String _centre(String s, int width) {
  if (s.length >= width) return s;
  final left = (width - s.length) ~/ 2;
  return (' ' * left + s).padRight(width);
}

/// Everything that prints for one order, based on the slip style setting.
Uint8List buildOrderSlips(Order order, AppSettings settings,
    {bool reprint = false}) {
  final b = BytesBuilder();
  if (settings.slipStyle != 'kitchen') {
    b.add(buildReceipt(order, settings, reprint: reprint));
  }
  if (settings.slipStyle != 'receipt') {
    b.add(buildOrderTicket(order, settings, reprint: reprint));
  }
  return b.toBytes();
}

/// A short slip to check the printer connection from Settings.
Uint8List buildTestTicket(AppSettings settings) {
  final p = EscPos()..init();
  final now = DateTime.now();
  p.alignCenter();
  p.size(width: 2, height: 2);
  p.bold(true);
  p.line('TEST PRINT');
  p.bold(false);
  p.size();
  p.line(settings.restaurantName);
  p.line('Printer ${settings.printerHost}:${settings.printerPort}');
  p.line('${_two(now.hour)}:${_two(now.minute)}  '
      '${_two(now.day)}/${_two(now.month)}/${now.year}');
  p.line('Pound sign check: £1.50');
  p.alignLeft();
  p.feed(4);
  p.cut();
  return p.bytes();
}

/// End-of-day (or any period) sales report for the receipt printer.
Uint8List buildSalesReportTicket(
    SalesReport r, ReportPeriod period, AppSettings settings) {
  final p = EscPos()..init();
  final now = DateTime.now();

  void section(String title) {
    p.line();
    p.bold(true);
    p.line(title);
    p.bold(false);
    p.divider();
  }

  p.alignCenter();
  p.size(width: 2, height: 2);
  p.bold(true);
  for (final l in EscPos.wrap(settings.restaurantName.trim(), 24)) {
    p.line(l);
  }
  p.size();
  p.line('SALES REPORT');
  p.bold(false);
  p.line('${period.label}: ${period.dates}');
  p.line('Printed ${formatTime(now)} ${formatDate(now)}');
  p.alignLeft();
  p.divider('=');

  p.size(height: 2);
  p.bold(true);
  p.leftRight('TOTAL SALES', formatPrice(r.grossPence));
  p.bold(false);
  p.size();
  if (r.vatRate > 0) {
    p.leftRight('Net sales', formatPrice(r.netPence));
    p.leftRight(r.vatLabel, formatPrice(r.vatPence));
  }
  p.leftRight('Orders', '${r.orderCount}');
  p.leftRight('Average order', formatPrice(r.averagePence));
  p.leftRight('Items sold', '${r.itemCount}');
  if (r.voidCount > 0) {
    p.leftRight('Voided (${r.voidCount})', formatPrice(r.voidPence));
  }

  section('PAYMENTS');
  for (final e in SalesReport.sorted(r.byPayment)) {
    p.leftRight('${e.key} (${e.value.count})', formatPrice(e.value.pence));
  }

  section('ORDER TYPES');
  for (final e in SalesReport.sorted(r.byType)) {
    p.leftRight('${e.key} (${e.value.count})', formatPrice(e.value.pence));
  }

  section('CATEGORIES');
  for (final e in SalesReport.sorted(r.byCategory)) {
    p.leftRight('${e.key} (${e.value.count})', formatPrice(e.value.pence));
  }

  section('ITEMS SOLD');
  for (final i in r.items) {
    p.leftRight('${i.qty} x ${i.name}', formatPrice(i.pence));
  }

  if (r.unpaid.count > 0) {
    p.line();
    p.bold(true);
    p.line('UNPAID: ${r.unpaid.count} order(s), ${formatPrice(r.unpaid.pence)}');
    p.bold(false);
  }

  p.divider('=');
  p.feed(4);
  p.cut();
  return p.bytes();
}
