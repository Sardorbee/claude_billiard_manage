import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../blocs/blocs.dart';
import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../session/session_screen.dart' show AddItemsSheet;

class FloorScreen extends StatelessWidget {
  const FloorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('BILYARD'),
            Text('JONLI HOLAT',
                style: TextStyle(color: AppTheme.textMuted.withOpacity(0.7), fontSize: 9, letterSpacing: 0.15)),
          ],
        ),
        actions: [
          if (user != null)
            IconButton(
              tooltip: 'Stolsiz savdo',
              icon: const Icon(Icons.point_of_sale_outlined),
              onPressed: () => _showCounterSale(context, user),
            ),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: GestureDetector(
                onTap: () => _showUserMenu(context, user),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.green.withOpacity(0.2),
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: BlocBuilder<FloorBloc, FloorState>(
        builder: (context, state) {
          if (state is FloorLoading) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.green));
          }
          if (state is FloorError) {
            return Center(child: Text(state.message, style: const TextStyle(color: AppTheme.red)));
          }
          if (state is FloorLoaded) {
            return Column(
              children: [
                _FilterBar(activeFilter: state.activeFilter),
                Expanded(
                  child: RefreshIndicator(
                    color: AppTheme.green,
                    onRefresh: () async {},
                    child: CustomScrollView(
                      slivers: [
                        ...state.byZone.entries.map((entry) => _ZoneSection(
                          zone: entry.key,
                          tables: entry.value,
                        )),
                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return const SizedBox();
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showWalkInDialog(context),
        backgroundColor: AppTheme.green,
        foregroundColor: AppTheme.bg,
        label: const Text("Bo'sh stollar", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.05)),
      ),
    );
  }

  void _showWalkInDialog(BuildContext context) {
    final floorState = context.read<FloorBloc>().state;
    if (floorState is! FloorLoaded) return;
    final openTables = floorState.allTables.where((t) => t.status == TableStatus.open).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        side: BorderSide(color: AppTheme.border),
      ),
      builder: (_) => _WalkInSheet(
        openTables: openTables,
        onSelected: (table) {
          final authState = context.read<AuthBloc>().state;
          if (authState is! AuthAuthenticated) return;
          showModalBottomSheet(
            context: context,
            backgroundColor: AppTheme.surface,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              side: BorderSide(color: AppTheme.border),
            ),
            builder: (_) =>
                _OpenSessionSheet(table: table, user: authState.user),
          );
        },
      ),
    );
  }

  // A sale with no table: pick items, pick how it was paid, save.
  void _showCounterSale(BuildContext context, AppUser user) {
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
        builder: (__, ctrl) => AddItemsSheet(
          controller: ctrl,
          title: 'STOLSIZ SAVDO',
          subtitle: 'Stolsiz mahsulot sotish',
          onConfirm: (items) => _payCounterSale(context, user, items),
        ),
      ),
    );
  }

  Future<void> _payCounterSale(
      BuildContext context, AppUser user, List<OrderItem> items) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<SessionRepository>();
    final debtorNames =
        context.read<DebtRepository>().customerNames(user.venueId);
    final total = items.fold(0.0, (sum, i) => sum + i.subtotal);

    final choice = await showDialog<PaymentChoice>(
      context: context,
      builder: (_) => PaymentDialog(
        title: 'Stolsiz savdo',
        confirmLabel: 'TASDIQLASH',
        debtorNames: debtorNames,
        summary: [
          ...items.map((i) => _SaleRow('${i.quantity}× ${i.name}',
              formatCurrency(i.subtotal))),
          const Divider(color: AppTheme.border),
          _SaleRow('Umumiy summa', formatCurrency(total),
              bold: true),
        ],
      ),
    );
    if (choice == null) return;

    try {
      await repo.createCounterSale(
        venueId: user.venueId,
        items: items,
        paymentMethod: choice.method,
        debtorName: choice.debtorName,
        soldBy: user,
      );
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Savdo saqlandi · ${formatCurrency(total)} · ${paymentLabel(choice.method)}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Savdo saqlanmadi: $e'),
          backgroundColor: AppTheme.red));
    }
  }

  void _showUserMenu(BuildContext context, AppUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        side: BorderSide(color: AppTheme.border),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(user.email, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 8),
            StatusBadge(user.role.name),
            const SizedBox(height: 24),
            const Divider(color: AppTheme.border),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout, color: AppTheme.red, size: 20),
              title: const Text('Chiqish', style: TextStyle(color: AppTheme.red)),
              onTap: () {
                Navigator.pop(context);
                context.read<AuthBloc>().add(AuthSignOutRequested());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String? activeFilter;
  const _FilterBar({this.activeFilter});

  @override
  Widget build(BuildContext context) {
    final filters = [
      (null, 'HAMMASI'),
      ('billiard', 'Bilyard'),
      ('ps', 'Play Station'),
    ];
    return Container(
      height: 48,
      color: AppTheme.surface,
      child: Row(
        children: [
          const SizedBox(width: 16),
          ...filters.map((f) {
            final isActive = f.$1 == activeFilter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => context.read<FloorBloc>().add(FloorFilterChanged(f.$1)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive ? AppTheme.green.withOpacity(0.15) : Colors.transparent,
                    border: Border.all(color: isActive ? AppTheme.green : AppTheme.border),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(f.$2,
                      style: TextStyle(
                        color: isActive ? AppTheme.green : AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.08,
                      )),
                ),
              ),
            );
          }),
          const Spacer(),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.red.withOpacity(0.1),
              border: Border.all(color: AppTheme.red.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(color: AppTheme.red, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                const Text('JONLI', style: TextStyle(color: AppTheme.red, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneSection extends StatelessWidget {
  final String zone;
  final List<TableModel> tables;
  const _ZoneSection({required this.zone, required this.tables});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(zone),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.5,
              ),
              itemCount: tables.length,
              itemBuilder: (context, i) {
                final table = tables[i];
                // KEY = table.id so Flutter reuses the exact same StatefulWidget
                // instance for the same table across rebuilds — no timer reset.
                return _LiveTableCard(key: ValueKey(table.id), table: table);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Each table card owns its own RTDB subscription + 1-second ticker.
/// It is completely isolated from every other card and from SessionBloc.
class _LiveTableCard extends StatefulWidget {
  final TableModel table;
  const _LiveTableCard({super.key, required this.table});

  @override
  State<_LiveTableCard> createState() => _LiveTableCardState();
}

class _LiveTableCardState extends State<_LiveTableCard> {
  StreamSubscription<Map<String, dynamic>?>? _rtdbSub;
  StreamSubscription<SessionModel?>? _fsSub;
  double _fbTotal = 0;
  Timer? _ticker;
  Map<String, dynamic>? _liveData;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(_LiveTableCard old) {
    super.didUpdateWidget(old);
    // If the table's status changed (e.g. open → active or active → open),
    // tear down and re-subscribe so we start/stop the ticker correctly.
    if (old.table.status != widget.table.status ||
        old.table.id != widget.table.id) {
      _unsubscribe();
      _subscribe();
    }
  }

  void _subscribe() {
    if (widget.table.status != TableStatus.active) return;

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final venueId = authState.user.venueId;

    final repo = context.read<SessionRepository>();
    _rtdbSub = repo.watchLiveSession(venueId, widget.table.id).listen((data) {
      if (mounted) setState(() => _liveData = data);
    });

    final sessionId = widget.table.currentSessionId;
    if (sessionId != null) {
      _fsSub = repo.watchActiveSession(venueId, sessionId).listen((session) {
        if (mounted) setState(() => _fbTotal = session?.fbTotal ?? 0);
      });
    }

    // Tick every second to advance the displayed timer
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // triggers _computeElapsed() in build
    });
  }

  void _unsubscribe() {
    _ticker?.cancel();
    _rtdbSub?.cancel();
    _fsSub?.cancel();
    _fsSub = null;
    _fbTotal = 0;
    _ticker = null;
    _rtdbSub = null;
    _liveData = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  /// Elapsed seconds computed purely from this table's own RTDB data.
  /// No reference to SessionBloc whatsoever.
  int _computeElapsed() {
    if (_liveData == null) return 0;
    final startedAt   = (_liveData!['startedAt']     as int?) ?? 0;
    final pausedMs    = (_liveData!['totalPausedMs']  as int?) ?? 0;
    final pausedAt    = (_liveData!['pausedAt']       as int?);
    final now         = pausedAt ?? DateTime.now().millisecondsSinceEpoch;
    final result      = ((now - startedAt - pausedMs) / 1000).floor();
    return result < 0 ? 0 : result;
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;

    final isActive = widget.table.status == TableStatus.active;
    final elapsed   = isActive ? _computeElapsed() : null;
    final total = isActive && elapsed != null
        ? (elapsed / 3600) * widget.table.hourlyRate + _fbTotal  // ← add _fbTotal
        : null;

    return TableCard(
      table: widget.table,
      elapsedSeconds: elapsed,
      runningTotal: total,
      onTap: () => _onTap(context, user),
    );
  }

  void _onTap(BuildContext context, AppUser? user) {
    if (user == null) return;
    final table = widget.table;
    if (table.status == TableStatus.active && table.currentSessionId != null) {
      context.push('/session/${table.id}/${table.currentSessionId}');
    } else if (table.status == TableStatus.open) {
      _showOpenSessionSheet(context, table, user);
    } else if (table.status == TableStatus.reserved) {
      _showReservedOptions(context, table, user);
    }
  }

  void _showOpenSessionSheet(BuildContext context, TableModel table, AppUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        side: BorderSide(color: AppTheme.border),
      ),
      builder: (_) => _OpenSessionSheet(table: table, user: user),
    );
  }

  void _showReservedOptions(BuildContext context, TableModel table, AppUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(table.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Text('Bu stol band qilingan', style: TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showOpenSessionSheet(context, table, user);
                },
                child: const Text('Baribir seansni boshlash'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Open session bottom sheet ───────────────────────────────────────────────

class _OpenSessionSheet extends StatefulWidget {
  final TableModel table;
  final AppUser user;
  const _OpenSessionSheet({required this.table, required this.user});
  @override State<_OpenSessionSheet> createState() => _OpenSessionSheetState();
}

class _OpenSessionSheetState extends State<_OpenSessionSheet> {
  int _guestCount = 2;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_bar_rounded, color: AppTheme.green, size: 20),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Seans ochish · ${widget.table.name}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('${formatCurrency(widget.table.hourlyRate)}/soat',
                      style: const TextStyle(color: AppTheme.green, fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text("O'YINCHILAR SONI", style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.1)),
          const SizedBox(height: 12),
          Row(
            children: [
              _CountButton(icon: Icons.remove, onTap: () { if (_guestCount > 1) setState(() => _guestCount--); }),
              const SizedBox(width: 20),
              Text('$_guestCount', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(width: 20),
              _CountButton(icon: Icons.add, onTap: () { if (_guestCount < 10) setState(() => _guestCount++); }),
              const Spacer(),
              Icon(Icons.person, color: AppTheme.textMuted, size: 16),
              Text(' ${widget.table.capacity} gacha', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // Pass table + guestCount as `extra` — the router creates a
                // fresh SessionBloc for this route and dispatches SessionOpenRequested.
                context.push(
                  '/session/${widget.table.id}/new',
                  extra: {
                    'table': widget.table,
                    'guestCount': _guestCount,
                  },
                );
              },
              child: const Text('SEANSNI BOSHLASH'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CountButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: AppTheme.textPrimary, size: 18),
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _SaleRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: AppTheme.textPrimary,
      fontSize: bold ? 15 : 13,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _WalkInSheet extends StatelessWidget {
  final List<TableModel> openTables;
  final ValueChanged<TableModel> onSelected;
  const _WalkInSheet({required this.openTables, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    if (openTables.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_bar_rounded, color: AppTheme.textMuted, size: 40),
            SizedBox(height: 12),
            Text("Bo'sh stol yo'q", style: TextStyle(color: AppTheme.textMuted)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Bo'sh stollar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Text("Bo'sh stolni tanlang", style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const SizedBox(height: 20),
          ...openTables.map((t) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(4)),
              child: const Icon(Icons.table_bar, color: AppTheme.green, size: 18),
            ),
            title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${formatCurrency(t.hourlyRate)}/soat · ${tableTypeLabel(t.type)}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.textMuted),
            onTap: () {
              Navigator.pop(context);
              onSelected(t);
            },
          )),
        ],
      ),
    );
  }
}
