import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

/// The end-of-day report: what was sold, how it was paid, and how much
/// money should be on hand.
class DailyCloseScreen extends StatefulWidget {
  final String venueId;
  const DailyCloseScreen({super.key, required this.venueId});

  @override
  State<DailyCloseScreen> createState() => _DailyCloseScreenState();
}

class _DailyCloseScreenState extends State<DailyCloseScreen> {
  int _dayEndHour = Venue.defaultDayEndHour;
  BusinessDay? _day;
  Future<DailyReport>? _report;

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
      // Fall back to the default hour; the report itself will surface any
      // real connection problem.
    }
    if (mounted) _show(BusinessDay.containing(DateTime.now(), _dayEndHour));
  }

  void _show(BusinessDay day) {
    final sessions = context.read<SessionRepository>();
    final debts = context.read<DebtRepository>();
    setState(() {
      _day = day;
      _report = () async {
        final results = await Future.wait([
          sessions.getSessionsEndedBetween(widget.venueId, day.start, day.end),
          debts.getEntriesBetween(widget.venueId, day.start, day.end),
        ]);
        return DailyReport.from(
            results[0] as List<SessionModel>, results[1] as List<DebtEntry>);
      }();
    });
  }

  bool get _isCurrentDay {
    final today = BusinessDay.containing(DateTime.now(), _dayEndHour);
    return _day?.date == today.date;
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Kunlik hisobot'),
        actions: [
          if (day != null)
            IconButton(
              tooltip: 'Yangilash',
              icon: const Icon(Icons.refresh),
              onPressed: () => _show(day),
            ),
        ],
      ),
      body: day == null
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.green))
          : Column(
              children: [
                _DayPicker(
                  day: day,
                  onPrevious: () => _show(day.shifted(-1, _dayEndHour)),
                  onNext: _isCurrentDay
                      ? null
                      : () => _show(day.shifted(1, _dayEndHour)),
                ),
                Expanded(
                  child: FutureBuilder<DailyReport>(
                    future: _report,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.green));
                      }
                      if (snap.hasError) {
                        return Center(
                            child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('${snap.error}',
                              style: const TextStyle(color: AppTheme.red)),
                        ));
                      }
                      return _ReportView(report: snap.data!);
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _DayPicker extends StatelessWidget {
  final BusinessDay day;
  final VoidCallback onPrevious;
  final VoidCallback? onNext; // null on the current day
  const _DayPicker(
      {required this.day, required this.onPrevious, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('dd.MM HH:mm');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left), onPressed: onPrevious),
          Expanded(
            child: Column(
              children: [
                Text(DateFormat('dd.MM.yyyy').format(day.date),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                Text('${time.format(day.start)} – ${time.format(day.end)}',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  final DailyReport report;
  const _ReportView({required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final categories = r.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final repaidCash = r.debtPayments[PaymentMethod.cash] ?? 0;
    final repaidTransfer = r.debtPayments[PaymentMethod.transfer] ?? 0;
    final salesCash = r.salesByPayment[PaymentMethod.cash] ?? 0;
    final salesTransfer = r.salesByPayment[PaymentMethod.transfer] ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // What the worker should hand over / what should have arrived.
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'NAQD PUL',
                value: formatCurrency(r.cashExpected),
                valueColor: AppTheme.green,
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: "O'TKAZMA",
                value: formatCurrency(r.transferExpected),
                valueColor: AppTheme.blue,
                icon: Icons.phone_iphone,
              ),
            ),
          ],
        ),

        const SectionHeader('SAVDO'),
        _Card(children: [
          _Line('Stol vaqti', r.tableTime),
          ...categories.map((c) => _Line(c.key, c.value)),
          const Divider(color: AppTheme.border),
          _Line('Jami savdo', r.totalSales, bold: true),
        ]),

        const SectionHeader("TO'LOV TURI BO'YICHA"),
        _Card(children: [
          _Line('Naqd', salesCash),
          _Line("O'tkazma", salesTransfer),
          _Line('Qarzga', r.soldOnDebt, color: AppTheme.amber),
          if (r.unknownPayment > 0)
            _Line("Noma'lum", r.unknownPayment, color: AppTheme.textMuted),
        ]),

        if (repaidCash > 0 || repaidTransfer > 0) ...[
          const SectionHeader("QAYTARILGAN QARZLAR"),
          _Card(children: [
            if (repaidCash > 0) _Line('Naqd', repaidCash),
            if (repaidTransfer > 0) _Line("O'tkazma", repaidTransfer),
          ]),
        ],

        const SectionHeader('SOTILGAN MAHSULOTLAR'),
        _Card(children: [
          if (r.items.isEmpty)
            const Text("Mahsulot sotilmagan",
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ...r.items.map((i) => _Line('${i.quantity}× ${i.name}', i.amount)),
        ]),

        const SectionHeader('SEANSLAR'),
        _Card(children: [
          _Count('Stol seanslari', r.tableSessions),
          _Count('Stolsiz savdo', r.counterSales),
          _Count('Bekor qilingan', r.voided,
              color: r.voided > 0 ? AppTheme.red : null),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _Line extends StatelessWidget {
  final String label;
  final double amount;
  final bool bold;
  final Color? color;
  const _Line(this.label, this.amount, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => _Row(
      label: label, value: formatCurrency(amount), bold: bold, color: color);
}

class _Count extends StatelessWidget {
  final String label;
  final int count;
  final Color? color;
  const _Count(this.label, this.count, {this.color});

  @override
  Widget build(BuildContext context) =>
      _Row(label: label, value: '$count', color: color);
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const _Row(
      {required this.label, required this.value, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: bold ? AppTheme.textPrimary : AppTheme.textSecondary,
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
