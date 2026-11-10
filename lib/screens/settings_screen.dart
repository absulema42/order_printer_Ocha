import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../printer_service.dart';
import '../ticket.dart';
import 'menu_editor_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppState app;
  const SettingsScreen({super.key, required this.app});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _vat;
  late final TextEditingController _business;
  late final TextEditingController _email;
  late final TextEditingController _vatNumber;
  late final TextEditingController _footer;
  late final TextEditingController _staff;
  late final TextEditingController _device;
  late String _slipStyle;
  late String _itemSize;
  late int _copies;
  late bool _showPrices;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final s = widget.app.settings;
    _name = TextEditingController(text: s.restaurantName);
    _host = TextEditingController(text: s.printerHost);
    _port = TextEditingController(text: '${s.printerPort}');
    _vat = TextEditingController(
        text: s.vatRate == s.vatRate.roundToDouble()
            ? '${s.vatRate.toInt()}'
            : '${s.vatRate}');
    _business = TextEditingController(text: s.businessLine);
    _email = TextEditingController(text: s.email);
    _vatNumber = TextEditingController(text: s.vatNumber);
    _footer = TextEditingController(text: s.footer);
    _staff = TextEditingController(text: s.staffName);
    _device = TextEditingController(text: s.deviceName);
    _slipStyle = s.slipStyle;
    _itemSize = s.itemSize;
    _copies = s.copies;
    _showPrices = s.showPrices;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _vat.dispose();
    for (final c in [_business, _email, _vatNumber, _footer, _staff, _device]) {
      c.dispose();
    }
    super.dispose();
  }

  AppSettings _current() => AppSettings(
        restaurantName: _name.text.trim(),
        printerHost: _host.text.trim(),
        printerPort: int.tryParse(_port.text.trim()) ?? 9100,
        copies: _copies,
        showPrices: _showPrices,
        vatRate: (double.tryParse(_vat.text.replaceAll('%', '').trim()) ?? 20)
            .clamp(0, 100)
            .toDouble(),
        businessLine: _business.text.trim(),
        email: _email.text.trim(),
        vatNumber: _vatNumber.text.trim(),
        footer: _footer.text.trim(),
        staffName: _staff.text.trim(),
        deviceName: _device.text.trim(),
        slipStyle: _slipStyle,
        itemSize: _itemSize,
      );

  Widget _field(TextEditingController c, String label,
          {String? helper, TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          decoration: InputDecoration(
              labelText: label,
              helperText: helper,
              border: const OutlineInputBorder()),
        ),
      );

  Future<void> _save() async {
    await widget.app.saveSettings(_current());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  Future<void> _testPrint() async {
    final s = _current();
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _testing = true);
    try {
      await PrinterService.send(
          s.printerHost, s.printerPort, buildTestTicket(s));
      await widget.app.saveSettings(s);
      messenger.showSnackBar(const SnackBar(
          content: Text('Test page sent. Settings saved.')));
    } on PrinterException catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: errorColor));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Restaurant', style: text.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Name printed on slips',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _vat,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'VAT rate included in prices',
                    helperText: 'Shown on receipts and used in sales '
                        'reports. Enter 0 if not VAT registered.',
                    suffixText: '%',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 24),
              Text('Receipt', style: text.titleMedium),
              _field(_business, 'Business / address line'),
              _field(_email, 'Email',
                  keyboard: TextInputType.emailAddress),
              _field(_vatNumber, 'VAT number'),
              _field(_footer, 'Message at the bottom'),
              Row(children: [
                Expanded(child: _field(_staff, 'Staff')),
                const SizedBox(width: 12),
                Expanded(child: _field(_device, 'Device / till')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Print for each order'),
                const Spacer(),
                DropdownButton<String>(
                  value: _slipStyle,
                  items: [
                    for (final e in AppSettings.slipStyles.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) =>
                      setState(() => _slipStyle = v ?? 'receipt'),
                ),
              ]),
              Row(children: [
                const Text('Product text size on receipt'),
                const Spacer(),
                DropdownButton<String>(
                  value: _itemSize,
                  items: [
                    for (final e in AppSettings.itemSizes.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _itemSize = v ?? 'tall'),
                ),
              ]),
              const SizedBox(height: 24),
              Text('Printer', style: text.titleMedium),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _host,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                        labelText: 'IP address',
                        hintText: 'e.g. 192.168.1.50',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Port', border: OutlineInputBorder()),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Copies per order'),
                const Spacer(),
                DropdownButton<int>(
                  value: _copies,
                  items: [
                    for (final n in [1, 2, 3])
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (v) => setState(() => _copies = v ?? 1),
                ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show prices on kitchen tickets'),
                value: _showPrices,
                onChanged: (v) => setState(() => _showPrices = v),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _testing ? null : _testPrint,
                icon: _testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print),
                label: const Text('Print test page'),
              ),
              const SizedBox(height: 24),
              Text('Menu', style: text.titleMedium),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.restaurant_menu),
                  title: const Text('Edit menu'),
                  subtitle: Text('${widget.app.menu.length} items'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MenuEditorScreen(app: widget.app)));
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _save, child: const Text('Save settings')),
            ],
          ),
        ),
      ),
    );
  }
}
