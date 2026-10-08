import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/blocs.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'package:billiardtm/repositories/repositories.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Boshqaruv'),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppTheme.green,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.green,
          indicatorSize: TabBarIndicatorSize.tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'STOLLAR'),
            Tab(text: 'MENYU'),
            Tab(text: 'XODIMLAR'),
            Tab(text: 'JURNAL'),
            Tab(text: 'SOZLAMALAR'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _TablesTab(),
          _MenuTab(),
          _StaffTab(),
          _ActivityTab(),
          _SettingsTab(),
        ],
      ),
    );
  }
}

// ─── TABLES TAB ───────────────────────────────────────────────────────────────

class _TablesTab extends StatelessWidget {
  const _TablesTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FloorBloc, FloorState>(
      builder: (context, state) {
        if (state is! FloorLoaded)
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.green));
        return Scaffold(
          backgroundColor: AppTheme.bg,
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddTableSheet(context),
            backgroundColor: AppTheme.green,
            foregroundColor: AppTheme.bg,
            child: const Icon(Icons.add),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppTheme.surface,
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(4)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _TableStat('JAMI', '${state.allTables.length}',
                        AppTheme.textPrimary),
                    _TableStat(
                        'FAOL',
                        '${state.allTables.where((t) => t.status == TableStatus.active).length}',
                        AppTheme.green),
                    _TableStat(
                        "BO'SH",
                        '${state.allTables.where((t) => t.status == TableStatus.open).length}',
                        AppTheme.textMuted),
                    _TableStat(
                        'BAND',
                        '${state.allTables.where((t) => t.status == TableStatus.reserved).length}',
                        AppTheme.amber),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...state.allTables.map((table) => _AdminTableRow(table: table)),
            ],
          ),
        );
      },
    );
  }

  void _showAddTableSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        side: BorderSide(color: AppTheme.border),
      ),
      builder: (_) => BlocProvider.value(
        value: context.read<FloorBloc>(),
        child: const _AddTableSheet(),
      ),
    );
  }
}

class _TableStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _TableStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 9, letterSpacing: 0.1)),
        ],
      );
}

class _AdminTableRow extends StatelessWidget {
  final TableModel table;
  const _AdminTableRow({required this.table});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: AppTheme.surface2,
                borderRadius: BorderRadius.circular(4)),
            child: const Icon(Icons.table_bar,
                color: AppTheme.textMuted, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(table.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                    '${table.zone} · ${tableTypeLabel(table.type)} · ${formatCurrency(table.hourlyRate)}/soat',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 12)),
              ],
            ),
          ),
          StatusBadge(table.status.name),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            color: AppTheme.surface2,
            onSelected: (v) => _handleAction(context, v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Tahrirlash')),
              const PopupMenuItem(
                  value: 'maintenance', child: Text("Ta'mirga qo'yish / chiqarish")),
              PopupMenuItem(
                  value: 'delete',
                  child: Text("O'chirish", style: TextStyle(color: AppTheme.red))),
            ],
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, String action) {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    if (user == null) return;

    switch (action) {
      case 'edit':
        _showEditSheet(context);
        break;
      case 'maintenance':
        final newStatus = table.status == TableStatus.maintenance
            ? TableStatus.open
            : TableStatus.maintenance;
        context
            .read<TableRepository>()
            .updateTable(user.venueId, table.copyWith(status: newStatus));
        break;
      case 'delete':
        showDialog(
            context: context,
            builder: (_) => AlertDialog(
                  title: const Text("Stol o'chirilsinmi?"),
                  content:
                      Text('${table.name} zaldan olib tashlanadi.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(_),
                        child: const Text('Bekor qilish')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.red),
                      onPressed: () {
                        context
                            .read<TableRepository>()
                            .deleteTable(user.venueId, table);
                        Navigator.pop(_);
                      },
                      child: const Text("O'CHIRISH"),
                    ),
                  ],
                ));
        break;
    }
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      builder: (_) => _EditTableSheet(table: table),
    );
  }
}

class _AddTableSheet extends StatefulWidget {
  const _AddTableSheet();
  @override
  State<_AddTableSheet> createState() => _AddTableSheetState();
}

class _AddTableSheetState extends State<_AddTableSheet> {
  final _nameCtrl = TextEditingController();
  final _zoneCtrl = TextEditingController();
  final _rateCtrl = TextEditingController(text: '10.00');
  TableType _type = TableType.billiard;
  int _capacity = 2;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Stol qo'shish",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 24),
            TextField(
                controller: _nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Stol nomi (masalan, Stol 1)'),
                style: const TextStyle(color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            TextField(
                controller: _zoneCtrl,
                decoration: const InputDecoration(
                    labelText: 'Zona (masalan, Asosiy zal)'),
                style: const TextStyle(color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            DropdownButtonFormField<TableType>(
              value: _type,
              dropdownColor: AppTheme.surface2,
              decoration: const InputDecoration(labelText: 'Stol turi'),
              items: TableType.values
                  .map((t) => DropdownMenuItem(
                      value: t, child: Text(tableTypeLabel(t))))
                  .toList(),
              onChanged: (t) => setState(() => _type = t!),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _rateCtrl,
                decoration: const InputDecoration(
                    labelText: "Soatlik narx (so'm)",
                    prefixIcon: Icon(Icons.payments_outlined)),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppTheme.textPrimary)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Text("STOL QO'SHISH"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    if (user == null) return;
    context.read<TableRepository>().addTable(
        user.venueId,
        TableModel(
          id: '',
          name: _nameCtrl.text.trim(),
          zone: _zoneCtrl.text.trim(),
          type: _type,
          status: TableStatus.open,
          hourlyRate: double.tryParse(_rateCtrl.text) ?? 10,
          capacity: _capacity,
        ));
    Navigator.pop(context);
  }
}

class _EditTableSheet extends StatefulWidget {
  final TableModel table;
  const _EditTableSheet({required this.table});
  @override
  State<_EditTableSheet> createState() => _EditTableSheetState();
}

class _EditTableSheetState extends State<_EditTableSheet> {
  late final _nameCtrl = TextEditingController(text: widget.table.name);
  late final _rateCtrl =
      TextEditingController(text: widget.table.hourlyRate.toString());
  late TableType _type = widget.table.type;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Stolni tahrirlash',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Stol nomi'),
              style: const TextStyle(color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          TextField(
              controller: _rateCtrl,
              decoration: const InputDecoration(labelText: "Soatlik narx (so'm)"),
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final authState = context.read<AuthBloc>().state;
                final user =
                    authState is AuthAuthenticated ? authState.user : null;
                if (user == null) return;
                context.read<TableRepository>().updateTable(
                    user.venueId,
                    widget.table.copyWith(
                      name: _nameCtrl.text.trim(),
                      hourlyRate: double.tryParse(_rateCtrl.text) ??
                          widget.table.hourlyRate,
                      type: _type,
                    ),
                    previous: widget.table);
                Navigator.pop(context);
              },
              child: const Text('SAQLASH'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── MENU TAB ────────────────────────────────────────────────────────────────

class _MenuTab extends StatefulWidget {
  const _MenuTab();

  @override
  State<_MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<_MenuTab> {
  Stream<Venue>? _venue;
  String? _venueId;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _venueId = authState.user.venueId;
      _venue = context.read<VenueRepository>().watchVenue(_venueId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Venue>(
      stream: _venue,
      builder: (context, venueSnap) {
        final categories =
            venueSnap.data?.menuCategories ?? Venue.defaultMenuCategories;
        return BlocBuilder<MenuBloc, MenuState>(
          builder: (context, state) {
            final items = state is MenuLoaded ? state.allItems : <MenuItem>[];
            return Scaffold(
              backgroundColor: AppTheme.bg,
              floatingActionButton: FloatingActionButton(
                onPressed: () => _showAddItemSheet(context, categories),
                backgroundColor: AppTheme.green,
                foregroundColor: AppTheme.bg,
                child: const Icon(Icons.add),
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _CategoriesBar(
                    categories: categories,
                    onEdit: () => _showCategoriesDialog(
                        context, categories, items),
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(
                          child: Text("Menyuda hali mahsulot yo'q",
                              style: TextStyle(color: AppTheme.textMuted))),
                    ),
                  ...items.map((item) =>
                      _AdminMenuRow(item: item, categories: categories)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddItemSheet(BuildContext context, List<String> categories) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
          value: context.read<MenuBloc>(),
          child: _AddMenuItemSheet(categories: categories)),
    );
  }

  void _showCategoriesDialog(
      BuildContext context, List<String> categories, List<MenuItem> items) {
    final venueId = _venueId;
    if (venueId == null) return;
    showDialog(
      context: context,
      builder: (_) => _CategoriesDialog(
        initial: categories,
        inUse: items.map((i) => i.category).toSet(),
        onSave: (list) => context
            .read<VenueRepository>()
            .setMenuCategories(venueId, list),
      ),
    );
  }
}

class _CategoriesBar extends StatelessWidget {
  final List<String> categories;
  final VoidCallback onEdit;
  const _CategoriesBar({required this.categories, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: categories.map((c) => StatusBadge(c)).toList(),
          ),
        ),
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Kategoriyalar'),
        ),
      ],
    );
  }
}

class _CategoriesDialog extends StatefulWidget {
  final List<String> initial;
  final Set<String> inUse; // categories that menu items still point at
  final Future<void> Function(List<String>) onSave;
  const _CategoriesDialog(
      {required this.initial, required this.inUse, required this.onSave});

  @override
  State<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends State<_CategoriesDialog> {
  late final List<String> _list = [...widget.initial];
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    if (_list.any((c) => c.toLowerCase() == name.toLowerCase())) {
      setState(() => _error = "Ro'yxatda bor");
      return;
    }
    setState(() {
      _list.add(name);
      _ctrl.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    try {
      await widget.onSave(_list);
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Menyu kategoriyalari'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._list.map((c) {
              final used = widget.inUse.contains(c);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(c),
                subtitle: used
                    ? const Text('Mahsulotlarda ishlatilmoqda',
                        style:
                            TextStyle(color: AppTheme.textMuted, fontSize: 11))
                    : null,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  // Removing a category that items still use would orphan
                  // them in reports.
                  onPressed: used || _list.length == 1
                      ? null
                      : () => setState(() => _list.remove(c)),
                ),
              );
            }),
            TextField(
              controller: _ctrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Yangi kategoriya',
                errorText: _error,
                suffixIcon:
                    IconButton(icon: const Icon(Icons.add), onPressed: _add),
              ),
              onSubmitted: (_) => _add(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish')),
        ElevatedButton(onPressed: _save, child: const Text('SAQLASH')),
      ],
    );
  }
}

// Asks where the photo comes from and returns it shrunk for upload, or
// null if nothing was picked.
Future<MenuImage?> _pickMenuImage(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppTheme.surface,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Galereyadan tanlash'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Suratga olish'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  // Menu photos are shown small, so a modest size keeps uploads quick and
  // storage use low.
  final file = await ImagePicker()
      .pickImage(source: source, maxWidth: 800, imageQuality: 75);
  if (file == null) return null;
  final name = file.name.toLowerCase();
  final contentType = file.mimeType ??
      (name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg');
  return (bytes: await file.readAsBytes(), contentType: contentType);
}

class _AdminMenuRow extends StatefulWidget {
  final MenuItem item;
  final List<String> categories;
  const _AdminMenuRow({required this.item, required this.categories});

  @override
  State<_AdminMenuRow> createState() => _AdminMenuRowState();
}

class _AdminMenuRowState extends State<_AdminMenuRow> {
  bool _uploading = false;

  MenuItem get item => widget.item;

  Future<void> _changeImage() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<MenuRepository>();
    final image = await _pickMenuImage(context);
    if (image == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await repo.setItemImage(authState.user.venueId, item, image);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Rasm yuklanmadi: $e'),
          backgroundColor: AppTheme.red));
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(
            color: item.isAvailable
                ? AppTheme.border
                : AppTheme.red.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // Tap the picture to add or replace the photo.
          GestureDetector(
            onTap: _uploading ? null : _changeImage,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(4)),
              child: _uploading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.green))
                  : item.imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(item.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppTheme.textMuted,
                                  size: 20)))
                      : const Icon(Icons.add_a_photo_outlined,
                          color: AppTheme.textMuted, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                  '${item.category.toUpperCase()} · ${formatCurrency(item.price)}',
                  style:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          )),
          Switch(
            value: item.isAvailable,
            activeColor: AppTheme.green,
            onChanged: (v) {
              final authState = context.read<AuthBloc>().state;
              final user =
                  authState is AuthAuthenticated ? authState.user : null;
              if (user != null) {
                context
                    .read<MenuRepository>()
                    .toggleAvailability(user.venueId, item.id, v);
              }
            },
          ),
          PopupMenuButton<String>(
            color: AppTheme.surface2,
            onSelected: (v) {
              if (v == 'edit') {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: AppTheme.surface,
                  isScrollControlled: true,
                  builder: (_) => _AddMenuItemSheet(
                      categories: widget.categories, item: item),
                );
              }
              if (v == 'image') _changeImage();
              if (v == 'removeImage') {
                final authState = context.read<AuthBloc>().state;
                if (authState is AuthAuthenticated) {
                  context
                      .read<MenuRepository>()
                      .removeItemImage(authState.user.venueId, item);
                }
              }
              if (v == 'delete') {
                final authState = context.read<AuthBloc>().state;
                final user =
                    authState is AuthAuthenticated ? authState.user : null;
                if (user != null)
                  context
                      .read<MenuBloc>()
                      .add(MenuItemDeleteRequested(item.id));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Tahrirlash')),
              PopupMenuItem(
                  value: 'image',
                  child: Text(item.imageUrl == null
                      ? "Rasm qo'shish"
                      : 'Rasmni almashtirish')),
              if (item.imageUrl != null)
                const PopupMenuItem(
                    value: 'removeImage', child: Text("Rasmni o'chirish")),
              PopupMenuItem(
                  value: 'delete',
                  child: Text("O'chirish", style: TextStyle(color: AppTheme.red))),
            ],
          ),
        ],
      ),
    );
  }
}

// Adds a menu item, or edits [item] when one is given.
class _AddMenuItemSheet extends StatefulWidget {
  final List<String> categories;
  final MenuItem? item;
  const _AddMenuItemSheet({required this.categories, this.item});
  @override
  State<_AddMenuItemSheet> createState() => _AddMenuItemSheetState();
}

class _AddMenuItemSheetState extends State<_AddMenuItemSheet> {
  late final _nameCtrl = TextEditingController(text: widget.item?.name);
  late final _priceCtrl = TextEditingController(
      text: widget.item == null
          ? null
          : widget.item!.price
              .toStringAsFixed(widget.item!.price % 1 == 0 ? 0 : 2));
  late String _category = widget.item?.category ?? widget.categories.first;
  MenuImage? _image;

  // An item can still carry a category that was since removed from the
  // list; keep it selectable so the dropdown has a matching value.
  List<String> get _categories => widget.categories.contains(_category)
      ? widget.categories
      : [...widget.categories, _category];
  bool _saving = false;

  Future<void> _pick() async {
    final image = await _pickMenuImage(context);
    if (image != null && mounted) setState(() => _image = image);
  }

  Future<void> _save() async {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    final name = _nameCtrl.text.trim();
    if (user == null || name.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      // Saved directly rather than through the bloc so the sheet can wait
      // for the photo upload and report a failure.
      final repo = context.read<MenuRepository>();
      final price = double.tryParse(
              _priceCtrl.text.replaceAll(RegExp(r'[\s,]'), '')) ??
          0;
      final existing = widget.item;
      if (existing == null) {
        await repo.addItem(
          user.venueId,
          MenuItem(
            id: '',
            name: name,
            price: price,
            category: _category,
            venueId: user.venueId,
          ),
          image: _image,
        );
      } else {
        final updated =
            existing.copyWith(name: name, price: price, category: _category);
        await repo.updateItem(user.venueId, updated, previous: existing);
        if (_image != null) {
          await repo.setItemImage(user.venueId, updated, _image!);
        }
      }
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
          content: Text('Saqlanmadi: $e'), backgroundColor: AppTheme.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.item == null ? "Mahsulot qo'shish" : 'Mahsulotni tahrirlash',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          Row(
            children: [
              GestureDetector(
                onTap: _pick,
                child: Container(
                  width: 72,
                  height: 72,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppTheme.surface2,
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _image != null
                      ? Image.memory(_image!.bytes, fit: BoxFit.cover)
                      : widget.item?.imageUrl != null
                          ? Image.network(widget.item!.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppTheme.textMuted))
                          : const Icon(Icons.add_a_photo_outlined,
                              color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _pick,
                child: Text(_image == null && widget.item?.imageUrl == null
                    ? "Rasm qo'shish (ixtiyoriy)"
                    : 'Rasmni almashtirish'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Mahsulot nomi'),
              style: const TextStyle(color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          TextField(
              controller: _priceCtrl,
              decoration: const InputDecoration(
                  labelText: "Narx (so'm)", prefixIcon: Icon(Icons.payments_outlined)),
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _category,
            dropdownColor: AppTheme.surface2,
            decoration: const InputDecoration(labelText: 'Kategoriya'),
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (c) => setState(() => _category = c!),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.bg))
                  : Text(widget.item == null ? "QO'SHISH" : 'SAQLASH'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── STAFF TAB ───────────────────────────────────────────────────────────────

class _StaffTab extends StatelessWidget {
  const _StaffTab();

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    if (user == null) return const SizedBox();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddStaffSheet(context),
        backgroundColor: AppTheme.green,
        foregroundColor: AppTheme.bg,
        child: const Icon(Icons.person_add_outlined),
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: context.read<VenueRepository>().watchUsers(user.venueId),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.green));
          }
          final users = snap.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...users.map((u) => _StaffRow(user: u)),
            ],
          );
        },
      ),
    );
  }

  void _showAddStaffSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: context.read<AuthBloc>(),
        child: const _AddStaffSheet(),
      ),
    );
  }
}

class _StaffRow extends StatelessWidget {
  final AppUser user;
  const _StaffRow({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.green.withOpacity(0.15),
            child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: AppTheme.green, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(user.email,
                  style:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          )),
          StatusBadge(user.role.name),
        ],
      ),
    );
  }
}

class _AddStaffSheet extends StatefulWidget {
  const _AddStaffSheet();
  @override
  State<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends State<_AddStaffSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  UserRole _role = UserRole.staff;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Xodim qo'shish",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: "To'liq ism"),
              style: const TextStyle(color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          TextField(
              controller: _passCtrl,
              decoration: const InputDecoration(labelText: "Boshlang'ich parol"),
              obscureText: true,
              style: const TextStyle(color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          DropdownButtonFormField<UserRole>(
            value: _role,
            dropdownColor: AppTheme.surface2,
            decoration: const InputDecoration(labelText: 'Lavozim'),
            items: UserRole.values
                .map((r) => DropdownMenuItem(value: r, child: Text(roleLabel(r))))
                .toList(),
            onChanged: (r) => setState(() => _role = r!),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.bg))
                  : const Text('HISOB YARATISH'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final authState = context.read<AuthBloc>().state;
      final user = authState is AuthAuthenticated ? authState.user : null;
      if (user == null) return;

      await context.read<AuthRepository>().createUser(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
            name: _nameCtrl.text.trim(),
            role: _role,
            venueId: user.venueId,
          );
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      // Thrown when sign-up is switched off in the Firebase console.
      final signUpOff = e.code == 'admin-restricted-operation' ||
          e.code == 'operation-not-allowed';
      _showError(signUpOff
          ? "Bu loyihada yangi hisob ochish o'chirilgan. "
              'Loginni Firebase konsolida yarating.'
          : e.message ?? e.code);
    } catch (e) {
      _showError(e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.red),
    );
  }
}

// ─── ACTIVITY TAB ────────────────────────────────────────────────────────────

class _ActivityTab extends StatefulWidget {
  const _ActivityTab();

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  Stream<List<ActivityEntry>>? _entries;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _entries = context
          .read<ActivityRepository>()
          .watchRecent(authState.user.venueId);
    }
  }

  static (String, IconData, Color) _look(String type) => switch (type) {
        ActivityType.sessionVoided => (
            'Seans bekor qilindi',
            Icons.delete_outline,
            AppTheme.red
          ),
        ActivityType.discountApplied => (
            'Chegirma berildi',
            Icons.discount_outlined,
            AppTheme.amber
          ),
        ActivityType.sessionTransferred => (
            'Stol almashtirildi',
            Icons.swap_horiz,
            AppTheme.blue
          ),
        ActivityType.tableAdded => (
            "Stol qo'shildi",
            Icons.add_box_outlined,
            AppTheme.textSecondary
          ),
        ActivityType.tableRateChanged => (
            "Stol narxi o'zgardi",
            Icons.price_change_outlined,
            AppTheme.amber
          ),
        ActivityType.tableDeleted => (
            "Stol o'chirildi",
            Icons.delete_outline,
            AppTheme.red
          ),
        ActivityType.menuItemAdded => (
            "Mahsulot qo'shildi",
            Icons.add_box_outlined,
            AppTheme.textSecondary
          ),
        ActivityType.menuItemDeleted => (
            "Mahsulot o'chirildi",
            Icons.delete_outline,
            AppTheme.red
          ),
        ActivityType.debtAdded => (
            "Qarz qo'lda qo'shildi",
            Icons.receipt_long_outlined,
            AppTheme.amber
          ),
        ActivityType.debtWrittenOff => (
            'Qarz kechildi',
            Icons.money_off,
            AppTheme.red
          ),
        ActivityType.staffCreated => (
            "Xodim qo'shildi",
            Icons.person_add_outlined,
            AppTheme.textSecondary
          ),
        ActivityType.dayEndChanged => (
            "Kun tugash vaqti o'zgardi",
            Icons.schedule,
            AppTheme.textSecondary
          ),
        ActivityType.menuItemPriceChanged => (
            "Mahsulot narxi o'zgardi",
            Icons.price_change_outlined,
            AppTheme.amber
          ),
        ActivityType.expenseDeleted => (
            "Xarajat o'chirildi",
            Icons.delete_outline,
            AppTheme.red
          ),
        _ => (type, Icons.info_outline, AppTheme.textSecondary),
      };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActivityEntry>>(
      stream: _entries,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child: Text('${snap.error}',
                  style: const TextStyle(color: AppTheme.red)));
        }
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.green));
        }
        final entries = snap.data!;
        if (entries.isEmpty) {
          return const Center(
              child: Text("Hozircha yozuvlar yo'q",
                  style: TextStyle(color: AppTheme.textMuted)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final e = entries[i];
            final (label, icon, color) = _look(e.type);
            final what =
                [e.subject, if ((e.detail ?? '').isNotEmpty) e.detail!].join(' · ');
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(what,
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12)),
                        Text('${formatDate(e.at)} · ${e.byName}',
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── SETTINGS TAB ────────────────────────────────────────────────────────────

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  Stream<Venue>? _venue;
  String? _venueId;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _venueId = authState.user.venueId;
      _venue = context.read<VenueRepository>().watchVenue(_venueId!);
    }
  }

  Future<void> _setHour(int hour) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<VenueRepository>().setDayEndHour(_venueId!, hour);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Venue>(
      stream: _venue,
      builder: (context, snap) {
        final hour = snap.data?.dayEndHour ?? Venue.defaultDayEndHour;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Ish kuni tugash vaqti',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            const Text(
                'Kunlik hisobot shu soatda yangi kunga o\'tadi. Klub yarim '
                'tundan keyin ishlasa, yopilishdan keyingi soatni tanlang.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              // Rebuild when the stored value arrives or changes elsewhere.
              key: ValueKey(hour),
              initialValue: hour,
              dropdownColor: AppTheme.surface2,
              decoration: const InputDecoration(labelText: 'Soat'),
              items: List.generate(
                  13,
                  (h) => DropdownMenuItem(
                      value: h,
                      child: Text('${h.toString().padLeft(2, '0')}:00'))),
              onChanged: (h) {
                if (h != null && h != hour) _setHour(h);
              },
            ),
          ],
        );
      },
    );
  }
}
