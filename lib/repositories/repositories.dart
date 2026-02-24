import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

const _uuid = Uuid();

// ─── AUTH REPOSITORY ─────────────────────────────────────────────────────────

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    final user = AppUser(
      uid: cred.user!.uid,
      name: name,
      email: email,
      role: role,
      venueId: venueId,
    );
    await _db.collection('users').doc(user.uid).set(user.toFirestore());
    return user;
  }

  Future<void> updateUser(AppUser user) =>
      _db.collection('users').doc(user.uid).update(user.toFirestore());

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email);
}

// ─── TABLE REPOSITORY ─────────────────────────────────────────────────────────

class TableRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
    return newTable;
  }

  Future<void> updateTable(String venueId, TableModel table) =>
      _db.collection('venues').doc(venueId).collection('tables').doc(table.id)
          .update(table.toFirestore());

  Future<void> deleteTable(String venueId, String tableId) =>
      _db.collection('venues').doc(venueId).collection('tables').doc(tableId)
          .update({'isActive': false});
}

// ─── SESSION REPOSITORY ───────────────────────────────────────────────────────

class SessionRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://billiard-manage-default-rtdb.asia-southeast1.firebasedatabase.app',
  );



  // RTDB: live session state (timer + status)
  DatabaseReference _liveRef(String venueId, String tableId) =>
      _rtdb.ref('venues/$venueId/sessions/$tableId');

  Stream<Map<String, dynamic>?> watchLiveSession(String venueId, String tableId) {
    return _liveRef(venueId, tableId).onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return Map<String, dynamic>.from(event.snapshot.value as Map);
    });
  }

  Future<SessionModel> openSession({
    required String venueId,
    required TableModel table,
    required int guestCount,
    required String openedBy,
  }) async {
    final sessionId = _uuid.v4();
    final now = DateTime.now();

    final session = SessionModel(
      id: sessionId,
      tableId: table.id,
      tableName: table.name,
      startedAt: now,
      guestCount: guestCount,
      hourlyRate: table.hourlyRate,
      openedBy: openedBy,
      venueId: venueId,
    );

    // Firestore: full session doc
    await _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId)
        .set(session.toFirestore());

    // RTDB: live state
    await _liveRef(venueId, table.id).set({
      'sessionId': sessionId,
      'startedAt': now.millisecondsSinceEpoch,
      'pausedAt': null,
      'totalPausedMs': 0,
      'status': 'active',
    });

    // Update table status
    await _db.collection('venues').doc(venueId).collection('tables').doc(table.id).update({
      'status': 'active',
      'currentSessionId': sessionId,
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
    final doc = await _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId).get();
    final session = SessionModel.fromFirestore(doc);
    final existing = List<OrderItem>.from(session.orderItems);
    for (final item in items) {
      final idx = existing.indexWhere((e) => e.menuItemId == item.menuItemId);
      if (idx >= 0) {
        existing[idx] = existing[idx].copyWith(quantity: existing[idx].quantity + item.quantity);
      } else {
        existing.add(item);
      }
    }
    await _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId)
        .update({'orderItems': existing.map((e) => e.toMap()).toList()});
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
    final batch = _db.batch();
    final sessionRef = _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId);
    batch.update(sessionRef, {'tableId': toTableId, 'tableName': toTableName});

    final fromRef = _db.collection('venues').doc(venueId).collection('tables').doc(fromTableId);
    batch.update(fromRef, {'status': 'open', 'currentSessionId': null});

    final toRef = _db.collection('venues').doc(venueId).collection('tables').doc(toTableId);
    batch.update(toRef, {'status': 'active', 'currentSessionId': sessionId});

    await batch.commit();

    // Move RTDB live state
    final snapshot = await _liveRef(venueId, fromTableId).get();
    if (snapshot.exists) {
      await _liveRef(venueId, toTableId).set(snapshot.value);
      await _liveRef(venueId, fromTableId).remove();
    }
  }

  Future<SessionModel> getSession(String venueId, String sessionId) async {
    final doc = await _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId).get();
    return SessionModel.fromFirestore(doc);
  }

  Future<void> updateSessionNotes(String venueId, String sessionId, String notes) =>
      _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId)
          .update({'notes': notes});

  Future<void> applyDiscount(String venueId, String sessionId, double discountPct) =>
      _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId)
          .update({'discount': discountPct});

  Future<SessionModel> checkoutSession({
    required String venueId,
    required String sessionId,
    required String tableId,
    required double finalTotal,
  }) async {
    final now = DateTime.now();
    final batch = _db.batch();

    final sessionRef = _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId);
    batch.update(sessionRef, {
      'status': 'completed',
      'endedAt': Timestamp.fromDate(now),
      'finalTotal': finalTotal,
    });

    final tableRef = _db.collection('venues').doc(venueId).collection('tables').doc(tableId);
    batch.update(tableRef, {'status': 'open', 'currentSessionId': null});

    await batch.commit();
    await _liveRef(venueId, tableId).remove();

    final doc = await sessionRef.get();
    return SessionModel.fromFirestore(doc);
  }

  Future<void> voidSession(String venueId, String sessionId, String tableId) async {
    final batch = _db.batch();
    final sessionRef = _db.collection('venues').doc(venueId).collection('sessions').doc(sessionId);
    batch.update(sessionRef, {'status': 'voided', 'endedAt': Timestamp.fromDate(DateTime.now())});
    final tableRef = _db.collection('venues').doc(venueId).collection('tables').doc(tableId);
    batch.update(tableRef, {'status': 'open', 'currentSessionId': null});
    await batch.commit();
    await _liveRef(venueId, tableId).remove();
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
    return newItem;
  }

  Future<void> updateItem(String venueId, MenuItem item) =>
      _db.collection('venues').doc(venueId).collection('menu').doc(item.id)
          .update(item.toFirestore());

  Future<void> deleteItem(String venueId, String itemId) =>
      _db.collection('venues').doc(venueId).collection('menu').doc(itemId).delete();

  Future<void> toggleAvailability(String venueId, String itemId, bool isAvailable) =>
      _db.collection('venues').doc(venueId).collection('menu').doc(itemId)
          .update({'isAvailable': isAvailable});
}

// ─── BOOKING REPOSITORY ───────────────────────────────────────────────────────

class BookingRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
    await ref.set(newBooking.toFirestore());

    // Update table status to reserved
    await _db.collection('venues').doc(venueId).collection('tables').doc(booking.tableId)
        .update({'status': 'reserved', 'reservationId': ref.id});

    return newBooking;
  }

  Future<void> updateBookingStatus(String venueId, String bookingId, String status, String tableId) async {
    await _db.collection('venues').doc(venueId).collection('bookings').doc(bookingId)
        .update({'status': status});
    if (status == 'cancelled' || status == 'completed' || status == 'no_show') {
      await _db.collection('venues').doc(venueId).collection('tables').doc(tableId)
          .update({'status': 'open', 'reservationId': null});
    }
  }

  Future<void> deleteBooking(String venueId, String bookingId, String tableId) async {
    await _db.collection('venues').doc(venueId).collection('bookings').doc(bookingId).delete();
    await _db.collection('venues').doc(venueId).collection('tables').doc(tableId)
        .update({'status': 'open', 'reservationId': null});
  }
}

// ─── VENUE REPOSITORY ─────────────────────────────────────────────────────────

class VenueRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
