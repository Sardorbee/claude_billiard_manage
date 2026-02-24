import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../blocs/blocs.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import '../screens/login_screen.dart';
import '../screens/floor/floor_screen.dart';
import '../screens/session/session_screen.dart';
import '../screens/stats/stats_screen.dart';
import '../screens/admin/admin_screen.dart';

class AppRouter {
  static GoRouter create(AuthBloc authBloc) {
    return GoRouter(
      initialLocation: '/floor',
      redirect: (context, state) {
        final authState = authBloc.state;
        final isLoggingIn = state.matchedLocation == '/login';

        // ← Don't redirect while Firebase is still checking auth
        if (authState is AuthInitial) return null;

        if (authState is AuthUnauthenticated) {
          return isLoggingIn ? null : '/login';
        }
        if (authState is AuthAuthenticated && isLoggingIn) {
          return '/floor';
        }
        return null;
      },
      refreshListenable: GoRouterRefreshStream(authBloc.stream),
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

        ShellRoute(
          builder: (context, state, child) {final authState = context.watch<AuthBloc>().state;
          if (authState is AuthInitial) {
            return const Scaffold(
              backgroundColor: Color(0xFF080C0E),
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF00E676)),
              ),
            );
          }

            final user = authState is AuthAuthenticated ? authState.user : null;
            final isAdmin = user?.canAccessAdmin ?? false;

            int currentIndex = 0;
            final loc = state.matchedLocation;
            if (loc.startsWith('/bookings')) {
              currentIndex = 4;
            } else if (loc.startsWith('/stats')) {
              currentIndex = 1;
            } else if (loc.startsWith('/admin')) {
              currentIndex = 2;
            }

            return Scaffold(
              body: child,
              bottomNavigationBar: _BottomNav(
                currentIndex: currentIndex,
                isAdmin: isAdmin,
                onTap: (i) {
                  switch (i) {
                    case 0:
                      context.go('/floor');
                      break;
                    // case 1: context.go('/bookings'); break;
                    case 1:
                      context.go('/stats');
                      break;
                    case 2:
                      context.go('/admin');
                      break;
                  }
                },
              ),
            );
          },
          routes: [
            GoRoute(path: '/floor', builder: (_, __) => const FloorScreen()),
            // GoRoute(path: '/bookings', builder: (_, __) => const BookingsScreen()),
            GoRoute(path: '/stats', builder: (_, __) => const StatsScreen()),
            GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
          ],
        ),

        // ── Session screen ────────────────────────────────────────────────
        // A FRESH SessionBloc is created here and disposed when the route
        // is popped. Two tables open simultaneously = two separate blocs,
        // each with their own timer, RTDB listener, and session state.
        //
        // Navigation options:
        //   A) Tap existing active table:
        //      context.push('/session/T-01/abc123')
        //
        //   B) Open new session (pass TableModel + guestCount via `extra`):
        //      context.push('/session/T-01/new',
        //        extra: {'table': tableModel, 'guestCount': 2})
        GoRoute(
          path: '/session/:tableId/:sessionId',
          builder: (context, routeState) {
            final tableId = routeState.pathParameters['tableId']!;
            final sessionId = routeState.pathParameters['sessionId']!;
            final extra = routeState.extra as Map<String, dynamic>?;

            final sessionRepo = context.read<SessionRepository>();
            final menuBloc = context.read<MenuBloc>(); // shared, read-only
            final authState = context.read<AuthBloc>().state;
            final user = authState is AuthAuthenticated ? authState.user : null;

            // BlocProvider.value would share ownership — we use BlocProvider
            // (create) so this bloc is OWNED by this route and auto-disposed.
            return BlocProvider<SessionBloc>(
              create: (_) {
                final bloc = SessionBloc(sessionRepo);

                if (sessionId == 'new' && extra != null) {
                  // Opening a brand-new session
                  final table = extra['table'] as TableModel;
                  final guestCount = extra['guestCount'] as int? ?? 2;
                  bloc.add(SessionOpenRequested(
                    venueId: user?.venueId ?? '',
                    table: table,
                    guestCount: guestCount,
                    openedBy: user?.uid ?? '',
                  ));
                } else {
                  // Re-entering an existing active session
                  bloc.add(SessionLoadRequested(
                    venueId: user?.venueId ?? '',
                    tableId: tableId,
                    sessionId: sessionId,
                  ));
                }
                return bloc;
              },
              // Inject MenuBloc so _AddItemsSheet can read it inside the route
              child: BlocProvider.value(
                value: menuBloc,
                child: SessionScreen(tableId: tableId, sessionId: sessionId),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─── Bottom nav (inlined to avoid widgets.dart circular dep) ─────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final bool isAdmin;
  final Function(int) onTap;
  const _BottomNav(
      {required this.currentIndex, required this.isAdmin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E1417),
        border: Border(top: BorderSide(color: Color(0xFF1E2D32))),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: const Color(0xFF5A7A84),
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded), label: 'Floor'),
          // const BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Bookings'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded), label: 'Stats'),
          if (isAdmin)
            const BottomNavigationBarItem(
                icon: Icon(Icons.admin_panel_settings_outlined),
                label: 'Admin'),
        ],
      ),
    );
  }
}

// Makes GoRouter listen to bloc state changes
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    stream.listen((_) => notifyListeners());
  }
}
