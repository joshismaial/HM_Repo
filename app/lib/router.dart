import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'core/back_nav.dart';
import 'screens/common/legal_screen.dart';
import 'screens/owner/add_room_screen.dart';
import 'screens/owner/auth_screens.dart';
import 'screens/owner/complaints_screen.dart';
import 'screens/owner/delete_account_screen.dart';
import 'screens/owner/home_screen.dart';
import 'screens/owner/hostel_form_screen.dart';
import 'screens/owner/hostels_screen.dart';
import 'screens/owner/invite_screen.dart';
import 'screens/owner/more_screen.dart';
import 'screens/owner/notices_screen.dart';
import 'screens/owner/owner_shell.dart';
import 'screens/owner/record_payment_screen.dart';
import 'screens/owner/removed_hostels_screen.dart';
import 'screens/owner/rent_screen.dart';
import 'screens/owner/reports_screen.dart';
import 'screens/owner/requests_screen.dart';
import 'screens/owner/rooms_screen.dart';
import 'screens/owner/settings_screen.dart';
import 'screens/owner/staff_screen.dart';
import 'screens/owner/share_bed_screen.dart';
import 'screens/owner/tenant_details_screen.dart';
import 'screens/owner/tenant_rooms_screen.dart';
import 'screens/owner/tenants_screen.dart';
import 'screens/owner/welcome_screen.dart';
import 'screens/student/get_app_screen.dart';
import 'screens/student/join_screens.dart';
import 'screens/student/student_home.dart';
import 'screens/student/verify_screen.dart';

/// Re-checks routes when the owner logs in or out.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

bool _isOwnerArea(String path) =>
    path == '/hostels' || path.startsWith('/hostels/') || path.startsWith('/h/') || path == '/delete-account';

GoRouter buildRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: _AuthListenable(),
    redirect: (context, state) {
      final path = state.uri.path;
      final loggedIn = Supabase.instance.client.auth.currentSession != null;
      if (path == '/') return loggedIn ? '/hostels' : '/login';
      if ((_isOwnerArea(path) || path == '/welcome') && !loggedIn) return '/login';
      // just logged in: short welcome screen, which then opens My hostels
      if ((path == '/login' || path == '/signup') && loggedIn) return '/welcome';
      return null;
    },
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      // Every page sits inside BackScope so the phone's back button follows core/back_nav.dart.
      ShellRoute(
        builder: (context, state, child) => BackScope(child: child),
        routes: [
      GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),

      // ---------- owner: before a hostel is chosen ----------
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignUpScreen()),
      GoRoute(path: '/forgot', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/hostels', builder: (_, __) => const HostelsScreen()),
      GoRoute(path: '/hostels/new', builder: (_, __) => const HostelFormScreen()),
      GoRoute(path: '/hostels/removed', builder: (_, __) => const RemovedHostelsScreen()),
      GoRoute(path: '/delete-account', builder: (_, __) => const DeleteAccountScreen()),

      // ---------- owner forms (back button only, no tab bar) ----------
      GoRoute(
        path: '/h/:hid/add-room',
        builder: (_, s) => AddRoomScreen(hostelId: s.pathParameters['hid']!),
      ),
      GoRoute(
        path: '/h/:hid/record/:tid',
        builder: (_, s) => RecordPaymentScreen(
          hostelId: s.pathParameters['hid']!,
          tenantId: s.pathParameters['tid']!,
        ),
      ),

      // ---------- owner: inside a hostel (bottom tab bar) ----------
      ShellRoute(
        builder: (context, state, child) => OwnerShell(
          hostelId: state.pathParameters['hid']!,
          location: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(path: '/h/:hid', redirect: (_, s) => '/h/${s.pathParameters['hid']}/home'),
          GoRoute(path: '/h/:hid/home', builder: (_, s) => HomeScreen(hostelId: s.pathParameters['hid']!)),
          GoRoute(path: '/h/:hid/requests', builder: (_, s) => RequestsScreen(hostelId: s.pathParameters['hid']!)),
          GoRoute(path: '/h/:hid/tenants', builder: (_, s) => TenantsScreen(hostelId: s.pathParameters['hid']!)),
          GoRoute(
            path: '/h/:hid/tenants/:tid',
            builder: (_, s) => TenantDetailsScreen(
              hostelId: s.pathParameters['hid']!,
              tenantId: s.pathParameters['tid']!,
            ),
          ),
          GoRoute(path: '/h/:hid/rent', builder: (_, s) => RentScreen(hostelId: s.pathParameters['hid']!)),
          GoRoute(path: '/h/:hid/more', builder: (_, s) => MoreScreen(hostelId: s.pathParameters['hid']!)),
          GoRoute(path: '/h/:hid/rooms', builder: (_, s) => RoomsScreen(hostelId: s.pathParameters['hid']!)),
          GoRoute(path: '/h/:hid/settings', builder: (_, s) => SettingsScreen(hostelId: s.pathParameters['hid']!)),
          GoRoute(
            path: '/h/:hid/share-bed/:bid',
            builder: (_, s) => ShareBedScreen(hostelId: s.pathParameters['hid']!, bedId: s.pathParameters['bid']!),
          ),
          // Rooms & beds now lives at the top of Hostel settings
          GoRoute(path: '/h/:hid/manage-rooms', redirect: (_, s) => '/h/${s.pathParameters['hid']}/settings'),
          GoRoute(path: '/h/:hid/reports', builder: (_, s) => ReportsScreen(hostelId: s.pathParameters['hid']!)),
          GoRoute(path: '/h/:hid/invite', builder: (_, s) => InviteScreen(hostelId: s.pathParameters['hid']!)),
          // Phase 1: rooms entered by tenants (More → Rooms from tenants; Hostel settings → Price by sharing)
          GoRoute(path: '/h/:hid/tenant-rooms', builder: (_, s) => TenantRoomsScreen(hostelId: s.pathParameters['hid']!)),
          GoRoute(path: '/h/:hid/sharing-prices', builder: (_, s) => SharingPricesScreen(hostelId: s.pathParameters['hid']!)),
          // More → Staff (owner only)
          GoRoute(path: '/h/:hid/staff', builder: (_, s) => StaffScreen(hostelId: s.pathParameters['hid']!)),
          GoRoute(path: '/h/:hid/notices', builder: (_, s) => NoticesScreen(hostelId: s.pathParameters['hid']!)),
          GoRoute(path: '/h/:hid/complaints', builder: (_, s) => ComplaintsScreen(hostelId: s.pathParameters['hid']!)),
        ],
      ),

      // ---------- shared ----------
      GoRoute(
        path: '/privacy',
        builder: (_, s) => LegalScreen(initialTab: s.uri.queryParameters['tab'] == 'terms' ? 1 : 0),
      ),

      // ---------- students (no login) ----------
      GoRoute(
        // Hostel QR / join link. Web (app not installed): "Get the app" page.
        // App: Welcome with the hostel name and Student registration (plus the held bed for an owner's bed QR).
        path: '/j/:code',
        builder: (_, s) {
          final code = s.pathParameters['code']!.toUpperCase();
          final bed = s.uri.queryParameters['bed'];
          final k = s.uri.queryParameters['k'];
          if (kIsWeb && !AppConfig.studentWeb) return GetAppScreen(joinCode: code, bedId: bed, bookingCode: k);
          return StudentWelcomeScreen(joinCode: code, bedId: bed, bookingCode: k);
        },
      ),
      GoRoute(
        path: '/j/:code/verify',
        builder: (_, s) {
          final code = s.pathParameters['code']!.toUpperCase();
          final bed = s.uri.queryParameters['bed'];
          final k = s.uri.queryParameters['k'];
          if (kIsWeb && !AppConfig.studentWeb) return GetAppScreen(joinCode: code, bedId: bed, bookingCode: k);
          return VerifyScreen(joinCode: code, bedId: bed, bookingCode: k, findBooking: s.uri.queryParameters['find'] == '1');
        },
      ),
      GoRoute(path: '/j/:code/hostel', builder: (_, s) => HostelDetailsScreen(joinCode: s.pathParameters['code']!)),
      GoRoute(path: '/j/:code/rooms', builder: (_, s) => RoomsPickScreen(joinCode: s.pathParameters['code']!)),
      GoRoute(path: '/j/:code/details', builder: (_, s) => DetailsScreen(joinCode: s.pathParameters['code']!)),
      GoRoute(path: '/j/:code/profile', builder: (_, s) => StudentProfileScreen(joinCode: s.pathParameters['code']!)),
      GoRoute(path: '/j/:code/pay', builder: (_, s) => PaymentScreen(joinCode: s.pathParameters['code']!)),
      GoRoute(
        path: '/j/:code/done',
        builder: (_, s) => DoneScreen(
          joinCode: s.pathParameters['code']!,
          existing: s.uri.queryParameters['existing'] == '1',
          amount: int.tryParse(s.uri.queryParameters['amount'] ?? ''),
        ),
      ),
      GoRoute(path: '/s/:token', builder: (_, s) => StudentHome(token: s.pathParameters['token']!)),
        ],
      ),
    ],
  );
}
