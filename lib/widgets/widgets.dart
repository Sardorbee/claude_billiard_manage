import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';

// ─── STATUS BADGE ────────────────────────────────────────────────────────────

class StatusBadge extends StatelessWidget {
  final String status;
  final bool dot;
  const StatusBadge(this.status, {super.key, this.dot = false});

  // Statuses and roles arrive as their stored English names.
  static const _labels = {
    'active': 'FAOL',
    'reserved': 'BAND',
    'maintenance': "TA'MIRDA",
    'open': "BO'SH",
    'completed': 'YOPILGAN',
    'cancelled': 'BEKOR QILINGAN',
    'no_show': 'KELMADI',
    'confirmed': 'TASDIQLANGAN',
    'staff': 'XODIM',
    'supervisor': 'NAZORATCHI',
    'manager': 'MENEJER',
    'owner': 'EGASI',
  };

  Color get color {
    switch (status) {
      case 'active':
        return AppTheme.green;
      case 'reserved':
        return AppTheme.amber;
      case 'maintenance':
        return AppTheme.red;
      case 'open':
        return AppTheme.textMuted;
      case 'completed':
        return AppTheme.blue;
      case 'cancelled':
      case 'no_show':
        return AppTheme.red;
      case 'confirmed':
        return AppTheme.green;
      default:
        return AppTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dot) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.5), blurRadius: 4, spreadRadius: 1)
          ],
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
        _labels[status] ?? status.toUpperCase(),
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

  // A fixed-time session that has run past its booked end.
  bool get _timeIsUp =>
      table.status == TableStatus.active &&
      table.sessionEndsAt != null &&
      !table.sessionEndsAt!.isAfter(DateTime.now());

  Color get _borderColor {
    switch (table.status) {
      case TableStatus.active:
        if (_timeIsUp) return AppTheme.red;
        return AppTheme.green.withOpacity(0.4);
      case TableStatus.reserved:
        return AppTheme.amber.withOpacity(0.4);
      case TableStatus.maintenance:
        return AppTheme.red.withOpacity(0.4);
      default:
        return AppTheme.border;
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
              _ActiveContent(
                  elapsedSeconds: elapsedSeconds ?? 0,
                  total: runningTotal ?? 0,
                  endsAt: table.sessionEndsAt)
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
        child: Text("BO'SH",
            style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1)),
      ),
    );
  }
}

class _ActiveContent extends StatelessWidget {
  final int elapsedSeconds;
  final double total;
  final DateTime? endsAt; // booked end of a fixed-time session
  const _ActiveContent(
      {required this.elapsedSeconds, required this.total, this.endsAt});

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
          formatCurrency(total),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        if (endsAt != null) ...[
          const SizedBox(height: 4),
          TimeLeftLabel(
              remainingSeconds: endsAt!.difference(DateTime.now()).inSeconds),
        ],
      ],
    );
  }
}

/// "Qoldi 12:34" for a fixed-time session; turns amber in the last five
/// minutes and red once the time is up.
class TimeLeftLabel extends StatelessWidget {
  final int remainingSeconds; // negative once over time
  final double fontSize;
  const TimeLeftLabel(
      {super.key, required this.remainingSeconds, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    final over = remainingSeconds <= 0;
    final color = over
        ? AppTheme.red
        : remainingSeconds <= 300
            ? AppTheme.amber
            : AppTheme.textSecondary;
    return Text(
      over
          ? 'VAQT TUGADI · +${formatTime(-remainingSeconds)}'
          : 'Qoldi ${formatTime(remainingSeconds)}',
      style: TextStyle(
          color: color, fontSize: fontSize, fontWeight: FontWeight.w700),
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
        Text('BAND',
            style: TextStyle(
                color: AppTheme.amber,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
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
        Text("TA'MIRDA",
            style: TextStyle(
                color: AppTheme.red,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
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
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      letterSpacing: 0.05)),
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
        border: Border.all(
            color: quantity > 0
                ? AppTheme.green.withOpacity(0.3)
                : AppTheme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(3)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.imageUrl != null
                      ? Image.network(item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
                  if (!item.isAvailable)
                    Container(
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: const Text('TUGAGAN',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppTheme.red,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
            ),
          ),
          // Info. Takes the height its lines need and leaves the rest to
          // the image, so it fits however narrow the card gets.
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatCurrency(item.price),
                      style: const TextStyle(
                          color: AppTheme.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (quantity > 0)
                  // As tall as the lone "+" below, so cards don't jump.
                  SizedBox(
                    height: 24,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: onRemove,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                                color: AppTheme.surface2,
                                borderRadius: BorderRadius.circular(2)),
                            child: const Icon(Icons.remove,
                                size: 12, color: AppTheme.textMuted),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text('$quantity',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 13)),
                        ),
                        GestureDetector(
                          onTap: item.isAvailable ? onAdd : null,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                                color: AppTheme.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(2)),
                            child: const Icon(Icons.add,
                                size: 12, color: AppTheme.green),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  GestureDetector(
                    onTap: item.isAvailable ? onAdd : null,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: item.isAvailable
                            ? AppTheme.green.withOpacity(0.15)
                            : AppTheme.surface2,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                            color: item.isAvailable
                                ? AppTheme.green.withOpacity(0.4)
                                : AppTheme.border),
                      ),
                      child: Icon(Icons.add,
                          size: 14,
                          color: item.isAvailable
                              ? AppTheme.green
                              : AppTheme.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppTheme.surface2,
        child: const Icon(Icons.fastfood_outlined,
            color: AppTheme.textMuted, size: 28),
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
          const BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded), label: 'Zal'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined), label: 'Bookings'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded), label: 'Hisobot'),
          if (isAdmin)
            const BottomNavigationBarItem(
                icon: Icon(Icons.admin_panel_settings_outlined),
                label: 'Boshqaruv'),
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
            const CircularProgressIndicator(
                color: AppTheme.green, strokeWidth: 2),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(message!,
                  style: const TextStyle(color: AppTheme.textPrimary)),
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
  final String startedTime;
  final String subLabel;

  const TimerRing({
    super.key,
    required this.elapsedSeconds,
    required this.isPaused,
    required this.timeLabel,
    required this.subLabel,
    required this.startedTime,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Center content
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text(
                    "Boshlangan vaqti:",
                    style: const TextStyle(
                        color: AppTheme.blue,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    startedTime,
                    style: const TextStyle(
                        color: AppTheme.blue,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
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
                style: const TextStyle(
                    color: AppTheme.green,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── CURRENCY FORMATTER ───────────────────────────────────────────────────────

// Whole so'm with a space between thousands: 35 000 so'm.
String formatCurrency(double amount) {
  final whole = amount.round();
  final digits = whole
      .abs()
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
  return "${whole < 0 ? '-' : ''}$digits so'm";
}

// Short form for chart axes: 35 ming, 1.2 mln.
String formatCompact(double amount) {
  if (amount.abs() >= 1000000) {
    return '${(amount / 1000000).toStringAsFixed(1)} mln';
  }
  if (amount.abs() >= 1000) return '${(amount / 1000).round()} ming';
  return '${amount.round()}';
}

// 30 daq, 1 soat, 1.5 soat
String durationLabel(int minutes) => minutes < 60
    ? '$minutes daq'
    : '${(minutes / 60).toStringAsFixed(minutes % 60 == 0 ? 0 : 1)} soat';

String tableTypeLabel(TableType type) => switch (type) {
      TableType.billiard => 'Bilyard',
      TableType.ps => 'PlayStation',
    };

String roleLabel(UserRole role) => switch (role) {
      UserRole.staff => 'Xodim',
      UserRole.supervisor => 'Nazoratchi',
      UserRole.manager => 'Menejer',
      UserRole.owner => 'Egasi',
    };

String formatTime(int seconds) {
  final h = (seconds ~/ 3600).toString().padLeft(2, '0');
  final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

// Numeric dates need no locale data and read the same in Uzbek.
String formatDate(DateTime dt) => DateFormat('dd.MM.yyyy · HH:mm').format(dt);
String formatTimeOnly(DateTime dt) => DateFormat('HH:mm').format(dt);

// When one game of a session was played: 21:05 – 21:40
String splitTimes(SessionSplit split) =>
    '${formatTimeOnly(split.startedAt)} – ${formatTimeOnly(split.splitAt)}';

// ─── Payment dialog ──────────────────────────────────────────────────────────

typedef PaymentChoice = ({PaymentMethod method, String? debtorName});

String paymentLabel(PaymentMethod method) => switch (method) {
      PaymentMethod.cash => 'Naqd',
      PaymentMethod.transfer => "O'tkazma",
      PaymentMethod.debt => 'Qarz',
    };

/// Shows [summary] and asks how the customer paid. Pops with a
/// [PaymentChoice], or null if cancelled.
class PaymentDialog extends StatefulWidget {
  final String title;
  final List<Widget> summary;
  final String confirmLabel;
  // Existing debtors, offered as suggestions so a regular isn't entered
  // twice under two spellings.
  final Future<List<String>>? debtorNames;
  const PaymentDialog({
    super.key,
    required this.title,
    required this.summary,
    required this.confirmLabel,
    this.debtorNames,
  });

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  PaymentMethod _method = PaymentMethod.cash;
  final _debtorCtrl = TextEditingController();
  bool _debtorMissing = false;
  List<String> _known = const [];

  @override
  void initState() {
    super.initState();
    widget.debtorNames?.then((names) {
      if (mounted) setState(() => _known = names);
    }).catchError((_) {});
    _debtorCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debtorCtrl.dispose();
    super.dispose();
  }

  List<String> get _suggestions {
    final q = _debtorCtrl.text.trim().toLowerCase();
    return _known
        .where((n) => n.toLowerCase().contains(q) && n.toLowerCase() != q)
        .take(6)
        .toList();
  }

  void _confirm() {
    final debtor = _debtorCtrl.text.trim();
    if (_method == PaymentMethod.debt && debtor.isEmpty) {
      setState(() => _debtorMissing = true);
      return;
    }
    Navigator.pop<PaymentChoice>(context, (
      method: _method,
      debtorName: _method == PaymentMethod.debt ? debtor : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...widget.summary,
            const SizedBox(height: 16),
            const Text("TO'LOV TURI",
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    letterSpacing: 0.1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: PaymentMethod.values
                  .map((m) => ChoiceChip(
                        label: Text(paymentLabel(m)),
                        selected: _method == m,
                        selectedColor: AppTheme.green,
                        backgroundColor: AppTheme.surface2,
                        labelStyle: TextStyle(
                            color: _method == m
                                ? AppTheme.bg
                                : AppTheme.textPrimary,
                            fontWeight: FontWeight.w700),
                        onSelected: (_) => setState(() {
                          _method = m;
                          _debtorMissing = false;
                        }),
                      ))
                  .toList(),
            ),
            if (_method == PaymentMethod.debt) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _debtorCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Kim qarzdor?',
                  errorText: _debtorMissing ? 'Ismni kiriting' : null,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: _suggestions
                    .map((n) => ActionChip(
                          label: Text(n),
                          backgroundColor: AppTheme.surface2,
                          labelStyle:
                              const TextStyle(color: AppTheme.textPrimary),
                          onPressed: () => _debtorCtrl.text = n,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish')),
        ElevatedButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
