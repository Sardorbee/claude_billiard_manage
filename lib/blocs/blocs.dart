import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';

// ════════════════════════════════════════════════════════════════════════════
// AUTH BLOC
// ════════════════════════════════════════════════════════════════════════════

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override List<Object?> get props => [];
}
class AuthSignInRequested extends AuthEvent {
  final String email, password;
  const AuthSignInRequested(this.email, this.password);
  @override List<Object?> get props => [email, password];
}
class AuthSignOutRequested extends AuthEvent {}
class AuthUserChanged extends AuthEvent {
  final AppUser? user;
  const AuthUserChanged(this.user);
  @override List<Object?> get props => [user];
}

abstract class AuthState extends Equatable {
  const AuthState();
  @override List<Object?> get props => [];
}
class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class AuthAuthenticated extends AuthState {
  final AppUser user;
  const AuthAuthenticated(this.user);
  @override List<Object?> get props => [user];
}
class AuthUnauthenticated extends AuthState {}
class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
  @override List<Object?> get props => [message];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepo;
  StreamSubscription? _authSub;

  AuthBloc(this._authRepo) : super(AuthInitial()) {
    _authSub = _authRepo.authStateChanges.listen((user) async {
      if (user != null) {
        final appUser = await _authRepo.getUser(user.uid);
        add(AuthUserChanged(appUser));
      } else {
        add(AuthUserChanged(null));
      }
    });

    on<AuthSignInRequested>(_onSignIn);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthUserChanged>(_onUserChanged);
  }

  Future<void> _onSignIn(AuthSignInRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _authRepo.signIn(event.email, event.password);
      if (user != null) {
        emit(AuthAuthenticated(user));
      } else {
        emit(const AuthError('User not found'));
      }
    } catch (e) {
      emit(AuthError(e.toString().replaceAll('Exception:', '').trim()));
    }
  }

  Future<void> _onSignOut(AuthSignOutRequested event, Emitter<AuthState> emit) async {
    await _authRepo.signOut();
    emit(AuthUnauthenticated());
  }

  void _onUserChanged(AuthUserChanged event, Emitter<AuthState> emit) {
    if (event.user != null) {
      emit(AuthAuthenticated(event.user!));
    } else {
      emit(AuthUnauthenticated());
    }
  }

  @override
  Future<void> close() {
    _authSub?.cancel();
    return super.close();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// FLOOR BLOC
// ════════════════════════════════════════════════════════════════════════════

abstract class FloorEvent extends Equatable {
  const FloorEvent();
  @override List<Object?> get props => [];
}
class FloorLoadRequested extends FloorEvent {
  final String venueId;
  const FloorLoadRequested(this.venueId);
  @override List<Object?> get props => [venueId];
}
class FloorFilterChanged extends FloorEvent {
  final String? filter; // null = all
  const FloorFilterChanged(this.filter);
  @override List<Object?> get props => [filter];
}
class _FloorTablesUpdated extends FloorEvent {
  final List<TableModel> tables;
  const _FloorTablesUpdated(this.tables);
  @override List<Object?> get props => [tables];
}

abstract class FloorState extends Equatable {
  const FloorState();
  @override List<Object?> get props => [];
}
class FloorInitial extends FloorState {}
class FloorLoading extends FloorState {}
class FloorLoaded extends FloorState {
  final List<TableModel> allTables;
  final String? activeFilter;

  const FloorLoaded(this.allTables, {this.activeFilter});

  List<TableModel> get filteredTables {
    if (activeFilter == null) return allTables;
    return allTables.where((t) => t.type.name == activeFilter).toList();
  }

  Map<String, List<TableModel>> get byZone {
    final map = <String, List<TableModel>>{};
    for (final t in filteredTables) {
      map.putIfAbsent(t.zone, () => []).add(t);
    }
    return map;
  }

  @override List<Object?> get props => [allTables, activeFilter];
}
class FloorError extends FloorState {
  final String message;
  const FloorError(this.message);
  @override List<Object?> get props => [message];
}

class FloorBloc extends Bloc<FloorEvent, FloorState> {
  final TableRepository _tableRepo;
  StreamSubscription? _tablesSub;

  FloorBloc(this._tableRepo) : super(FloorInitial()) {
    on<FloorLoadRequested>(_onLoad);
    on<FloorFilterChanged>(_onFilter);
    on<_FloorTablesUpdated>(_onTablesUpdated);
  }

  Future<void> _onLoad(FloorLoadRequested event, Emitter<FloorState> emit) async {
    emit(FloorLoading());
    await _tablesSub?.cancel();
    _tablesSub = _tableRepo.watchTables(event.venueId).listen(
      (tables) => add(_FloorTablesUpdated(tables)),
      onError: (e) => emit(FloorError(e.toString())),
    );
  }

  void _onFilter(FloorFilterChanged event, Emitter<FloorState> emit) {
    if (state is FloorLoaded) {
      final s = state as FloorLoaded;
      emit(FloorLoaded(s.allTables, activeFilter: event.filter));
    }
  }

  void _onTablesUpdated(_FloorTablesUpdated event, Emitter<FloorState> emit) {
    final filter = state is FloorLoaded ? (state as FloorLoaded).activeFilter : null;
    emit(FloorLoaded(event.tables, activeFilter: filter));
  }

  @override
  Future<void> close() {
    _tablesSub?.cancel();
    return super.close();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SESSION BLOC
// ════════════════════════════════════════════════════════════════════════════

abstract class SessionEvent extends Equatable {
  const SessionEvent();
  @override List<Object?> get props => [];
}
class SessionOpenRequested extends SessionEvent {
  final String venueId;
  final TableModel table;
  final int guestCount;
  final String openedBy;
  const SessionOpenRequested({required this.venueId, required this.table, required this.guestCount, required this.openedBy});
  @override List<Object?> get props => [venueId, table.id, guestCount];
}
class SessionLoadRequested extends SessionEvent {
  final String venueId, tableId, sessionId;
  const SessionLoadRequested({required this.venueId, required this.tableId, required this.sessionId});
  @override List<Object?> get props => [sessionId];
}
class SessionPauseRequested extends SessionEvent {}
class SessionResumeRequested extends SessionEvent {}
class SessionAddItemsRequested extends SessionEvent {
  final List<OrderItem> items;
  const SessionAddItemsRequested(this.items);
  @override List<Object?> get props => [items];
}
class SessionTransferRequested extends SessionEvent {
  final String toTableId, toTableName;
  const SessionTransferRequested({required this.toTableId, required this.toTableName});
  @override List<Object?> get props => [toTableId];
}
class SessionNotesUpdated extends SessionEvent {
  final String notes;
  const SessionNotesUpdated(this.notes);
  @override List<Object?> get props => [notes];
}
class SessionDiscountApplied extends SessionEvent {
  final double discountPct;
  const SessionDiscountApplied(this.discountPct);
  @override List<Object?> get props => [discountPct];
}
class SessionCheckoutRequested extends SessionEvent {}
class SessionVoidRequested extends SessionEvent {}
class _SessionLiveUpdated extends SessionEvent {
  final Map<String, dynamic>? live;
  const _SessionLiveUpdated(this.live);
  @override List<Object?> get props => [live];
}
class _SessionFsUpdated extends SessionEvent {
  final SessionModel session;
  const _SessionFsUpdated(this.session);
  @override List<Object?> get props => [session?.id];
}
class SessionTick extends SessionEvent {}

abstract class SessionState extends Equatable {
  const SessionState();
  @override List<Object?> get props => [];
}
class SessionInitial extends SessionState {}
class SessionLoading extends SessionState {}
class SessionActive extends SessionState {
  final SessionModel session;
  final Map<String, dynamic>? live;
  final int elapsedSeconds;
  final bool isPaused;

  const SessionActive({required this.session, this.live, required this.elapsedSeconds, this.isPaused = false});

  double get currentTimeCharge => (elapsedSeconds / 3600) * session.hourlyRate;
  double get fbTotal => session.fbTotal;
  double get subtotal => currentTimeCharge + fbTotal;
  double get discountAmount => session.discount > 0 ? subtotal * (session.discount / 100) : 0;
  double get total => subtotal - discountAmount;

  @override List<Object?> get props => [session, live, elapsedSeconds, isPaused];
}
class SessionCompleted extends SessionState {
  final SessionModel session;
  const SessionCompleted(this.session);
  @override List<Object?> get props => [session];
}
class SessionError extends SessionState {
  final String message;
  const SessionError(this.message);
  @override List<Object?> get props => [message];
}

class SessionBloc extends Bloc<SessionEvent, SessionState> {
  final SessionRepository _sessionRepo;
  StreamSubscription? _liveSub;
  StreamSubscription? _fsSub;
  Timer? _ticker;
  String? _venueId, _tableId, _sessionId;
  Map<String, dynamic>? _liveData;
  SessionModel? _session;

  SessionBloc(this._sessionRepo) : super(SessionInitial()) {
    on<SessionOpenRequested>(_onOpen);
    on<SessionLoadRequested>(_onLoad);
    on<SessionPauseRequested>(_onPause);
    on<SessionResumeRequested>(_onResume);
    on<SessionAddItemsRequested>(_onAddItems);
    on<SessionTransferRequested>(_onTransfer);
    on<SessionNotesUpdated>(_onNotes);
    on<SessionDiscountApplied>(_onDiscount);
    on<SessionCheckoutRequested>(_onCheckout);
    on<SessionVoidRequested>(_onVoid);
    on<_SessionLiveUpdated>(_onLiveUpdate);
    on<_SessionFsUpdated>(_onFsUpdate);
    on<SessionTick>(_onTick);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => add(SessionTick()));
  }

  void _startListeners(String venueId, String tableId, String sessionId) {
    _venueId = venueId; _tableId = tableId; _sessionId = sessionId;
    _liveSub?.cancel();
    _liveSub = _sessionRepo.watchLiveSession(venueId, tableId).listen(
      (data) => add(_SessionLiveUpdated(data)));
  }

  int _computeElapsed() {
    if (_liveData == null || _session == null) return 0;
    final startedAt = _liveData!['startedAt'] as int? ?? _session!.startedAt.millisecondsSinceEpoch;
    final totalPausedMs = _liveData!['totalPausedMs'] as int? ?? 0;
    final pausedAt = _liveData!['pausedAt'] as int?;
    final now = pausedAt ?? DateTime.now().millisecondsSinceEpoch;
    final elapsed = ((now - startedAt - totalPausedMs) / 1000).floor();
    return elapsed < 0 ? 0 : elapsed;
  }

  Future<void> _onOpen(SessionOpenRequested event, Emitter<SessionState> emit) async {
    emit(SessionLoading());
    try {
      final session = await _sessionRepo.openSession(
        venueId: event.venueId, table: event.table,
        guestCount: event.guestCount, openedBy: event.openedBy,
      );
      _session = session;
      _startListeners(event.venueId, event.table.id, session.id);
      _startTicker();
      emit(SessionActive(session: session, elapsedSeconds: 0));
    } catch (e) {
      emit(SessionError(e.toString()));
    }
  }

  Future<void> _onLoad(SessionLoadRequested event, Emitter<SessionState> emit) async {
    emit(SessionLoading());
    try {
      _session = await _sessionRepo.getSession(event.venueId, event.sessionId);
      _startListeners(event.venueId, event.tableId, event.sessionId);
      _startTicker();
      emit(SessionActive(session: _session!, elapsedSeconds: _computeElapsed()));
    } catch (e) {
      emit(SessionError(e.toString()));
    }
  }

  Future<void> _onPause(SessionPauseRequested event, Emitter<SessionState> emit) async {
    if (_venueId == null || _tableId == null || _sessionId == null) return;
    await _sessionRepo.pauseSession(_venueId!, _tableId!, _sessionId!);
  }

  Future<void> _onResume(SessionResumeRequested event, Emitter<SessionState> emit) async {
    if (_venueId == null || _tableId == null || _sessionId == null || _liveData == null) return;
    final pausedAt = _liveData!['pausedAt'] as int?;
    if (pausedAt != null) {
      await _sessionRepo.resumeSession(_venueId!, _tableId!, _sessionId!, pausedAt);
    }
  }

  Future<void> _onAddItems(SessionAddItemsRequested event, Emitter<SessionState> emit) async {
    if (_venueId == null || _sessionId == null) return;
    await _sessionRepo.addOrderItems(_venueId!, _sessionId!, event.items);
    _session = await _sessionRepo.getSession(_venueId!, _sessionId!);
    if (state is SessionActive) {
      final s = state as SessionActive;
      emit(SessionActive(session: _session!, live: s.live, elapsedSeconds: s.elapsedSeconds, isPaused: s.isPaused));
    }
  }

  Future<void> _onTransfer(SessionTransferRequested event, Emitter<SessionState> emit) async {
    if (_venueId == null || _sessionId == null || _tableId == null) return;
    await _sessionRepo.transferSession(_venueId!, _sessionId!, _tableId!, event.toTableId, event.toTableName);
    _tableId = event.toTableId;
    _startListeners(_venueId!, event.toTableId, _sessionId!);
    if (state is SessionActive) {
      final s = state as SessionActive;
      final updated = s.session.copyWith(tableId: event.toTableId, tableName: event.toTableName);
      _session = updated;
      emit(SessionActive(session: updated, live: s.live, elapsedSeconds: s.elapsedSeconds));
    }
  }

  Future<void> _onNotes(SessionNotesUpdated event, Emitter<SessionState> emit) async {
    if (_venueId == null || _sessionId == null) return;
    await _sessionRepo.updateSessionNotes(_venueId!, _sessionId!, event.notes);
    _session = _session?.copyWith(notes: event.notes);
    if (state is SessionActive) {
      final s = state as SessionActive;
      emit(SessionActive(session: _session!, live: s.live, elapsedSeconds: s.elapsedSeconds, isPaused: s.isPaused));
    }
  }

  Future<void> _onDiscount(SessionDiscountApplied event, Emitter<SessionState> emit) async {
    if (_venueId == null || _sessionId == null) return;
    await _sessionRepo.applyDiscount(_venueId!, _sessionId!, event.discountPct);
    _session = _session?.copyWith(discount: event.discountPct);
    if (state is SessionActive) {
      final s = state as SessionActive;
      emit(SessionActive(session: _session!, live: s.live, elapsedSeconds: s.elapsedSeconds, isPaused: s.isPaused));
    }
  }

  Future<void> _onCheckout(SessionCheckoutRequested event, Emitter<SessionState> emit) async {
    if (_venueId == null || _sessionId == null || _tableId == null) return;
    final s = state as SessionActive;
    final completed = await _sessionRepo.checkoutSession(
      venueId: _venueId!, sessionId: _sessionId!,
      tableId: _tableId!, finalTotal: s.total,
    );
    _ticker?.cancel();
    emit(SessionCompleted(completed));
  }

  Future<void> _onVoid(SessionVoidRequested event, Emitter<SessionState> emit) async {
    if (_venueId == null || _sessionId == null || _tableId == null) return;
    await _sessionRepo.voidSession(_venueId!, _sessionId!, _tableId!);
    _ticker?.cancel();
    emit(SessionInitial());
  }

  void _onLiveUpdate(_SessionLiveUpdated event, Emitter<SessionState> emit) {
    _liveData = event.live;
    _emitActive(emit);
  }

  void _onFsUpdate(_SessionFsUpdated event, Emitter<SessionState> emit) {
    _session = event.session;
    _emitActive(emit);
  }

  void _onTick(SessionTick event, Emitter<SessionState> emit) {
    _emitActive(emit);
  }

  void _emitActive(Emitter<SessionState> emit) {
    if (_session == null) return;
    final isPaused = _liveData?['status'] == 'paused';
    final elapsed = _computeElapsed();
    emit(SessionActive(
      session: _session!,
      live: _liveData,
      elapsedSeconds: elapsed,
      isPaused: isPaused,
    ));
  }

  @override
  Future<void> close() {
    _liveSub?.cancel();
    _fsSub?.cancel();
    _ticker?.cancel();
    return super.close();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MENU BLOC
// ════════════════════════════════════════════════════════════════════════════

abstract class MenuEvent extends Equatable {
  const MenuEvent();
  @override List<Object?> get props => [];
}
class MenuLoadRequested extends MenuEvent {
  final String venueId;
  const MenuLoadRequested(this.venueId);
  @override List<Object?> get props => [venueId];
}
class MenuCategoryFilterChanged extends MenuEvent {
  final String? category;
  const MenuCategoryFilterChanged(this.category);
  @override List<Object?> get props => [category];
}
class MenuSearchChanged extends MenuEvent {
  final String query;
  const MenuSearchChanged(this.query);
  @override List<Object?> get props => [query];
}
class MenuItemAddRequested extends MenuEvent {
  final MenuItem item;
  const MenuItemAddRequested(this.item);
  @override List<Object?> get props => [item];
}
class MenuItemUpdateRequested extends MenuEvent {
  final MenuItem item;
  const MenuItemUpdateRequested(this.item);
  @override List<Object?> get props => [item];
}
class MenuItemDeleteRequested extends MenuEvent {
  final String itemId;
  const MenuItemDeleteRequested(this.itemId);
  @override List<Object?> get props => [itemId];
}
class _MenuItemsUpdated extends MenuEvent {
  final List<MenuItem> items;
  const _MenuItemsUpdated(this.items);
  @override List<Object?> get props => [items];
}

abstract class MenuState extends Equatable {
  const MenuState();
  @override List<Object?> get props => [];
}
class MenuInitial extends MenuState {}
class MenuLoading extends MenuState {}
class MenuLoaded extends MenuState {
  final List<MenuItem> allItems;
  final String? activeCategory;
  final String searchQuery;

  const MenuLoaded(this.allItems, {this.activeCategory, this.searchQuery = ''});

  List<MenuItem> get filteredItems {
    var items = allItems;
    if (activeCategory != null) {
      items = items.where((i) => i.category == activeCategory).toList();
    }
    if (searchQuery.isNotEmpty) {
      items = items.where((i) => i.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();
    }
    return items;
  }

  List<String> get categories {
    final cats = allItems.map((i) => i.category).toSet().toList();
    cats.sort();
    return cats;
  }

  @override List<Object?> get props => [allItems, activeCategory, searchQuery];
}
class MenuError extends MenuState {
  final String message;
  const MenuError(this.message);
  @override List<Object?> get props => [message];
}

class MenuBloc extends Bloc<MenuEvent, MenuState> {
  final MenuRepository _menuRepo;
  StreamSubscription? _menuSub;
  String? _venueId;

  MenuBloc(this._menuRepo) : super(MenuInitial()) {
    on<MenuLoadRequested>(_onLoad);
    on<MenuCategoryFilterChanged>(_onCategoryFilter);
    on<MenuSearchChanged>(_onSearch);
    on<MenuItemAddRequested>(_onAdd);
    on<MenuItemUpdateRequested>(_onUpdate);
    on<MenuItemDeleteRequested>(_onDelete);
    on<_MenuItemsUpdated>(_onUpdated);
  }

  Future<void> _onLoad(MenuLoadRequested event, Emitter<MenuState> emit) async {
    _venueId = event.venueId;
    emit(MenuLoading());
    await _menuSub?.cancel();
    _menuSub = _menuRepo.watchMenu(event.venueId).listen(
      (items) => add(_MenuItemsUpdated(items)));
  }

  void _onCategoryFilter(MenuCategoryFilterChanged event, Emitter<MenuState> emit) {
    if (state is MenuLoaded) {
      final s = state as MenuLoaded;
      emit(MenuLoaded(s.allItems, activeCategory: event.category, searchQuery: s.searchQuery));
    }
  }

  void _onSearch(MenuSearchChanged event, Emitter<MenuState> emit) {
    if (state is MenuLoaded) {
      final s = state as MenuLoaded;
      emit(MenuLoaded(s.allItems, activeCategory: s.activeCategory, searchQuery: event.query));
    }
  }

  Future<void> _onAdd(MenuItemAddRequested event, Emitter<MenuState> emit) async {
    if (_venueId == null) return;
    await _menuRepo.addItem(_venueId!, event.item);
  }

  Future<void> _onUpdate(MenuItemUpdateRequested event, Emitter<MenuState> emit) async {
    if (_venueId == null) return;
    await _menuRepo.updateItem(_venueId!, event.item);
  }

  Future<void> _onDelete(MenuItemDeleteRequested event, Emitter<MenuState> emit) async {
    if (_venueId == null) return;
    await _menuRepo.deleteItem(_venueId!, event.itemId);
  }

  void _onUpdated(_MenuItemsUpdated event, Emitter<MenuState> emit) {
    final s = state is MenuLoaded ? state as MenuLoaded : null;
    emit(MenuLoaded(event.items, activeCategory: s?.activeCategory, searchQuery: s?.searchQuery ?? ''));
  }

  @override
  Future<void> close() {
    _menuSub?.cancel();
    return super.close();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BOOKINGS BLOC
// ════════════════════════════════════════════════════════════════════════════

abstract class BookingsEvent extends Equatable {
  const BookingsEvent();
  @override List<Object?> get props => [];
}
class BookingsLoadRequested extends BookingsEvent {
  final String venueId;
  const BookingsLoadRequested(this.venueId);
  @override List<Object?> get props => [venueId];
}
class BookingsDateSelected extends BookingsEvent {
  final DateTime date;
  const BookingsDateSelected(this.date);
  @override List<Object?> get props => [date];
}
class BookingCreateRequested extends BookingsEvent {
  final Booking booking;
  const BookingCreateRequested(this.booking);
  @override List<Object?> get props => [booking];
}
class BookingStatusUpdateRequested extends BookingsEvent {
  final String bookingId, status, tableId;
  const BookingStatusUpdateRequested({required this.bookingId, required this.status, required this.tableId});
  @override List<Object?> get props => [bookingId, status];
}
class BookingDeleteRequested extends BookingsEvent {
  final String bookingId, tableId;
  const BookingDeleteRequested({required this.bookingId, required this.tableId});
  @override List<Object?> get props => [bookingId];
}
class _BookingsUpdated extends BookingsEvent {
  final List<Booking> bookings;
  const _BookingsUpdated(this.bookings);
  @override List<Object?> get props => [bookings];
}

abstract class BookingsState extends Equatable {
  const BookingsState();
  @override List<Object?> get props => [];
}
class BookingsInitial extends BookingsState {}
class BookingsLoading extends BookingsState {}
class BookingsLoaded extends BookingsState {
  final List<Booking> allBookings;
  final DateTime selectedDate;
  final Map<DateTime, List<Booking>> eventsByDay;

  const BookingsLoaded({required this.allBookings, required this.selectedDate, required this.eventsByDay});

  List<Booking> get selectedDayBookings {
    final key = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    return eventsByDay[key] ?? [];
  }

  @override List<Object?> get props => [allBookings, selectedDate];
}
class BookingsError extends BookingsState {
  final String message;
  const BookingsError(this.message);
  @override List<Object?> get props => [message];
}

class BookingsBloc extends Bloc<BookingsEvent, BookingsState> {
  final BookingRepository _bookingRepo;
  StreamSubscription? _bookingsSub;
  String? _venueId;

  BookingsBloc(this._bookingRepo) : super(BookingsInitial()) {
    on<BookingsLoadRequested>(_onLoad);
    on<BookingsDateSelected>(_onDateSelected);
    on<BookingCreateRequested>(_onCreate);
    on<BookingStatusUpdateRequested>(_onStatusUpdate);
    on<BookingDeleteRequested>(_onDelete);
    on<_BookingsUpdated>(_onUpdated);
  }

  Future<void> _onLoad(BookingsLoadRequested event, Emitter<BookingsState> emit) async {
    _venueId = event.venueId;
    emit(BookingsLoading());
    await _bookingsSub?.cancel();
    _bookingsSub = _bookingRepo.watchBookings(event.venueId).listen(
      (bookings) => add(_BookingsUpdated(bookings)));
  }

  void _onDateSelected(BookingsDateSelected event, Emitter<BookingsState> emit) {
    if (state is BookingsLoaded) {
      final s = state as BookingsLoaded;
      emit(BookingsLoaded(allBookings: s.allBookings, selectedDate: event.date, eventsByDay: s.eventsByDay));
    }
  }

  Future<void> _onCreate(BookingCreateRequested event, Emitter<BookingsState> emit) async {
    if (_venueId == null) return;
    await _bookingRepo.createBooking(_venueId!, event.booking);
  }

  Future<void> _onStatusUpdate(BookingStatusUpdateRequested event, Emitter<BookingsState> emit) async {
    if (_venueId == null) return;
    await _bookingRepo.updateBookingStatus(_venueId!, event.bookingId, event.status, event.tableId);
  }

  Future<void> _onDelete(BookingDeleteRequested event, Emitter<BookingsState> emit) async {
    if (_venueId == null) return;
    await _bookingRepo.deleteBooking(_venueId!, event.bookingId, event.tableId);
  }

  void _onUpdated(_BookingsUpdated event, Emitter<BookingsState> emit) {
    final byDay = <DateTime, List<Booking>>{};
    for (final b in event.bookings) {
      final key = DateTime(b.scheduledAt.year, b.scheduledAt.month, b.scheduledAt.day);
      byDay.putIfAbsent(key, () => []).add(b);
    }
    final selectedDate = state is BookingsLoaded ? (state as BookingsLoaded).selectedDate : DateTime.now();
    emit(BookingsLoaded(allBookings: event.bookings, selectedDate: selectedDate, eventsByDay: byDay));
  }

  @override
  Future<void> close() {
    _bookingsSub?.cancel();
    return super.close();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// STATS BLOC
// ════════════════════════════════════════════════════════════════════════════

abstract class StatsEvent extends Equatable {
  const StatsEvent();
  @override List<Object?> get props => [];
}
class StatsLoadRequested extends StatsEvent {
  final String venueId;
  final String range; // today | week | month
  const StatsLoadRequested(this.venueId, {this.range = 'today'});
  @override List<Object?> get props => [venueId, range];
}

class StatsData {
  final double totalRevenue;
  final double timeRevenue;
  final double fbRevenue;
  final int totalSessions;
  final double avgSessionMinutes;
  final double avgSessionValue;
  final List<SessionModel> sessions;
  final Map<String, double> revenueByDay;
  final Map<String, double> revenueByTable;
  final Map<String, int> topMenuItems;
  final Map<int, int> sessionsByHour;

  const StatsData({
    required this.totalRevenue,
    required this.timeRevenue,
    required this.fbRevenue,
    required this.totalSessions,
    required this.avgSessionMinutes,
    required this.avgSessionValue,
    required this.sessions,
    required this.revenueByDay,
    required this.revenueByTable,
    required this.topMenuItems,
    required this.sessionsByHour,
  });
}

abstract class StatsState extends Equatable {
  const StatsState();
  @override List<Object?> get props => [];
}
class StatsInitial extends StatsState {}
class StatsLoading extends StatsState {}
class StatsLoaded extends StatsState {
  final StatsData data;
  final String range;
  const StatsLoaded(this.data, this.range);
  @override List<Object?> get props => [data, range];
}
class StatsError extends StatsState {
  final String message;
  const StatsError(this.message);
  @override List<Object?> get props => [message];
}

class StatsBloc extends Bloc<StatsEvent, StatsState> {
  final SessionRepository _sessionRepo;

  StatsBloc(this._sessionRepo) : super(StatsInitial()) {
    on<StatsLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(StatsLoadRequested event, Emitter<StatsState> emit) async {
    emit(StatsLoading());
    try {
      final now = DateTime.now();
      DateTime from;
      switch (event.range) {
        case 'week': from = now.subtract(const Duration(days: 7)); break;
        case 'month': from = DateTime(now.year, now.month, 1); break;
        default: from = DateTime(now.year, now.month, now.day);
      }

      final sessions = await _sessionRepo.getSessionsInRange(event.venueId, from, now);

      double totalRevenue = 0, timeRevenue = 0, fbRevenue = 0;
      double totalMinutes = 0;
      final revenueByDay = <String, double>{};
      final revenueByTable = <String, double>{};
      final topItems = <String, int>{};
      final byHour = <int, int>{};

      for (final s in sessions) {
        totalRevenue += s.total;
        timeRevenue += s.timeCharge;
        fbRevenue += s.fbTotal;
        totalMinutes += s.elapsedSeconds / 60;

        final dayKey = '${s.startedAt.month}/${s.startedAt.day}';
        revenueByDay[dayKey] = (revenueByDay[dayKey] ?? 0) + s.total;
        revenueByTable[s.tableName] = (revenueByTable[s.tableName] ?? 0) + s.total;

        final hour = s.startedAt.hour;
        byHour[hour] = (byHour[hour] ?? 0) + 1;

        for (final item in s.orderItems) {
          topItems[item.name] = (topItems[item.name] ?? 0) + item.quantity;
        }
      }

      emit(StatsLoaded(StatsData(
        totalRevenue: totalRevenue,
        timeRevenue: timeRevenue,
        fbRevenue: fbRevenue,
        totalSessions: sessions.length,
        avgSessionMinutes: sessions.isNotEmpty ? totalMinutes / sessions.length : 0,
        avgSessionValue: sessions.isNotEmpty ? totalRevenue / sessions.length : 0,
        sessions: sessions,
        revenueByDay: revenueByDay,
        revenueByTable: revenueByTable,
        topMenuItems: topItems,
        sessionsByHour: byHour,
      ), event.range));
    } catch (e) {
      emit(StatsError(e.toString()));
    }
  }
}
