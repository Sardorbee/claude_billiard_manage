import 'package:billiardtm/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

SessionModel _sale({
  String tableId = 't1',
  String status = 'completed',
  double finalTotal = 0,
  PaymentMethod? method,
  List<OrderItem> items = const [],
}) {
  final at = DateTime(2026, 10, 7, 22);
  return SessionModel(
    id: 's',
    tableId: tableId,
    tableName: tableId.isEmpty ? 'Counter' : 'Stol 1',
    startedAt: at,
    endedAt: at,
    guestCount: 2,
    hourlyRate: 40000,
    orderItems: items,
    status: status,
    openedBy: 'u',
    venueId: 'v',
    finalTotal: finalTotal,
    paymentMethod: method,
  );
}

DebtEntry _entry(DebtEntryType type, double amount, [PaymentMethod? method]) =>
    DebtEntry(
      id: 'e',
      customerId: 'c',
      customerName: 'Ali',
      type: type,
      amount: amount,
      paymentMethod: method,
      createdBy: 'u',
      createdByName: 'U',
      createdAt: DateTime(2026, 10, 7, 23),
    );

const _cola = OrderItem(
    menuItemId: 'cola',
    name: 'Cola',
    unitPrice: 10000,
    quantity: 2,
    category: 'Ichimliklar');
const _burger = OrderItem(
    menuItemId: 'burger',
    name: 'Burger',
    unitPrice: 30000,
    quantity: 1,
    category: 'Burger');

void main() {
  group('BusinessDay', () {
    test('an hour after midnight still belongs to the previous day', () {
      final day = BusinessDay.containing(DateTime(2026, 10, 8, 2), 6);
      expect(day.date, DateTime(2026, 10, 7));
      expect(day.start, DateTime(2026, 10, 7, 6));
      expect(day.end, DateTime(2026, 10, 8, 6));
    });

    test('the day rolls over exactly at the end hour', () {
      expect(BusinessDay.containing(DateTime(2026, 10, 8, 5, 59), 6).date,
          DateTime(2026, 10, 7));
      expect(BusinessDay.containing(DateTime(2026, 10, 8, 6), 6).date,
          DateTime(2026, 10, 8));
    });

    test('an end hour of 0 is a plain calendar day', () {
      final day = BusinessDay.containing(DateTime(2026, 10, 8, 2), 0);
      expect(day.start, DateTime(2026, 10, 8));
      expect(day.end, DateTime(2026, 10, 9));
    });
  });

  group('DailyReport', () {
    final report = DailyReport.from([
      // 40000 of table time + 50000 of food, paid in cash.
      _sale(finalTotal: 90000, method: PaymentMethod.cash, items: [_cola, _burger]),
      // 20000 of table time, paid by transfer.
      _sale(finalTotal: 20000, method: PaymentMethod.transfer),
      // 30000 of table time, on debt.
      _sale(finalTotal: 30000, method: PaymentMethod.debt),
      // Counter sale: two colas in cash.
      _sale(tableId: '', finalTotal: 20000, method: PaymentMethod.cash, items: [_cola]),
      _sale(status: 'voided', finalTotal: 99999),
    ], [
      _entry(DebtEntryType.payment, 15000, PaymentMethod.cash),
      _entry(DebtEntryType.payment, 5000, PaymentMethod.transfer),
      _entry(DebtEntryType.debt, 70000),
      _entry(DebtEntryType.writeoff, 8000),
    ]);

    test('table time, drinks and burgers are separate lines', () {
      expect(report.tableTime, 90000);
      expect(report.byCategory, {'Ichimliklar': 40000.0, 'Burger': 30000.0});
      expect(report.totalSales, 160000);
    });

    test('the lines add up to the money taken', () {
      final taken = report.salesByPayment.values.fold(0.0, (a, b) => a + b);
      expect(report.totalSales, taken + report.unknownPayment);
    });

    test('cash on hand is cash sales plus debts repaid in cash', () {
      expect(report.cashExpected, 90000 + 20000 + 15000);
      expect(report.transferExpected, 20000 + 5000);
      expect(report.soldOnDebt, 30000);
    });

    test('new debts and write-offs are not money received', () {
      expect(report.debtPayments.values.fold(0.0, (a, b) => a + b), 20000);
    });

    test('voided sessions are counted but bring no revenue', () {
      expect(report.voided, 1);
      expect(report.tableSessions, 3);
      expect(report.counterSales, 1);
    });

    test('items are totalled across sessions', () {
      final cola = report.items.firstWhere((i) => i.name == 'Cola');
      expect(cola.quantity, 4);
      expect(cola.amount, 40000);
    });
  });
}
