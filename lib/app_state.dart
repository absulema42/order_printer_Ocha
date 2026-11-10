import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'sales.dart';

/// Holds settings, the menu and the order being taken, and saves them on
/// the device so they survive restarts.
class AppState extends ChangeNotifier {
  static const _kSettings = 'settings';
  static const _kMenu = 'menu';
  static const _kLastNumber = 'lastOrderNumber';
  static const _kLastDate = 'lastOrderDate';
  static const _kBrand = 'brandVersion';

  late SharedPreferences _prefs;
  AppSettings settings = AppSettings();
  List<MenuItem> menu = [];
  final OrderController order = OrderController();
  final SalesStore sales = SalesStore();

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final s = _prefs.getString(_kSettings);
    if (s != null) {
      settings = AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
    }
    final m = _prefs.getString(_kMenu);
    menu = m != null ? MenuItem.decodeList(m) : sampleMenu();

    // One-time switch from the generic version to O'Cha Thai. Only replaces
    // the old placeholder name and untouched sample menu, never your edits.
    // ocha2: swaps an untouched placeholder menu for the real O'Cha menu.
    if (_prefs.getString(_kBrand) != 'ocha2') {
      if (settings.restaurantName == 'My Restaurant') {
        settings.restaurantName = defaultRestaurantName;
        await _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
      }
      if (menu.isNotEmpty &&
          menu.every(
              (i) => i.id.startsWith('sample') || i.id.startsWith('ocha'))) {
        menu = sampleMenu();
        await _prefs.setString(_kMenu, MenuItem.encodeList(menu));
      }
      await _prefs.setString(_kBrand, 'ocha2');
    }
  }

  List<String> get categories {
    final seen = <String>[];
    for (final i in menu) {
      if (!seen.contains(i.category)) seen.add(i.category);
    }
    return seen;
  }

  Future<void> saveSettings(AppSettings s) async {
    settings = s;
    await _prefs.setString(_kSettings, jsonEncode(s.toJson()));
    notifyListeners();
  }

  Future<void> saveMenu() async {
    await _prefs.setString(_kMenu, MenuItem.encodeList(menu));
    notifyListeners();
  }

  /// Adds imported items to the menu. With [replace] the whole menu is
  /// swapped; otherwise items with the same category and name are updated
  /// and new ones are added. Returns (added, updated).
  Future<(int, int)> importMenu(List<MenuItem> items,
      {required bool replace}) async {
    if (replace) {
      menu = List.of(items);
      await saveMenu();
      return (items.length, 0);
    }
    String key(MenuItem i) =>
        '${i.category.trim().toLowerCase()}|${i.name.trim().toLowerCase()}';
    final byKey = {for (final i in menu) key(i): i};
    var added = 0, updated = 0;
    for (final i in items) {
      final existing = byKey[key(i)];
      if (existing != null) {
        existing
          ..pricePence = i.pricePence
          ..takeawayPence = i.takeawayPence
          ..code = i.code.isNotEmpty ? i.code : existing.code;
        updated++;
      } else {
        menu.add(i);
        byKey[key(i)] = i;
        added++;
      }
    }
    await saveMenu();
    return (added, updated);
  }

  String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// The number the next order will get. Numbers restart at 1 each day.
  int peekOrderNumber() {
    if (_prefs.getString(_kLastDate) != _today()) return 1;
    return (_prefs.getInt(_kLastNumber) ?? 0) + 1;
  }

  Future<void> commitOrderNumber(int n) async {
    await _prefs.setInt(_kLastNumber, n);
    await _prefs.setString(_kLastDate, _today());
  }
}

class OrderController extends ChangeNotifier {
  final List<OrderLine> lines = [];
  final TextEditingController reference = TextEditingController();
  String type = 'Eat in';
  String payment = 'Card';

  static const types = ['Eat in', 'Takeaway', 'Delivery'];

  int get totalPence => lines.fold(0, (s, l) => s + l.totalPence);
  int get itemCount => lines.fold(0, (s, l) => s + l.qty);
  bool get isEmpty => lines.isEmpty;

  int qtyOf(MenuItem item) => lines
      .where((l) => l.item.id == item.id)
      .fold(0, (s, l) => s + l.qty);

  void add(MenuItem item) {
    final existing = lines.where(
        (l) => l.item.id == item.id && l.note.isEmpty && !l.manualPrice);
    if (existing.isNotEmpty) {
      existing.first.qty++;
    } else {
      lines.add(OrderLine(item, unitPence: item.priceFor(type)));
    }
    notifyListeners();
  }

  void increment(OrderLine l) {
    l.qty++;
    notifyListeners();
  }

  void decrement(OrderLine l) {
    l.qty--;
    if (l.qty <= 0) lines.remove(l);
    notifyListeners();
  }

  void remove(OrderLine l) {
    lines.remove(l);
    notifyListeners();
  }

  void setLine(OrderLine l, {int? unitPence, String? note}) {
    if (unitPence != null) {
      l.unitPence = unitPence;
      l.manualPrice = unitPence != l.item.priceFor(type);
    }
    if (note != null) l.note = note.trim();
    notifyListeners();
  }

  void setNote(OrderLine l, String note) {
    l.note = note.trim();
    notifyListeners();
  }

  void setType(String t) {
    type = t;
    // Switch to takeaway prices (or back), except prices typed by hand.
    for (final l in lines) {
      if (!l.manualPrice) l.unitPence = l.item.priceFor(t);
    }
    notifyListeners();
  }

  void setPayment(String p) {
    payment = p;
    notifyListeners();
  }

  void clear() {
    lines.clear();
    reference.clear();
    payment = 'Card';
    notifyListeners();
  }

  Order toOrder(int number) => Order(
        number: number,
        type: type,
        reference: reference.text,
        lines: lines
            .map((l) => OrderLine(l.item,
                qty: l.qty,
                note: l.note,
                unitPence: l.unitPence,
                manualPrice: l.manualPrice))
            .toList(),
        time: DateTime.now(),
        payment: payment,
      );
}
