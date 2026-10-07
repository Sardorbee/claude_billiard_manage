import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'firebase_options.dart';
import 'blocs/blocs.dart';
import 'repositories/repositories.dart';
import 'services/table_time_notifier.dart';
import 'theme/app_theme.dart';
import 'utils/router.dart';

const useEmulators = bool.fromEnvironment('USE_EMULATORS');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  // `--dart-define=USE_EMULATORS=true` points the app at the local Firebase
  // emulators (see firebase.json) instead of the live project.
  if (useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    // On web a remembered sign-in makes the SDK contact the live project
    // before the line above runs, and the switch to the emulator is then
    // silently ignored. Not remembering sign-ins in emulator mode avoids it.
    if (kIsWeb) await FirebaseAuth.instance.setPersistence(Persistence.NONE);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    SessionRepository.liveDatabase.useDatabaseEmulator('localhost', 9000);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
  }

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const TheFloorApp());
}

class TheFloorApp extends StatelessWidget {
  const TheFloorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Repositories (singletons)
    final activityRepo = ActivityRepository();
    final authRepo = AuthRepository(activityRepo);
    final tableRepo = TableRepository(activityRepo);
    final debtRepo = DebtRepository(activityRepo);
    final sessionRepo = SessionRepository(debtRepo, activityRepo);
    final menuRepo = MenuRepository(activityRepo);
    final bookingRepo = BookingRepository();
    final venueRepo = VenueRepository(activityRepo);
    final expenseRepo = ExpenseRepository(activityRepo);

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: activityRepo),
        RepositoryProvider.value(value: authRepo),
        RepositoryProvider.value(value: tableRepo),
        RepositoryProvider.value(value: sessionRepo),
        RepositoryProvider.value(value: debtRepo),
        RepositoryProvider.value(value: menuRepo),
        RepositoryProvider.value(value: bookingRepo),
        RepositoryProvider.value(value: venueRepo),
        RepositoryProvider.value(value: expenseRepo),
      ],
      child: _BlocProviders(
        authRepo: authRepo,
        tableRepo: tableRepo,
        sessionRepo: sessionRepo,
        menuRepo: menuRepo,
        bookingRepo: bookingRepo,
      ),
    );
  }
}

class _BlocProviders extends StatefulWidget {
  final AuthRepository authRepo;
  final TableRepository tableRepo;
  final SessionRepository sessionRepo; // still needed for StatsBloc
  final MenuRepository menuRepo;
  final BookingRepository bookingRepo;

  const _BlocProviders({
    required this.authRepo,
    required this.tableRepo,
    required this.sessionRepo,
    required this.menuRepo,
    required this.bookingRepo,
  });

  @override
  State<_BlocProviders> createState() => _BlocProvidersState();
}

class _BlocProvidersState extends State<_BlocProviders> {
  late final AuthBloc _authBloc;
  late final FloorBloc _floorBloc;
  late final MenuBloc _menuBloc;
  late final BookingsBloc _bookingsBloc;
  late final StatsBloc _statsBloc;
  final _notifier = TableTimeNotifier();
  // ✅ SessionBloc is intentionally NOT here — a fresh one is created per
  //    session screen so multiple tables never share state.

  @override
  void initState() {
    super.initState();
    _authBloc = AuthBloc(widget.authRepo);
    _floorBloc = FloorBloc(widget.tableRepo);
    _menuBloc = MenuBloc(widget.menuRepo);
    _bookingsBloc = BookingsBloc(widget.bookingRepo);
    _statsBloc = StatsBloc(widget.sessionRepo);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _authBloc),
        BlocProvider.value(value: _floorBloc),
        BlocProvider.value(value: _menuBloc),
        BlocProvider.value(value: _bookingsBloc),
        BlocProvider.value(value: _statsBloc),
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<AuthBloc, AuthState>(listener: _onAuthChange),
          // Keep the phone's time-up notifications in step with the floor.
          BlocListener<FloorBloc, FloorState>(
            listener: (_, state) {
              if (state is FloorLoaded) _notifier.sync(state.allTables);
            },
          ),
        ],
        child: _AppRoot(authBloc: _authBloc),
      ),
    );
  }

  void _onAuthChange(BuildContext context, AuthState state) {
    context.read<ActivityRepository>().actor =
        state is AuthAuthenticated ? state.user : null;
    if (state is AuthUnauthenticated) _notifier.clear();
    if (state is AuthAuthenticated) {
      final user = state.user;
      // Ask for notification permission once someone is signed in, then
      // schedule for whatever is already on the floor.
      _notifier.init().then((_) {
        final floor = _floorBloc.state;
        if (floor is FloorLoaded) _notifier.sync(floor.allTables);
      });
      _floorBloc.add(FloorLoadRequested(user.venueId));
      _menuBloc.add(MenuLoadRequested(user.venueId));
      _bookingsBloc.add(BookingsLoadRequested(user.venueId));
      _statsBloc.add(StatsLoadRequested(user.venueId));
    }
  }

  @override
  void dispose() {
    _authBloc.close();
    _floorBloc.close();
    _menuBloc.close();
    _bookingsBloc.close();
    _statsBloc.close();
    super.dispose();
  }
}

class _AppRoot extends StatefulWidget {
  final AuthBloc authBloc;
  const _AppRoot({required this.authBloc});
  @override State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  late final GoRouterRefreshStream _routerStream;

  @override
  void initState() {
    super.initState();
    _routerStream = GoRouterRefreshStream(widget.authBloc.stream);
  }

  @override
  Widget build(BuildContext context) {
    final router = AppRouter.create(widget.authBloc);
    return MaterialApp.router(
      title: 'The Floor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
