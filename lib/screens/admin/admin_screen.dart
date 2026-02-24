import 'package:flutter/material.dart';
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
    _tab = TabController(length: 3, vsync: this);
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
        title: const Text('Admin'),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppTheme.green,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.green,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(text: 'TABLES'),
            Tab(text: 'MENU'),
            Tab(text: 'STAFF'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _TablesTab(),
          _MenuTab(),
          _StaffTab(),
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
                    _TableStat('TOTAL', '${state.allTables.length}',
                        AppTheme.textPrimary),
                    _TableStat(
                        'ACTIVE',
                        '${state.allTables.where((t) => t.status == TableStatus.active).length}',
                        AppTheme.green),
                    _TableStat(
                        'OPEN',
                        '${state.allTables.where((t) => t.status == TableStatus.open).length}',
                        AppTheme.textMuted),
                    _TableStat(
                        'RESERVED',
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
                    '${table.zone} · ${table.type.name} · \$${table.hourlyRate.toStringAsFixed(2)}/hr',
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
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(
                  value: 'maintenance', child: Text('Toggle Maintenance')),
              PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: AppTheme.red))),
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
                  title: const Text('Delete Table?'),
                  content:
                      Text('${table.name} will be removed from the floor.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(_),
                        child: const Text('Cancel')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.red),
                      onPressed: () {
                        context
                            .read<TableRepository>()
                            .deleteTable(user.venueId, table.id);
                        Navigator.pop(_);
                      },
                      child: const Text('DELETE'),
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
            const Text('Add Table',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 24),
            TextField(
                controller: _nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Table Name (e.g. T-01)'),
                style: const TextStyle(color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            TextField(
                controller: _zoneCtrl,
                decoration: const InputDecoration(
                    labelText: 'Zone (e.g. Zone A – Pool Hall)'),
                style: const TextStyle(color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            DropdownButtonFormField<TableType>(
              value: _type,
              dropdownColor: AppTheme.surface2,
              decoration: const InputDecoration(labelText: 'Table Type'),
              items: TableType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                  .toList(),
              onChanged: (t) => setState(() => _type = t!),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _rateCtrl,
                decoration: const InputDecoration(
                    labelText: 'Hourly Rate (\$)',
                    prefixIcon: Icon(Icons.attach_money)),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppTheme.textPrimary)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Text('ADD TABLE'),
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
          const Text('Edit Table',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Table Name'),
              style: const TextStyle(color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          TextField(
              controller: _rateCtrl,
              decoration: const InputDecoration(labelText: 'Hourly Rate'),
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
                    ));
                Navigator.pop(context);
              },
              child: const Text('SAVE CHANGES'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── MENU TAB ────────────────────────────────────────────────────────────────

class _MenuTab extends StatelessWidget {
  const _MenuTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MenuBloc, MenuState>(
      builder: (context, state) {
        final items = state is MenuLoaded ? state.allItems : <MenuItem>[];
        return Scaffold(
          backgroundColor: AppTheme.bg,
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddItemSheet(context),
            backgroundColor: AppTheme.green,
            foregroundColor: AppTheme.bg,
            child: const Icon(Icons.add),
          ),
          body: items.isEmpty
              ? const Center(
                  child: Text('No menu items yet',
                      style: TextStyle(color: AppTheme.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) => _AdminMenuRow(item: items[i]),
                ),
        );
      },
    );
  }

  void _showAddItemSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
          value: context.read<MenuBloc>(), child: const _AddMenuItemSheet()),
    );
  }
}

class _AdminMenuRow extends StatelessWidget {
  final MenuItem item;
  const _AdminMenuRow({required this.item});

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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: AppTheme.surface2,
                borderRadius: BorderRadius.circular(4)),
            child: item.imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(item.imageUrl!, fit: BoxFit.cover))
                : const Icon(Icons.fastfood_outlined,
                    color: AppTheme.textMuted, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                  '${item.category.toUpperCase()} · \$${item.price.toStringAsFixed(2)}',
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
              PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: AppTheme.red))),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddMenuItemSheet extends StatefulWidget {
  const _AddMenuItemSheet();
  @override
  State<_AddMenuItemSheet> createState() => _AddMenuItemSheetState();
}

class _AddMenuItemSheetState extends State<_AddMenuItemSheet> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  String _category = 'Ichimliklar';

  static const _categories = [
    'Non-dog',
    'Ichimliklar',
    'Sigaret',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add Menu Item',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Item Name'),
              style: const TextStyle(color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          TextField(
              controller: _priceCtrl,
              decoration: const InputDecoration(
                  labelText: 'Price', prefixIcon: Icon(Icons.attach_money)),
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _category,
            dropdownColor: AppTheme.surface2,
            decoration: const InputDecoration(labelText: 'Category'),
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (c) => setState(() => _category = c!),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final authState = context.read<AuthBloc>().state;
                final user =
                    authState is AuthAuthenticated ? authState.user : null;
                if (user == null) return;
                context.read<MenuBloc>().add(MenuItemAddRequested(MenuItem(
                      id: '',
                      name: _nameCtrl.text.trim(),
                      price: double.tryParse(_priceCtrl.text) ?? 0,
                      category: _category,
                      venueId: user.venueId,
                    )));
                Navigator.pop(context);
              },
              child: const Text('ADD ITEM'),
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
          const Text('Add Staff Member',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name'),
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
              decoration: const InputDecoration(labelText: 'Initial Password'),
              obscureText: true,
              style: const TextStyle(color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          DropdownButtonFormField<UserRole>(
            value: _role,
            dropdownColor: AppTheme.surface2,
            decoration: const InputDecoration(labelText: 'Role'),
            items: UserRole.values
                .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
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
                  : const Text('CREATE ACCOUNT'),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.red),
        );
      }
    }
    setState(() => _loading = false);
  }
}
