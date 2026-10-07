import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../blocs/blocs.dart';
import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

class SessionScreen extends StatelessWidget {
  final String tableId;
  final String sessionId;

  const SessionScreen(
      {super.key, required this.tableId, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SessionBloc, SessionState>(
      // A failed action on a running session is shown as a message; the
      // session view stays up instead of being replaced by the error page.
      buildWhen: (prev, curr) =>
          !(prev is SessionActive && curr is SessionError),
      listenWhen: (prev, curr) =>
          curr is! SessionError || prev is SessionActive,
      listener: (context, state) {
        if (state is SessionError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(state.message), backgroundColor: AppTheme.red));
        }
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
            body:
                Center(child: CircularProgressIndicator(color: AppTheme.green)),
          );
        }
        if (state is SessionActive) {
          return _ActiveSessionView(state: state);
        }
        if (state is SessionError) {
          return Scaffold(
            backgroundColor: AppTheme.bg,
            body: Center(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: AppTheme.red, size: 40),
                const SizedBox(height: 12),
                Text(state.message,
                    style: const TextStyle(color: AppTheme.red)),
                const SizedBox(height: 16),
                TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Orqaga')),
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
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: AppTheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: AppTheme.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 500, // control width
            ),
            child: _ReceiptSheet(
              session: session,
              onDone: () {
                Navigator.pop(context);
                ctx.pop();
              },
            ),
          ),
        );
      },
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
    final authState = context.watch<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
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
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppTheme.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                const Text('FAOL SEANS',
                    style: TextStyle(
                        color: AppTheme.green,
                        fontSize: 10,
                        letterSpacing: 0.1)),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            color: AppTheme.surface2,
            onSelected: (val) => _handleMenu(context, val),
            itemBuilder: (_) => [
              _menuItem('notes', Icons.note_outlined, "Izoh qo'shish"),
              if (user?.canApplyDiscount ?? false)
                _menuItem(
                    'discount', Icons.discount_outlined, 'Chegirma berish'),
              if (user?.canVoid ?? false)
                _menuItem('void', Icons.delete_outline, 'Seansni bekor qilish',
                    color: AppTheme.red),
            ],
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Splits history
          if (session.splits.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader("Bo'linishlar (${session.splits.length})"),
                    const SizedBox(height: 8),
                    ...session.splits.asMap().entries.map((e) {
                      final split = e.value;
                      final idx = e.key + 1;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          border: Border.all(
                              color: AppTheme.amber.withOpacity(0.35)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            // Split number badge
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppTheme.amber.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Center(
                                child: Text('$idx',
                                    style: const TextStyle(
                                        color: AppTheme.amber,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Payer name + time
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(split.payerName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                  Text(_formatTime(split.durationSeconds),
                                      style: const TextStyle(
                                          color: AppTheme.textMuted,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            // Charge
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(formatCurrency(split.timeCharge),
                                    style: const TextStyle(
                                        color: AppTheme.amber,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15)),
                                const Text('vaqt haqi',
                                    style: TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          // Timer section
          SliverToBoxAdapter(
            child: Container(
              color: AppTheme.surface,
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                children: [
                  TimerRing(
                    elapsedSeconds: state.elapsedSeconds,
                    isPaused: state.isPaused,
                    startedTime:
                        DateFormat('HH:mm').format(state.session.startedAt),
                    timeLabel: _formatTime(state.elapsedSeconds),
                    subLabel: formatCurrency(state.currentTimeCharge),
                  ),
                  _TimeLimitButton(state: state),
                  const SizedBox(height: 8),

                  // Quick actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ActionButton(
                        icon: state.isPaused ? Icons.play_arrow : Icons.pause,
                        label: state.isPaused ? 'DAVOM' : "TO'XTATISH",
                        onTap: () {
                          if (state.isPaused) {
                            context
                                .read<SessionBloc>()
                                .add(SessionResumeRequested());
                          } else {
                            context
                                .read<SessionBloc>()
                                .add(SessionPauseRequested());
                          }
                        },
                      ),
                      _ActionButton(
                        icon: Icons.call_split,
                        label: "BO'LISH",
                        color: AppTheme.amber,
                        onTap: () => _showSplitSheet(context),
                      ),
                      _ActionButton(
                        icon: Icons.swap_horiz,
                        label: "KO'CHIRISH",
                        onTap: () => _showTransferSheet(context),
                      ),
                      _ActionButton(
                        icon: Icons.note_add_outlined,
                        label: 'IZOH',
                        onTap: () => _handleMenu(context, 'notes'),
                      ),
                      _ActionButton(
                        icon: Icons.add_shopping_cart_outlined,
                        label: "QO'SHISH",
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
                child:
                    SectionHeader('Buyurtmalar (${session.orderItems.length})'),
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
                      const Icon(Icons.note,
                          color: AppTheme.textMuted, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(session.notes!,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13))),
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

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {Color? color}) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: color ?? AppTheme.textPrimary, fontSize: 14)),
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
        title: const Text('Seans izohi'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration:
              const InputDecoration(hintText: 'Seans uchun izoh yozing...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_), child: const Text('Bekor qilish')),
          ElevatedButton(
            onPressed: () {
              context.read<SessionBloc>().add(SessionNotesUpdated(ctrl.text));
              Navigator.pop(_);
            },
            child: const Text('Saqlash'),
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
              const Text('Chegirma berish',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [5, 10, 15, 20, 25, 50]
                    .map((pct) => GestureDetector(
                          onTap: () => setSt(() => discount = pct.toDouble()),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: discount == pct
                                  ? AppTheme.green.withOpacity(0.15)
                                  : AppTheme.surface2,
                              border: Border.all(
                                  color: discount == pct
                                      ? AppTheme.green
                                      : AppTheme.border),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('$pct%',
                                style: TextStyle(
                                    color: discount == pct
                                        ? AppTheme.green
                                        : AppTheme.textPrimary,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    context
                        .read<SessionBloc>()
                        .add(SessionDiscountApplied(discount));
                    Navigator.pop(_);
                  },
                  child: Text('${discount.toInt()}% CHEGIRMA BERISH'),
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
        title: const Text('Seans bekor qilinsinmi?'),
        content: const Text(
            "Seans bekor qilinadi va stol bo'shatiladi. Bu amalni qaytarib bo'lmaydi."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_), child: const Text('Bekor qilish')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.red,
                foregroundColor: AppTheme.textPrimary),
            onPressed: () {
              context.read<SessionBloc>().add(SessionVoidRequested());
              Navigator.pop(_);
            },
            child: const Text('BEKOR QILISH'),
          ),
        ],
      ),
    );
  }

  void _showSplitSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        side: BorderSide(color: AppTheme.border),
      ),
      builder: (_) => BlocProvider.value(
        value: context.read<SessionBloc>(),
        child: _SplitSheet(state: state),
      ),
    );
  }

  void _showTransferSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      // The sheet sits above this route in the widget tree, so it needs
      // the route's SessionBloc handed to it.
      builder: (_) => BlocProvider.value(
        value: context.read<SessionBloc>(),
        child: _TransferSheet(currentTableId: state.session.tableId),
      ),
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
        builder: (__, ctrl) => AddItemsSheet(
          controller: ctrl,
          onConfirm: (items) => context
              .read<SessionBloc>()
              .add(SessionAddItemsRequested(items)),
        ),
      ),
    );
  }
}

// Shows a fixed-time session's countdown; tapping it sets, extends or
// removes the limit.
class _TimeLimitButton extends StatelessWidget {
  final SessionActive state;
  const _TimeLimitButton({required this.state});

  @override
  Widget build(BuildContext context) {
    final remaining = state.remainingSeconds;
    final endsAt = state.session.plannedEndAt;
    return TextButton(
      onPressed: () => _showSheet(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 6),
          if (remaining == null)
            const Text("Vaqt cheklovi yo'q",
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13))
          else ...[
            TimeLeftLabel(remainingSeconds: remaining, fontSize: 13),
            Text(' · ${DateFormat('HH:mm').format(endsAt!)} gacha',
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  void _showSheet(BuildContext context) {
    final bloc = context.read<SessionBloc>();
    final endsAt = state.session.plannedEndAt;
    void apply(DateTime? end) {
      bloc.add(SessionPlannedEndChanged(end));
      Navigator.pop(context);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(endsAt == null ? 'Vaqt belgilash' : 'Vaqtni uzaytirish',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [30, 60, 90, 120]
                  .map((m) => ActionChip(
                        // An existing limit is pushed back; a new one counts
                        // from now.
                        label: Text(endsAt == null
                            ? 'Hozirdan ${durationLabel(m)}'
                            : '+${durationLabel(m)}'),
                        backgroundColor: AppTheme.surface2,
                        labelStyle: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700),
                        onPressed: () => apply((endsAt ?? DateTime.now())
                            .add(Duration(minutes: m))),
                      ))
                  .toList(),
            ),
            if (endsAt != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => apply(null),
                icon: const Icon(Icons.timer_off_outlined,
                    size: 18, color: AppTheme.red),
                label: const Text('Cheklovni olib tashlash',
                    style: TextStyle(color: AppTheme.red)),
              ),
            ],
          ],
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

  const _ActionButton(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.withOpacity(0.1),
              border: Border.all(color: c.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, color: c, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: c,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.08)),
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
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              Text('${formatCurrency(item.unitPrice)} × ${item.quantity}',
                  style:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          )),
          Text(formatCurrency(item.subtotal),
              style: const TextStyle(
                  color: AppTheme.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
        ],
      ),
    );
  }
}

class _BottomBillingBar extends StatelessWidget {
  final SessionActive state;
  const _BottomBillingBar({required this.state});

  String _fmt(int secs) {
    final h = (secs ~/ 3600).toString().padLeft(2, '0');
    final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
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
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BillRow("O'ynalgan vaqt (${_fmt(state.activeSeconds)})",
                      formatCurrency(state.activeTimeCharge)),
                  if (state.pausedSeconds > 0)
                    _BillRow("To'xtatilgan vaqt (${_fmt(state.pausedSeconds)})",
                        formatCurrency(state.pausedTimeCharge),
                        color: AppTheme.amber),
                  _BillRow('Mahsulotlar', formatCurrency(state.fbTotal)),
                  if (state.session.discount > 0)
                    _BillRow('Chegirma (${state.session.discount.toInt()}%)',
                        '-${formatCurrency(state.discountAmount)}',
                        color: AppTheme.green),
                ],
              )),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('JAMI SUMMA',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 9,
                          letterSpacing: 0.1)),
                  Text(formatCurrency(state.total),
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -1)),
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
              label: Text(
                  'HISOBNI YOPISH · ${formatCurrency(state.total)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, letterSpacing: 0.05)),
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

  Future<void> _showCheckoutConfirm(BuildContext context) async {
    final bloc = context.read<SessionBloc>();
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final user = authState.user;
    final debtorNames =
        context.read<DebtRepository>().customerNames(user.venueId);
    final choice = await showDialog<PaymentChoice>(
      context: context,
      builder: (_) => PaymentDialog(
        title: 'Hisobni yopish',
        confirmLabel: 'TASDIQLASH',
        debtorNames: debtorNames,
        summary: [
            _DialogRow('Stol', state.session.tableName),
            _DialogRow('Umumiy vaqt', formatTime(state.elapsedSeconds)),
            _DialogRow("O'ynalgan vaqt", formatTime(state.activeSeconds)),
            _DialogRow("O'ynalgan summa",
                formatCurrency(state.activeTimeCharge)),
            if (state.pausedSeconds > 0) ...[
              _DialogRow("To'xtatilgan vaqt", formatTime(state.pausedSeconds)),
              _DialogRow("To'xtatilgan summa",
                  formatCurrency(state.pausedTimeCharge),
                  color: AppTheme.amber),
            ],
            _DialogRow("Qo'shimcha", formatCurrency(state.fbTotal)),
            if (state.session.discount > 0)
              _DialogRow(
                  'Chegirma', '-${formatCurrency(state.discountAmount)}'),
            const Divider(color: AppTheme.border),
            _DialogRow(
              "To'xtatilgan summa",
              formatCurrency(state.pausedTimeCharge),
              color: AppTheme.amber,
              bold: true,
            ),
            _DialogRow(
              "O'ynalgan summa",
              formatCurrency(state.activeTimeCharge),
              bold: true,
            ),
            _DialogRow('Umumiy summa', formatCurrency(state.total),
                bold: true),
        ],
      ),
    );
    if (choice == null) return;
    bloc.add(SessionCheckoutRequested(choice.method,
        debtorName: choice.debtorName, closedBy: user, quote: state));
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
            Text('$label  ',
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            Text(value,
                style: TextStyle(
                    color: color ?? AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _DialogRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color; // ← add this
  const _DialogRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                  color: bold ? AppTheme.textPrimary : AppTheme.textMuted,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
                  fontSize: bold ? 15 : 13,
                )),
            Text(value,
                style: TextStyle(
                  color:
                      color ?? (bold ? AppTheme.green : AppTheme.textPrimary),
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  fontSize: bold ? 15 : 13,
                )),
          ],
        ),
      );
}

/// Menu picker. Hands the chosen items to [onConfirm] and closes; used for
/// both table orders and counter sales.
class AddItemsSheet extends StatefulWidget {
  final ScrollController controller;
  final String title;
  final String subtitle;
  final ValueChanged<List<OrderItem>> onConfirm;
  const AddItemsSheet({
    super.key,
    required this.controller,
    required this.onConfirm,
    this.title = "STOLGA QO'SHISH",
    this.subtitle = 'Seans uchun mahsulot tanlang',
  });
  @override
  State<AddItemsSheet> createState() => _AddItemsSheetState();
}

class _AddItemsSheetState extends State<AddItemsSheet> {
  final Map<String, int> _cart = {};
  String? _category;
  String _search = '';
  final _searchCtrl = TextEditingController();

  List<MenuItem> _filtered(List<MenuItem> all) {
    var items = all;
    if (_category != null) {
      items = items.where((i) => i.category == _category).toList();
    }
    if (_search.isNotEmpty) {
      items = items
          .where((i) => i.name.toLowerCase().contains(_search.toLowerCase()))
          .toList();
    }
    return items;
  }

  int get _totalItems => _cart.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MenuBloc, MenuState>(
      builder: (context, menuState) {
        final allItems =
            menuState is MenuLoaded ? menuState.allItems : <MenuItem>[];
        final categories = allItems.map((i) => i.category).toSet().toList()
          ..sort();
        final filtered = _filtered(allItems);

        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(widget.subtitle,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12)),
                  const SizedBox(height: 12),
                  // Search
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (q) => setState(() => _search = q),
                    decoration: const InputDecoration(
                      hintText: 'Mahsulot qidirish...',
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
                        _CategoryChip(
                            label: 'Hammasi',
                            selected: _category == null,
                            onTap: () => setState(() => _category = null)),
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
                      if (qty > 1) {
                        _cart[item.id] = qty - 1;
                      } else {
                        _cart.remove(item.id);
                      }
                    }),
                  );
                },
              ),
            ),
            // Confirm bar
            if (_totalItems > 0)
              Container(
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
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
                          Text('BUYURTMA',
                              style: TextStyle(
                                  color: AppTheme.textMuted.withOpacity(0.8),
                                  fontSize: 9,
                                  letterSpacing: 0.1)),
                          Text(
                              '$_totalItems ta · ${formatCurrency(_cartTotal(allItems))}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _confirmOrder(context, allItems),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('TASDIQLASH'),
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
      final item = items.firstWhere((i) => i.id == entry.key,
          orElse: () =>
              MenuItem(id: '', name: '', price: 0, category: '', venueId: ''));
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
    Navigator.pop(context);
    widget.onConfirm(orderItems);
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.green.withOpacity(0.15)
                  : AppTheme.surface2,
              border: Border.all(
                  color: selected ? AppTheme.green : AppTheme.border),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(label,
                style: TextStyle(
                    color: selected ? AppTheme.green : AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      );
}

class _SplitSheet extends StatefulWidget {
  final SessionActive state;
  const _SplitSheet({required this.state});
  @override
  State<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<_SplitSheet> {
  final _nameCtrl = TextEditingController();

  String _fmt(int secs) {
    final h = (secs ~/ 3600).toString().padLeft(2, '0');
    final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final splitCount = s.session.splits.length + 1;
    final legSeconds = s.currentLegSeconds;
    final legCharge = s.currentLegCharge;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.call_split,
                    color: AppTheme.amber, size: 18),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Bo'linish #$splitCount",
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  const Text('Bu qism uchun yutqazganni yozing',
                      style:
                          TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Current leg summary
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('QISM VAQTI',
                        style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 9,
                            letterSpacing: 0.1)),
                    const SizedBox(height: 4),
                    Text(_fmt(legSeconds),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18)),
                  ],
                ),
                Container(width: 1, height: 36, color: AppTheme.border),
                Column(
                  children: [
                    const Text('QISM SUMMASI',
                        style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 9,
                            letterSpacing: 0.1)),
                    const SizedBox(height: 4),
                    Text(formatCurrency(legCharge),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: AppTheme.amber)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Previous splits
          if (s.session.splits.isNotEmpty) ...[
            const Text("OLDINGI BO'LINISHLAR",
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    letterSpacing: 0.1)),
            const SizedBox(height: 8),
            ...s.session.splits.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppTheme.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Center(
                          child: Text('${e.key + 1}',
                              style: const TextStyle(
                                  color: AppTheme.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.value.payerName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Text(_fmt(e.value.durationSeconds),
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 12)),
                      const SizedBox(width: 10),
                      Text(formatCurrency(e.value.timeCharge),
                          style: const TextStyle(
                              color: AppTheme.amber,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
          ],

          // Loser name input
          const Text("BU QISMNI KIM TO'LAYDI?",
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.1)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Yutqazgan ismi...',
              prefixIcon: Icon(Icons.person_outline, size: 18),
            ),
          ),
          const SizedBox(height: 20),

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.amber,
                foregroundColor: AppTheme.bg,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                final name = _nameCtrl.text.trim();
                if (name.isEmpty) return;
                context
                    .read<SessionBloc>()
                    .add(SessionSplitRequested(name, quote: s));
                Navigator.pop(context);
              },
              icon: const Icon(Icons.call_split, size: 18),
              label: Text("BO'LISHNI YOZISH · ${formatCurrency(legCharge)}",
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferSheet extends StatelessWidget {
  final String currentTableId;
  const _TransferSheet({required this.currentTableId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FloorBloc, FloorState>(
      builder: (context, state) {
        if (state is! FloorLoaded) return const SizedBox();
        final openTables = state.allTables
            .where(
                (t) => t.status == TableStatus.open && t.id != currentTableId)
            .toList();
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Seansni ko'chirish",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Text('Qaysi stolga?',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              const SizedBox(height: 20),
              if (openTables.isEmpty)
                const Center(
                    child: Text("Bo'sh stol yo'q",
                        style: TextStyle(color: AppTheme.textMuted)))
              else
                ...openTables.map((t) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: AppTheme.surface2,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Icon(Icons.table_bar,
                            color: AppTheme.green, size: 18),
                      ),
                      title: Text(t.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(t.zone,
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 12)),
                      onTap: () {
                        context.read<SessionBloc>().add(
                            SessionTransferRequested(
                                toTableId: t.id, toTableName: t.name));
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
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: AppTheme.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.check, color: AppTheme.green, size: 22),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Seans yopildi',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text("Stol bo'shadi",
                      style: TextStyle(color: AppTheme.green, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: AppTheme.border),
          ...session.splits.asMap().entries.map((e) {
            final split = e.value;
            final idx = e.key + 1;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.amber.withOpacity(0.15),
                          border: Border.all(
                              color: AppTheme.amber.withOpacity(0.4)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text("BO'LINISH $idx",
                            style: const TextStyle(
                                color: AppTheme.amber,
                                fontSize: 9,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 8),
                      Text(split.payerName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                    ],
                  ),
                ),
                _DialogRow('Davomiyligi', formatTime(split.durationSeconds)),
                _DialogRow(
                    'Vaqt haqi', formatCurrency(split.timeCharge),
                    color: AppTheme.amber),
                const Divider(color: AppTheme.border),
              ],
            );
          }),

          // Remaining (current/last) leg — whoever was playing when checkout happened
          _DialogRow(
              'Qolgan vaqt', formatTime(session.currentLegSeconds.toInt())),
          _DialogRow('Qolgan vaqt summasi',
              formatCurrency(session.currentLegCharge)),
          _DialogRow("To'liq vaqt", formatTime(session.elapsedSeconds.toInt())),
          _DialogRow(
              "O'ynalgan vaqt",
              formatTime((session.elapsedSeconds - session.totalPausedSeconds)
                  .clamp(0, session.elapsedSeconds)
                  .toInt())),
          _DialogRow("O'ynalgan summa:",
              formatCurrency(session.activeTimeCharge)),
          if (session.totalPausedSeconds > 0) ...[
            _DialogRow(
                "To'xtatilgan vaqt:", formatTime(session.totalPausedSeconds)),
            _DialogRow("To'xtatilgan summa:",
                formatCurrency(session.pausedTimeCharge),
                color: AppTheme.amber),
          ],
          _DialogRow("Qo'shimcha", formatCurrency(session.fbTotal)),
          if (session.discount > 0)
            _DialogRow('Chegirma (${session.discount.toInt()}%)',
                '-${formatCurrency(session.discountAmount)}'),
          const Divider(color: AppTheme.border),
          _DialogRow("To'xtatilgan summa:",
              formatCurrency(session.pausedTimeCharge),
              color: AppTheme.amber, bold: true),
          _DialogRow(
            "O'ynalgan summa:",
            formatCurrency(session.activeTimeCharge),
            bold: true,
          ),
          _DialogRow(
              'Umumiy summa', formatCurrency(session.paidTotal),
              bold: true),
          if (session.paymentMethod != null)
            _DialogRow(
                "To'lov turi",
                session.paymentMethod == PaymentMethod.debt
                    ? '${paymentLabel(session.paymentMethod!)} · ${session.debtorName ?? ''}'
                    : paymentLabel(session.paymentMethod!)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onDone,
              child: const Text('YOPISH'),
            ),
          ),
        ],
      ),
    );
  }
}
