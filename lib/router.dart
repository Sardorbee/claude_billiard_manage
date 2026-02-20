import 'package:billiardtm/bloc/blocs.dart';
import 'package:billiardtm/screens/admin_screen.dart';
import 'package:billiardtm/screens/booking_screen.dart';
import 'package:billiardtm/screens/floor_screen.dart';
import 'package:billiardtm/screens/session_screen.dart';
import 'package:billiardtm/screens/stats_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../widgets/widgets.dart';
import '../screens/login_screen.dart';


class AppRouter {
  static GoRouter create(AuthBloc authBloc) {
    return GoRouter(
      initialLocation: '/floor',
      redirect: (context, state) {
        final authState = authBloc.state;
        final isLoggingIn = state.matchedLocation == '/login';

        if (authState is AuthUnauthenticated || authState is AuthInitial) {
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
          builder: (context, state, child) {
            final authState = context.read<AuthBloc>().state;
            final user = authState is AuthAuthenticated ? authState.user : null;
            final isAdmin = user?.canAccessAdmin ?? false;

            int currentIndex = 0;
            final loc = state.matchedLocation;
            if (loc.startsWith('/bookings')) currentIndex = 1;
            else if (loc.startsWith('/stats')) currentIndex = 2;
            else if (loc.startsWith('/admin')) currentIndex = 3;

            return Scaffold(
              body: child,
              bottomNavigationBar: AppBottomNav(
                currentIndex: currentIndex,
                isAdmin: isAdmin,
                onTap: (i) {
                  switch (i) {
                    case 0: context.go('/floor'); break;
                    case 1: context.go('/bookings'); break;
                    case 2: context.go('/stats'); break;
                    case 3: context.go('/admin'); break;
                  }
                },
              ),
            );
          },
          routes: [
            GoRoute(path: '/floor', builder: (_, __) => const FloorScreen()),
            GoRoute(path: '/bookings', builder: (_, __) => const BookingsScreen()),
            GoRoute(path: '/stats', builder: (_, __) => const StatsScreen()),
            GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
          ],
        ),

        // Session screen outside shell (no bottom nav)
        GoRoute(
          path: '/session/:tableId/:sessionId',
          builder: (context, state) {
            final tableId = state.pathParameters['tableId']!;
            final sessionId = state.pathParameters['sessionId']!;

            // If sessionId == 'new', wait for SessionBloc to have an active session
            return BlocListener<SessionBloc, SessionState>(
              listenWhen: (prev, curr) => prev is SessionLoading && curr is SessionActive,
              listener: (ctx, s) {
                // Session just opened, we're already on the right screen
              },
              child: sessionId == 'new'
                  ? _WaitingForSession(tableId: tableId)
                  : SessionScreen(tableId: tableId, sessionId: sessionId),
            );
          },
        ),
      ],
    );
  }
}

class _WaitingForSession extends StatelessWidget {
  final String tableId;
  const _WaitingForSession({required this.tableId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionBloc, SessionState>(
      builder: (context, state) {
        if (state is SessionActive) {
          return SessionScreen(tableId: state.session.tableId, sessionId: state.session.id);
        }
        return const Scaffold(
          backgroundColor: Color(0xFF080C0E),
          body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
        );
      },
    );
  }
}

// Makes GoRouter listen to bloc state changes
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    stream.listen((_) => notifyListeners());
  }
}