import 'package:billiardtm/app_theme.dart';
import 'package:billiardtm/bloc/blocs.dart';
import 'package:billiardtm/repos/repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../models/models.dart';
import '../../widgets/widgets.dart';

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
            const Text('THE FLOOR'),
            Text('LIVE STATUS MONITOR',
                style: TextStyle(color: AppTheme.textMuted.withOpacity(0.7), fontSize: 9, letterSpacing: 0.15)),
          ],
        ),
        actions: [
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
        icon: const Icon(Icons.flash_on),
        label: const Text('QUICK WALK-IN', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.05)),
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
      builder: (_) => _WalkInSheet(openTables: openTables),
    );
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
              title: const Text('Sign Out', style: TextStyle(color: AppTheme.red)),
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
      (null, 'ALL'),
      ('pool', 'POOL'),
      ('snooker', 'SNOOKER'),
      ('vipSuite', 'VIP SUITE'),
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
          // Live indicator
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
                const Text('LIVE', style: TextStyle(color: AppTheme.red, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.1)),
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
                return _LiveTableCard(table: table);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// Wraps TableCard with live RTDB data
class _LiveTableCard extends StatelessWidget {
  final TableModel table;
  const _LiveTableCard({required this.table});

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;

    if (table.status != TableStatus.active || table.currentSessionId == null) {
      return TableCard(
        table: table,
        onTap: () => _onTap(context, table, user),
      );
    }

    // Use a StreamBuilder for live data
    final sessionRepo = context.read<SessionRepository>();
    return StreamBuilder<Map<String, dynamic>?>(
      stream: sessionRepo.watchLiveSession(user?.venueId ?? '', table.id),
      builder: (context, snap) {
        int elapsed = 0;
        double total = 0;
        if (snap.hasData && snap.data != null) {
          final live = snap.data!;
          final startedAt = live['startedAt'] as int? ?? 0;
          final totalPausedMs = live['totalPausedMs'] as int? ?? 0;
          final pausedAt = live['pausedAt'] as int?;
          final now = pausedAt ?? DateTime.now().millisecondsSinceEpoch;
          elapsed = ((now - startedAt - totalPausedMs) / 1000).floor();
          if (elapsed < 0) elapsed = 0;
          total = (elapsed / 3600) * table.hourlyRate;
        }
        return TableCard(
          table: table,
          elapsedSeconds: elapsed,
          runningTotal: total,
          onTap: () => _onTap(context, table, user),
        );
      },
    );
  }

  void _onTap(BuildContext context, TableModel table, AppUser? user) {
    if (user == null) return;
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
            const Text('This table is reserved', style: TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showOpenSessionSheet(context, table, user);
                },
                child: const Text('Start Session Anyway'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
                  Text('Open Session · ${widget.table.name}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('\$${widget.table.hourlyRate.toStringAsFixed(2)}/hr',
                      style: const TextStyle(color: AppTheme.green, fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text('NUMBER OF PLAYERS', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.1)),
          const SizedBox(height: 12),
          Row(
            children: [
              _CountButton(
                icon: Icons.remove,
                onTap: () { if (_guestCount > 1) setState(() => _guestCount--); },
              ),
              const SizedBox(width: 20),
              Text('$_guestCount', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(width: 20),
              _CountButton(
                icon: Icons.add,
                onTap: () { if (_guestCount < 10) setState(() => _guestCount++); },
              ),
              const Spacer(),
              Icon(Icons.person, color: AppTheme.textMuted, size: 16),
              Text(' ${widget.table.capacity} max', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.read<SessionBloc>().add(SessionOpenRequested(
                  venueId: widget.user.venueId,
                  table: widget.table,
                  guestCount: _guestCount,
                  openedBy: widget.user.uid,
                ));
                context.push('/session/${widget.table.id}/new');
              },
              child: const Text('START SESSION'),
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

class _WalkInSheet extends StatelessWidget {
  final List<TableModel> openTables;
  const _WalkInSheet({required this.openTables});

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
            Text('No open tables available', style: TextStyle(color: AppTheme.textMuted)),
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
          const Text('Quick Walk-In', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Text('Select an available table', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const SizedBox(height: 20),
          ...openTables.map((t) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(4)),
              child: const Icon(Icons.table_bar, color: AppTheme.green, size: 18),
            ),
            title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('\$${t.hourlyRate.toStringAsFixed(2)}/hr · ${t.type.name}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.textMuted),
            onTap: () {
              Navigator.pop(context);
              // Navigate to floor and tap table - or directly open session sheet
            },
          )),
        ],
      ),
    );
  }
}