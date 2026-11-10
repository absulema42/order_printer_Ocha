import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:order_printer/app_state.dart';
import 'package:order_printer/menu_import.dart';
import 'package:order_printer/models.dart';

void main() {
  test("imports the O'Cha spreadsheet", () {
    final bytes = File('test/fixtures/O_cha_menu.xlsx').readAsBytesSync();
    final r = readMenuFile('O_cha_menu.xlsx', bytes);
    expect(r.items.length, 151);
    expect(r.skippedRows, 0);
    final first = r.items.first;
    expect(first.name, 'Chicken satay');
    expect(first.category, 'Starters');
    expect(first.pricePence, 695);
    expect(first.code, '1');
    // Variants without a number share the dish number above them.
    final tomYumChicken = r.items.firstWhere((i) => i.name == 'Tom Yum Chicken');
    expect(tomYumChicken.code, '18');
    expect(tomYumChicken.pricePence, 675);
    // Drinks have eat-in and takeaway prices.
    final coke = r.items.firstWhere((i) => i.name == 'Coke');
    expect(coke.category, 'Drinks');
    expect(coke.pricePence, 300);
    expect(coke.takeawayPence, 180);
    expect(r.categoryCounts['Curry'], 24);
  });

  test('flat table with a category column, and CSV', () {
    final r = readMenuFile('menu.csv', '''Code,Name,Category,Price
1,Spring Rolls,Starters,£5.50
2,"Pad Thai, Chicken",Noodles,10.95
,Bad row,Noodles,free
'''.codeUnits);
    expect(r.items.length, 2);
    expect(r.items[1].name, 'Pad Thai, Chicken');
    expect(r.items[1].category, 'Noodles');
    expect(r.items[0].pricePence, 550);
    expect(r.skippedRows, 1);
  });

  test('takeaway price is used for takeaway orders', () {
    final coke = MenuItem(
        id: 'c', name: 'Coke', category: 'Drinks', pricePence: 300,
        takeawayPence: 180);
    final order = OrderController();
    order.add(coke);
    expect(order.totalPence, 300);
    order.setType('Takeaway');
    expect(order.totalPence, 180);
    order.setLine(order.lines.first, unitPence: 150); // typed by hand
    order.setType('Eat in');
    expect(order.totalPence, 150);
  });

  test('built-in menu matches the spreadsheet', () {
    final m = sampleMenu();
    expect(m.length, 151);
    expect(m.where((i) => i.category == 'Noodles').length, 19);
  });
}
