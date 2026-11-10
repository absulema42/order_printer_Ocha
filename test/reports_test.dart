import 'package:flutter_test/flutter_test.dart';
import 'package:order_printer/reports.dart';
import 'package:order_printer/sales.dart';

SaleRecord _sale(int n, DateTime t, String pay, List<SaleLine> lines,
        {String type = 'Eat in', bool voided = false}) =>
    SaleRecord(
      id: '$n',
      number: n,
      time: t,
      type: type,
      reference: '',
      payment: pay,
      lines: lines,
      voided: voided,
    );

void main() {
  final day = DateTime(2026, 11, 3);
  const curry = SaleLine(
      name: 'Green Curry', category: 'Curries', qty: 2, unitPence: 1200);
  const rice = SaleLine(
      name: 'Jasmine Rice', category: 'Rice', qty: 2, unitPence: 300);
  const padThai =
      SaleLine(name: 'Pad Thai', category: 'Noodles', qty: 1, unitPence: 1200);

  final orders = [
    _sale(1, day.add(const Duration(hours: 12)), 'Card', [curry, rice]),
    _sale(2, day.add(const Duration(hours: 18)), 'Cash', [padThai],
        type: 'Takeaway'),
    _sale(3, day.add(const Duration(hours: 19)), 'Card', [padThai],
        voided: true),
  ];

  test('totals leave out voided orders', () {
    final r = SalesReport(orders, vatRate: 20);
    expect(r.grossPence, 3000 + 1200);
    expect(r.orderCount, 2);
    expect(r.itemCount, 5);
    expect(r.voidCount, 1);
    expect(r.voidPence, 1200);
    expect(r.averagePence, 2100);
  });

  test('VAT is the VAT-inclusive fraction', () {
    final r = SalesReport(orders, vatRate: 20);
    expect(r.vatPence, 700); // 4200 * 20 / 120
    expect(r.netPence, 3500);
    expect(SalesReport(orders, vatRate: 0).vatPence, 0);
  });

  test('breakdowns', () {
    final r = SalesReport(orders, vatRate: 20);
    expect(r.byPayment['Card']!.pence, 3000);
    expect(r.byPayment['Cash']!.pence, 1200);
    expect(r.byType['Takeaway']!.count, 1);
    expect(r.byCategory['Curries']!.count, 2);
    expect(r.byHour[18]!.pence, 1200);
    expect(r.items.first.name, 'Green Curry');
  });

  test('periods', () {
    final now = DateTime(2026, 11, 4, 15, 30); // a Wednesday
    final week = ReportPeriod.preset('week', now);
    expect(week.from, DateTime(2026, 11, 2));
    expect(week.to, DateTime(2026, 11, 9));
    final lastMonth = ReportPeriod.preset('lastMonth', now);
    expect(lastMonth.from, DateTime(2026, 10, 1));
    expect(lastMonth.to, DateTime(2026, 11, 1));
    expect(ReportPeriod.preset('today', now).isSingleDay, isTrue);
    expect(ReportPeriod.range(DateTime(2026, 11, 1), DateTime(2026, 11, 3)).dates,
        '01/11/2026 - 03/11/2026');
  });

  test('CSV quotes commas and blocks formulas', () {
    final r = SalesReport([
      _sale(4, day, 'Card', const [
        SaleLine(
            name: 'Red Curry',
            category: 'Curries',
            qty: 1,
            unitPence: 1100,
            note: 'beef, hot'),
        SaleLine(
            name: '=HYPERLINK()', category: 'Other', qty: 1, unitPence: 0),
      ]),
    ], vatRate: 20);
    final csv = itemsCsv(r);
    expect(csv, contains('"beef, hot"'));
    expect(csv, contains("'=HYPERLINK()"));
    expect(csv, contains('11.00'));
  });

  test('sale record survives a save/load round trip', () {
    final o = orders.first;
    final back = SaleRecord.fromJson(o.toJson());
    expect(back.totalPence, o.totalPence);
    expect(back.time, o.time);
    expect(back.payment, 'Card');
  });
}
