import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../printer_service.dart';
import '../sales.dart';
import '../ticket.dart';
import 'sales_screen.dart';
import 'settings_screen.dart';

class OrderScreen extends StatefulWidget {
  final AppState app;
  const OrderScreen({super.key, required this.app});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  String? _category; // null = all
  String _query = '';
  bool _printing = false;

  AppState get app => widget.app;

  Future<void> _print() async {
    final order = app.order;
    if (order.isEmpty || _printing) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    if (app.settings.printerHost.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(
        content: const Text('Set the printer IP address first.'),
        action: SnackBarAction(label: 'Settings', onPressed: _openSettings),
      ));
      return;
    }

    setState(() => _printing = true);
    final number = app.peekOrderNumber();
    final placed = order.toOrder(number);
    final bytes = buildOrderSlips(placed, app.settings);
    try {
      for (var i = 0; i < app.settings.copies; i++) {
        await PrinterService.send(
            app.settings.printerHost, app.settings.printerPort, bytes);
      }
      await app.commitOrderNumber(number);
      var saved = true;
      try {
        await app.sales.add(SaleRecord.fromOrder(placed));
      } catch (_) {
        saved = false;
      }
      order.clear();
      if (navigator.canPop()) navigator.pop(); // close the order sheet on phones
      messenger.showSnackBar(SnackBar(
        content: Text(saved
            ? 'Order #$number sent to printer'
            : 'Order #$number printed, but it could not be saved to sales '
                'history.'),
        backgroundColor: saved ? null : errorColor,
      ));
    } on PrinterException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: errorColor,
        duration: const Duration(seconds: 6),
      ));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SettingsScreen(app: app)));
    if (mounted) setState(() {});
  }

  void _openOrderSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _OrderPanel(app: app, onPrint: _print, printing: () => _printing),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(app.settings.restaurantName),
        actions: [
          IconButton(
            tooltip: 'Sales & reports',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SalesScreen(app: app))),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 800;
        final menu = _MenuPanel(
          app: app,
          category: _category,
          onCategory: (cat) => setState(() => _category = cat),
          query: _query,
          onQuery: (q) => setState(() => _query = q),
        );
        if (wide) {
          return Row(children: [
            Expanded(child: menu),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 380,
              child: _OrderPanel(
                  app: app, onPrint: _print, printing: () => _printing),
            ),
          ]);
        }
        return Column(children: [
          Expanded(child: menu),
          ListenableBuilder(
            listenable: app.order,
            builder: (context, _) => SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: app.order.isEmpty ? null : _openOrderSheet,
                    icon: const Icon(Icons.receipt_long),
                    label: Text(app.order.isEmpty
                        ? 'Tap items to start an order'
                        : 'View order (${app.order.itemCount})  ·  '
                            '${formatPrice(app.order.totalPence)}'),
                  ),
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

class _MenuPanel extends StatelessWidget {
  final AppState app;
  final String? category;
  final ValueChanged<String?> onCategory;
  final String query;
  final ValueChanged<String> onQuery;

  const _MenuPanel({
    required this.app,
    required this.category,
    required this.onCategory,
    required this.query,
    required this.onQuery,
  });

  @override
  Widget build(BuildContext context) {
    final cats = app.categories;
    final q = query.trim().toLowerCase();
    final items = q.isNotEmpty
        ? app.menu
            .where((i) => i.name.toLowerCase().contains(q) || i.code == q)
            .toList()
        : category == null
            ? app.menu
            : app.menu.where((i) => i.category == category).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: TextField(
          onChanged: onQuery,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search by name or number',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            _chip(context, 'All', category == null, () => onCategory(null)),
            for (final c in cats)
              _chip(context, c, category == c, () => onCategory(c)),
          ],
        ),
      ),
      Expanded(
        child: items.isEmpty
            ? Center(
                child: Text(q.isNotEmpty
                    ? 'Nothing matches "$query".'
                    : 'No items. Add some in Settings → Menu.'))
            : ListenableBuilder(
                listenable: app.order,
                builder: (context, _) => GridView.extent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 1.35,
                  padding: const EdgeInsets.all(12),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    for (final item in items)
                      _MenuTile(
                        item: item,
                        pricePence: item.priceFor(app.order.type),
                        qty: app.order.qtyOf(item),
                        onTap: () => app.order.add(item),
                      ),
                  ],
                ),
              ),
      ),
    ]);
  }

  Widget _chip(
          BuildContext context, String label, bool selected, VoidCallback f) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
            label: Text(label), selected: selected, onSelected: (_) => f()),
      );
}

class _MenuTile extends StatelessWidget {
  final MenuItem item;
  final int pricePence;
  final int qty;
  final VoidCallback onTap;

  const _MenuTile(
      {required this.item,
      required this.pricePence,
      required this.qty,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: qty > 0 ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Stack(children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.code.isEmpty ? item.name : '${item.code}. ${item.name}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(formatPrice(pricePence),
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            if (qty > 0)
              Positioned(
                right: 0,
                top: 0,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primary,
                  child: Text('$qty',
                      style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// One-tap notes for the order line dialog: protein, spice level, dietary.
const quickNotes = [
  'Chicken', 'Beef', 'Pork', 'Prawn', 'Tofu', 'Vegetable', 'Duck',
  'Mild', 'Medium', 'Hot', 'Thai hot',
  'No peanuts', 'No chilli', 'Vegan', 'Gluten free', 'Extra rice',
];

class _OrderPanel extends StatelessWidget {
  final AppState app;
  final Future<void> Function() onPrint;
  final bool Function() printing;

  const _OrderPanel(
      {required this.app, required this.onPrint, required this.printing});

  Future<void> _editLine(BuildContext context, OrderLine line) async {
    final note = TextEditingController(text: line.note);
    final price =
        TextEditingController(text: (line.unitPence / 100).toStringAsFixed(2));
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) {
        void save() {
          final pence = parsePrice(price.text);
          if (pence == null) {
            setDialog(() => error = 'Enter a price like 8.50');
            return;
          }
          app.order.setLine(line, unitPence: pence, note: note.text);
          Navigator.pop(ctx);
        }

        return AlertDialog(
          title: Text(line.item.name),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: price,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Price each',
                      prefixText: '£',
                      helperText:
                          'Menu price '
                          '${formatPrice(line.item.priceFor(app.order.type))}. '
                          'Changes apply to this order only.',
                      errorText: error,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => save(),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setDialog(() => price.text =
                          (line.item.priceFor(app.order.type) / 100)
                              .toStringAsFixed(2)),
                      child: const Text('Reset to menu price'),
                    ),
                  ),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      hintText: 'e.g. chicken, medium spicy',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => save(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final q in quickNotes)
                      ActionChip(
                        label: Text(q),
                        onPressed: () {
                          final t = note.text.trim();
                          note.text = t.isEmpty ? q : '$t, $q';
                          note.selection =
                              TextSelection.collapsed(offset: note.text.length);
                        },
                      ),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(onPressed: save, child: const Text('Save')),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = app.order;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: order,
      builder: (context, _) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: [
                  for (final t in OrderController.types)
                    ButtonSegment(value: t, label: Text(t)),
                ],
                selected: {order.type},
                showSelectedIcon: false,
                onSelectionChanged: (s) => order.setType(s.first),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: order.reference,
              decoration: InputDecoration(
                labelText: order.type == 'Eat in'
                    ? 'Table number'
                    : 'Customer name / phone',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: [
                  for (final m in paymentMethods)
                    ButtonSegment(value: m, label: Text(m)),
                ],
                selected: {order.payment},
                showSelectedIcon: false,
                onSelectionChanged: (s) => order.setPayment(s.first),
              ),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: order.isEmpty
              ? Center(
                  child: Text('No items yet',
                      style: text.bodyLarge
                          ?.copyWith(color: Theme.of(context).hintColor)))
              : ListView.separated(
                  itemCount: order.lines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final l = order.lines[i];
                    final hint = Theme.of(context).hintColor;
                    return ListTile(
                      onTap: () => _editLine(context, l),
                      isThreeLine: true,
                      title: Text(l.item.name),
                      subtitle: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.priceChanged
                                ? '${formatPrice(l.unitPence)} each '
                                    '(menu ${formatPrice(l.item.priceFor(order.type))})'
                                : '${formatPrice(l.unitPence)} each',
                            style: l.priceChanged
                                ? TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600)
                                : null,
                          ),
                          Text(
                            l.note.isEmpty
                                ? 'Tap to change price or add a note'
                                : '>> ${l.note}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: l.note.isEmpty
                                ? TextStyle(color: hint)
                                : const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => order.decrement(l),
                        ),
                        Text('${l.qty}', style: text.titleMedium),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => order.increment(l),
                        ),
                      ]),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Text('Total', style: text.titleLarge),
                const Spacer(),
                Text(formatPrice(order.totalPence),
                    style:
                        text.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                OutlinedButton(
                  onPressed: order.isEmpty ? null : order.clear,
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: _PrintButton(
                        enabled: !order.isEmpty,
                        onPrint: onPrint,
                        printing: printing),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Keeps its own spinner state so it works both in the side panel and
/// inside the phone bottom sheet.
class _PrintButton extends StatefulWidget {
  final bool enabled;
  final Future<void> Function() onPrint;
  final bool Function() printing;

  const _PrintButton(
      {required this.enabled, required this.onPrint, required this.printing});

  @override
  State<_PrintButton> createState() => _PrintButtonState();
}

class _PrintButtonState extends State<_PrintButton> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await widget.onPrint();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy || widget.printing();
    return FilledButton.icon(
      onPressed: widget.enabled && !busy ? _go : null,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.print),
      label: Text(busy ? 'Printing…' : 'Print order'),
    );
  }
}
