// End-to-end checks of the app's real data layer against the Firebase
// emulators, with the security rules in force. Runs in Chrome:
//
//   firebase emulators:exec --only auth,firestore,database,storage \
//     "python3 tool/seed_emulator.py && \
//      flutter test --platform chrome test/emulator_flow_test.dart"
//
// The tests share one emulator state and run in order: first the admin's
// day, then what the worker may and may not do.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:billiardtm/blocs/blocs.dart';
import 'package:billiardtm/firebase_options.dart';
import 'package:billiardtm/models/models.dart';
import 'package:billiardtm/repositories/repositories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:firebase_database_web/firebase_database_web.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_web/firebase_storage_web.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

const venue = 'test-venue';

// A 1×1 PNG.
final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAIAAAUAAeIhvDMAAAAASUVORK5CYII=');

const cola = OrderItem(
    menuItemId: 'cola',
    name: 'Cola',
    unitPrice: 10000,
    quantity: 1,
    category: 'Ichimliklar');
const hotdog = OrderItem(
    menuItemId: 'hotdog',
    name: 'Hot-dog',
    unitPrice: 25000,
    quantity: 1,
    category: 'Non-dog');

final denied = throwsA(predicate((e) {
  final text = e.toString().toLowerCase();
  return text.contains('permission') || text.contains('unauthorized');
}, 'a permission-denied error'));

void main() {
  // Created in setUpAll: the repositories reach for Firebase as soon as
  // they are constructed.
  late final ActivityRepository activity;
  late final AuthRepository auth;
  late final TableRepository tables;
  late final DebtRepository debts;
  late final SessionRepository sessions;
  late final MenuRepository menu;
  late final ExpenseRepository expenses;
  late final VenueRepository venues;

  late AppUser admin;
  late AppUser worker;

  Future<AppUser> signIn(String email, String password) async {
    sessions.stopLive();
    final user = (await auth.signIn(email, password))!;
    activity.actor = user;
    return user;
  }

  Future<TableModel> table(String id) async =>
      (await tables.getTables(venue)).firstWhere((t) => t.id == id);

  Future<Map<String, dynamic>?> live(String tableId) =>
      sessions.watchLiveSession(venue, tableId).first
          .timeout(const Duration(seconds: 10));

  // Checks read straight from the server. The first value of a live stream
  // can come from the local cache, which a transaction's writes only reach
  // a moment later; the app's screens keep listening, a test must not guess.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> stored(
      String collection,
      {String? where,
      Object? equals}) async {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('venues')
        .doc(venue)
        .collection(collection);
    if (where != null) query = query.where(where, isEqualTo: equals);
    return (await query.get(const GetOptions(source: Source.server))).docs;
  }

  Future<List<String>> loggedTypes() async =>
      (await stored('activity')).map((d) => d['type'] as String).toList();

  Future<List<Customer>> customers() async =>
      (await stored('customers')).map(Customer.fromFirestore).toList();

  Future<Customer> customer(String name) async => (await customers())
      .firstWhere((c) => c.name.toLowerCase() == name.toLowerCase());

  Future<List<DebtEntry>> entriesOf(String customerId) async =>
      (await stored('debtEntries', where: 'customerId', equals: customerId))
          .map(DebtEntry.fromFirestore)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<List<MenuItem>> menuItems() async =>
      (await stored('menu')).map(MenuItem.fromFirestore).toList();

  // On the web a refusal raised inside a transaction arrives wrapped, with
  // its message hidden, so these only assert that the action was refused;
  // each test then checks nothing changed.
  final refused = throwsA(anything);

  // Closes a session as the app does: at a quoted elapsed time and total.
  Future<SessionModel> checkout(String sessionId, String tableId, AppUser by,
      {required int elapsedSeconds,
      required PaymentMethod method,
      String? debtor}) async {
    final current = await sessions.getSession(venue, sessionId);
    final quoted = current.copyWith(
        endedAt: current.startedAt.add(Duration(seconds: elapsedSeconds)));
    return sessions.checkoutSession(
      venueId: venue,
      sessionId: sessionId,
      tableId: tableId,
      session: quoted.copyWith(
          finalTotal: quoted.total,
          paymentMethod: method,
          debtorName: debtor),
      closedBy: by,
    );
  }

  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FirebaseCoreWeb.registerWith(webPluginRegistrar);
    FirebaseAuthWeb.registerWith(webPluginRegistrar);
    FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
    FirebaseDatabaseWeb.registerWith(webPluginRegistrar);
    FirebaseStorageWeb.registerWith(webPluginRegistrar);
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    await FirebaseAuth.instance.setPersistence(Persistence.NONE);
    AuthRepository.authEmulator = (host: 'localhost', port: 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    SessionRepository.liveDatabase.useDatabaseEmulator('localhost', 9000);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);

    activity = ActivityRepository();
    auth = AuthRepository(activity);
    tables = TableRepository(activity);
    debts = DebtRepository(activity);
    sessions = SessionRepository(debts, activity);
    menu = MenuRepository(activity);
    expenses = ExpenseRepository(activity);
    venues = VenueRepository(activity);
  });

  group('admin', () {
    late SessionModel timed; // 30-minute session, starts on table-1
    late SessionModel other;

    test('a wrong password is refused with a readable message', () async {
      Object? error;
      try {
        await auth.signIn('admin@test.local', 'not-the-password');
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(authErrorText(error!), "Email yoki parol noto'g'ri");
      expect(FirebaseAuth.instance.currentUser, isNull);
    });

    test('signs in', () async {
      admin = await signIn('admin@test.local', 'test-admin-4821');
      expect(admin.role, UserRole.owner);
      expect(admin.canAccessAdmin, isTrue);
    });

    test('opens a fixed-time session', () async {
      timed = await sessions.openSession(
          venueId: venue,
          table: await table('table-1'),
          guestCount: 2,
          openedBy: admin.uid,
          plannedMinutes: 30);
      final t = await table('table-1');
      expect(t.status, TableStatus.active);
      expect(t.currentSessionId, timed.id);
      expect(t.sessionEndsAt!.difference(DateTime.now()).inMinutes,
          inInclusiveRange(29, 30));
      final stored = await sessions.getSession(venue, timed.id);
      expect(stored.status, 'active');
      expect(stored.plannedEndAt, t.sessionEndsAt);
      expect((await live('table-1'))?['sessionId'], timed.id);
    });

    test('refuses a second session on the same table', () async {
      // The stale table object still says "open", as a second phone's would.
      final stale = (await table('table-1')).copyWith(status: TableStatus.open);
      await expectLater(
          sessions.openSession(
              venueId: venue, table: stale, guestCount: 2, openedBy: admin.uid),
          refused);
      expect((await table('table-1')).currentSessionId, timed.id);
    });

    test('keeps both orders when two are added at once', () async {
      await Future.wait([
        sessions.addOrderItems(venue, timed.id, [cola]),
        sessions.addOrderItems(venue, timed.id, [cola, hotdog]),
      ]);
      final items = (await sessions.getSession(venue, timed.id)).orderItems;
      expect(items.firstWhere((i) => i.menuItemId == 'cola').quantity, 2);
      expect(items.firstWhere((i) => i.menuItemId == 'hotdog').quantity, 1);
    });

    test('pauses and resumes, recording the paused time', () async {
      await sessions.pauseSession(venue, 'table-1', timed.id);
      final paused = (await live('table-1'))!;
      expect(paused['status'], 'paused');
      await Future<void>.delayed(const Duration(seconds: 2));
      await sessions.resumeSession(
          venue, 'table-1', timed.id, paused['pausedAt'] as int);
      final resumed = (await live('table-1'))!;
      expect(resumed['status'], 'active');
      expect(resumed['pausedAt'], isNull);
      expect(resumed['totalPausedMs'], greaterThanOrEqualTo(1900));
    });

    test('extends and removes the time limit', () async {
      final later = DateTime.now().add(const Duration(hours: 2));
      await sessions.setPlannedEnd(venue, timed.id, 'table-1', later);
      expect((await table('table-1')).sessionEndsAt!.difference(later).inSeconds,
          0);
      await sessions.setPlannedEnd(venue, timed.id, 'table-1', null);
      expect((await table('table-1')).sessionEndsAt, isNull);
      expect((await sessions.getSession(venue, timed.id)).plannedEndAt, isNull);
      await sessions.setPlannedEnd(venue, timed.id, 'table-1', later);
    });

    test('transfers to a free table, taking timer and time limit along',
        () async {
      final before = (await live('table-1'))!;
      await sessions.transferSession(
          venue, timed.id, 'table-1', 'table-2', 'Stol 2');
      final from = await table('table-1');
      final to = await table('table-2');
      expect(from.status, TableStatus.open);
      expect(from.currentSessionId, isNull);
      expect(from.sessionEndsAt, isNull);
      expect(to.status, TableStatus.active);
      expect(to.currentSessionId, timed.id);
      expect(to.sessionEndsAt, isNotNull);
      expect((await sessions.getSession(venue, timed.id)).tableName, 'Stol 2');
      expect((await live('table-2'))?['startedAt'], before['startedAt']);
      expect(await live('table-1'), isNull);
    });

    test('refuses to transfer onto an occupied table', () async {
      other = await sessions.openSession(
          venueId: venue,
          table: await table('table-1'),
          guestCount: 2,
          openedBy: admin.uid);
      await expectLater(
          sessions.transferSession(
              venue, timed.id, 'table-2', 'table-1', 'Stol 1'),
          refused);
      expect((await table('table-1')).currentSessionId, other.id);
      expect((await table('table-2')).currentSessionId, timed.id);
    });

    test('applies a discount to table time only', () async {
      await sessions.applyDiscount(venue, timed.id, 50, tableName: 'Stol 2');
      final s = (await sessions.getSession(venue, timed.id)).copyWith(
          endedAt: timed.startedAt.add(const Duration(hours: 1)));
      expect(s.timeCharge, 40000);
      expect(s.fbTotal, 45000);
      expect(s.discountAmount, 20000);
      expect(s.total, 65000);
    });

    test('checks out on debt: session, table and ledger agree', () async {
      final closed = await checkout(timed.id, 'table-2', admin,
          elapsedSeconds: 3600, method: PaymentMethod.debt, debtor: 'Ali');
      expect(closed.status, 'completed');
      final stored = await sessions.getSession(venue, timed.id);
      expect(stored.status, 'completed');
      expect(stored.finalTotal, 65000);
      expect(stored.paymentMethod, PaymentMethod.debt);
      expect(stored.debtorName, 'Ali');
      expect(stored.elapsedSeconds, 3600);
      final t = await table('table-2');
      expect(t.status, TableStatus.open);
      expect(t.currentSessionId, isNull);
      expect(t.sessionEndsAt, isNull);
      expect(await live('table-2'), isNull);
      final ali = await customer('Ali');
      expect(ali.balance, 65000);
      final entries = await entriesOf(ali.id);
      expect(entries.single.type, DebtEntryType.debt);
      expect(entries.single.sessionId, timed.id);
    });

    test('refuses to check out the same session twice', () async {
      await expectLater(
          checkout(timed.id, 'table-2', admin,
              elapsedSeconds: 3600, method: PaymentMethod.cash),
          refused);
      expect((await customer('Ali')).balance, 65000);
    });

    test('voids a session', () async {
      await sessions.voidSession(venue, other.id, 'table-1');
      expect((await sessions.getSession(venue, other.id)).status, 'voided');
      expect((await table('table-1')).status, TableStatus.open);
      expect(await live('table-1'), isNull);
    });

    test('records splits through the session screen logic', () async {
      final bloc = SessionBloc(sessions);
      bloc.add(SessionOpenRequested(
          venueId: venue,
          table: await table('table-1'),
          guestCount: 2,
          openedBy: admin.uid));
      SessionActive active() => bloc.state as SessionActive;
      await bloc.stream
          .firstWhere((s) => s is SessionActive && s.elapsedSeconds >= 2)
          .timeout(const Duration(seconds: 15));

      final first = active();
      bloc.add(SessionSplitRequested('Vali', quote: first));
      await bloc.stream
          .firstWhere((s) => s is SessionActive && s.session.splits.length == 1)
          .timeout(const Duration(seconds: 10));
      expect(active().session.splits.single.durationSeconds,
          first.elapsedSeconds);

      await bloc.stream
          .firstWhere((s) =>
              s is SessionActive && s.elapsedSeconds >= first.elapsedSeconds + 2)
          .timeout(const Duration(seconds: 15));
      bloc.add(SessionAddItemsRequested(const [cola]));
      await bloc.stream
          .firstWhere((s) => s is SessionActive && s.session.orderItems.isNotEmpty)
          .timeout(const Duration(seconds: 10));

      // The quote: the bill as the checkout dialog would show it.
      final quote = active();
      expect(quote.currentLegSeconds,
          quote.elapsedSeconds - first.elapsedSeconds);
      await Future<void>.delayed(const Duration(seconds: 2));
      bloc.add(SessionCheckoutRequested(PaymentMethod.cash,
          closedBy: admin, quote: quote));
      final done = await bloc.stream
          .firstWhere((s) => s is SessionCompleted)
          .timeout(const Duration(seconds: 10)) as SessionCompleted;

      // Charged what was quoted, not what the clock had reached by then.
      final stored = await sessions.getSession(venue, done.session.id);
      expect(stored.finalTotal, quote.total);
      expect(stored.elapsedSeconds, quote.elapsedSeconds);
      expect(stored.paymentMethod, PaymentMethod.cash);
      expect(stored.splits.single.payerName, 'Vali');
      expect(stored.splitTotal + stored.currentLegCharge,
          closeTo(stored.timeCharge, 0.001));
      expect((await table('table-1')).status, TableStatus.open);
      await bloc.close();
    });

    test('saves counter sales, in cash and on debt', () async {
      final cash = await sessions.createCounterSale(
          venueId: venue,
          items: [cola.copyWith(quantity: 2)],
          paymentMethod: PaymentMethod.cash,
          soldBy: admin);
      expect(cash.isCounterSale, isTrue);
      expect((await sessions.getSession(venue, cash.id)).finalTotal, 20000);

      // "ali" must land on the same customer as "Ali".
      await sessions.createCounterSale(
          venueId: venue,
          items: [hotdog],
          paymentMethod: PaymentMethod.debt,
          debtorName: 'ali',
          soldBy: admin);
      expect(
          (await customers()).where((c) => c.name.toLowerCase() == 'ali').length,
          1);
      expect((await customer('Ali')).balance, 65000 + 25000);
    });

    test('runs a customer debt from entry to settled', () async {
      await debts.addDebt(
          venueId: venue,
          name: 'Bek',
          phone: '901234567',
          amount: 10000,
          note: 'eski qarz',
          by: admin);
      var bek = await customer('Bek');
      expect(bek.balance, 10000);
      expect(bek.phone, '901234567');

      await expectLater(
          debts.reduceDebt(
              venueId: venue,
              customer: bek,
              type: DebtEntryType.payment,
              amount: 10001,
              paymentMethod: PaymentMethod.cash,
              by: admin),
          refused);

      await debts.reduceDebt(
          venueId: venue,
          customer: bek,
          type: DebtEntryType.payment,
          amount: 4000,
          paymentMethod: PaymentMethod.transfer,
          by: admin);
      await debts.reduceDebt(
          venueId: venue,
          customer: bek,
          type: DebtEntryType.writeoff,
          amount: 6000,
          by: admin);
      bek = await customer('Bek');
      expect(bek.balance, 0);
      expect(bek.owes, isFalse);
      final entries = await entriesOf(bek.id);
      expect(entries.map((e) => e.type), [
        DebtEntryType.writeoff,
        DebtEntryType.payment,
        DebtEntryType.debt,
      ]);

      await debts.updateCustomer(venue, bek.id, name: 'Bekzod', phone: '99');
      expect((await customer('Bekzod')).phone, '99');
      expect(await debts.customerNames(venue), containsAll(['Ali', 'Bekzod']));
    });

    test('records, lists and deletes expenses', () async {
      Expense spend(double amount, String category, PaymentMethod method) =>
          Expense(
              id: '',
              amount: amount,
              category: category,
              paymentMethod: method,
              date: DateTime.now(),
              createdBy: admin.uid,
              createdByName: admin.name);
      await expenses.add(venue, spend(30000, 'Mahsulot xaridi', PaymentMethod.cash));
      await expenses.add(venue, spend(7000, 'Kommunal', PaymentMethod.transfer));
      await expenses.add(venue, spend(1, 'Boshqa', PaymentMethod.cash));
      final day = BusinessDay.containing(DateTime.now(), 6);
      var list = await expenses.getBetween(venue, day.start, day.end);
      expect(list.length, 3);
      await expenses.delete(venue, list.firstWhere((e) => e.amount == 1));
      list = await expenses.getBetween(venue, day.start, day.end);
      expect(totalExpenses(list), 37000);
    });

    test('daily report adds up from the stored data', () async {
      final day = BusinessDay.containing(DateTime.now(), 6);
      // The timed session was closed at start + 1h, which may fall just past
      // "now"; the window is the business day either way.
      final report = DailyReport.from(
        await sessions.getSessionsEndedBetween(venue, day.start, day.end),
        await debts.getEntriesBetween(venue, day.start, day.end),
        await expenses.getBetween(venue, day.start, day.end),
      );
      expect(report.voided, 1);
      expect(report.tableSessions, 2);
      expect(report.counterSales, 2);
      // Lines add up to the money taken.
      final taken =
          report.salesByPayment.values.fold(0.0, (a, b) => a + b);
      expect(report.totalSales, closeTo(taken, 0.001));
      expect(report.unknownPayment, 0);
      // 65 000 timed session + 25 000 counter sale, both on debt.
      expect(report.soldOnDebt, 90000);
      expect(report.byCategory['Non-dog'], 50000);
      // Cash: split session + 20 000 counter sale − 30 000 expense.
      final cashSales = report.salesByPayment[PaymentMethod.cash]!;
      expect(report.cashExpected, cashSales - 30000);
      // Transfer: Bek's 4 000 repayment − 7 000 expense.
      expect(report.transferExpected, 4000 - 7000);
      expect(report.spent, 37000);
      expect(report.profit, report.totalSales - 37000);
      final colas = report.items.firstWhere((i) => i.name == 'Cola');
      expect(colas.quantity, 2 + 1 + 2);
    });

    test('manages tables', () async {
      final added = await tables.addTable(
          venue,
          const TableModel(
              id: '',
              name: 'Stol 3',
              zone: 'Zal',
              type: TableType.ps,
              status: TableStatus.open,
              hourlyRate: 50000,
              capacity: 4));
      await tables.updateTable(venue, added.copyWith(hourlyRate: 60000),
          previous: added);
      expect((await table(added.id)).hourlyRate, 60000);
      await tables.updateTable(
          venue, added.copyWith(status: TableStatus.maintenance));
      expect((await table(added.id)).status, TableStatus.maintenance);
      await tables.deleteTable(venue, added);
      final visible =
          (await tables.getTables(venue)).where((t) => t.isActive).toList();
      expect(visible.any((t) => t.id == added.id), isFalse);
      expect(visible.length, 2);
    });

    test('manages the menu, categories and a photo', () async {
      await venues.setMenuCategories(venue, ['Ichimliklar', 'Non-dog', 'Burger']);
      expect((await venues.getVenue(venue))!.menuCategories, contains('Burger'));

      final added = await menu.addItem(
          venue,
          const MenuItem(
              id: '',
              name: 'Burger',
              price: 30000,
              category: 'Burger',
              venueId: venue),
          image: (bytes: png, contentType: 'image/png'));
      expect(added.imageUrl, isNotNull);

      final edited = added.copyWith(name: 'Chizburger', price: 35000);
      await menu.updateItem(venue, edited, previous: added);
      await menu.setItemImage(
          venue, edited, (bytes: png, contentType: 'image/png'));
      await menu.toggleAvailability(venue, added.id, false);
      var item = (await menuItems()).firstWhere((i) => i.id == added.id);
      expect(item.name, 'Chizburger');
      expect(item.price, 35000);
      expect(item.isAvailable, isFalse);
      expect(item.imageUrl, isNot(added.imageUrl));

      await menu.removeItemImage(venue, item);
      item = (await menuItems()).firstWhere((i) => i.id == added.id);
      expect(item.imageUrl, isNull);
      await menu.deleteItem(venue, item);
      expect((await menuItems()).any((i) => i.id == added.id), isFalse);
    });

    test('changes the day-end hour', () async {
      await venues.setDayEndHour(venue, 5);
      expect((await venues.getVenue(venue))!.dayEndHour, 5);
      await venues.setDayEndHour(venue, 6);
    });

    test('adds a staff account without being signed out', () async {
      final created = await auth.createUser(
          email: 'new-worker@test.local',
          password: 'test-new-5521',
          name: 'New Worker',
          role: UserRole.staff,
          venueId: venue);
      expect(FirebaseAuth.instance.currentUser!.uid, admin.uid);
      expect((await auth.getUser(created.uid))!.role, UserRole.staff);
      final staff = await FirebaseFirestore.instance
          .collection('users')
          .where('venueId', isEqualTo: venue)
          .get(const GetOptions(source: Source.server));
      expect(staff.docs.map((d) => d.id), contains(created.uid));
      expect(staff.docs.length, 3);
    });

    test('the activity log has every sensitive action', () async {
      expect(
          await loggedTypes(),
          containsAll([
            ActivityType.sessionTransferred,
            ActivityType.discountApplied,
            ActivityType.sessionVoided,
            ActivityType.debtAdded,
            ActivityType.debtWrittenOff,
            ActivityType.expenseDeleted,
            ActivityType.tableAdded,
            ActivityType.tableRateChanged,
            ActivityType.tableDeleted,
            ActivityType.menuItemAdded,
            ActivityType.menuItemPriceChanged,
            ActivityType.menuItemDeleted,
            ActivityType.dayEndChanged,
            ActivityType.staffCreated,
          ]));
    });
  });

  group('worker', () {
    late SessionModel session;

    test('signs in as staff', () async {
      await auth.signOut();
      worker = await signIn('worker@test.local', 'test-worker-7359');
      expect(worker.role, UserRole.staff);
      expect(worker.canAccessAdmin, isFalse);
      expect(worker.canVoid, isFalse);
      expect(worker.canApplyDiscount, isFalse);
    });

    test('runs a normal session', () async {
      session = await sessions.openSession(
          venueId: venue,
          table: await table('table-1'),
          guestCount: 2,
          openedBy: worker.uid,
          plannedMinutes: 60);
      await sessions.addOrderItems(venue, session.id, [cola]);
      await sessions.updateSessionNotes(venue, session.id, 'deraza yonida');
      await sessions.setPlannedEnd(venue, session.id, 'table-1',
          DateTime.now().add(const Duration(hours: 2)));
      await sessions.transferSession(
          venue, session.id, 'table-1', 'table-2', 'Stol 2');
      expect((await table('table-2')).currentSessionId, session.id);
    });

    test('cannot discount or void', () async {
      await expectLater(
          sessions.applyDiscount(venue, session.id, 50, tableName: 'Stol 2'),
          denied);
      await expectLater(sessions.voidSession(venue, session.id, 'table-2'), denied);
      final stored = await sessions.getSession(venue, session.id);
      expect(stored.discount, 0);
      expect(stored.status, 'active');
    });

    test('checks out and sells at the counter', () async {
      final closed = await checkout(session.id, 'table-2', worker,
          elapsedSeconds: 1800, method: PaymentMethod.transfer);
      expect(closed.status, 'completed');
      final stored = await sessions.getSession(venue, session.id);
      expect(stored.finalTotal, 20000 + 10000);
      expect(stored.notes, 'deraza yonida');
      expect((await table('table-2')).status, TableStatus.open);
      final sale = await sessions.createCounterSale(
          venueId: venue,
          items: [cola],
          paymentMethod: PaymentMethod.debt,
          debtorName: 'Ali',
          soldBy: worker);
      expect((await sessions.getSession(venue, sale.id)).finalTotal, 10000);
      expect((await customer('Ali')).balance, 90000 + 10000);
    });

    test('takes a debt payment but cannot add or write off debts', () async {
      final ali = await customer('Ali');
      await debts.reduceDebt(
          venueId: venue,
          customer: ali,
          type: DebtEntryType.payment,
          amount: 50000,
          paymentMethod: PaymentMethod.cash,
          by: worker);
      expect((await customer('Ali')).balance, 50000);
      await expectLater(
          debts.addDebt(venueId: venue, name: 'Ali', amount: 1000, by: worker),
          denied);
      await expectLater(
          debts.reduceDebt(
              venueId: venue,
              customer: ali,
              type: DebtEntryType.writeoff,
              amount: 1000,
              by: worker),
          denied);
      expect((await customer('Ali')).balance, 50000);
    });

    test('records an expense but cannot delete one', () async {
      await expenses.add(
          venue,
          Expense(
              id: '',
              amount: 5000,
              category: 'Boshqa',
              paymentMethod: PaymentMethod.cash,
              date: DateTime.now(),
              createdBy: worker.uid,
              createdByName: worker.name));
      final day = BusinessDay.containing(DateTime.now(), 6);
      final list = await expenses.getBetween(venue, day.start, day.end);
      expect(totalExpenses(list), 42000);
      await expectLater(expenses.delete(venue, list.first), denied);
    });

    test('can load the daily report', () async {
      final day = BusinessDay.containing(DateTime.now(), 6);
      final report = DailyReport.from(
        await sessions.getSessionsEndedBetween(venue, day.start, day.end),
        await debts.getEntriesBetween(venue, day.start, day.end),
        await expenses.getBetween(venue, day.start, day.end),
      );
      expect(report.tableSessions, 3);
      expect(report.debtPayments[PaymentMethod.cash], 50000);
    });

    test('cannot touch admin data', () async {
      final t = await table('table-1');
      await expectLater(
          tables.updateTable(venue, t.copyWith(hourlyRate: 1)), denied);
      await expectLater(
          tables.addTable(venue, t.copyWith(name: 'X')), denied);
      await expectLater(
          menu.addItem(
              venue,
              const MenuItem(
                  id: '', name: 'X', price: 1, category: 'Boshqa', venueId: venue)),
          denied);
      await expectLater(
          menu.setItemImage(
              venue,
              const MenuItem(
                  id: 'cola',
                  name: 'Cola',
                  price: 10000,
                  category: 'Ichimliklar',
                  venueId: venue),
              (bytes: png, contentType: 'image/png')),
          denied);
      await expectLater(venues.setDayEndHour(venue, 3), denied);
      await expectLater(venues.setMenuCategories(venue, ['X']), denied);
      await expectLater(stored('activity'), denied);
      await expectLater(
          FirebaseFirestore.instance
              .collection('users')
              .where('venueId', isEqualTo: venue)
              .get(const GetOptions(source: Source.server)),
          denied);
      expect((await table('table-1')).hourlyRate, 40000);
    });
  });
}
