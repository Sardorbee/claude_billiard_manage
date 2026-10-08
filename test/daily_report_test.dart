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

  group('expenses and profit', () {
    Expense spent(double amount, String category, PaymentMethod method) =>
        Expense(
          id: 'x',
          amount: amount,
          category: category,
          paymentMethod: method,
          date: DateTime(2026, 10, 7, 21),
          createdBy: 'u',
          createdByName: 'U',
        );

    final report = DailyReport.from([
      _sale(finalTotal: 100000, method: PaymentMethod.cash),
      _sale(finalTotal: 50000, method: PaymentMethod.transfer),
    ], [], [
      spent(30000, 'Mahsulot xaridi', PaymentMethod.cash),
      spent(10000, 'Mahsulot xaridi', PaymentMethod.cash),
      spent(20000, 'Kommunal', PaymentMethod.transfer),
    ]);

    test('profit is sales minus expenses', () {
      expect(report.spent, 60000);
      expect(report.profit, 150000 - 60000);
    });

    test('expenses paid in cash reduce the cash on hand', () {
      expect(report.cashExpected, 100000 - 40000);
      expect(report.transferExpected, 50000 - 20000);
    });

    test('expenses are totalled per category', () {
      expect(expensesByCategory(report.expenses),
          {'Mahsulot xaridi': 40000.0, 'Kommunal': 20000.0});
    });

    test('a business month runs between the first-day rollovers', () {
      final month = BusinessMonth.containing(DateTime(2026, 11, 1, 3), 6);
      expect(month.month, DateTime(2026, 10));
      expect(month.start, DateTime(2026, 10, 1, 6));
      expect(month.end, DateTime(2026, 11, 1, 6));
      expect(month.shifted(3, 6).month, DateTime(2027, 1));
    });
  });

  group('TableHistory', () {
    test('sums completed sessions and only counts voided ones', () {
      final h = TableHistory.from([
        _sale(finalTotal: 50000, items: [
          const OrderItem(
              menuItemId: 'cola',
              name: 'Cola',
              unitPrice: 10000,
              quantity: 2,
              category: 'Ichimliklar'),
        ]),
        _sale(finalTotal: 40000),
        _sale(status: 'voided', finalTotal: 99000),
      ]);
      expect(h.completed, 2);
      expect(h.voided, 1);
      expect(h.extras, 20000);
      expect(h.tableTime, 70000);
      expect(h.total, 90000);
      expect(h.sessions, hasLength(3));
    });
  });

  test('a business year runs from 1 January at the day-end hour', () {
    final year = BusinessYear(2026, 6);
    expect(year.start, DateTime(2026, 1, 1, 6));
    expect(year.end, DateTime(2027, 1, 1, 6));
  });
}
