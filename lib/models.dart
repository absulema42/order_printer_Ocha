import 'dart:convert';

/// One dish or drink on the menu. Prices are stored in pence to avoid
/// floating-point rounding errors.
class MenuItem {
  final String id;
  String name;
  String category;
  int pricePence;

  /// Menu number, e.g. "23". Optional.
  String code;

  /// Price for takeaway and delivery orders, if different. Optional.
  int? takeawayPence;

  MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.pricePence,
    this.code = '',
    this.takeawayPence,
  });

  /// The price to charge for an order of this type.
  int priceFor(String orderType) =>
      orderType != 'Eat in' && takeawayPence != null
          ? takeawayPence!
          : pricePence;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'price': pricePence,
        if (code.isNotEmpty) 'code': code,
        if (takeawayPence != null) 'ta': takeawayPence,
      };

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        id: j['id'] as String,
        name: j['name'] as String,
        category: (j['category'] as String?) ?? 'Other',
        pricePence: (j['price'] as num?)?.toInt() ?? 0,
        code: (j['code'] as String?) ?? '',
        takeawayPence: (j['ta'] as num?)?.toInt(),
      );

  static String encodeList(List<MenuItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<MenuItem> decodeList(String s) => (jsonDecode(s) as List)
      .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// A line on the current order: an item, how many, and an optional note
/// such as "no onions".
class OrderLine {
  final MenuItem item;
  int qty;
  String note;

  /// Price for this order only. Starts as the menu price and can be
  /// changed in the basket without touching the menu.
  int unitPence;

  /// True when staff typed a price in the basket. Such lines keep their
  /// price when the order type changes.
  bool manualPrice;

  OrderLine(this.item,
      {this.qty = 1, this.note = '', int? unitPence, this.manualPrice = false})
      : unitPence = unitPence ?? item.pricePence;

  int get totalPence => unitPence * qty;
  bool get priceChanged => manualPrice;
}

/// Everything needed to print one order.
class Order {
  final int number;
  final String type; // Eat in / Takeaway / Delivery
  final String reference; // table number or customer name
  final List<OrderLine> lines;
  final DateTime time;
  final String payment; // Card / Cash / Online / Unpaid, '' = not shown

  Order({
    required this.number,
    required this.type,
    required this.reference,
    required this.lines,
    required this.time,
    this.payment = '',
  });

  int get totalPence => lines.fold(0, (sum, l) => sum + l.totalPence);
  int get itemCount => lines.fold(0, (sum, l) => sum + l.qty);
}

/// Printer and slip settings.
class AppSettings {
  String restaurantName;
  String printerHost;
  int printerPort;
  int copies;
  bool showPrices;
  double vatRate; // percent included in prices; 0 = not VAT registered

  // Customer receipt details
  String businessLine;
  String email;
  String vatNumber;
  String footer;
  String staffName;
  String deviceName;

  /// What prints for each order: 'receipt' (customer receipt),
  /// 'kitchen' (large kitchen ticket) or 'both'.
  String slipStyle;

  /// Size of the product lines on the receipt: 'normal', 'tall' (double
  /// height, same columns) or 'large' (double height and width).
  String itemSize;

  AppSettings({
    this.restaurantName = defaultRestaurantName,
    this.printerHost = '',
    this.printerPort = 9100,
    this.copies = 1,
    this.showPrices = true,
    this.vatRate = 20,
    this.businessLine = 'Korvipong Ltd Main Store',
    this.email = 'korvipong2523@gmail.com',
    this.vatNumber = '334898753',
    this.footer = 'Thank you for shopping with us',
    this.staffName = 'Supervisor',
    this.deviceName = 'Till1',
    this.slipStyle = 'receipt',
    this.itemSize = 'tall',
  });

  static const itemSizes = {
    'normal': 'Normal',
    'tall': 'Tall',
    'large': 'Extra large',
  };

  static const slipStyles = {
    'receipt': 'Customer receipt',
    'kitchen': 'Kitchen ticket',
    'both': 'Receipt + kitchen ticket',
  };

  Map<String, dynamic> toJson() => {
        'restaurantName': restaurantName,
        'printerHost': printerHost,
        'printerPort': printerPort,
        'copies': copies,
        'showPrices': showPrices,
        'vatRate': vatRate,
        'businessLine': businessLine,
        'email': email,
        'vatNumber': vatNumber,
        'footer': footer,
        'staffName': staffName,
        'deviceName': deviceName,
        'slipStyle': slipStyle,
        'itemSize': itemSize,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        restaurantName: (j['restaurantName'] as String?) ?? defaultRestaurantName,
        printerHost: (j['printerHost'] as String?) ?? '',
        printerPort: (j['printerPort'] as num?)?.toInt() ?? 9100,
        copies: (j['copies'] as num?)?.toInt() ?? 1,
        showPrices: (j['showPrices'] as bool?) ?? true,
        vatRate: (j['vatRate'] as num?)?.toDouble() ?? 20,
        businessLine:
            (j['businessLine'] as String?) ?? 'Korvipong Ltd Main Store',
        email: (j['email'] as String?) ?? 'korvipong2523@gmail.com',
        vatNumber: (j['vatNumber'] as String?) ?? '334898753',
        footer: (j['footer'] as String?) ?? 'Thank you for shopping with us',
        staffName: (j['staffName'] as String?) ?? 'Supervisor',
        deviceName: (j['deviceName'] as String?) ?? 'Till1',
        slipStyle: slipStyles.containsKey(j['slipStyle'])
            ? j['slipStyle'] as String
            : 'receipt',
        itemSize: itemSizes.containsKey(j['itemSize'])
            ? j['itemSize'] as String
            : 'tall',
      );
}

const paymentMethods = ['Card', 'Cash', 'Online', 'Unpaid'];

String formatPrice(int pence) => '£${(pence / 100).toStringAsFixed(2)}';

/// Parses "8.50", "£8.50" or "8" into pence. Returns null if invalid.
int? parsePrice(String input) {
  final cleaned = input.replaceAll('£', '').replaceAll(',', '.').trim();
  final value = double.tryParse(cleaned);
  if (value == null || value < 0) return null;
  return (value * 100).round();
}

const String defaultRestaurantName = "O'Cha Thai";

/// O'Cha Thai menu, from O_cha_menu.xlsx. Edit it in Settings -> Edit menu
/// or import an updated spreadsheet.
List<MenuItem> sampleMenu() {
  var n = 0;
  MenuItem m(String name, String cat, int p, {String code = '', int? ta}) =>
      MenuItem(
          id: 'menu_${n++}',
          name: name,
          category: cat,
          pricePence: p,
          code: code,
          takeawayPence: ta);
  return [
    m('Chicken satay', 'Starters', 695, code: '1'),
    m('Prawan Satay', 'Starters', 695, code: '2'),
    m('Khanom Pang Goong Gai', 'Starters', 695, code: '3'),
    m('Pho Pia Tord', 'Starters', 650, code: '4'),
    m('Prawan Spring role', 'Starters', 695, code: '5'),
    m('Tempura Goong', 'Starters', 695, code: '6'),
    m('Tord Mun Pla', 'Starters', 695, code: '7'),
    m('Pork Dumplings', 'Starters', 695, code: '8'),
    m('Spare Ribs', 'Starters', 695, code: '9'),
    m('Tempura Mixed Pak', 'Starters', 595, code: '10'),
    m('Tord Mun Khaw Pod', 'Starters', 650, code: '11'),
    m('Calamari', 'Starters', 695, code: '12'),
    m('Squid Rings', 'Starters', 695, code: '13'),
    m('Peek Gai Tord', 'Starters', 695, code: '14'),
    m('Tao Hoo Tord', 'Starters', 595, code: '15'),
    m('Khaw Keep Goon', 'Starters', 320, code: '16'),
    m('O Cha Mixed Starters', 'Starters', 1595, code: '17'),
    m('Tom Yum Prawn', 'Soup', 695, code: '18'),
    m('Tom Yum Chicken', 'Soup', 675, code: '18'),
    m('Tom Yum Mushroom', 'Soup', 595, code: '18'),
    m('Tom Kha Prawn', 'Soup', 695, code: '19'),
    m('Tom Kha Chicken', 'Soup', 675, code: '19'),
    m('Tom Kha Mushroom', 'Soup', 625, code: '19'),
    m('Poh Teak Talay', 'Soup', 795, code: '20'),
    m('Pad Med Mamuang', 'Chicken', 995, code: '21'),
    m('Pad Prew Wan', 'Chicken', 995, code: '22'),
    m('Pad Kra Pow Gai', 'Chicken', 995, code: '23'),
    m('Pad Kra Tiem', 'Chicken', 995, code: '24'),
    m('Pad King', 'Chicken', 995, code: '25'),
    m('Pad Khaw Pod', 'Chicken', 995, code: '26'),
    m('Pad Prig Khing', 'Chicken', 995, code: '27'),
    m('Pad Num Prig Phow', 'Chicken', 995, code: '28'),
    m('Pad Saparod Gai', 'Chicken', 995, code: '29'),
    m('Spicy Jungle Pork', 'Pork', 995, code: '30'),
    m('Moo Prew Wan', 'Pork', 995, code: '31'),
    m('Moo Kra Tiem', 'Pork', 995, code: '32'),
    m('Moo Pad King', 'Pork', 995, code: '33'),
    m('Moo Kra Pow', 'Pork', 995, code: '34'),
    m('Moo Prig King', 'Pork', 995, code: '35'),
    m('Neau Num Mun Hoi', 'Beef', 995, code: '36'),
    m('Neau Kra Tiem', 'Beef', 995, code: '37'),
    m('Neau Kra Pow', 'Beef', 995, code: '38'),
    m('Neau Pad King', 'Beef', 995, code: '39'),
    m('Neau Nor Mai', 'Beef', 995, code: '40'),
    m('Ped Pad Phed', 'Duck', 1095, code: '41'),
    m('Pad Kra Pow', 'Duck', 1095, code: '42'),
    m('Pad Med Mamuang', 'Duck', 1095, code: '43'),
    m('Ped Pad Khing', 'Duck', 1095, code: '44'),
    m('Goong Siam', 'Seafood', 995, code: '45'),
    m('Samui Seafood', 'Seafood', 1195, code: '46'),
    m('Black Sea', 'Seafood', 1195, code: '47'),
    m('Talay Deang', 'Seafood', 1195, code: '48'),
    m('Talay Dead', 'Seafood', 1195, code: '49'),
    m('Beauty On The Beach', 'Seafood', 1195, code: '50'),
    m('Hello Mea Maid', 'Seafood', 1050, code: '51'),
    m('Pha Jien', 'Seafood', 1050, code: '52'),
    m('Pad Ped Talay', 'Seafood', 1195, code: '53'),
    m('Pad Kra Pow Pla Maug', 'Seafood', 1050, code: '54'),
    m('Pad Kra Pow Goong', 'Seafood', 995, code: '55'),
    m('Pad Prew Wan Goong', 'Seafood', 995, code: '56'),
    m('Pla Prew Wan', 'Seafood', 1050, code: '57'),
    m('Baby Corn & Mushroom', 'Vegetarian', 750, code: '58'),
    m('Mixed Vegetables', 'Vegetarian', 750, code: '59'),
    m('Tofu with Cashew Nuts', 'Vegetarian', 795, code: '60'),
    m('Tofu with Garlic', 'Vegetarian', 795, code: '61'),
    m('Tofu with Bean Sprouts', 'Vegetarian', 795, code: '62'),
    m('Broccoli with Garlic', 'Vegetarian', 750, code: '63'),
    m('Aubergine with Chilli', 'Vegetarian', 750, code: '64'),
    m('Long Bean with Tofu', 'Vegetarian', 795, code: '65'),
    m('Glass Noodles with Vegetables', 'Vegetarian', 795, code: '66'),
    m('Crispy Bean Curd with Chilli', 'Vegetarian', 795, code: '67'),
    m('Green Chicken', 'Curry', 1050, code: '68'),
    m('Green Beef', 'Curry', 1050, code: '68'),
    m('Green Pork', 'Curry', 1050, code: '68'),
    m('Green Prawns', 'Curry', 1150, code: '68'),
    m('Green Vegetables', 'Curry', 950, code: '68'),
    m('Red Chicken', 'Curry', 1050, code: '69'),
    m('Red Beef', 'Curry', 1050, code: '69'),
    m('Red Pork', 'Curry', 1050, code: '69'),
    m('Red Prawns', 'Curry', 1150, code: '69'),
    m('Red Vegetables', 'Curry', 950, code: '69'),
    m('Gaeng Gar Rie Chicken', 'Curry', 1050, code: '70'),
    m('Gaeng Gar Rie Beef', 'Curry', 1050, code: '70'),
    m('Gaeng Gar Rie Pork', 'Curry', 1050, code: '70'),
    m('Gaeng Gar Rie Vegetables', 'Curry', 950, code: '70'),
    m('Jungle Curry Chicken', 'Curry', 1050, code: '71'),
    m('Jungle Curry Beef', 'Curry', 1050, code: '71'),
    m('Jungle Curry Vegetables', 'Curry', 950, code: '71'),
    m('Panaeng Chicken', 'Curry', 1150, code: '72'),
    m('Panaeng Beef', 'Curry', 1150, code: '72'),
    m('Panaeng Pork', 'Curry', 1150, code: '72'),
    m('Panaeng Prawns', 'Curry', 1250, code: '72'),
    m('Quack Quack Curry', 'Curry', 1250, code: '73'),
    m('Massaman Beef', 'Curry', 1250, code: '74'),
    m('Massaman Chicken', 'Curry', 1250, code: '74'),
    m('Yum Hed', 'Salad', 895, code: '75'),
    m('Yum Woon Sen', 'Salad', 1195, code: '76'),
    m('Yum Neau (Beef Salad)', 'Salad', 1195, code: '77'),
    m('Yum Talay', 'Salad', 1295, code: '78'),
    m('Pla Siam', 'Salad', 1195, code: '79'),
    m('Pia Goong (Prawn Salad)', 'Salad', 1095, code: '80'),
    m('Som Tum', 'Salad', 895, code: '81'),
    m('Ped Makram Duck', 'Special', 1295, code: '82'),
    m('Moo Yang', 'Special', 1295, code: '83'),
    m('Laab Chicken', 'Special', 1195, code: '84'),
    m('Laab Pork', 'Special', 1195, code: '84'),
    m('Laab Roast Duck', 'Special', 1295, code: '84'),
    m('Goong Pow', 'Special', 950, code: '85'),
    m('Pad Thai Chicken', 'Noodles', 1095, code: '86'),
    m('Pad Thai Beef', 'Noodles', 1095, code: '86'),
    m('Pad Thai Pork', 'Noodles', 1095, code: '86'),
    m('Pad Thai Prawn', 'Noodles', 1195, code: '86'),
    m('Pad Thai Vegetable', 'Noodles', 995, code: '86'),
    m('Pad Si-ew Chicken', 'Noodles', 1095, code: '87'),
    m('Pad Si-ew Beef', 'Noodles', 1095, code: '87'),
    m('Pad Si-ew Pork', 'Noodles', 1095, code: '87'),
    m('Pad Si-ew Prawn', 'Noodles', 1195, code: '87'),
    m('Pad Si-ew Vegetable', 'Noodles', 995, code: '87'),
    m('Pad Meed Goreng Chicken', 'Noodles', 1095, code: '88'),
    m('Pad Meed Goreng Beef', 'Noodles', 1095, code: '88'),
    m('Pad Meed Goreng Pork', 'Noodles', 1095, code: '88'),
    m('Pad Kee Mao Goong', 'Noodles', 1195, code: '89'),
    m('Pad Chow Mian Chicken', 'Noodles', 1095, code: '90'),
    m('Pad Chow Mian Pork', 'Noodles', 1095, code: '90'),
    m('Pad Chow Mian Beef', 'Noodles', 1095, code: '90'),
    m('Pad Kee Mao Talay', 'Noodles', 1295, code: '91'),
    m('Yellow Egg Noodles', 'Noodles', 695, code: '92'),
    m('Jasmine Rice', 'Rice', 330),
    m('Coconut Rice', 'Rice', 380),
    m('Khao Pad Ocha', 'Rice', 1195),
    m('Egg Rice', 'Rice', 380),
    m('Sticky Rice', 'Rice', 400),
    m('Chips', 'Rice', 380),
    m('Omelette with Onions', 'Rice', 595),
    m('Veg Set 2', 'Set Menu', 4200),
    m('Set A', 'Set Menu', 4600),
    m('Coke', 'Drinks', 300, ta: 180),
    m('Diet Coke', 'Drinks', 300, ta: 180),
    m('7 Up', 'Drinks', 300, ta: 180),
    m('Sprite', 'Drinks', 300, ta: 180),
    m('Fanta', 'Drinks', 300, ta: 180),
    m('Tango', 'Drinks', 300, ta: 180),
    m('Water', 'Drinks', 300, ta: 180),
    m('Rubicon', 'Drinks', 300, ta: 180),
    m('Dr Pepper', 'Drinks', 300, ta: 180),
    m('Apple Juice', 'Drinks', 300, ta: 230),
    m('Orange Juice', 'Drinks', 300, ta: 230),
    m('Coconut Juice', 'Drinks', 300, ta: 230),
    m('Appletiser', 'Drinks', 300, ta: 230),
    m('Tamarind Juice', 'Drinks', 300, ta: 230),
    m('Red Bull', 'Drinks', 300, ta: 250),
  ];
}
