import 'package:billiardtm/app_theme.dart';
import 'package:billiardtm/bloc/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../models/models.dart';
import '../../widgets/widgets.dart';
import 'package:intl/intl.dart';

class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Bookings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateBookingSheet(context),
          ),
        ],
      ),
      body: BlocBuilder<BookingsBloc, BookingsState>(
        builder: (context, state) {
          if (state is BookingsLoading) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.green));
          }
          if (state is BookingsLoaded) {
            return Column(
              children: [
                // Calendar
                Container(
                  color: AppTheme.surface,
                  child: TableCalendar(
                    firstDay: DateTime.utc(2024, 1, 1),
                    lastDay: DateTime.utc(2027, 12, 31),
                    focusedDay: state.selectedDate,
                    selectedDayPredicate: (d) => isSameDay(d, state.selectedDate),
                    eventLoader: (day) {
                      final key = DateTime(day.year, day.month, day.day);
                      return state.eventsByDay[key] ?? [];
                    },
                    onDaySelected: (selected, focused) {
                      context.read<BookingsBloc>().add(BookingsDateSelected(selected));
                    },
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      defaultTextStyle: const TextStyle(color: AppTheme.textPrimary),
                      weekendTextStyle: const TextStyle(color: AppTheme.textPrimary),
                      selectedDecoration: BoxDecoration(color: AppTheme.green, borderRadius: BorderRadius.circular(4)),
                      todayDecoration: BoxDecoration(color: AppTheme.green.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                      todayTextStyle: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w700),
                      selectedTextStyle: const TextStyle(color: AppTheme.bg, fontWeight: FontWeight.w800),
                      markerDecoration: const BoxDecoration(color: AppTheme.green, shape: BoxShape.circle),
                      markerSize: 5,
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
                      leftChevronIcon: Icon(Icons.chevron_left, color: AppTheme.textMuted),
                      rightChevronIcon: Icon(Icons.chevron_right, color: AppTheme.textMuted),
                    ),
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      weekendStyle: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ),
                ),
                const Divider(color: AppTheme.border, height: 1),
                // Day bookings
                Expanded(
                  child: state.selectedDayBookings.isEmpty
                      ? _EmptyDay(date: state.selectedDate)
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: state.selectedDayBookings.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) => _BookingCard(booking: state.selectedDayBookings[i]),
                        ),
                ),
              ],
            );
          }
          return const SizedBox();
        },
      ),
    );
  }

  void _showCreateBookingSheet(BuildContext context) {
    final floorState = context.read<FloorBloc>().state;
    if (floorState is! FloorLoaded) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        side: BorderSide(color: AppTheme.border),
      ),
      builder: (_) => BlocProvider.value(
        value: context.read<BookingsBloc>(),
        child: _CreateBookingSheet(tables: floorState.allTables),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  final DateTime date;
  const _EmptyDay({required this.date});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_available, color: AppTheme.textMuted, size: 40),
          const SizedBox(height: 12),
          Text('No bookings for ${DateFormat('MMM d').format(date)}',
              style: const TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Booking'),
          ),
        ],
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;
  const _BookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: _statusBorderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(booking.guestName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (booking.guestPhone != null)
                      Text(booking.guestPhone!, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              StatusBadge(booking.status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _InfoChip(Icons.table_bar, booking.tableName),
              const SizedBox(width: 12),
              _InfoChip(Icons.access_time, '${DateFormat('h:mm a').format(booking.scheduledAt)} · ${booking.durationMinutes}min'),
              const SizedBox(width: 12),
              _InfoChip(Icons.person_outline, '${booking.guestCount} guests'),
            ],
          ),
          if (booking.notes != null && booking.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(booking.notes!, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ],
          if (booking.status == 'confirmed') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _updateStatus(context, 'cancelled'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.red,
                      side: const BorderSide(color: AppTheme.red),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('CANCEL', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _updateStatus(context, 'no_show'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.amber,
                      side: const BorderSide(color: AppTheme.amber),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('NO SHOW', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _updateStatus(context, 'completed'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                    child: const Text('CHECK IN', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color get _statusBorderColor {
    switch (booking.status) {
      case 'confirmed': return AppTheme.green.withOpacity(0.3);
      case 'cancelled': return AppTheme.red.withOpacity(0.3);
      case 'no_show': return AppTheme.amber.withOpacity(0.3);
      default: return AppTheme.border;
    }
  }

  void _updateStatus(BuildContext context, String status) {
    context.read<BookingsBloc>().add(BookingStatusUpdateRequested(
      bookingId: booking.id,
      status: status,
      tableId: booking.tableId,
    ));
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: AppTheme.textMuted),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
    ],
  );
}

class _CreateBookingSheet extends StatefulWidget {
  final List<TableModel> tables;
  const _CreateBookingSheet({required this.tables});
  @override State<_CreateBookingSheet> createState() => _CreateBookingSheetState();
}

class _CreateBookingSheetState extends State<_CreateBookingSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  TableModel? _selectedTable;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _duration = 60;
  int _guestCount = 2;
  double? _deposit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Booking', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 24),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Guest Name'), style: const TextStyle(color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone (optional)'), keyboardType: TextInputType.phone, style: const TextStyle(color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            // Table selector
            DropdownButtonFormField<TableModel>(
              value: _selectedTable,
              dropdownColor: AppTheme.surface2,
              decoration: const InputDecoration(labelText: 'Table'),
              items: widget.tables.map((t) => DropdownMenuItem(value: t, child: Text('${t.name} · ${t.zone}'))).toList(),
              onChanged: (t) => setState(() => _selectedTable = t),
            ),
            const SizedBox(height: 12),
            // Date & time row
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (d != null) setState(() => _selectedDate = d);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppTheme.surface2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(4)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today, size: 14, color: AppTheme.textMuted),
                        const SizedBox(width: 8),
                        Text(DateFormat('MMM d').format(_selectedDate), style: const TextStyle(color: AppTheme.textPrimary)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: _selectedTime);
                      if (t != null) setState(() => _selectedTime = t);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppTheme.surface2, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(4)),
                      child: Row(children: [
                        const Icon(Icons.access_time, size: 14, color: AppTheme.textMuted),
                        const SizedBox(width: 8),
                        Text(_selectedTime.format(context), style: const TextStyle(color: AppTheme.textPrimary)),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Duration
            DropdownButtonFormField<int>(
              value: _duration,
              dropdownColor: AppTheme.surface2,
              decoration: const InputDecoration(labelText: 'Duration'),
              items: [30, 60, 90, 120, 180, 240].map((m) => DropdownMenuItem(value: m, child: Text('$m minutes'))).toList(),
              onChanged: (d) => setState(() => _duration = d ?? 60),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              controller: _notesCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canCreate ? _create : null,
                child: const Text('CREATE BOOKING'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canCreate => _nameCtrl.text.isNotEmpty && _selectedTable != null;

  void _create() {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    if (user == null || _selectedTable == null) return;

    final scheduled = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _selectedTime.hour, _selectedTime.minute,
    );

    context.read<BookingsBloc>().add(BookingCreateRequested(Booking(
      id: '',
      tableId: _selectedTable!.id,
      tableName: _selectedTable!.name,
      guestName: _nameCtrl.text.trim(),
      guestPhone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      scheduledAt: scheduled,
      durationMinutes: _duration,
      guestCount: _guestCount,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdBy: user.uid,
      venueId: user.venueId,
    )));
    Navigator.pop(context);
  }
}