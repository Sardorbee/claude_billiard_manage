import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'firebase_options.dart';
import 'blocs/blocs.dart';
import 'repositories/repositories.dart';
import 'theme/app_theme.dart';
import 'utils/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
    final authRepo = AuthRepository();
    final tableRepo = TableRepository();
    final sessionRepo = SessionRepository();
    final menuRepo = MenuRepository();
    final bookingRepo = BookingRepository();
    final venueRepo = VenueRepository();

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: authRepo),
        RepositoryProvider.value(value: tableRepo),
        RepositoryProvider.value(value: sessionRepo),
        RepositoryProvider.value(value: menuRepo),
        RepositoryProvider.value(value: bookingRepo),
        RepositoryProvider.value(value: venueRepo),
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
      child: BlocListener<AuthBloc, AuthState>(
        listener: _onAuthChange,
        child: _AppRoot(authBloc: _authBloc),
      ),
    );
  }

  void _onAuthChange(BuildContext context, AuthState state) {
    if (state is AuthAuthenticated) {
      final user = state.user;
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
