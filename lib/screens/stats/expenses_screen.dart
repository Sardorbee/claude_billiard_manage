import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/blocs.dart';
import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

const _monthNames = [
  'Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun',
  'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr',
];

/// A month's expenses, with that month's sales and the profit left over.
class ExpensesScreen extends StatefulWidget {
  final String venueId;
  const ExpensesScreen({super.key, required this.venueId});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  int _dayEndHour = Venue.defaultDayEndHour;
  BusinessMonth? _month;
  Stream<List<Expense>>? _expenses;
  Future<double>? _sales;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final venue =
          await context.read<VenueRepository>().getVenue(widget.venueId);
      _dayEndHour = venue?.dayEndHour ?? Venue.defaultDayEndHour;
    } catch (_) {
      // Keep the default hour; the lists below surface real errors.
    }
    if (mounted) {
      _show(BusinessMonth.containing(DateTime.now(), _dayEndHour));
    }
  }

  void _show(BusinessMonth month) {
    final sessions = context.read<SessionRepository>();
    setState(() {
      _month = month;
      _expenses = context
          .read<ExpenseRepository>()
          .watchBetween(widget.venueId, month.start, month.end);
      _sales = sessions
          .getSessionsEndedBetween(widget.venueId, month.start, month.end)
          .then((list) => DailyReport.from(list, const []).totalSales);
    });
  }

  bool get _isCurrentMonth =>
      _month?.month ==
      BusinessMonth.containing(DateTime.now(), _dayEndHour).month;

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    final month = _month;
    if (user == null) return const SizedBox();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Xarajatlar')),
      // New expenses are dated now, so they only belong in the current month.
      floatingActionButton: _isCurrentMonth
          ? FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet(
                context: context,
                backgroundColor: AppTheme.surface,
                isScrollControlled: true,
                builder: (_) => _AddExpenseSheet(user: user),
              ),
              backgroundColor: AppTheme.green,
              foregroundColor: AppTheme.bg,
              icon: const Icon(Icons.add),
              label: const Text("Xarajat qo'shish",
                  style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: month == null
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.green))
          : Column(
              children: [
                _MonthPicker(
                  month: month,
                  onPrevious: () => _show(month.shifted(-1, _dayEndHour)),
                  onNext: _isCurrentMonth
                      ? null
                      : () => _show(month.shifted(1, _dayEndHour)),
                ),
                Expanded(
                  child: StreamBuilder<List<Expense>>(
                    stream: _expenses,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(
                            child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('${snap.error}',
                              style: const TextStyle(color: AppTheme.red)),
                        ));
                      }
                      if (!snap.hasData) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.green));
                      }
                      return _MonthView(
                        expenses: snap.data!,
                        sales: _sales,
                        canDelete: user.canManageDebts,
                        onDelete: _confirmDelete,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmDelete(Expense expense) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<ExpenseRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Xarajat o'chirilsinmi?"),
        content: Text('${expense.category} · ${formatCurrency(expense.amount)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Bekor qilish')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("O'CHIRISH"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.delete(widget.venueId, expense);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.red));
    }
  }
}

class _MonthPicker extends StatelessWidget {
  final BusinessMonth month;
  final VoidCallback onPrevious;
  final VoidCallback? onNext; // null on the current month
  const _MonthPicker(
      {required this.month, required this.onPrevious, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left), onPressed: onPrevious),
          Expanded(
            child: Text(
                '${_monthNames[month.month.month - 1]} ${month.month.year}',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      ),
    );
  }
}

class _MonthView extends StatelessWidget {
  final List<Expense> expenses;
  final Future<double>? sales;
  final bool canDelete;
  final ValueChanged<Expense> onDelete;
  const _MonthView({
    required this.expenses,
    required this.sales,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final spent = totalExpenses(expenses);
    final categories = expensesByCategory(expenses).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // Sales, expenses and what is left for the month.
        FutureBuilder<double>(
          future: sales,
          builder: (context, snap) {
            final revenue = snap.data;
            final profit = revenue == null ? null : revenue - spent;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  _SummaryRow(
                      'Savdo',
                      snap.hasError
                          ? '—'
                          : revenue == null
                              ? '...'
                              : formatCurrency(revenue)),
                  _SummaryRow('Xarajat', formatCurrency(spent),
                      color: AppTheme.amber),
                  const Divider(color: AppTheme.border),
                  _SummaryRow(
                    'Sof foyda',
                    profit == null ? '...' : formatCurrency(profit),
                    bold: true,
                    color: profit != null && profit < 0
                        ? AppTheme.red
                        : AppTheme.green,
                  ),
                ],
              ),
            );
          },
        ),

        if (categories.isNotEmpty) ...[
          const SectionHeader("TURLAR BO'YICHA"),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: categories
                  .map((c) => _SummaryRow(c.key, formatCurrency(c.value)))
                  .toList(),
            ),
          ),
        ],

        const SectionHeader('YOZUVLAR'),
        if (expenses.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(
                child: Text("Bu oyda xarajat yo'q",
                    style: TextStyle(color: AppTheme.textMuted))),
          ),
        ...expenses.map((e) => _ExpenseRow(
              expense: e,
              onDelete: canDelete ? () => onDelete(e) : null,
            )),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const _SummaryRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color:
                          bold ? AppTheme.textPrimary : AppTheme.textSecondary,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
                      fontSize: bold ? 15 : 13)),
            ),
            Text(value,
                style: TextStyle(
                    color: color ?? AppTheme.textPrimary,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    fontSize: bold ? 15 : 13)),
          ],
        ),
      );
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  final VoidCallback? onDelete; // null when the viewer may not delete
  const _ExpenseRow({required this.expense, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final details = [
      formatDate(expense.date),
      paymentLabel(expense.paymentMethod),
      if (expense.createdByName.isNotEmpty) expense.createdByName,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
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
                Text(
                    (expense.note ?? '').isEmpty
                        ? expense.category
                        : '${expense.category} · ${expense.note}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(details,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Text(formatCurrency(expense.amount),
              style: const TextStyle(
                  color: AppTheme.amber,
                  fontWeight: FontWeight.w800,
                  fontSize: 14)),
          if (onDelete != null)
            IconButton(
              tooltip: "O'chirish",
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: AppTheme.textMuted),
              onPressed: onDelete,
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }
}

// ─── Add an expense ──────────────────────────────────────────────────────────

class _AddExpenseSheet extends StatefulWidget {
  final AppUser user;
  const _AddExpenseSheet({required this.user});

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _category = Expense.categories.first;
  PaymentMethod _method = PaymentMethod.cash;
  String? _amountError;
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(
        _amountCtrl.text.replaceAll(RegExp(r'[\s,]'), ''));
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Summani kiriting');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final note = _noteCtrl.text.trim();
    setState(() => _saving = true);
    try {
      await context.read<ExpenseRepository>().add(
            widget.user.venueId,
            Expense(
              id: '',
              amount: amount,
              category: _category,
              note: note.isEmpty ? null : note,
              paymentMethod: _method,
              date: DateTime.now(),
              createdBy: widget.user.uid,
              createdByName: widget.user.name,
            ),
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(
          content: Text(
              "Xarajat qo'shildi · $_category · ${formatCurrency(amount)}")));
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.red));
    }
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: AppTheme.green,
        backgroundColor: AppTheme.surface2,
        labelStyle: TextStyle(
            color: selected ? AppTheme.bg : AppTheme.textPrimary,
            fontWeight: FontWeight.w700),
        onSelected: (_) => setState(onTap),
      );

  @override
  Widget build(BuildContext context) {
    const label =
        TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.1);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Xarajat qo'shish",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                  labelText: "Summa (so'm)", errorText: _amountError),
            ),
            const SizedBox(height: 16),
            const Text('TURI', style: label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Expense.categories
                  .map((c) => _chip(c, _category == c, () => _category = c))
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Text("QAYERDAN TO'LANDI", style: label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [PaymentMethod.cash, PaymentMethod.transfer]
                  .map((m) =>
                      _chip(paymentLabel(m), _method == m, () => _method = m))
                  .toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration:
                  const InputDecoration(labelText: 'Izoh (ixtiyoriy)'),
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
                    : const Text('SAQLASH'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
