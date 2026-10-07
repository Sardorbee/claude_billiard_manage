import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart' hide Transaction;
import 'package:uuid/uuid.dart';
import '../models/models.dart';

const _uuid = Uuid();

Timestamp? _stamp(DateTime? at) => at == null ? null : Timestamp.fromDate(at);

String _money(double amount) =>
    amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2);

// ─── ACTIVITY REPOSITORY ─────────────────────────────────────────────────────

// The owner's record of sensitive actions. Other repositories write to it
// as part of the action itself; entries are never edited or deleted.
class ActivityRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // The signed-in user, set at sign-in, so every entry says who did it.
  AppUser? actor;

  DocumentReference<Map<String, dynamic>> _newRef(String venueId) =>
      _db.collection('venues').doc(venueId).collection('activity').doc();

  Map<String, dynamic>? _entry(String type, String subject, String? detail) {
    final by = actor;
    if (by == null) return null;
    return ActivityEntry(
      id: '',
      type: type,
      subject: subject,
      detail: detail,
      byUid: by.uid,
      byName: by.name,
      at: DateTime.now(),
    ).toFirestore();
  }

  // For actions that are a plain write. A failed log must not undo or block
  // the action it describes, so errors are swallowed.
  Future<void> log(String venueId, String type, String subject,
      {String? detail}) async {
    final entry = _entry(type, subject, detail);
    if (entry == null) return;
    try {
      await _newRef(venueId).set(entry);
    } catch (_) {}
  }

  // For actions inside a transaction: the entry commits with the action.
  void logIn(Transaction tx, String venueId, String type, String subject,
      {String? detail}) {
    final entry = _entry(type, subject, detail);
    if (entry != null) tx.set(_newRef(venueId), entry);
  }

  Stream<List<ActivityEntry>> watchRecent(String venueId, {int limit = 200}) {
    return _db
        .collection('venues')
        .doc(venueId)
        .collection('activity')
        .orderBy('at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ActivityEntry.fromFirestore).toList());
  }
}

// ─── AUTH REPOSITORY ─────────────────────────────────────────────────────────

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ActivityRepository _activity;

  AuthRepository(this._activity);

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<AppUser?> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    if (cred.user == null) return null;
    // Update lastLogin
    await _db.collection('users').doc(cred.user!.uid).update({
      'lastLogin': FieldValue.serverTimestamp(),
    });
    return getUser(cred.user!.uid);
  }

  Future<void> signOut() => _auth.signOut();

  Future<AppUser?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(doc);
  }

  Future<AppUser> createUser({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    required String venueId,
  }) async {
    // createUserWithEmailAndPassword signs the new account in, so it runs on a
    // throwaway app to leave the manager's own session untouched.
    final secondary = await Firebase.initializeApp(
      name: 'staff-creator-${_uuid.v4()}',
      options: Firebase.app().options,
    );
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
      final cred = await secondaryAuth.createUserWithEmailAndPassword(email: email, password: password);
      final user = AppUser(
        uid: cred.user!.uid,
        name: name,
        email: email,
        role: role,
        venueId: venueId,
      );
      // Written as the manager, which is what the security rules require.
      await _db.collection('users').doc(user.uid).set(user.toFirestore());
      await _activity.log(venueId, ActivityType.staffCreated, name,
          detail: role.name);
      await secondaryAuth.signOut();
      return user;
    } finally {
      await secondary.delete();
    }
  }

  Future<void> updateUser(AppUser user) =>
      _db.collection('users').doc(user.uid).update(user.toFirestore());

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email);
}

// ─── TABLE REPOSITORY ─────────────────────────────────────────────────────────

class TableRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ActivityRepository _activity;

  TableRepository(this._activity);

  Stream<List<TableModel>> watchTables(String venueId) {
    return _db
        .collection('venues')
        .doc(venueId)
        .collection('tables')
        .where('isActive', isEqualTo: true)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map(TableModel.fromFirestore).toList());
  }

  Future<List<TableModel>> getTables(String venueId) async {
    final snap = await _db
        .collection('venues')
        .doc(venueId)
        .collection('tables')
        .orderBy('name')
        .get();
    return snap.docs.map(TableModel.fromFirestore).toList();
  }

  Future<TableModel> addTable(String venueId, TableModel table) async {
    final ref = _db.collection('venues').doc(venueId).collection('tables').doc();
    final newTable = TableModel(
      id: ref.id, name: table.name, zone: table.zone, type: table.type,
      status: TableStatus.open, hourlyRate: table.hourlyRate, capacity: table.capacity,
    );
    await ref.set(newTable.toFirestore());
    await _activity.log(venueId, ActivityType.tableAdded, table.name,
        detail: _money(table.hourlyRate));
    return newTable;
  }

  // Pass [previous] when editing so a change of hourly rate is logged.
  Future<void> updateTable(String venueId, TableModel table,
      {TableModel? previous}) async {
    await _db.collection('venues').doc(venueId).collection('tables').doc(table.id)
        .update(table.toFirestore());
    if (previous != null && previous.hourlyRate != table.hourlyRate) {
      await _activity.log(venueId, ActivityType.tableRateChanged, table.name,
          detail: '${_money(previous.hourlyRate)} → ${_money(table.hourlyRate)}');
    }
  }

  Future<void> deleteTable(String venueId, TableModel table) async {
    await _db.collection('venues').doc(venueId).collection('tables').doc(table.id)
        .update({'isActive': false});
    await _activity.log(venueId, ActivityType.tableDeleted, table.name);
  }
}

// ─── SESSION REPOSITORY ───────────────────────────────────────────────────────

class SessionRepository {
  static const counterSaleName = 'Stolsiz savdo';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final DebtRepository _debts;
  final ActivityRepository _activity;

  SessionRepository(this._debts, this._activity);
  static final FirebaseDatabase liveDatabase = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://billiard-manage-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
  final FirebaseDatabase _rtdb = liveDatabase;



  // RTDB: live session state (timer + status)
  DatabaseReference _liveRef(String venueId, String tableId) =>
      _rtdb.ref('venues/$venueId/sessions/$tableId');

  Stream<Map<String, dynamic>?> watchLiveSession(String venueId, String tableId) {
    return _liveRef(venueId, tableId).onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return Map<String, dynamic>.from(event.snapshot.value as Map);
    });
  }

  Future<void> addSplit(String venueId, String sessionId, SessionSplit split) async {
    final sessionRef = _db
        .collection('venues').doc(venueId)
        .collection('sessions').doc(sessionId);

    await sessionRef.update({
      'splits': FieldValue.arrayUnion([split.toMap()]),
    });
  }

  Future<SessionModel> openSession({
    required String venueId,
    required TableModel table,
    required int guestCount,
    required String openedBy,
    int? plannedMinutes, // null = open-ended
  }) async {
    final sessionId = _uuid.v4();
    final now = DateTime.now();
    final plannedEndAt = plannedMinutes == null
        ? null
        : now.add(Duration(minutes: plannedMinutes));

    final session = SessionModel(
      id: sessionId,
      tableId: table.id,
      tableName: table.name,
      startedAt: now,
      guestCount: guestCount,
      hourlyRate: table.hourlyRate,
      openedBy: openedBy,
      venueId: venueId,
      plannedEndAt: plannedEndAt,
    );

    final sessionRef = _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId);
    final tableRef = _db.collection('venues').doc(venueId).collection('tables').doc(table.id);

    // Session doc + table status together, and only if nobody else opened
    // this table first.
    await _db.runTransaction((tx) async {
      final tableSnap = await tx.get(tableRef);
      final t = tableSnap.data();
      if (t != null && t['status'] == 'active' && t['currentSessionId'] != null) {
        throw Exception('${table.name} stolida faol seans bor');
      }
      tx.set(sessionRef, session.toFirestore());
      tx.update(tableRef, {
        'status': 'active',
        'currentSessionId': sessionId,
        'sessionEndsAt': _stamp(plannedEndAt),
      });
    });

    // RTDB: live state
    await _liveRef(venueId, table.id).set({
      'sessionId': sessionId,
      'startedAt': now.millisecondsSinceEpoch,
      'pausedAt': null,
      'totalPausedMs': 0,
      'status': 'active',
    });

    return session;
  }

  Future<void> pauseSession(String venueId, String tableId, String sessionId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _liveRef(venueId, tableId).update({'pausedAt': now, 'status': 'paused'});
    await _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId)
        .update({'pausedAt': Timestamp.fromDate(DateTime.now())});
  }

  Future<void> resumeSession(String venueId, String tableId, String sessionId, int pausedAt) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pausedMs = now - pausedAt;
    await _liveRef(venueId, tableId).update({
      'pausedAt': null,
      'status': 'active',
      'totalPausedMs': ServerValue.increment(pausedMs),
    });
    await _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId)
        .update({'pausedAt': null});
  }

  Future<void> addOrderItems(String venueId, String sessionId, List<OrderItem> items) async {
    final sessionRef = _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId);
    // Read-modify-write in a transaction so two devices adding items at once
    // don't overwrite each other.
    await _db.runTransaction((tx) async {
      final session = SessionModel.fromFirestore(await tx.get(sessionRef));
      final existing = List<OrderItem>.from(session.orderItems);
      for (final item in items) {
        final idx = existing.indexWhere((e) => e.menuItemId == item.menuItemId);
        if (idx >= 0) {
          existing[idx] = existing[idx].copyWith(quantity: existing[idx].quantity + item.quantity);
        } else {
          existing.add(item);
        }
      }
      tx.update(sessionRef, {'orderItems': existing.map((e) => e.toMap()).toList()});
    });
  }

  Stream<SessionModel?> watchActiveSession(String venueId, String sessionId) {
    return _db
        .collection('venues')
        .doc(venueId)
        .collection('sessions')
        .doc(sessionId)
        .snapshots()
        .map((doc) => doc.exists ? SessionModel.fromFirestore(doc) : null);
  }

  Future<void> transferSession(String venueId, String sessionId, String fromTableId, String toTableId, String toTableName) async {
    final sessionRef = _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId);
    final fromRef = _db.collection('venues').doc(venueId).collection('tables').doc(fromTableId);
    final toRef = _db.collection('venues').doc(venueId).collection('tables').doc(toTableId);

    await _db.runTransaction((tx) async {
      final to = (await tx.get(toRef)).data();
      if (to != null && to['status'] == 'active' && to['currentSessionId'] != null) {
        throw Exception('$toTableName stolida faol seans bor');
      }
      final session = (await tx.get(sessionRef)).data();
      final fromName = session?['tableName'] ?? '';
      tx.update(sessionRef, {'tableId': toTableId, 'tableName': toTableName});
      _activity.logIn(tx, venueId, ActivityType.sessionTransferred, fromName,
          detail: '→ $toTableName');
      tx.update(fromRef,
          {'status': 'open', 'currentSessionId': null, 'sessionEndsAt': null});
      // The booked end time travels with the session.
      tx.update(toRef, {
        'status': 'active',
        'currentSessionId': sessionId,
        'sessionEndsAt': session?['plannedEndAt'],
      });
    });

    // Move RTDB live state
    final snapshot = await _liveRef(venueId, fromTableId).get();
    if (snapshot.exists) {
      await _liveRef(venueId, toTableId).set(snapshot.value);
      await _liveRef(venueId, fromTableId).remove();
    }
  }

  // Sets, extends or (with null) removes a running session's booked end
  // time, on the session and on its table together.
  Future<void> setPlannedEnd(String venueId, String sessionId, String tableId,
      DateTime? plannedEndAt) {
    final batch = _db.batch();
    batch.update(
        _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId),
        {'plannedEndAt': _stamp(plannedEndAt)});
    batch.update(
        _db.collection('venues').doc(venueId).collection('tables').doc(tableId),
        {'sessionEndsAt': _stamp(plannedEndAt)});
    return batch.commit();
  }

  Future<SessionModel> getSession(String venueId, String sessionId) async {
    final doc = await _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId).get();
    return SessionModel.fromFirestore(doc);
  }

  Future<void> updateSessionNotes(String venueId, String sessionId, String notes) =>
      _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId)
          .update({'notes': notes});

  Future<void> applyDiscount(String venueId, String sessionId, double discountPct,
      {required String tableName}) async {
    await _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId)
        .update({'discount': discountPct});
    await _activity.log(venueId, ActivityType.discountApplied, tableName,
        detail: '${_money(discountPct)}%');
  }

  Future<SessionModel> checkoutSession({
    required String venueId,
    required String sessionId,
    required String tableId,
    required SessionModel session,
    required AppUser closedBy,
  }) async {
    final now = session.endedAt ?? DateTime.now();
    final debtor = await _debtorRef(venueId, session);
    final sessionRef = _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId);
    final tableRef   = _db.collection('venues').doc(venueId).collection('tables').doc(tableId);

    await _db.runTransaction((tx) async {
      await _ensureActive(tx, sessionRef);
      // The debt lands in the customer's ledger in the same write as the
      // checkout, so one can't exist without the other.
      if (debtor != null) {
        await _debts.applyEntry(tx,
            venueId: venueId,
            customerRef: debtor,
            customerName: session.debtorName!,
            type: DebtEntryType.debt,
            amount: session.finalTotal ?? session.total,
            note: session.tableName,
            sessionId: sessionId,
            by: closedBy);
      }
      tx.update(sessionRef, {
        'status':             'completed',
        'endedAt':            Timestamp.fromDate(now),
        'finalTotal':         session.finalTotal,
        'totalPausedSeconds': session.totalPausedSeconds,  // ← save paused seconds
        'paymentMethod':      session.paymentMethod?.name,
        'debtorName':         session.debtorName,
        'closedBy':           closedBy.uid,
      });
      tx.update(tableRef, {
        'status':           'open',
        'currentSessionId': null,
        'sessionEndsAt':    null,
      });
    });

    // Only after Firestore has committed, so a failed checkout keeps its timer.
    await _liveRef(venueId, tableId).remove();

    // Return locally — no extra Firestore read needed
    return session.copyWith(
      status:  'completed',
      endedAt: now,
    );
  }

  Future<void> voidSession(String venueId, String sessionId, String tableId) async {
    final sessionRef = _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId);
    final tableRef = _db.collection('venues').doc(venueId).collection('tables').doc(tableId);
    await _db.runTransaction((tx) async {
      await _ensureActive(tx, sessionRef);
      final tableName = (await tx.get(sessionRef)).data()?['tableName'] ?? '';
      _activity.logIn(tx, venueId, ActivityType.sessionVoided, tableName);
      tx.update(sessionRef, {'status': 'voided', 'endedAt': Timestamp.fromDate(DateTime.now())});
      tx.update(tableRef,
          {'status': 'open', 'currentSessionId': null, 'sessionEndsAt': null});
    });
    await _liveRef(venueId, tableId).remove();
  }

  // Stops a second device from closing a session that is already closed.
  Future<void> _ensureActive(Transaction tx, DocumentReference<Map<String, dynamic>> sessionRef) async {
    final status = (await tx.get(sessionRef)).data()?['status'];
    if (status != 'active') {
      throw Exception('Bu seans allaqachon yopilgan');
    }
  }

  // A sale with no table: stored as an already-completed session so reports
  // pick it up alongside table sessions.
  Future<SessionModel> createCounterSale({
    required String venueId,
    required List<OrderItem> items,
    required PaymentMethod paymentMethod,
    String? debtorName,
    required AppUser soldBy,
  }) async {
    final ref = _db.collection('venues').doc(venueId).collection('sessions').doc();
    final now = DateTime.now();
    final total = items.fold(0.0, (sum, i) => sum + i.subtotal);
    final sale = SessionModel(
      id: ref.id,
      tableId: '',
      tableName: counterSaleName,
      startedAt: now,
      endedAt: now,
      guestCount: 0,
      hourlyRate: 0,
      orderItems: items,
      status: 'completed',
      openedBy: soldBy.uid,
      venueId: venueId,
      finalTotal: total,
      paymentMethod: paymentMethod,
      debtorName: debtorName,
    );
    final debtor = await _debtorRef(venueId, sale);
    await _db.runTransaction((tx) async {
      if (debtor != null) {
        await _debts.applyEntry(tx,
            venueId: venueId,
            customerRef: debtor,
            customerName: debtorName!,
            type: DebtEntryType.debt,
            amount: total,
            note: counterSaleName,
            sessionId: ref.id,
            by: soldBy);
      }
      tx.set(ref, {...sale.toFirestore(), 'closedBy': soldBy.uid});
    });
    return sale;
  }

  // The ledger account to charge when a sale is paid as debt, else null.
  Future<DocumentReference<Map<String, dynamic>>?> _debtorRef(
      String venueId, SessionModel session) async {
    final name = session.debtorName;
    if (session.paymentMethod != PaymentMethod.debt || name == null) return null;
    return _debts.customerRefFor(venueId, name);
  }

  // Every session closed (completed or voided) in [from, to). Filtered by
  // end time alone so it needs no composite index; callers split by status.
  Future<List<SessionModel>> getSessionsEndedBetween(
      String venueId, DateTime from, DateTime to) async {
    final snap = await _db
        .collection('venues').doc(venueId).collection('sessions')
        .where('endedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('endedAt', isLessThan: Timestamp.fromDate(to))
        .get();
    return snap.docs.map(SessionModel.fromFirestore).toList();
  }

  // History queries
  Stream<List<SessionModel>> watchRecentSessions(String venueId, {int limit = 50}) {
    return _db
        .collection('venues')
        .doc(venueId)
        .collection('sessions')
        .orderBy('startedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(SessionModel.fromFirestore).toList());
  }

  Future<List<SessionModel>> getSessionsInRange(String venueId, DateTime from, DateTime to) async {
    final snap = await _db
        .collection('venues')
        .doc(venueId)
        .collection('sessions')
        .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('startedAt', isLessThanOrEqualTo: Timestamp.fromDate(to))
        .where('status', isEqualTo: 'completed')
        .orderBy('startedAt', descending: true)
        .get();
    return snap.docs.map(SessionModel.fromFirestore).toList();
  }
}

// ─── MENU REPOSITORY ──────────────────────────────────────────────────────────

class MenuRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ActivityRepository _activity;

  MenuRepository(this._activity);

  Stream<List<MenuItem>> watchMenu(String venueId) {
    return _db
        .collection('venues')
        .doc(venueId)
        .collection('menu')
        .orderBy('category')
        .snapshots()
        .map((snap) => snap.docs.map(MenuItem.fromFirestore).toList());
  }

  Future<MenuItem> addItem(String venueId, MenuItem item) async {
    final ref = _db.collection('venues').doc(venueId).collection('menu').doc();
    final newItem = MenuItem(
      id: ref.id, name: item.name, price: item.price,
      category: item.category, imageUrl: item.imageUrl,
      isAvailable: item.isAvailable, stockCount: item.stockCount, venueId: venueId,
    );
    await ref.set(newItem.toFirestore());
    await _activity.log(venueId, ActivityType.menuItemAdded, item.name,
        detail: _money(item.price));
    return newItem;
  }

  Future<void> updateItem(String venueId, MenuItem item) =>
      _db.collection('venues').doc(venueId).collection('menu').doc(item.id)
          .update(item.toFirestore());

  Future<void> deleteItem(String venueId, MenuItem item) async {
    await _db.collection('venues').doc(venueId).collection('menu').doc(item.id).delete();
    await _activity.log(venueId, ActivityType.menuItemDeleted, item.name,
        detail: _money(item.price));
  }

  Future<void> toggleAvailability(String venueId, String itemId, bool isAvailable) =>
      _db.collection('venues').doc(venueId).collection('menu').doc(itemId)
          .update({'isAvailable': isAvailable});
}

// ─── BOOKING REPOSITORY ───────────────────────────────────────────────────────

class BookingRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const reserveLeadTime = Duration(hours: 1);

  Stream<List<Booking>> watchBookings(String venueId) {
    return _db
        .collection('venues')
        .doc(venueId)
        .collection('bookings')
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 1))))
        .orderBy('scheduledAt')
        .snapshots()
        .map((snap) => snap.docs.map(Booking.fromFirestore).toList());
  }

  Future<List<Booking>> getBookingsForDate(String venueId, DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final snap = await _db
        .collection('venues').doc(venueId).collection('bookings')
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('scheduledAt')
        .get();
    return snap.docs.map(Booking.fromFirestore).toList();
  }

  Future<Booking> createBooking(String venueId, Booking booking) async {
    final ref = _db.collection('venues').doc(venueId).collection('bookings').doc();
    final newBooking = Booking(
      id: ref.id, tableId: booking.tableId, tableName: booking.tableName,
      guestName: booking.guestName, guestPhone: booking.guestPhone,
      scheduledAt: booking.scheduledAt, durationMinutes: booking.durationMinutes,
      guestCount: booking.guestCount, depositAmount: booking.depositAmount,
      notes: booking.notes, createdBy: booking.createdBy, venueId: venueId,
    );
    final tableRef = _db.collection('venues').doc(venueId).collection('tables').doc(booking.tableId);

    // Only a booking that starts soon holds the table; a booking for a later
    // day must not block it now.
    final startsSoon = booking.scheduledAt.difference(DateTime.now()) <= reserveLeadTime;
    await _db.runTransaction((tx) async {
      final table = (await tx.get(tableRef)).data();
      tx.set(ref, newBooking.toFirestore());
      if (startsSoon && table != null && table['status'] == 'open') {
        tx.update(tableRef, {'status': 'reserved', 'reservationId': ref.id});
      }
    });

    return newBooking;
  }

  Future<void> updateBookingStatus(String venueId, String bookingId, String status, String tableId) async {
    final bookingRef = _db.collection('venues').doc(venueId).collection('bookings').doc(bookingId);
    final closes = status == 'cancelled' || status == 'completed' || status == 'no_show';
    await _db.runTransaction((tx) async {
      if (closes) await _releaseTable(tx, venueId, tableId, bookingId);
      tx.update(bookingRef, {'status': status});
    });
  }

  Future<void> deleteBooking(String venueId, String bookingId, String tableId) async {
    final bookingRef = _db.collection('venues').doc(venueId).collection('bookings').doc(bookingId);
    await _db.runTransaction((tx) async {
      await _releaseTable(tx, venueId, tableId, bookingId);
      tx.delete(bookingRef);
    });
  }

  // Frees the table only if this booking is what holds it, so closing a
  // booking never reopens a table that has a session running.
  Future<void> _releaseTable(Transaction tx, String venueId, String tableId, String bookingId) async {
    final tableRef = _db.collection('venues').doc(venueId).collection('tables').doc(tableId);
    final table = (await tx.get(tableRef)).data();
    if (table == null || table['reservationId'] != bookingId) return;
    tx.update(tableRef, {
      'reservationId': null,
      if (table['status'] == 'reserved') 'status': 'open',
    });
  }
}

// ─── DEBT REPOSITORY ──────────────────────────────────────────────────────────

class DebtRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ActivityRepository _activity;

  DebtRepository(this._activity);

  CollectionReference<Map<String, dynamic>> _customers(String venueId) =>
      _db.collection('venues').doc(venueId).collection('customers');

  CollectionReference<Map<String, dynamic>> _entries(String venueId) =>
      _db.collection('venues').doc(venueId).collection('debtEntries');

  // Largest debt first, then by name.
  Stream<List<Customer>> watchCustomers(String venueId) {
    return _customers(venueId).snapshots().map((snap) {
      final list = snap.docs.map(Customer.fromFirestore).toList();
      list.sort((a, b) {
        final byBalance = b.balance.compareTo(a.balance);
        return byBalance != 0
            ? byBalance
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return list;
    });
  }

  Stream<Customer?> watchCustomer(String venueId, String customerId) =>
      _customers(venueId).doc(customerId).snapshots()
          .map((doc) => doc.exists ? Customer.fromFirestore(doc) : null);

  // Sorted here rather than in the query, so no composite index is needed.
  Stream<List<DebtEntry>> watchEntries(String venueId, String customerId) {
    return _entries(venueId)
        .where('customerId', isEqualTo: customerId)
        .snapshots()
        .map((snap) => snap.docs.map(DebtEntry.fromFirestore).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Future<List<String>> customerNames(String venueId) async {
    final snap = await _customers(venueId).get();
    return snap.docs.map((d) => (d.data()['name'] ?? '') as String).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  // The customer with this name, or a fresh reference if there is none yet.
  // Names match case-insensitively so "ali" and "Ali" are one person.
  Future<DocumentReference<Map<String, dynamic>>> customerRefFor(
      String venueId, String name) async {
    final snap = await _customers(venueId)
        .where('nameLower', isEqualTo: name.trim().toLowerCase())
        .limit(1)
        .get();
    return snap.docs.isNotEmpty
        ? snap.docs.first.reference
        : _customers(venueId).doc();
  }

  // Writes one ledger entry and moves the customer's balance with it.
  // Reads the customer first, so call it before any other write in [tx].
  Future<void> applyEntry(
    Transaction tx, {
    required String venueId,
    required DocumentReference<Map<String, dynamic>> customerRef,
    required String customerName,
    String? phone,
    required DebtEntryType type,
    required double amount,
    String? note,
    String? sessionId,
    PaymentMethod? paymentMethod,
    required AppUser by,
  }) async {
    final now = DateTime.now();
    final entry = DebtEntry(
      id: '',
      customerId: customerRef.id,
      customerName: customerName.trim(),
      type: type,
      amount: amount,
      note: note,
      sessionId: sessionId,
      paymentMethod: paymentMethod,
      createdBy: by.uid,
      createdByName: by.name,
      createdAt: now,
    );

    final customer = await tx.get(customerRef);
    if (customer.exists) {
      tx.update(customerRef, {
        'balance': FieldValue.increment(entry.delta),
        'updatedAt': Timestamp.fromDate(now),
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      });
    } else {
      tx.set(customerRef, {
        'name': customerName.trim(),
        'nameLower': customerName.trim().toLowerCase(),
        'phone': phone,
        'balance': entry.delta,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    }
    tx.set(_entries(venueId).doc(), entry.toFirestore());
  }

  // A debt entered by hand, for a new or an existing customer.
  Future<void> addDebt({
    required String venueId,
    required String name,
    String? phone,
    required double amount,
    String? note,
    required AppUser by,
  }) async {
    final customerRef = await customerRefFor(venueId, name);
    await _db.runTransaction((tx) async {
      await applyEntry(tx,
          venueId: venueId,
          customerRef: customerRef,
          customerName: name,
          phone: phone,
          type: DebtEntryType.debt,
          amount: amount,
          note: note,
          by: by);
      _activity.logIn(tx, venueId, ActivityType.debtAdded, name.trim(),
          detail: _money(amount));
    });
  }

  // Debt payments and write-offs recorded in [from, to), for the daily report.
  Future<List<DebtEntry>> getEntriesBetween(
      String venueId, DateTime from, DateTime to) async {
    final snap = await _entries(venueId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('createdAt', isLessThan: Timestamp.fromDate(to))
        .get();
    return snap.docs.map(DebtEntry.fromFirestore).toList();
  }

  // Money received (payment) or a balance forgiven (writeoff).
  Future<void> reduceDebt({
    required String venueId,
    required Customer customer,
    required DebtEntryType type,
    required double amount,
    PaymentMethod? paymentMethod,
    String? note,
    required AppUser by,
  }) async {
    final customerRef = _customers(venueId).doc(customer.id);
    await _db.runTransaction((tx) async {
      final balance = ((await tx.get(customerRef)).data()?['balance'] ?? 0).toDouble();
      if (amount > balance) {
        throw Exception("${customer.name} qarzi faqat ${_money(balance)} so'm");
      }
      await applyEntry(tx,
          venueId: venueId,
          customerRef: customerRef,
          customerName: customer.name,
          type: type,
          amount: amount,
          paymentMethod: paymentMethod,
          note: note,
          by: by);
      if (type == DebtEntryType.writeoff) {
        _activity.logIn(tx, venueId, ActivityType.debtWrittenOff,
            customer.name, detail: _money(amount));
      }
    });
  }

  Future<void> updateCustomer(String venueId, String customerId,
          {required String name, String? phone}) =>
      _customers(venueId).doc(customerId).update({
        'name': name.trim(),
        'nameLower': name.trim().toLowerCase(),
        'phone': phone,
      });
}

// ─── VENUE REPOSITORY ─────────────────────────────────────────────────────────

class VenueRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ActivityRepository _activity;

  VenueRepository(this._activity);

  Future<void> setDayEndHour(String venueId, int hour) async {
    await _db.collection('venues').doc(venueId)
        .set({'dayEndHour': hour}, SetOptions(merge: true));
    await _activity.log(venueId, ActivityType.dayEndChanged,
        '${hour.toString().padLeft(2, '0')}:00');
  }

  // Emits defaults when the venue has no document of its own yet.
  Stream<Venue> watchVenue(String venueId) =>
      _db.collection('venues').doc(venueId).snapshots().map(Venue.fromFirestore);

  // set+merge rather than update, so it also works before the venue
  // document exists.
  Future<void> setMenuCategories(String venueId, List<String> categories) =>
      _db.collection('venues').doc(venueId)
          .set({'menuCategories': categories}, SetOptions(merge: true));

  Future<Venue?> getVenue(String venueId) async {
    final doc = await _db.collection('venues').doc(venueId).get();
    if (!doc.exists) return null;
    return Venue.fromFirestore(doc);
  }

  Future<void> updateVenue(Venue venue) =>
      _db.collection('venues').doc(venue.id).update(venue.toFirestore());

  Stream<List<AppUser>> watchUsers(String venueId) {
    return _db.collection('users')
        .where('venueId', isEqualTo: venueId)
        .snapshots()
        .map((snap) => snap.docs.map(AppUser.fromFirestore).toList());
  }

  Future<void> createVenue(Venue venue) =>
      _db.collection('venues').doc(venue.id).set(venue.toFirestore());
}
