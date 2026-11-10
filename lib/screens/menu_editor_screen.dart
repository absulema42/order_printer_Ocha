import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../menu_import.dart';
import '../models.dart';

class MenuEditorScreen extends StatefulWidget {
  final AppState app;
  const MenuEditorScreen({super.key, required this.app});

  @override
  State<MenuEditorScreen> createState() => _MenuEditorScreenState();
}

class _MenuEditorScreenState extends State<MenuEditorScreen> {
  String _query = '';
  bool _importing = false;

  AppState get app => widget.app;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      duration: Duration(seconds: error ? 8 : 4),
    ));
  }

  Future<void> _edit([MenuItem? item]) async {
    final result = await showDialog<MenuItem>(
      context: context,
      builder: (_) => _ItemDialog(item: item, categories: app.categories),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (item == null) {
        app.menu.add(result);
      } else {
        item
          ..name = result.name
          ..category = result.category
          ..pricePence = result.pricePence
          ..code = result.code
          ..takeawayPence = result.takeawayPence;
      }
    });
    await app.saveMenu();
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<void> _delete(MenuItem item) async {
    if (!await _confirm('Remove ${item.name}?', 'This removes it from the menu.',
        'Remove')) {
      return;
    }
    setState(() => app.menu.remove(item));
    await app.saveMenu();
  }

  Future<void> _resetToBuiltIn() async {
    if (!await _confirm('Load the built-in O\'Cha menu?',
        'Your current items will be replaced.', 'Replace')) {
      return;
    }
    setState(() => app.menu = sampleMenu());
    await app.saveMenu();
  }

  Future<void> _removeAll() async {
    if (!await _confirm('Remove all ${app.menu.length} items?',
        'The menu will be empty until you add or import items.',
        'Remove all')) {
      return;
    }
    setState(() => app.menu = []);
    await app.saveMenu();
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose your menu spreadsheet',
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final f = picked.files.single;
      var bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null) {
        _snack('Could not read that file.', error: true);
        return;
      }

      final MenuImport result;
      try {
        result = readMenuFile(f.name, bytes);
      } on FormatException catch (e) {
        _snack(e.message, error: true);
        return;
      }
      if (result.items.isEmpty) {
        _snack(
            'No products found. The sheet needs a header row with a '
            '"Price" column, and the product names in the next column.',
            error: true);
        return;
      }
      if (!mounted) return;

      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => _ImportPreview(
            fileName: f.name, result: result, currentCount: app.menu.length),
      );
      if (choice == null || !mounted) return;
      final (added, updated) =
          await app.importMenu(result.items, replace: choice == 'replace');
      if (!mounted) return;
      setState(() {});
      _snack(choice == 'replace'
          ? 'Menu replaced with $added items from ${f.name}'
          : 'Imported ${f.name}: $added added, $updated updated');
    } catch (e) {
      _snack('Import failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    bool matches(MenuItem i) =>
        q.isEmpty ||
        i.name.toLowerCase().contains(q) ||
        i.category.toLowerCase().contains(q) ||
        i.code == q;
    final cats = app.categories;
    final hint = Theme.of(context).hintColor;

    return Scaffold(
      appBar: AppBar(
        title: Text('Menu (${app.menu.length} items)'),
        actions: [
          TextButton.icon(
            onPressed: _importing ? null : _import,
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: const Text('Import Excel'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'builtin') _resetToBuiltIn();
              if (v == 'clear') _removeAll();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'builtin', child: Text('Load built-in O\'Cha menu')),
              PopupMenuItem(value: 'clear', child: Text('Remove all items')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search items',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: app.menu.isEmpty
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'No items yet. Tap "Add item", or "Import Excel" to load '
                      'your menu spreadsheet.',
                      textAlign: TextAlign.center),
                ))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    for (final c in cats)
                      if (app.menu.any((i) => i.category == c && matches(i))) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                          child: Text(c,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary)),
                        ),
                        for (final item in app.menu
                            .where((i) => i.category == c && matches(i)))
                          ListTile(
                            leading: item.code.isEmpty
                                ? null
                                : SizedBox(
                                    width: 36,
                                    child: Text(item.code,
                                        style: TextStyle(color: hint))),
                            title: Text(item.name),
                            subtitle: Text(item.takeawayPence == null
                                ? formatPrice(item.pricePence)
                                : '${formatPrice(item.pricePence)} eat in · '
                                    '${formatPrice(item.takeawayPence!)} '
                                    'takeaway'),
                            onTap: () => _edit(item),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(item),
                            ),
                          ),
                      ],
                  ],
                ),
        ),
      ]),
    );
  }
}

class _ImportPreview extends StatelessWidget {
  final String fileName;
  final MenuImport result;
  final int currentCount;
  const _ImportPreview(
      {required this.fileName,
      required this.result,
      required this.currentCount});

  @override
  Widget build(BuildContext context) {
    final counts = result.categoryCounts;
    final takeaway =
        result.items.where((i) => i.takeawayPence != null).length;
    return AlertDialog(
      title: const Text('Import menu'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Found ${result.items.length} products in '
                  '${counts.length} categories in $fileName.'),
              if (takeaway > 0)
                Text('$takeaway have a separate takeaway price.'),
              if (result.skippedRows > 0)
                Text('${result.skippedRows} rows were skipped (no valid price).',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              for (final e in counts.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(child: Text(e.key)),
                    Text('${e.value}'),
                  ]),
                ),
              const SizedBox(height: 12),
              Text(
                'Replace: your current $currentCount items are removed and '
                'replaced with these.\n'
                'Add & update: items with the same category and name get the '
                'new price; new ones are added; nothing is removed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        OutlinedButton(
            onPressed: () => Navigator.pop(context, 'merge'),
            child: const Text('Add & update')),
        FilledButton(
            onPressed: () => Navigator.pop(context, 'replace'),
            child: const Text('Replace menu')),
      ],
    );
  }
}

class _ItemDialog extends StatefulWidget {
  final MenuItem? item;
  final List<String> categories;
  const _ItemDialog({this.item, required this.categories});

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _category;
  late final TextEditingController _price;
  late final TextEditingController _takeaway;
  String? _error;

  String _money(int p) => (p / 100).toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _name = TextEditingController(text: i?.name ?? '');
    _code = TextEditingController(text: i?.code ?? '');
    _category = TextEditingController(
        text: i?.category ??
            (widget.categories.isNotEmpty ? widget.categories.first : 'Mains'));
    _price = TextEditingController(text: i == null ? '' : _money(i.pricePence));
    _takeaway = TextEditingController(
        text: i?.takeawayPence == null ? '' : _money(i!.takeawayPence!));
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _category, _price, _takeaway]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final cat = _category.text.trim();
    final price = parsePrice(_price.text);
    final takeText = _takeaway.text.trim();
    final take = takeText.isEmpty ? null : parsePrice(takeText);
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    if (price == null) {
      setState(() => _error = 'Enter a price like 8.50');
      return;
    }
    if (takeText.isNotEmpty && take == null) {
      setState(() => _error = 'Enter a takeaway price like 1.80, or leave '
          'it empty');
      return;
    }
    Navigator.pop(
      context,
      MenuItem(
        id: widget.item?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        category: cat.isEmpty ? 'Other' : cat,
        pricePence: price,
        code: _code.text.trim(),
        takeawayPence: take == price ? null : take,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Add item' : 'Edit item'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'No.'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            if (widget.categories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in widget.categories)
                  ActionChip(
                    label: Text(c),
                    onPressed: () => setState(() => _category.text = c),
                  ),
              ]),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Price', prefixText: '£'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _takeaway,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Takeaway price',
                      hintText: 'Same',
                      prefixText: '£'),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
