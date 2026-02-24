import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';

// ─── STATUS BADGE ────────────────────────────────────────────────────────────

class StatusBadge extends StatelessWidget {
  final String status;
  final bool dot;
  const StatusBadge(this.status, {super.key, this.dot = false});

  Color get color {
    switch (status) {
      case 'active': return AppTheme.green;
      case 'reserved': return AppTheme.amber;
      case 'maintenance': return AppTheme.red;
      case 'open': return AppTheme.textMuted;
      case 'completed': return AppTheme.blue;
      case 'cancelled': case 'no_show': return AppTheme.red;
      case 'confirmed': return AppTheme.green;
      default: return AppTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dot) {
      return Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4, spreadRadius: 1)],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.08,
        ),
      ),
    );
  }
}

// ─── TABLE CARD ───────────────────────────────────────────────────────────────

class TableCard extends StatelessWidget {
  final TableModel table;
  final int? elapsedSeconds;
  final double? runningTotal;
  final VoidCallback? onTap;

  const TableCard({
    super.key,
    required this.table,
    this.elapsedSeconds,
    this.runningTotal,
    this.onTap,
  });

  Color get _borderColor {
    switch (table.status) {
      case TableStatus.active: return AppTheme.green.withOpacity(0.4);
      case TableStatus.reserved: return AppTheme.amber.withOpacity(0.4);
      case TableStatus.maintenance: return AppTheme.red.withOpacity(0.4);
      default: return AppTheme.border;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: _borderColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  table.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                StatusBadge(table.status.name, dot: true),
              ],
            ),
            const SizedBox(height: 10),
            if (table.status == TableStatus.open)
              _OpenContent()
            else if (table.status == TableStatus.active)
              _ActiveContent(elapsedSeconds: elapsedSeconds ?? 0, total: runningTotal ?? 0)
            else if (table.status == TableStatus.reserved)
              _ReservedContent()
            else
              _MaintenanceContent(),
          ],
        ),
      ),
    );
  }
}

class _OpenContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('OPEN', style: TextStyle(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.1)),
      ),
    );
  }
}

class _ActiveContent extends StatelessWidget {
  final int elapsedSeconds;
  final double total;
  const _ActiveContent({required this.elapsedSeconds, required this.total});

  String _formatTime(int secs) {
    final h = (secs ~/ 3600).toString().padLeft(2, '0');
    final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatTime(elapsedSeconds),
          style: const TextStyle(
            color: AppTheme.green,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '\$${total.toStringAsFixed(2)}',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _ReservedContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.schedule, color: AppTheme.amber, size: 14),
        SizedBox(width: 6),
        Text('RESERVED', style: TextStyle(color: AppTheme.amber, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _MaintenanceContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.build, color: AppTheme.red, size: 14),
        SizedBox(width: 6),
        Text('MAINTENANCE', style: TextStyle(color: AppTheme.red, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─── SECTION HEADER ───────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.12,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Divider(color: AppTheme.border, height: 1)),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

// ─── STAT CARD ───────────────────────────────────────────────────────────────

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  final Widget? child;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: AppTheme.textMuted, size: 14),
                const SizedBox(width: 6),
              ],
              Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.05)),
            ],
          ),
          const SizedBox(height: 8),
          if (child != null)
            child!
          else
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppTheme.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── MENU ITEM CARD ───────────────────────────────────────────────────────────

class MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback? onRemove;

  const MenuItemCard({
    super.key,
    required this.item,
    required this.quantity,
    required this.onAdd,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: quantity > 0 ? AppTheme.green.withOpacity(0.3) : AppTheme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.imageUrl != null
                      ? Image.network(item.imageUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
                  if (!item.isAvailable)
                    Container(
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: const Text('OUT OF\nSTOCK', textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.red, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
            ),
          ),
          // Info
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('\$${item.price.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppTheme.green, fontSize: 12, fontWeight: FontWeight.w700)),
                      if (quantity > 0)
                        Row(
                          children: [
                            GestureDetector(
                              onTap: onRemove,
                              child: Container(
                                width: 20, height: 20,
                                decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(2)),
                                child: const Icon(Icons.remove, size: 12, color: AppTheme.textMuted),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                            ),
                            GestureDetector(
                              onTap: item.isAvailable ? onAdd : null,
                              child: Container(
                                width: 20, height: 20,
                                decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
                                child: const Icon(Icons.add, size: 12, color: AppTheme.green),
                              ),
                            ),
                          ],
                        )
                      else
                        GestureDetector(
                          onTap: item.isAvailable ? onAdd : null,
                          child: Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                              color: item.isAvailable ? AppTheme.green.withOpacity(0.15) : AppTheme.surface2,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: item.isAvailable ? AppTheme.green.withOpacity(0.4) : AppTheme.border),
                            ),
                            child: Icon(Icons.add, size: 14, color: item.isAvailable ? AppTheme.green : AppTheme.textMuted),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppTheme.surface2,
    child: const Icon(Icons.fastfood_outlined, color: AppTheme.textMuted, size: 28),
  );
}

// ─── APP BOTTOM NAV ───────────────────────────────────────────────────────────

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final bool isAdmin;
  final Function(int) onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.isAdmin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        backgroundColor: Colors.transparent,
        elevation: 0,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Floor'),
          const BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Bookings'),
          const BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Stats'),
          if (isAdmin)
            const BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Admin'),
        ],
      ),
    );
  }
}

// ─── LOADING OVERLAY ─────────────────────────────────────────────────────────

class LoadingOverlay extends StatelessWidget {
  final String? message;
  const LoadingOverlay({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.green, strokeWidth: 2),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(message!, style: const TextStyle(color: AppTheme.textPrimary)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── TIMER RING ──────────────────────────────────────────────────────────────

class TimerRing extends StatelessWidget {
  final int elapsedSeconds;
  final bool isPaused;
  final String timeLabel;
  final String subLabel;

  const TimerRing({
    super.key,
    required this.elapsedSeconds,
    required this.isPaused,
    required this.timeLabel,
    required this.subLabel,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (elapsedSeconds % 3600) / 3600;
    return SizedBox(
      width: 200, height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring
          SizedBox(
            width: 200, height: 200,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 6,
              backgroundColor: AppTheme.border,
              valueColor: const AlwaysStoppedAnimation(AppTheme.border),
            ),
          ),
          // Progress ring
          SizedBox(
            width: 200, height: 200,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 6,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(isPaused ? AppTheme.amber : AppTheme.green),
            ),
          ),
          // Center content
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPaused)
                const Icon(Icons.pause, color: AppTheme.amber, size: 20),
              Text(
                timeLabel,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: isPaused ? AppTheme.amber : AppTheme.textPrimary,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
              Text(
                subLabel,
                style: const TextStyle(color: AppTheme.green, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── CURRENCY FORMATTER ───────────────────────────────────────────────────────

String formatCurrency(double amount, {String symbol = '\$'}) =>
    '$symbol${amount.toStringAsFixed(2)}';

String formatTime(int seconds) {
  final h = (seconds ~/ 3600).toString().padLeft(2, '0');
  final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String formatDate(DateTime dt) => DateFormat('MMM d, yyyy · h:mm a').format(dt);
String formatTimeOnly(DateTime dt) => DateFormat('h:mm a').format(dt);
