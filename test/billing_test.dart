import 'package:billiardtm/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

SessionModel _session({
  int minutes = 60,
  int pausedSeconds = 0,
  double discount = 0,
  List<OrderItem> items = const [],
  String tableId = 't1',
  double hourlyRate = 40000,
}) {
  final start = DateTime(2026, 1, 1, 20);
  return SessionModel(
    id: 's1',
    tableId: tableId,
    tableName: 'Table 1',
    startedAt: start,
    endedAt: start.add(Duration(minutes: minutes)),
    totalPausedSeconds: pausedSeconds,
    guestCount: 2,
    hourlyRate: hourlyRate,
    orderItems: items,
    discount: discount,
    status: 'completed',
    openedBy: 'u1',
    venueId: 'v1',
  );
}

const _cola = OrderItem(
    menuItemId: 'm1',
    name: 'Cola',
    unitPrice: 10000,
    quantity: 2,
    category: 'Ichimliklar');
const _burger = OrderItem(
    menuItemId: 'm2',
    name: 'Burger',
    unitPrice: 30000,
    quantity: 1,
    category: 'Burger');

void main() {
  test('one hour with no extras charges the hourly rate', () {
    final s = _session();
    expect(s.timeCharge, 40000);
    expect(s.total, 40000);
  });

  test('paused time is charged once, split from active time', () {
    final s = _session(minutes: 60, pausedSeconds: 900);
    expect(s.elapsedSeconds, 3600);
    expect(s.activeSeconds, 2700);
    expect(s.activeTimeCharge, 30000);
    expect(s.pausedTimeCharge, 10000);
    expect(s.timeCharge, 40000);
  });

  test('discount reduces table time only, not food and drink', () {
    final s = _session(discount: 50, items: [_cola, _burger]);
    expect(s.fbTotal, 50000);
    expect(s.discountAmount, 20000);
    expect(s.netTimeCharge, 20000);
    expect(s.total, 70000);
  });

  test('food and drink is totalled per category', () {
    final s = _session(items: [_cola, _burger]);
    expect(s.fbByCategory, {'Ichimliklar': 20000.0, 'Burger': 30000.0});
    expect(s.netTimeCharge + s.fbTotal, s.total);
  });

  test('a counter sale has no time charge', () {
    final s = _session(
        minutes: 0, tableId: '', hourlyRate: 0, items: [_cola, _burger]);
    expect(s.isCounterSale, isTrue);
    expect(s.timeCharge, 0);
    expect(s.total, 50000);
  });

  test('paidTotal prefers the amount stored at checkout', () {
    expect(_session().paidTotal, 40000);
    expect(_session().copyWith(finalTotal: 41000).paidTotal, 41000);
  });

  test('splits and the last leg add up to the whole session', () {
    final start = DateTime(2026, 1, 1, 20);
    final s = _session(minutes: 60).copyWith(splits: [
      SessionSplit(
          id: '1',
          payerName: 'Ali',
          durationSeconds: 1200,
          timeCharge: 1200 / 3600 * 40000,
          splitAt: start.add(const Duration(minutes: 20))),
      SessionSplit(
          id: '2',
          payerName: 'Vali',
          durationSeconds: 900,
          timeCharge: 900 / 3600 * 40000,
          splitAt: start.add(const Duration(minutes: 35))),
    ]);
    expect(s.currentLegSeconds, 3600 - 1200 - 900);
    expect(s.splitTotal + s.currentLegCharge, closeTo(s.timeCharge, 0.001));
  });
}
