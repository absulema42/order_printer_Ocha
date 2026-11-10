import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../models.dart';
import '../printer_service.dart';
import '../reports.dart';
import '../sales.dart';
import '../ticket.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class SalesScreen extends StatefulWidget {
  final AppState app;
  const SalesScreen({super.key, required this.app});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  String _periodKey = 'today';
  ReportPeriod _period = ReportPeriod.preset('today', DateTime.now());
  SalesReport? _report;
  bool _loading = true;
  bool _busy = false;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_loading) setState(() => _loading = true);
    List<SaleRecord> records;
    try {
      records = await app.sales.load(_period.from, _period.to);
    } catch (e) {
      records = [];
      _showError('Could not read sales history: $e');
    }
    if (!mounted) return;
    setState(() {
      _report = SalesReport(records, vatRate: app.settings.vatRate);
      _loading = false;
    });
  }

  void _recompute() {
    final r = _report;
    if (r == null || !mounted) return;
    setState(
        () => _report = SalesReport(r.orders, vatRate: app.settings.vatRate));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _choosePeriod(String key) async {
    if (key == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      var end = _period.lastDay;
      if (end.isAfter(today)) end = today;
      var start = _period.from;
      if (start.isAfter(end)) start = end;
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: today,
        initialDateRange: DateTimeRange(start: start, end: end),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _periodKey = 'custom';
        _period = ReportPeriod.range(picked.start, picked.end);
      });
    } else {
      setState(() {
        _periodKey = key;
        _period = ReportPeriod.preset(key, DateTime.now());
      });
    }
    await _load();
  }

  Future<void> _sendToPrinter(List<int> bytes, String done) async {
    final s = app.settings;
    if (s.printerHost.trim().isEmpty) {
      _showError('Set the printer IP address in Settings first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await PrinterService.send(s.printerHost, s.printerPort, bytes);
      _showInfo(done);
    } on PrinterException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printReport() async {
    final r = _report;
    if (r == null) return;
    await _sendToPrinter(buildSalesReportTicket(r, _period, app.settings),
        'Sales report sent to printer');
  }

  String _fileDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _export() async {
    final r = _report;
    if (r == null) return;
    setState(() => _busy = true);
    try {
      final mobile = Platform.isAndroid || Platform.isIOS;
      final stamp = _period.isSingleDay
          ? _fileDate(_period.from)
          : '${_fileDate(_period.from)}_to_${_fileDate(_period.lastDay)}';
      final Directory dir;
      if (mobile) {
        dir = await getTemporaryDirectory();
      } else {
        final docs = await getApplicationDocumentsDirectory();
        dir = Directory(
            '${docs.path}${Platform.pathSeparator}OCha Thai Sales');
      }
      await dir.create(recursive: true);
      final sep = Platform.pathSeparator;
      final summary = File('${dir.path}${sep}summary_$stamp.csv');
      final orders = File('${dir.path}${sep}orders_$stamp.csv');
      final items = File('${dir.path}${sep}items_$stamp.csv');
      await summary
          .writeAsString(summaryCsv(r, _period, app.settings.restaurantName));
      await orders.writeAsString(ordersCsv(r));
      await items.writeAsString(itemsCsv(r));

      if (mobile) {
        await SharePlus.instance.share(ShareParams(
          files: [
            for (final f in [summary, orders, items])
              XFile(f.path, mimeType: 'text/csv'),
          ],
          subject: '${app.settings.restaurantName} sales ${_period.dates}',
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 10),
          content: Text('Saved 3 spreadsheets to ${dir.path}'),
          action: SnackBarAction(
            label: 'Open folder',
            onPressed: () => Process.run(
                Platform.isWindows ? 'explorer' : 'xdg-open', [dir.path]),
          ),
        ));
      }
    } catch (e) {
      _showError('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveChange(SaleRecord rec) async {
    try {
      await app.sales.update(rec);
    } catch (e) {
      _showError('Could not save the change: $e');
    }
    _recompute();
  }

  Future<void> _openOrder(SaleRecord rec) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        var reprinting = false;
        return StatefulBuilder(builder: (ctx, setSheet) {
        final text = Theme.of(ctx).textTheme;
        final hint = Theme.of(ctx).hintColor;

        Future<void> toggleVoid() async {
          if (!rec.voided) {
            final ok = await showDialog<bool>(
              context: ctx,
              builder: (d) => AlertDialog(
                title: Text('Void order #${rec.number}?'),
                content: const Text(
                    'It will be kept in the history but left out of all '
                    'sales totals. You can restore it later.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Void order')),
                ],
              ),
            );
            if (ok != true) return;
          }
          rec.voided = !rec.voided;
          setSheet(() {});
          await _saveChange(rec);
        }

        return FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${rec.number}',
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          decoration:
                              rec.voided ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      Text(
                        [
                          rec.type,
                          if (rec.reference.isNotEmpty) rec.reference,
                          '${formatTime(rec.time)} ${formatDate(rec.time)}',
                        ].join(' · '),
                        style: text.bodyMedium?.copyWith(color: hint),
                      ),
                    ],
                  ),
                ),
                if (rec.voided)
                  Chip(
                    label: const Text('VOID'),
                    backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
                  ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(children: [
                for (final l in rec.lines)
                  ListTile(
                    dense: true,
                    title: Text('${l.qty} × ${l.name}'),
                    subtitle: l.note.isEmpty ? null : Text('>> ${l.note}'),
                    trailing: Text(formatPrice(l.totalPence)),
                  ),
              ]),
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
                    Text(formatPrice(rec.totalPence),
                        style: text.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Paid by', style: text.labelLarge),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: [
                        for (final m in paymentMethods)
                          ButtonSegment(value: m, label: Text(m)),
                      ],
                      selected: {rec.payment},
                      showSelectedIcon: false,
                      onSelectionChanged: rec.voided
                          ? null
                          : (s) {
                              rec.payment = s.first;
                              setSheet(() {});
                              _saveChange(rec);
                            },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: reprinting
                            ? null
                            : () async {
                                setSheet(() => reprinting = true);
                                await _sendToPrinter(
                                    buildOrderSlips(rec.toOrder(),
                                        app.settings,
                                        reprint: true),
                                    'Order #${rec.number} reprinted');
                                if (ctx.mounted) {
                                  setSheet(() => reprinting = false);
                                }
                              },
                        icon: const Icon(Icons.print),
                        label: const Text('Reprint'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: toggleVoid,
                        icon: Icon(
                            rec.voided ? Icons.restore : Icons.block),
                        label: Text(rec.voided ? 'Restore' : 'Void'),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ]),
        );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sales & reports'),
          actions: [
            IconButton(
              tooltip: 'Print report',
              icon: const Icon(Icons.print),
              onPressed: r == null || _busy ? null : _printReport,
            ),
            IconButton(
              tooltip: 'Export to spreadsheet',
              icon: const Icon(Icons.download),
              onPressed: r == null || _busy ? null : _export,
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Summary'),
            Tab(text: 'Orders'),
          ]),
        ),
        body: Column(children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final e in ReportPeriod.presets.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _periodKey == e.key,
                      onSelected: (_) => _choosePeriod(e.key),
                    ),
                  ),
                ChoiceChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: const Text('Choose dates'),
                  selected: _periodKey == 'custom',
                  onSelected: (_) => _choosePeriod('custom'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_period.dates,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).hintColor)),
            ),
          ),
          Expanded(
            child: _loading || r == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    _summary(context, r),
                    _orders(context, r),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No orders in this period yet.\n'
              'Orders are saved here each time one is printed.',
              textAlign: TextAlign.center),
        ),
      );

  Widget _summary(BuildContext context, SalesReport r) {
    if (r.orders.isEmpty) return _empty();
    final text = Theme.of(context).textTheme;
    final timeTitle = _period.isSingleDay ? 'Sales by hour' : 'Sales by day';
    final timeRows = _period.isSingleDay
        ? ((r.byHour.keys.toList()..sort())
            .map((h) => MapEntry('${h.toString().padLeft(2, '0')}:00',
                r.byHour[h]!))
            .toList())
        : ((r.byDay.keys.toList()..sort())
            .map((d) => MapEntry(
                '${_weekdays[d.weekday - 1]} ${formatDate(d).substring(0, 5)}',
                r.byDay[d]!))
            .toList());

    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 700 ? 4 : 2;
      final contentWidth = c.maxWidth > 900 ? 900.0 : c.maxWidth;
      final kpiWidth = (contentWidth - 32 - 12 * (cols - 1)) / cols;
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: contentWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                _Kpi('Total sales', formatPrice(r.grossPence), kpiWidth),
                _Kpi('Orders', '${r.orderCount}', kpiWidth),
                _Kpi('Average order', formatPrice(r.averagePence), kpiWidth),
                _Kpi('Items sold', '${r.itemCount}', kpiWidth),
              ]),
              if (r.vatRate > 0)
                _Section('VAT', [
                  _ValueRow('Net sales', formatPrice(r.netPence)),
                  _ValueRow(r.vatLabel, formatPrice(r.vatPence)),
                  _ValueRow('Total incl. VAT', formatPrice(r.grossPence),
                      bold: true),
                ]),
              _Section('Payments', _bars(SalesReport.sorted(r.byPayment), showCount: true)),
              _Section('Order types', _bars(SalesReport.sorted(r.byType), showCount: true)),
              _Section(timeTitle, _bars(timeRows, showCount: true)),
              _Section('Categories', _bars(SalesReport.sorted(r.byCategory),
                  showCount: true, countLabel: 'items')),
              _Section('Items sold', [
                for (final i in r.items)
                  _ValueRow('${i.qty} × ${i.name}', formatPrice(i.pence)),
              ]),
              if (r.voidCount > 0 || r.unpaid.count > 0)
                _Section('Check', [
                  if (r.unpaid.count > 0)
                    _ValueRow('Unpaid orders (${r.unpaid.count})',
                        formatPrice(r.unpaid.pence)),
                  if (r.voidCount > 0)
                    _ValueRow('Voided orders (${r.voidCount}, not in totals)',
                        formatPrice(r.voidPence)),
                ]),
              const SizedBox(height: 8),
              Text(
                'VAT is worked out from the rate in Settings, assuming menu '
                'prices include VAT. Check with your accountant before '
                'filing.',
                style: text.bodySmall
                    ?.copyWith(color: Theme.of(context).hintColor),
              ),
            ],
          ),
        ),
      );
    });
  }

  List<Widget> _bars(List<MapEntry<String, Tally>> rows,
      {bool showCount = false, String countLabel = 'orders'}) {
    final max = rows.fold<int>(0, (m, e) => e.value.pence > m ? e.value.pence : m);
    return [
      for (final e in rows)
        _BarRow(
          label: showCount
              ? '${e.key}  (${e.value.count} $countLabel)'
              : e.key,
          value: formatPrice(e.value.pence),
          fraction: max == 0 ? 0 : e.value.pence / max,
        ),
    ];
  }

  Widget _orders(BuildContext context, SalesReport r) {
    if (r.orders.isEmpty) return _empty();
    final list = r.orders.reversed.toList();
    final hint = Theme.of(context).hintColor;
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final o = list[i];
        final strike = o.voided
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null;
        return ListTile(
          onTap: () => _openOrder(o),
          leading: CircleAvatar(child: Text('${o.number}')),
          title: Text(
            [o.type, if (o.reference.isNotEmpty) o.reference].join(' · '),
            style: strike,
          ),
          subtitle: Text(
            '${_period.isSingleDay ? '' : '${formatDate(o.time)} '}'
            '${formatTime(o.time)} · ${o.itemCount} items · '
            '${o.voided ? 'VOID' : o.payment}',
            style: TextStyle(
                color: o.voided || o.payment == 'Unpaid'
                    ? Theme.of(context).colorScheme.error
                    : hint),
          ),
          trailing: Text(formatPrice(o.totalPence),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.merge(strike)),
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final double width;
  const _Kpi(this.label, this.value, this.width);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: text.labelLarge
                      ?.copyWith(color: scheme.onPrimaryContainer)),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _ValueRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(value, style: style),
      ]),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final String value;
  final double fraction;
  const _BarRow(
      {required this.label, required this.value, required this.fraction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: fraction, minHeight: 8),
          ),
        ],
      ),
    );
  }
}
