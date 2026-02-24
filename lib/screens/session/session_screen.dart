import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../blocs/blocs.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

class SessionScreen extends StatelessWidget {
  final String tableId;
  final String sessionId;

  const SessionScreen({super.key, required this.tableId, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SessionBloc, SessionState>(
      listener: (context, state) {
        if (state is SessionCompleted) {
          _showReceiptSheet(context, state.session);
        }
        if (state is SessionInitial) {
          // Voided — go back to floor
          if (context.canPop()) context.pop();
        }
      },
      builder: (context, state) {
        if (state is SessionLoading) {
          return const Scaffold(
            backgroundColor: AppTheme.bg,
            body: Center(child: CircularProgressIndicator(color: AppTheme.green)),
          );
        }
        if (state is SessionActive) {
          return _ActiveSessionView(state: state);
        }
        if (state is SessionError) {
          return Scaffold(
            backgroundColor: AppTheme.bg,
            body: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: AppTheme.red, size: 40),
                const SizedBox(height: 12),
                Text(state.message, style: const TextStyle(color: AppTheme.red)),
                const SizedBox(height: 16),
                TextButton(onPressed: () => context.pop(), child: const Text('Go back')),
              ],
            )),
          );
        }
        // SessionInitial = loading spinner while bloc fires the first event
        return const Scaffold(
          backgroundColor: AppTheme.bg,
          body: Center(child: CircularProgressIndicator(color: AppTheme.green)),
        );
      },
    );
  }

  void _showReceiptSheet(BuildContext ctx, SessionModel session) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        side: BorderSide(color: AppTheme.border),
      ),
      builder: (_) => _ReceiptSheet(session: session, onDone: () {
        Navigator.pop(_);
        ctx.pop();
      }),
    );
  }
}

class _ActiveSessionView extends StatelessWidget {
  final SessionActive state;
  const _ActiveSessionView({required this.state});

  String _formatTime(int secs) {
    final h = (secs ~/ 3600).toString().padLeft(2, '0');
    final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final session = state.session;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.tableName),
            Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(color: AppTheme.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                const Text('ACTIVE SESSION', style: TextStyle(color: AppTheme.green, fontSize: 10, letterSpacing: 0.1)),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            color: AppTheme.surface2,
            onSelected: (val) => _handleMenu(context, val),
            itemBuilder: (_) => [
              _menuItem('notes', Icons.note_outlined, 'Add Note'),
              _menuItem('discount', Icons.discount_outlined, 'Apply Discount'),
              _menuItem('void', Icons.delete_outline, 'Void Session', color: AppTheme.red),
            ],
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Timer section
          SliverToBoxAdapter(
            child: Container(
              color: AppTheme.surface,
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  const Text('TIME ELAPSED', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.15)),
                  const SizedBox(height: 20),
                  TimerRing(
                    elapsedSeconds: state.elapsedSeconds,
                    isPaused: state.isPaused,
                    timeLabel: _formatTime(state.elapsedSeconds),
                    subLabel: '\$${state.currentTimeCharge.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 24),
                  // Quick actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ActionButton(
                        icon: state.isPaused ? Icons.play_arrow : Icons.pause,
                        label: state.isPaused ? 'RESUME' : 'PAUSE',
                        onTap: () {
                          if (state.isPaused) {
                            context.read<SessionBloc>().add(SessionResumeRequested());
                          } else {
                            context.read<SessionBloc>().add(SessionPauseRequested());
                          }
                        },
                      ),
                      _ActionButton(
                        icon: Icons.swap_horiz,
                        label: 'TRANSFER',
                        onTap: () => _showTransferSheet(context),
                      ),
                      _ActionButton(
                        icon: Icons.note_add_outlined,
                        label: 'NOTE',
                        onTap: () => _handleMenu(context, 'notes'),
                      ),
                      _ActionButton(
                        icon: Icons.add_shopping_cart_outlined,
                        label: 'ADD ITEM',
                        color: AppTheme.green,
                        onTap: () => _showAddItemsSheet(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Order items
          if (session.orderItems.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: SectionHeader('Tab Items (${session.orderItems.length})'),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = session.orderItems[i];
                  return _OrderItemRow(item: item);
                },
                childCount: session.orderItems.length,
              ),
            ),
          ],

          // Notes
          if (session.notes != null && session.notes!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.note, color: AppTheme.textMuted, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(session.notes!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                    ],
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 200)),
        ],
      ),
      bottomSheet: _BottomBillingBar(state: state),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {Color? color}) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color ?? AppTheme.textPrimary, fontSize: 14)),
        ],
      ),
    );
  }

  void _handleMenu(BuildContext context, String value) {
    switch (value) {
      case 'notes':
        _showNotesDialog(context);
        break;
      case 'discount':
        _showDiscountSheet(context);
        break;
      case 'void':
        _showVoidConfirm(context);
        break;
    }
  }

  void _showNotesDialog(BuildContext context) {
    final ctrl = TextEditingController(text: state.session.notes);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Session Notes'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Add notes for this session...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              context.read<SessionBloc>().add(SessionNotesUpdated(ctrl.text));
              Navigator.pop(_);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDiscountSheet(BuildContext context) {
    double discount = state.session.discount;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Apply Discount', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [5, 10, 15, 20, 25, 50].map((pct) => GestureDetector(
                  onTap: () => setSt(() => discount = pct.toDouble()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: discount == pct ? AppTheme.green.withOpacity(0.15) : AppTheme.surface2,
                      border: Border.all(color: discount == pct ? AppTheme.green : AppTheme.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('$pct%', style: TextStyle(color: discount == pct ? AppTheme.green : AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    context.read<SessionBloc>().add(SessionDiscountApplied(discount));
                    Navigator.pop(_);
                  },
                  child: Text('APPLY ${discount.toInt()}% DISCOUNT'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVoidConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Void Session?'),
        content: const Text('This will cancel the session and free the table. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red, foregroundColor: AppTheme.textPrimary),
            onPressed: () {
              context.read<SessionBloc>().add(SessionVoidRequested());
              Navigator.pop(_);
            },
            child: const Text('VOID'),
          ),
        ],
      ),
    );
  }

  void _showTransferSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => _TransferSheet(currentTableId: state.session.tableId),
    );
  }

  void _showAddItemsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        side: BorderSide(color: AppTheme.border),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (__, ctrl) => BlocProvider.value(
          value: context.read<SessionBloc>(),
          child: _AddItemsSheet(controller: ctrl),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionButton({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: c.withOpacity(0.1),
              border: Border.all(color: c.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, color: c, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.08)),
        ],
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  final OrderItem item;
  const _OrderItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text('\$${item.unitPrice.toStringAsFixed(2)} × ${item.quantity}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          )),
          Text('\$${item.subtotal.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}

class _BottomBillingBar extends StatelessWidget {
  final SessionActive state;
  const _BottomBillingBar({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bill breakdown
          Row(
            children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BillRow('Time', '\$${state.currentTimeCharge.toStringAsFixed(2)}'),
                  _BillRow('F&B', '\$${state.fbTotal.toStringAsFixed(2)}'),
                  if (state.session.discount > 0)
                    _BillRow('Discount (${state.session.discount.toInt()}%)',
                        '-\$${state.discountAmount.toStringAsFixed(2)}', color: AppTheme.green),
                ],
              )),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('TOTAL BALANCE', style: TextStyle(color: AppTheme.textMuted, fontSize: 9, letterSpacing: 0.1)),
                  Text('\$${state.total.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -1)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Checkout button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showCheckoutConfirm(context),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text('CHECKOUT & CLEAR · \$${state.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.05)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.green,
                foregroundColor: AppTheme.bg,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCheckoutConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Checkout'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogRow('Table', state.session.tableName),
            _DialogRow('Time', formatTime(state.elapsedSeconds)),
            _DialogRow('Time Charge', '\$${state.currentTimeCharge.toStringAsFixed(2)}'),
            _DialogRow('F&B', '\$${state.fbTotal.toStringAsFixed(2)}'),
            if (state.session.discount > 0)
              _DialogRow('Discount', '-\$${state.discountAmount.toStringAsFixed(2)}'),
            const Divider(color: AppTheme.border),
            _DialogRow('TOTAL', '\$${state.total.toStringAsFixed(2)}', bold: true),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.payments_outlined, color: AppTheme.textMuted, size: 14),
                SizedBox(width: 6),
                Text('Cash payment', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              context.read<SessionBloc>().add(SessionCheckoutRequested());
              Navigator.pop(_);
            },
            child: const Text('CONFIRM CHECKOUT'),
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _BillRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        Text('$label  ', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        Text(value, style: TextStyle(color: color ?? AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _DialogRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _DialogRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: bold ? AppTheme.textPrimary : AppTheme.textMuted, fontWeight: bold ? FontWeight.w800 : FontWeight.normal, fontSize: bold ? 15 : 13)),
        Text(value, style: TextStyle(color: bold ? AppTheme.green : AppTheme.textPrimary, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 15 : 13)),
      ],
    ),
  );
}

class _AddItemsSheet extends StatefulWidget {
  final ScrollController controller;
  const _AddItemsSheet({required this.controller});
  @override State<_AddItemsSheet> createState() => _AddItemsSheetState();
}

class _AddItemsSheetState extends State<_AddItemsSheet> {
  final Map<String, int> _cart = {};
  String? _category;
  String _search = '';
  final _searchCtrl = TextEditingController();

  List<MenuItem> _filtered(List<MenuItem> all) {
    var items = all;
    if (_category != null) items = items.where((i) => i.category == _category).toList();
    if (_search.isNotEmpty) items = items.where((i) => i.name.toLowerCase().contains(_search.toLowerCase())).toList();
    return items;
  }

  int get _totalItems => _cart.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MenuBloc, MenuState>(
      builder: (context, menuState) {
        final allItems = menuState is MenuLoaded ? menuState.allItems : <MenuItem>[];
        final categories = allItems.map((i) => i.category).toSet().toList()..sort();
        final filtered = _filtered(allItems);

        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ADD TO TABLE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const Text('Select items for current session', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  const SizedBox(height: 12),
                  // Search
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (q) => setState(() => _search = q),
                    decoration: const InputDecoration(
                      hintText: 'Search consumables...',
                      prefixIcon: Icon(Icons.search, size: 18),
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Category chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _CategoryChip(label: 'All', selected: _category == null, onTap: () => setState(() => _category = null)),
                        ...categories.map((c) => _CategoryChip(
                          label: c.toUpperCase(),
                          selected: _category == c,
                          onTap: () => setState(() => _category = c),
                        )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Grid
            Expanded(
              child: GridView.builder(
                controller: widget.controller,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.75,
                ),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final item = filtered[i];
                  final qty = _cart[item.id] ?? 0;
                  return MenuItemCard(
                    item: item,
                    quantity: qty,
                    onAdd: () => setState(() => _cart[item.id] = qty + 1),
                    onRemove: () => setState(() {
                      if (qty > 1) _cart[item.id] = qty - 1;
                      else _cart.remove(item.id);
                    }),
                  );
                },
              ),
            ),
            // Confirm bar
            if (_totalItems > 0)
              Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DRAFT ORDER', style: TextStyle(color: AppTheme.textMuted.withOpacity(0.8), fontSize: 9, letterSpacing: 0.1)),
                          Text('$_totalItems item${_totalItems > 1 ? 's' : ''} · \$${_cartTotal(allItems).toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _confirmOrder(context, allItems),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('CONFIRM'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  double _cartTotal(List<MenuItem> items) {
    double total = 0;
    for (final entry in _cart.entries) {
      final item = items.firstWhere((i) => i.id == entry.key, orElse: () => MenuItem(id: '', name: '', price: 0, category: '', venueId: ''));
      total += item.price * entry.value;
    }
    return total;
  }

  void _confirmOrder(BuildContext context, List<MenuItem> items) {
    final orderItems = _cart.entries.map((entry) {
      final item = items.firstWhere((i) => i.id == entry.key);
      return OrderItem(
        menuItemId: item.id,
        name: item.name,
        unitPrice: item.price,
        quantity: entry.value,
        category: item.category,
      );
    }).toList();
    // SessionBloc here is the LOCAL one created by the router for this route
    context.read<SessionBloc>().add(SessionAddItemsRequested(orderItems));
    Navigator.pop(context);
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.green.withOpacity(0.15) : AppTheme.surface2,
          border: Border.all(color: selected ? AppTheme.green : AppTheme.border),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(label, style: TextStyle(color: selected ? AppTheme.green : AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    ),
  );
}

class _TransferSheet extends StatelessWidget {
  final String currentTableId;
  const _TransferSheet({required this.currentTableId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FloorBloc, FloorState>(
      builder: (context, state) {
        if (state is! FloorLoaded) return const SizedBox();
        final openTables = state.allTables.where((t) => t.status == TableStatus.open && t.id != currentTableId).toList();
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Transfer Session', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Text('Select destination table', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              const SizedBox(height: 20),
              if (openTables.isEmpty)
                const Center(child: Text('No open tables available', style: TextStyle(color: AppTheme.textMuted)))
              else
                ...openTables.map((t) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.table_bar, color: AppTheme.green, size: 18),
                  ),
                  title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(t.zone, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  onTap: () {
                    context.read<SessionBloc>().add(SessionTransferRequested(toTableId: t.id, toTableName: t.name));
                    Navigator.pop(context);
                  },
                )),
            ],
          ),
        );
      },
    );
  }
}

class _ReceiptSheet extends StatelessWidget {
  final SessionModel session;
  final VoidCallback onDone;
  const _ReceiptSheet({required this.session, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.check, color: AppTheme.green, size: 22),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Session Completed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('Table is now free', style: TextStyle(color: AppTheme.green, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: AppTheme.border),
          _DialogRow('Table', session.tableName),
          _DialogRow('Duration', formatTime(session.elapsedSeconds.toInt())),
          _DialogRow('Time', '\$${session.timeCharge.toStringAsFixed(2)}'),
          _DialogRow('F&B', '\$${session.fbTotal.toStringAsFixed(2)}'),
          if (session.discount > 0)
            _DialogRow('Discount (${session.discount.toInt()}%)', '-\$${session.discountAmount.toStringAsFixed(2)}'),
          const Divider(color: AppTheme.border),
          _DialogRow('TOTAL', '\$${session.total.toStringAsFixed(2)}', bold: true),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDone,
                  child: const Text('CLOSE'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onDone,
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: const Text('PRINT'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
