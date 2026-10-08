import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../blocs/blocs.dart';
import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

const _monthNames = [
  'Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun',
  'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr',
];

/// The history tab: the tables of the floor. Tapping one opens what
/// happened at it.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return const SizedBox();
    final venueId = authState.user.venueId;

    void open(String tableId, String tableName) => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => TableHistoryScreen(
                venueId: venueId, tableId: tableId, tableName: tableName)));

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Tarix')),
      body: BlocBuilder<FloorBloc, FloorState>(
        builder: (context, state) {
          if (state is FloorError) {
            return Center(
                child: Text(state.message,
                    style: const TextStyle(color: AppTheme.red)));
          }
          if (state is! FloorLoaded) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.green));
          }
          final zones = <String, List<TableModel>>{};
          for (final t in state.allTables) {
            zones.putIfAbsent(t.zone, () => []).add(t);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (final zone in zones.entries) ...[
                SectionHeader(zone.key.isEmpty ? 'Stollar' : zone.key),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.9,
                  children: zone.value
                      .map((t) => _TableTile(
                          table: t, onTap: () => open(t.id, t.name)))
                      .toList(),
                ),
              ],
              const SectionHeader('Stolsiz'),
              _Card(
                onTap: () => open('', SessionRepository.counterSaleName),
                child: const Row(
                  children: [
                    Icon(Icons.storefront_outlined,
                        color: AppTheme.textSecondary, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(SessionRepository.counterSaleName,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                    Icon(Icons.chevron_right, color: AppTheme.textMuted),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TableTile extends StatelessWidget {
  final TableModel table;
  final VoidCallback onTap;
  const _TableTile({required this.table, required this.onTap});

  @override
  Widget build(BuildContext context) => _Card(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(table.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                const Icon(Icons.history_rounded,
                    color: AppTheme.textMuted, size: 18),
              ],
            ),
            Text(
                '${tableTypeLabel(table.type)} · '
                '${formatCurrency(table.hourlyRate)}/soat',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ],
        ),
      );
}

// ─── ONE TABLE'S HISTORY ─────────────────────────────────────────────────────

enum _Period { day, month, year }

/// The closed sessions of one table for a day, a month or a year, with the
/// totals for that period. Tapping a session opens it on its own screen.
class TableHistoryScreen extends StatefulWidget {
  final String venueId;
  final String tableId; // empty for sales made without a table
  final String tableName;
  const TableHistoryScreen(
      {super.key,
      required this.venueId,
      required this.tableId,
      required this.tableName});

  @override
  State<TableHistoryScreen> createState() => _TableHistoryScreenState();
}

class _TableHistoryScreenState extends State<TableHistoryScreen> {
  int _dayEndHour = Venue.defaultDayEndHour;
  _Period _period = _Period.day;
  DateTime? _anchor; // a date inside the period being shown
  Future<TableHistory>? _history;

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
      // Keep the default hour; the list below surfaces real errors.
    }
    if (mounted) _show(_period, _today);
  }

  DateTime get _today =>
      BusinessDay.containing(DateTime.now(), _dayEndHour).date;

  ({DateTime start, DateTime end}) _range(_Period period, DateTime anchor) {
    switch (period) {
      case _Period.day:
        final day = BusinessDay.of(anchor, _dayEndHour);
        return (start: day.start, end: day.end);
      case _Period.month:
        final month = BusinessMonth(anchor, _dayEndHour);
        return (start: month.start, end: month.end);
      case _Period.year:
        final year = BusinessYear(anchor.year, _dayEndHour);
        return (start: year.start, end: year.end);
    }
  }

  void _show(_Period period, DateTime anchor) {
    final range = _range(period, anchor);
    final sessions = context.read<SessionRepository>();
    setState(() {
      _period = period;
      _anchor = anchor;
      _history = sessions
          .getTableSessionsEndedBetween(
              widget.venueId, widget.tableId, range.start, range.end)
          .then(TableHistory.from);
    });
  }

  void _shift(int by) {
    final a = _anchor!;
    _show(
        _period,
        switch (_period) {
          _Period.day => DateTime(a.year, a.month, a.day + by),
          _Period.month => DateTime(a.year, a.month + by),
          _Period.year => DateTime(a.year + by),
        });
  }

  // The period holding today is the last one; there is nothing after it.
  bool get _isCurrent {
    final range = _range(_period, _anchor!);
    final today = BusinessDay.of(_today, _dayEndHour).start;
    return !today.isBefore(range.start) && today.isBefore(range.end);
  }

  String get _label {
    final a = _anchor!;
    return switch (_period) {
      _Period.day => DateFormat('dd.MM.yyyy').format(a),
      _Period.month => '${_monthNames[a.month - 1]} ${a.year}',
      _Period.year => '${a.year}-yil',
    };
  }

  @override
  Widget build(BuildContext context) {
    final anchor = _anchor;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('${widget.tableName} · tarix'),
        actions: [
          if (anchor != null)
            IconButton(
              tooltip: 'Yangilash',
              icon: const Icon(Icons.refresh),
              onPressed: () => _show(_period, anchor),
            ),
        ],
      ),
      body: anchor == null
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.green))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      for (final (period, label) in const [
                        (_Period.day, 'Kunlik'),
                        (_Period.month, 'Oylik'),
                        (_Period.year, 'Yillik'),
                      ]) ...[
                        if (period != _Period.day) const SizedBox(width: 8),
                        Expanded(
                          child: _PeriodButton(
                            label: label,
                            selected: period == _period,
                            // Switching starts from the present, so
                            // "Kunlik" is never an arbitrary old day.
                            onTap: () => _show(period, _today),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: const BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: AppTheme.border))),
                  child: Row(
                    children: [
                      IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => _shift(-1)),
                      Expanded(
                        child: Text(_label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                      IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _isCurrent ? null : () => _shift(1)),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<TableHistory>(
                    future: _history,
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
                      return _HistoryView(
                        history: snap.data!,
                        isCounter: widget.tableId.isEmpty,
                        // A day's rows need only the time; longer periods
                        // need the date too.
                        showDate: _period != _Period.day,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _PeriodButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color:
                selected ? AppTheme.green.withOpacity(0.15) : AppTheme.surface,
            border:
                Border.all(color: selected ? AppTheme.green : AppTheme.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? AppTheme.green : AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
      );
}

class _HistoryView extends StatelessWidget {
  final TableHistory history;
  final bool isCounter;
  final bool showDate;
  const _HistoryView(
      {required this.history, required this.isCounter, required this.showDate});

  @override
  Widget build(BuildContext context) {
    final h = history;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: h.sessions.length + 1,
      itemBuilder: (context, index) {
        if (index > 0) {
          final session = h.sessions[index - 1];
          return _SessionRow(
            session: session,
            showDate: showDate,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SessionDetailScreen(session: session))),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Card(
              child: Column(
                children: [
                  _Line(isCounter ? 'Savdolar' : 'Seanslar', '${h.completed}'),
                  if (!isCounter) ...[
                    _Line("O'ynalgan vaqt", formatTime(h.playedSeconds.toInt())),
                    _Line('Stol vaqti', formatCurrency(h.tableTime)),
                  ],
                  _Line("Qo'shimcha", formatCurrency(h.extras)),
                  if (h.voided > 0)
                    _Line('Bekor qilingan', '${h.voided}',
                        color: AppTheme.red),
                  const Divider(color: AppTheme.border),
                  _Line('Jami', formatCurrency(h.total), bold: true),
                ],
              ),
            ),
            SectionHeader(isCounter ? 'Savdolar' : 'Seanslar'),
            if (h.sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(
                    child: Text("Bu davrda hech narsa bo'lmagan",
                        style: TextStyle(color: AppTheme.textMuted))),
              ),
          ],
        );
      },
    );
  }
}

class _SessionRow extends StatelessWidget {
  final SessionModel session;
  final bool showDate;
  final VoidCallback onTap;
  const _SessionRow(
      {required this.session, required this.showDate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final voided = s.status == 'voided';
    final end = s.endedAt ?? s.startedAt;
    final items = s.orderItems.fold(0, (sum, i) => sum + i.quantity);
    final when = s.isCounterSale
        ? formatTimeOnly(end)
        : '${formatTimeOnly(s.startedAt)} – ${formatTimeOnly(end)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Card(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      showDate
                          ? '${DateFormat('dd.MM.yyyy').format(s.startedAt)} · $when'
                          : when,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(
                      [
                        if (!s.isCounterSale)
                          formatTime(s.elapsedSeconds.toInt()),
                        if (items > 0) '$items ta mahsulot',
                        if (!voided && s.paymentMethod != null)
                          paymentLabel(s.paymentMethod!),
                      ].join(' · '),
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11)),
                ],
              ),
            ),
            if (voided)
              const _Badge('BEKOR QILINGAN', AppTheme.red)
            else
              Text(formatCurrency(s.paidTotal),
                  style: const TextStyle(
                      color: AppTheme.green,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            const Icon(Icons.chevron_right, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}

// ─── ONE SESSION ─────────────────────────────────────────────────────────────

/// Everything recorded about one closed session.
class SessionDetailScreen extends StatelessWidget {
  final SessionModel session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final voided = s.status == 'voided';
    final end = s.endedAt ?? s.startedAt;
    final method = s.paymentMethod;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text(s.tableName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(DateFormat('dd.MM.yyyy').format(s.startedAt),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              voided
                  ? const _Badge('BEKOR QILINGAN', AppTheme.red)
                  : const _Badge('YOPILGAN', AppTheme.blue),
            ],
          ),
          if (voided)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text("Seans bekor qilingan, pul olinmagan",
                  style: TextStyle(color: AppTheme.red, fontSize: 12)),
            ),

          if (s.isCounterSale) ...[
            const SectionHeader('Vaqt'),
            _Card(child: _Line('Sotilgan vaqti', formatDate(end))),
          ] else ...[
            const SectionHeader('Vaqt'),
            _Card(
              child: Column(children: [
                _Line('Boshlandi', formatDate(s.startedAt)),
                _Line('Tugadi', formatDate(end)),
                if (s.plannedEndAt != null)
                  _Line('Belgilangan vaqt', formatDate(s.plannedEndAt!)),
                _Line("To'liq vaqt", formatTime(s.elapsedSeconds.toInt())),
                _Line("O'ynalgan vaqt", formatTime(s.activeSeconds.toInt())),
                if (s.totalPausedSeconds > 0)
                  _Line("To'xtatilgan vaqt", formatTime(s.totalPausedSeconds),
                      color: AppTheme.amber),
                _Line('Soatlik narx', formatCurrency(s.hourlyRate)),
                _Line('Mehmonlar', '${s.guestCount}'),
              ]),
            ),
          ],

          if (s.splits.isNotEmpty) ...[
            const SectionHeader("O'yinlar"),
            _Card(
              child: Column(children: [
                for (final (i, split) in s.splits.indexed)
                  _Line(
                      '${i + 1}. ${split.payerName} · '
                      '${formatTime(split.durationSeconds)}',
                      formatCurrency(split.timeCharge),
                      note: splitTimes(split)),
                _Line(
                    'Oxirgi o\'yin · ${formatTime(s.currentLegSeconds.toInt())}',
                    formatCurrency(s.currentLegCharge),
                    note: '${formatTimeOnly(s.splits.last.splitAt)} – '
                        '${formatTimeOnly(end)}'),
              ]),
            ),
          ],

          const SectionHeader("Qo'shimcha"),
          _Card(
            child: Column(children: [
              if (s.orderItems.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Hech narsa olinmagan",
                      style:
                          TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                ),
              for (final i in s.orderItems)
                _Line(
                    '${i.quantity}× ${i.name}',
                    formatCurrency(i.subtotal),
                    note: i.quantity > 1
                        ? '${formatCurrency(i.unitPrice)} dan'
                        : null),
              if (s.orderItems.isNotEmpty) ...[
                const Divider(color: AppTheme.border),
                _Line("Jami qo'shimcha", formatCurrency(s.fbTotal)),
              ],
            ]),
          ),

          const SectionHeader('Hisob'),
          _Card(
            child: Column(children: [
              if (!s.isCounterSale) ...[
                _Line("O'ynalgan summa", formatCurrency(s.activeTimeCharge)),
                if (s.totalPausedSeconds > 0)
                  _Line("To'xtatilgan summa",
                      formatCurrency(s.pausedTimeCharge),
                      color: AppTheme.amber),
                if (s.discount > 0)
                  _Line('Chegirma (${s.discount.toInt()}%)',
                      '-${formatCurrency(s.discountAmount)}'),
              ],
              _Line("Qo'shimcha", formatCurrency(s.fbTotal)),
              const Divider(color: AppTheme.border),
              _Line('Umumiy summa', formatCurrency(s.paidTotal),
                  bold: true,
                  color: voided ? AppTheme.textMuted : AppTheme.green),
              if (!voided && method != null)
                _Line(
                    "To'lov turi",
                    method == PaymentMethod.debt
                        ? '${paymentLabel(method)} · ${s.debtorName ?? ''}'
                        : paymentLabel(method)),
            ]),
          ),

          if ((s.notes ?? '').isNotEmpty) ...[
            const SectionHeader('Izoh'),
            _Card(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(s.notes!,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── SHARED PIECES ───────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Card({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppTheme.border),
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: child,
          ),
        ),
      );
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final String? note; // small print under the label
  final bool bold;
  final Color? color;
  const _Line(this.label, this.value,
      {this.note, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: bold
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          fontWeight:
                              bold ? FontWeight.w800 : FontWeight.normal,
                          fontSize: bold ? 15 : 13)),
                  if (note != null)
                    Text(note!,
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(value,
                style: TextStyle(
                    color: color ?? AppTheme.textPrimary,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    fontSize: bold ? 15 : 13)),
          ],
        ),
      );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          border: Border.all(color: color.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.08)),
      );
}
