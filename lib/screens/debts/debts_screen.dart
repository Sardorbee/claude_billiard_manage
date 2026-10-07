import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/blocs.dart';
import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

double? _parseAmount(String text) =>
    double.tryParse(text.replaceAll(RegExp(r'[\s,]'), ''));

// ─── Debtors list ────────────────────────────────────────────────────────────

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  Stream<List<Customer>>? _customers;
  String _search = '';
  bool _showSettled = false;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _customers = context
          .read<DebtRepository>()
          .watchCustomers(authState.user.venueId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    if (user == null) return const SizedBox();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('QARZLAR')),
      floatingActionButton: user.canManageDebts
          ? FloatingActionButton.extended(
              onPressed: () => _showAddDebt(context, user),
              backgroundColor: AppTheme.green,
              foregroundColor: AppTheme.bg,
              icon: const Icon(Icons.add),
              label: const Text("Qarz qo'shish",
                  style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: StreamBuilder<List<Customer>>(
        stream: _customers,
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
          final all = snap.data!;
          final owing = all.where((c) => c.owes).toList();
          final totalOwed = owing.fold(0.0, (sum, c) => sum + c.balance);
          final q = _search.trim().toLowerCase();
          final visible = (_showSettled ? all : owing)
              .where((c) =>
                  q.isEmpty ||
                  c.name.toLowerCase().contains(q) ||
                  (c.phone ?? '').contains(q))
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              StatCard(
                label: 'UMUMIY QARZ · ${owing.length} KISHI',
                value: formatCurrency(totalOwed),
                valueColor: totalOwed > 0 ? AppTheme.amber : AppTheme.green,
                icon: Icons.receipt_long_outlined,
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Ism yoki telefon',
                  prefixIcon: Icon(Icons.search, size: 18),
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: AppTheme.green,
                title: const Text("To'laganlarni ham ko'rsatish",
                    style:
                        TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                value: _showSettled,
                onChanged: (v) => setState(() => _showSettled = v),
              ),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(
                      child: Text("Qarzdorlar yo'q",
                          style: TextStyle(color: AppTheme.textMuted))),
                ),
              ...visible.map((c) => _CustomerRow(
                    customer: c,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _CustomerPage(
                            venueId: user.venueId, customerId: c.id))),
                  )),
            ],
          );
        },
      ),
    );
  }

  void _showAddDebt(BuildContext context, AppUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      builder: (_) => _AddDebtSheet(user: user),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;
  const _CustomerRow({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  Text(customer.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  if ((customer.phone ?? '').isNotEmpty)
                    Text(customer.phone!,
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 11)),
                ],
              ),
            ),
            Text(
              customer.owes ? formatCurrency(customer.balance) : "To'langan",
              style: TextStyle(
                  color: customer.owes ? AppTheme.amber : AppTheme.green,
                  fontWeight: FontWeight.w800,
                  fontSize: 15),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                color: AppTheme.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── One customer: balance, actions, history ─────────────────────────────────

class _CustomerPage extends StatefulWidget {
  final String venueId;
  final String customerId;
  const _CustomerPage({required this.venueId, required this.customerId});

  @override
  State<_CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<_CustomerPage> {
  late final DebtRepository _repo = context.read<DebtRepository>();
  late final Stream<Customer?> _customer =
      _repo.watchCustomer(widget.venueId, widget.customerId);
  late final Stream<List<DebtEntry>> _entries =
      _repo.watchEntries(widget.venueId, widget.customerId);

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    if (user == null) return const SizedBox();

    return StreamBuilder<Customer?>(
      stream: _customer,
      builder: (context, snap) {
        final customer = snap.data;
        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: AppBar(
            title: Text(customer?.name ?? ''),
            actions: [
              if (customer != null && user.canManageDebts)
                IconButton(
                  tooltip: 'Tahrirlash',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editCustomer(context, customer),
                ),
            ],
          ),
          body: customer == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.green))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    StatCard(
                      label: 'QARZ',
                      value: formatCurrency(customer.balance),
                      valueColor:
                          customer.owes ? AppTheme.amber : AppTheme.green,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    if ((customer.phone ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(customer.phone!,
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 13)),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: customer.owes
                            ? () => _reduce(context, customer, user,
                                DebtEntryType.payment)
                            : null,
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: const Text("TO'LOV QABUL QILISH"),
                      ),
                    ),
                    if (user.canManageDebts) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => showModalBottomSheet(
                                context: context,
                                backgroundColor: AppTheme.surface,
                                isScrollControlled: true,
                                builder: (_) => _AddDebtSheet(
                                    user: user, customer: customer),
                              ),
                              child: const Text("QARZ QO'SHISH"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: customer.owes
                                  ? () => _reduce(context, customer, user,
                                      DebtEntryType.writeoff)
                                  : null,
                              child: const Text('KECHISH'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    const SectionHeader('TARIX'),
                    StreamBuilder<List<DebtEntry>>(
                      stream: _entries,
                      builder: (context, entriesSnap) {
                        if (entriesSnap.hasError) {
                          return Text('${entriesSnap.error}',
                              style: const TextStyle(color: AppTheme.red));
                        }
                        final entries = entriesSnap.data ?? const [];
                        return Column(
                            children: entries
                                .map((e) => _EntryRow(entry: e))
                                .toList());
                      },
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _reduce(BuildContext context, Customer customer, AppUser user,
      DebtEntryType type) async {
    final messenger = ScaffoldMessenger.of(context);
    final isPayment = type == DebtEntryType.payment;
    final result = await showDialog<_ReduceResult>(
      context: context,
      builder: (_) => _ReduceDialog(customer: customer, isPayment: isPayment),
    );
    if (result == null) return;
    try {
      await _repo.reduceDebt(
        venueId: widget.venueId,
        customer: customer,
        type: type,
        amount: result.amount,
        paymentMethod: result.method,
        note: result.note,
        by: user,
      );
      messenger.showSnackBar(SnackBar(
          content: Text(isPayment
              ? "To'lov saqlandi · ${formatCurrency(result.amount)}"
              : 'Qarz kechildi · ${formatCurrency(result.amount)}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception:', '').trim()),
          backgroundColor: AppTheme.red));
    }
  }

  Future<void> _editCustomer(BuildContext context, Customer customer) async {
    final messenger = ScaffoldMessenger.of(context);
    final nameCtrl = TextEditingController(text: customer.name);
    final phoneCtrl = TextEditingController(text: customer.phone ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mijoz'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Ism')),
            const SizedBox(height: 12),
            TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Telefon')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Bekor qilish')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('SAQLASH')),
        ],
      ),
    );
    if (save != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await _repo.updateCustomer(widget.venueId, customer.id,
          name: nameCtrl.text, phone: phoneCtrl.text.trim());
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('$e'), backgroundColor: AppTheme.red));
    }
  }
}

class _EntryRow extends StatelessWidget {
  final DebtEntry entry;
  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isDebt = entry.type == DebtEntryType.debt;
    final label = switch (entry.type) {
      DebtEntryType.debt => 'Qarz',
      DebtEntryType.payment => entry.paymentMethod == null
          ? "To'lov"
          : "To'lov · ${paymentLabel(entry.paymentMethod!)}",
      DebtEntryType.writeoff => 'Kechildi',
    };
    final details = [
      formatDate(entry.createdAt),
      if (entry.createdByName.isNotEmpty) entry.createdByName,
      if ((entry.note ?? '').isNotEmpty) entry.note!,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(details,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Text(
            '${isDebt ? '+' : '−'}${formatCurrency(entry.amount)}',
            style: TextStyle(
                color: isDebt ? AppTheme.amber : AppTheme.green,
                fontWeight: FontWeight.w800,
                fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ─── Take a payment / write off ──────────────────────────────────────────────

typedef _ReduceResult = ({double amount, PaymentMethod? method, String? note});

class _ReduceDialog extends StatefulWidget {
  final Customer customer;
  final bool isPayment; // false = write-off
  const _ReduceDialog({required this.customer, required this.isPayment});

  @override
  State<_ReduceDialog> createState() => _ReduceDialogState();
}

class _ReduceDialogState extends State<_ReduceDialog> {
  // Starts at the full balance: paying everything is the common case.
  late final _amountCtrl = TextEditingController(
      text: widget.customer.balance.toStringAsFixed(
          widget.customer.balance % 1 == 0 ? 0 : 2));
  final _noteCtrl = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final amount = _parseAmount(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Summani kiriting');
      return;
    }
    if (amount > widget.customer.balance) {
      setState(() => _error =
          "Qarz faqat ${formatCurrency(widget.customer.balance)}");
      return;
    }
    final note = _noteCtrl.text.trim();
    Navigator.pop<_ReduceResult>(context, (
      amount: amount,
      method: widget.isPayment ? _method : null,
      note: note.isEmpty ? null : note,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isPayment ? "To'lov qabul qilish" : 'Qarzni kechish'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${widget.customer.name} · ${formatCurrency(widget.customer.balance)}',
                style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration:
                  InputDecoration(labelText: 'Summa', errorText: _error),
            ),
            if (widget.isPayment) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [PaymentMethod.cash, PaymentMethod.transfer]
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
                          onSelected: (_) => setState(() => _method = m),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Izoh'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish')),
        ElevatedButton(onPressed: _confirm, child: const Text('SAQLASH')),
      ],
    );
  }
}

// ─── Add a debt by hand ──────────────────────────────────────────────────────

class _AddDebtSheet extends StatefulWidget {
  final AppUser user;
  final Customer? customer; // null = choose or create one
  const _AddDebtSheet({required this.user, this.customer});

  @override
  State<_AddDebtSheet> createState() => _AddDebtSheetState();
}

class _AddDebtSheetState extends State<_AddDebtSheet> {
  late final _nameCtrl = TextEditingController(text: widget.customer?.name);
  final _phoneCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  List<String> _known = const [];
  String? _nameError, _amountError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.customer == null) {
      context
          .read<DebtRepository>()
          .customerNames(widget.user.venueId)
          .then((names) {
        if (mounted) setState(() => _known = names);
      }).catchError((_) {});
      _nameCtrl.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  List<String> get _suggestions {
    final q = _nameCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _known
        .where((n) => n.toLowerCase().contains(q) && n.toLowerCase() != q)
        .take(6)
        .toList();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = _parseAmount(_amountCtrl.text);
    setState(() {
      _nameError = name.isEmpty ? 'Ismni kiriting' : null;
      _amountError =
          amount == null || amount <= 0 ? 'Summani kiriting' : null;
    });
    if (_nameError != null || _amountError != null) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final note = _noteCtrl.text.trim();
    setState(() => _saving = true);
    try {
      await context.read<DebtRepository>().addDebt(
            venueId: widget.user.venueId,
            name: name,
            phone: _phoneCtrl.text.trim(),
            amount: amount!,
            note: note.isEmpty ? null : note,
            by: widget.user,
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(
          content: Text("Qarz qo'shildi · $name · ${formatCurrency(amount)}")));
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
          content: Text('$e'), backgroundColor: AppTheme.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fixedCustomer = widget.customer != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Qarz qo'shish",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 24),
            TextField(
              controller: _nameCtrl,
              enabled: !fixedCustomer,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration:
                  InputDecoration(labelText: 'Ism', errorText: _nameError),
            ),
            if (_suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  children: _suggestions
                      .map((n) => ActionChip(
                            label: Text(n),
                            backgroundColor: AppTheme.surface2,
                            labelStyle:
                                const TextStyle(color: AppTheme.textPrimary),
                            onPressed: () => _nameCtrl.text = n,
                          ))
                      .toList(),
                ),
              ),
            if (!fixedCustomer) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                    labelText: 'Telefon (ixtiyoriy)'),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                  labelText: 'Summa', errorText: _amountError),
            ),
            const SizedBox(height: 12),
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
