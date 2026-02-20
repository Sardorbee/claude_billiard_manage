import 'package:cloud_firestore/cloud_firestore.dart';

// ─── TABLE ───────────────────────────────────────────────────────────────────

enum TableType { pool, snooker, vipSuite }
enum TableStatus { open, active, reserved, maintenance }

class TableModel {
  final String id;
  final String name;
  final String zone;
  final TableType type;
  final TableStatus status;
  final double hourlyRate;
  final int capacity;
  final String? currentSessionId;
  final String? reservationId;
  final bool isActive;

  const TableModel({
    required this.id,
    required this.name,
    required this.zone,
    required this.type,
    required this.status,
    required this.hourlyRate,
    required this.capacity,
    this.currentSessionId,
    this.reservationId,
    this.isActive = true,
  });

  factory TableModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return TableModel(
      id: doc.id,
      name: d['name'] ?? '',
      zone: d['zone'] ?? '',
      type: TableType.values.firstWhere(
        (e) => e.name == (d['type'] ?? 'pool'),
        orElse: () => TableType.pool,
      ),
      status: TableStatus.values.firstWhere(
        (e) => e.name == (d['status'] ?? 'open'),
        orElse: () => TableStatus.open,
      ),
      hourlyRate: (d['hourlyRate'] ?? 0.0).toDouble(),
      capacity: d['capacity'] ?? 2,
      currentSessionId: d['currentSessionId'],
      reservationId: d['reservationId'],
      isActive: d['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'zone': zone,
    'type': type.name,
    'status': status.name,
    'hourlyRate': hourlyRate,
    'capacity': capacity,
    'currentSessionId': currentSessionId,
    'reservationId': reservationId,
    'isActive': isActive,
  };

  TableModel copyWith({
    String? id, String? name, String? zone, TableType? type,
    TableStatus? status, double? hourlyRate, int? capacity,
    String? currentSessionId, String? reservationId, bool? isActive,
  }) => TableModel(
    id: id ?? this.id, name: name ?? this.name, zone: zone ?? this.zone,
    type: type ?? this.type, status: status ?? this.status,
    hourlyRate: hourlyRate ?? this.hourlyRate, capacity: capacity ?? this.capacity,
    currentSessionId: currentSessionId ?? this.currentSessionId,
    reservationId: reservationId ?? this.reservationId,
    isActive: isActive ?? this.isActive,
  );
}

// ─── SESSION ─────────────────────────────────────────────────────────────────

class SessionModel {
  final String id;
  final String tableId;
  final String tableName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime? pausedAt;
  final int totalPausedSeconds;
  final int guestCount;
  final double hourlyRate;
  final List<OrderItem> orderItems;
  final double discount;
  final String? notes;
  final String status; // active | completed | voided
  final String openedBy; // staff uid
  final String venueId;

  const SessionModel({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.startedAt,
    this.endedAt,
    this.pausedAt,
    this.totalPausedSeconds = 0,
    required this.guestCount,
    required this.hourlyRate,
    this.orderItems = const [],
    this.discount = 0,
    this.notes,
    this.status = 'active',
    required this.openedBy,
    required this.venueId,
  });

  // ─── Billing calculation (all local) ───────────────────────────
  double get elapsedSeconds {
    final end = endedAt ?? DateTime.now();
    final raw = end.difference(startedAt).inSeconds - totalPausedSeconds;
    return raw < 0 ? 0 : raw.toDouble();
  }

  double get timeCharge => (elapsedSeconds / 3600) * hourlyRate;

  double get fbTotal => orderItems.fold(0, (sum, i) => sum + i.subtotal);

  double get subtotal => timeCharge + fbTotal;

  double get discountAmount => discount > 0 ? subtotal * (discount / 100) : 0;

  double get total => subtotal - discountAmount;

  bool get isPaused => pausedAt != null && status == 'active';

  factory SessionModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SessionModel(
      id: doc.id,
      tableId: d['tableId'] ?? '',
      tableName: d['tableName'] ?? '',
      startedAt: (d['startedAt'] as Timestamp).toDate(),
      endedAt: d['endedAt'] != null ? (d['endedAt'] as Timestamp).toDate() : null,
      pausedAt: d['pausedAt'] != null ? (d['pausedAt'] as Timestamp).toDate() : null,
      totalPausedSeconds: d['totalPausedSeconds'] ?? 0,
      guestCount: d['guestCount'] ?? 1,
      hourlyRate: (d['hourlyRate'] ?? 0.0).toDouble(),
      orderItems: (d['orderItems'] as List<dynamic>? ?? [])
          .map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      discount: (d['discount'] ?? 0.0).toDouble(),
      notes: d['notes'],
      status: d['status'] ?? 'active',
      openedBy: d['openedBy'] ?? '',
      venueId: d['venueId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'tableId': tableId,
    'tableName': tableName,
    'startedAt': Timestamp.fromDate(startedAt),
    'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
    'pausedAt': pausedAt != null ? Timestamp.fromDate(pausedAt!) : null,
    'totalPausedSeconds': totalPausedSeconds,
    'guestCount': guestCount,
    'hourlyRate': hourlyRate,
    'orderItems': orderItems.map((e) => e.toMap()).toList(),
    'discount': discount,
    'notes': notes,
    'status': status,
    'openedBy': openedBy,
    'venueId': venueId,
  };

  SessionModel copyWith({
    String? id, String? tableId, String? tableName,
    DateTime? startedAt, DateTime? endedAt, DateTime? pausedAt,
    int? totalPausedSeconds, int? guestCount, double? hourlyRate,
    List<OrderItem>? orderItems, double? discount, String? notes,
    String? status, String? openedBy, String? venueId,
  }) => SessionModel(
    id: id ?? this.id, tableId: tableId ?? this.tableId,
    tableName: tableName ?? this.tableName, startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt, pausedAt: pausedAt ?? this.pausedAt,
    totalPausedSeconds: totalPausedSeconds ?? this.totalPausedSeconds,
    guestCount: guestCount ?? this.guestCount, hourlyRate: hourlyRate ?? this.hourlyRate,
    orderItems: orderItems ?? this.orderItems, discount: discount ?? this.discount,
    notes: notes ?? this.notes, status: status ?? this.status,
    openedBy: openedBy ?? this.openedBy, venueId: venueId ?? this.venueId,
  );
}

// ─── ORDER ITEM ──────────────────────────────────────────────────────────────

class OrderItem {
  final String menuItemId;
  final String name;
  final double unitPrice;
  final int quantity;
  final String category;

  const OrderItem({
    required this.menuItemId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.category,
  });

  double get subtotal => unitPrice * quantity;

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
    menuItemId: m['menuItemId'] ?? '',
    name: m['name'] ?? '',
    unitPrice: (m['unitPrice'] ?? 0.0).toDouble(),
    quantity: m['quantity'] ?? 1,
    category: m['category'] ?? '',
  );

  Map<String, dynamic> toMap() => {
    'menuItemId': menuItemId,
    'name': name,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'category': category,
  };

  OrderItem copyWith({int? quantity}) => OrderItem(
    menuItemId: menuItemId, name: name, unitPrice: unitPrice,
    quantity: quantity ?? this.quantity, category: category,
  );
}

// ─── MENU ITEM ───────────────────────────────────────────────────────────────

class MenuItem {
  final String id;
  final String name;
  final double price;
  final String category; // beers | snacks | spirits | soft drinks | food
  final String? imageUrl;
  final bool isAvailable;
  final int? stockCount;
  final String venueId;

  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.imageUrl,
    this.isAvailable = true,
    this.stockCount,
    required this.venueId,
  });

  factory MenuItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return MenuItem(
      id: doc.id,
      name: d['name'] ?? '',
      price: (d['price'] ?? 0.0).toDouble(),
      category: d['category'] ?? 'snacks',
      imageUrl: d['imageUrl'],
      isAvailable: d['isAvailable'] ?? true,
      stockCount: d['stockCount'],
      venueId: d['venueId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'price': price,
    'category': category,
    'imageUrl': imageUrl,
    'isAvailable': isAvailable,
    'stockCount': stockCount,
    'venueId': venueId,
  };

  MenuItem copyWith({
    String? name, double? price, String? category,
    String? imageUrl, bool? isAvailable, int? stockCount,
  }) => MenuItem(
    id: id, name: name ?? this.name, price: price ?? this.price,
    category: category ?? this.category, imageUrl: imageUrl ?? this.imageUrl,
    isAvailable: isAvailable ?? this.isAvailable, stockCount: stockCount ?? this.stockCount,
    venueId: venueId,
  );
}

// ─── BOOKING ─────────────────────────────────────────────────────────────────

class Booking {
  final String id;
  final String tableId;
  final String tableName;
  final String guestName;
  final String? guestPhone;
  final DateTime scheduledAt;
  final int durationMinutes;
  final int guestCount;
  final String status; // confirmed | cancelled | completed | no_show
  final double? depositAmount;
  final String? notes;
  final String createdBy;
  final String venueId;

  const Booking({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.guestName,
    this.guestPhone,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.guestCount,
    this.status = 'confirmed',
    this.depositAmount,
    this.notes,
    required this.createdBy,
    required this.venueId,
  });

  DateTime get endsAt => scheduledAt.add(Duration(minutes: durationMinutes));

  factory Booking.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Booking(
      id: doc.id,
      tableId: d['tableId'] ?? '',
      tableName: d['tableName'] ?? '',
      guestName: d['guestName'] ?? '',
      guestPhone: d['guestPhone'],
      scheduledAt: (d['scheduledAt'] as Timestamp).toDate(),
      durationMinutes: d['durationMinutes'] ?? 60,
      guestCount: d['guestCount'] ?? 2,
      status: d['status'] ?? 'confirmed',
      depositAmount: (d['depositAmount'])?.toDouble(),
      notes: d['notes'],
      createdBy: d['createdBy'] ?? '',
      venueId: d['venueId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'tableId': tableId,
    'tableName': tableName,
    'guestName': guestName,
    'guestPhone': guestPhone,
    'scheduledAt': Timestamp.fromDate(scheduledAt),
    'durationMinutes': durationMinutes,
    'guestCount': guestCount,
    'status': status,
    'depositAmount': depositAmount,
    'notes': notes,
    'createdBy': createdBy,
    'venueId': venueId,
  };

  Booking copyWith({String? status}) => Booking(
    id: id, tableId: tableId, tableName: tableName, guestName: guestName,
    guestPhone: guestPhone, scheduledAt: scheduledAt, durationMinutes: durationMinutes,
    guestCount: guestCount, status: status ?? this.status, depositAmount: depositAmount,
    notes: notes, createdBy: createdBy, venueId: venueId,
  );
}

// ─── APP USER ────────────────────────────────────────────────────────────────

enum UserRole { staff, supervisor, manager, owner }

class AppUser {
  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final String venueId;
  final bool isActive;
  final DateTime? lastLogin;

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.venueId,
    this.isActive = true,
    this.lastLogin,
  });

  bool get canAccessAdmin => role == UserRole.manager || role == UserRole.owner;
  bool get canVoid => role != UserRole.staff;
  bool get canApplyDiscount => role != UserRole.staff;

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      name: d['name'] ?? '',
      email: d['email'] ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.name == (d['role'] ?? 'staff'),
        orElse: () => UserRole.staff,
      ),
      venueId: d['venueId'] ?? '',
      isActive: d['isActive'] ?? true,
      lastLogin: d['lastLogin'] != null ? (d['lastLogin'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'email': email,
    'role': role.name,
    'venueId': venueId,
    'isActive': isActive,
    'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
  };
}

// ─── VENUE ───────────────────────────────────────────────────────────────────

class Venue {
  final String id;
  final String name;
  final String address;
  final String currency;
  final String currencySymbol;
  final Map<String, double> zoneRates; // zone -> rate override
  final bool isOpen;
  final String? logoUrl;

  const Venue({
    required this.id,
    required this.name,
    required this.address,
    this.currency = 'USD',
    this.currencySymbol = '\$',
    this.zoneRates = const {},
    this.isOpen = true,
    this.logoUrl,
  });

  factory Venue.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Venue(
      id: doc.id,
      name: d['name'] ?? '',
      address: d['address'] ?? '',
      currency: d['currency'] ?? 'USD',
      currencySymbol: d['currencySymbol'] ?? '\$',
      zoneRates: Map<String, double>.from(d['zoneRates'] ?? {}),
      isOpen: d['isOpen'] ?? true,
      logoUrl: d['logoUrl'],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'address': address,
    'currency': currency,
    'currencySymbol': currencySymbol,
    'zoneRates': zoneRates,
    'isOpen': isOpen,
    'logoUrl': logoUrl,
  };
}