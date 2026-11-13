import 'package:flutter_test/flutter_test.dart';
import 'package:order_printer/escpos.dart';
import 'package:order_printer/models.dart';
import 'package:order_printer/ticket.dart';

MenuItem _item(String name, int pence) =>
    MenuItem(id: name, name: name, category: 'Test', pricePence: pence);

void main() {
  test('pound sign is encoded for code page 437', () {
    expect(EscPos.encode('£5'), [0x9C, 0x35]);
  });

  test('wrap breaks on spaces', () {
    expect(EscPos.wrap('one two three', 7), ['one two', 'three']);
  });

  test('parsePrice', () {
    expect(parsePrice('8.50'), 850);
    expect(parsePrice('£12'), 1200);
    expect(parsePrice('abc'), isNull);
  });

  test('ticket starts with reset and ends with cut', () {
    final order = Order(
      number: 7,
      type: 'Eat in',
      reference: '12',
      lines: [
        OrderLine(_item('Green Curry', 1195),
            qty: 2, note: 'Chicken, Medium')
      ],
      time: DateTime(2026, 11, 2, 18, 5),
    );
    final bytes = buildOrderTicket(order, AppSettings());
    expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    expect(bytes.sublist(bytes.length - 3), [0x1D, 0x56, 0x00]);
    final text = String.fromCharCodes(bytes);
    expect(text, contains("O'Cha Thai"));
    expect(text, contains('ORDER #7'));
    expect(text, contains('2 x Green Curry'));
    expect(text, contains('Chicken, Medium'));
  });

  test('receipt shows business details, VAT and number', () {
    final order = Order(
      number: 3,
      type: 'Takeaway',
      reference: '',
      lines: [
        OrderLine(_item('Pad Thai', 1195), qty: 1),
        OrderLine(_item('Jasmine Rice', 350), qty: 1),
      ],
      time: DateTime(2026, 11, 6, 18, 5, 9),
      payment: 'Card',
    );
    final bytes = buildReceipt(order, AppSettings());
    final text = String.fromCharCodes(bytes);
    expect(text, contains('Korvipong Ltd Main Store'));
    expect(text, contains('korvipong2523@gmail.com'));
    expect(text, contains('VAT Number: 334898753'));
    expect(text, contains('20VAT'));
    expect(text, contains('20.00%'));
    // 1545 * 20 / 120 = 257.5 -> 258
    expect(text, contains('\x9C2.58'));
    expect(text, contains('18:05:09'));
    expect(text, contains('Thank you for shopping with us'));
    expect(bytes.sublist(bytes.length - 3), [0x1D, 0x56, 0x00]);
  });

  test('slip style controls what prints', () {
    final order = Order(
        number: 1, type: 'Eat in', reference: '', lines: [], time: DateTime(2026));
    final r = buildReceipt(order, AppSettings()).length;
    final k = buildOrderTicket(order, AppSettings()).length;
    expect(buildOrderSlips(order, AppSettings()).length, r);
    expect(buildOrderSlips(order, AppSettings(slipStyle: 'both')).length, r + k);
    expect(buildOrderSlips(order, AppSettings(slipStyle: 'kitchen')).length, k);
  });

  test('amended basket price is used on the receipt and total', () {
    final item = _item('Pad Thai', 1195);
    final line = OrderLine(item, qty: 2, unitPence: 1000, manualPrice: true);
    expect(line.totalPence, 2000);
    expect(line.priceChanged, isTrue);
    expect(item.pricePence, 1195); // menu untouched
    final order = Order(
        number: 1, type: 'Eat in', reference: '', lines: [line],
        time: DateTime(2026, 11, 6));
    final text = String.fromCharCodes(buildReceipt(order, AppSettings()));
    expect(text, contains('\x9C10.00'));
    expect(text, contains('\x9C20.00'));
  });

  test('product text sizes', () {
    final order = Order(
        number: 1, type: 'Eat in', reference: '',
        lines: [OrderLine(_item('Pad Thai Chicken', 1095), qty: 2)],
        time: DateTime(2026, 11, 6));
    String receipt(String size) => String.fromCharCodes(
        buildReceipt(order, AppSettings(itemSize: size)));
    // Tall: double height (GS ! 0x01) and extra row spacing (ESC J).
    expect(receipt('tall'), contains('\x1D\x21\x01'));
    // Wide (the default): double width, normal height (GS ! 0x10).
    expect(receipt('wide'), contains('\x1D\x21\x10'));
    expect(receipt('wide'), contains('2 x \x9C10.95'));
    expect(AppSettings().itemSize, 'large');
    expect(receipt('tall'), contains('\x1B\x4A'));
    expect(receipt('normal'), isNot(contains('\x1B\x4A')));
    // Extra large: name on its own line, then qty x price and total.
    expect(receipt('large'), contains('2 x \x9C10.95'));
    expect(receipt('large'), contains('\x9C21.90'));
  });
}
