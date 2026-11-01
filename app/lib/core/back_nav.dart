import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'format.dart';

/// Back navigation for the whole app (standing rule: back must work on every screen).
///
/// The top-left back arrow and the phone's back button / gesture both call [goBack]:
///  1. close an open dialog / sheet, or pop a pushed screen, if there is one;
///  2. otherwise go to the screen's logical parent from [backTarget];
///  3. otherwise (login, hostel list, student start page) leave the app.
///
/// NEW SCREENS: add the route to [backTarget] and use [AppBackButton] (or [goBack])
/// for the top-left arrow. Tab screens go back to Home before the app closes.
String? backTarget(String path) {
  final p = path.split('/').where((s) => s.isNotEmpty).toList();
  if (p.isEmpty) return null;

  switch (p[0]) {
    case 'signup':
    case 'forgot':
      return '/login';
    case 'privacy':
      return '/';
    case 'delete-account':
    case 'welcome':
      return '/hostels';
    case 'hostels':
      return p.length > 1 ? '/hostels' : null; // /hostels/new -> list; list -> leave app
    case 'h':
      if (p.length < 3) return '/hostels';
      final base = '/h/${p[1]}';
      final section = p[2];
      switch (section) {
        case 'home':
          return '/hostels';
        case 'requests':
        case 'rooms':
        case 'rent':
        case 'more':
          return '$base/home'; // tabs -> Home before the app closes
        case 'tenants':
          return p.length > 3 ? '$base/tenants' : '$base/home';
        case 'settings':
        case 'invite':
        case 'reports':
        case 'tenant-rooms':
        case 'staff':
        case 'notices':
          return '$base/more';
        case 'complaints':
          return '$base/home'; // opened from Home → Needs your action
        case 'sharing-prices':
          return '$base/settings';
        case 'share-bed':
          return '$base/rooms';
        case 'manage-rooms':
        case 'add-room':
          return '$base/settings'; // rooms are managed from hostel settings
        case 'record':
          return p.length > 3 ? '$base/tenants/${p[3]}' : '$base/tenants';
      }
      return '$base/home';
    case 'j':
      if (p.length < 3) return null; // OTP page is the start of the student flow
      final base = '/j/${p[1]}';
      return switch (p[2]) {
        // Welcome (hostel name + Student registration) → Verify → Details → Profile → [Room selection] → Pay
        'verify' => base,
        'details' => base,
        'profile' => '$base/details',
        'rooms' => '$base/profile',
        'pay' => '$base/details',
        _ => null, // hostel page, done page: nothing to go back to
      };
  }
  return null;
}

/// Back from the current screen (see the rules at the top of this file).
Future<void> goBack(BuildContext context) async {
  final router = GoRouter.of(context);
  if (await router.routerDelegate.popRoute()) return;
  final target = backTarget(router.routerDelegate.currentConfiguration.uri.path);
  if (target != null) {
    router.go(target);
  } else {
    await SystemNavigator.pop();
  }
}

/// Top-left back arrow that follows the same rules as the phone's back button.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: context.l10n.back,
        color: color,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => goBack(context),
      );
}

/// Wraps every page (top-level ShellRoute in router.dart) so the phone's back
/// button / gesture uses [goBack] instead of closing the app.
class BackScope extends StatelessWidget {
  const BackScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BackButtonListener(
      onBackButtonPressed: () async {
        final router = GoRouter.of(context);
        if (await router.routerDelegate.popRoute()) return true;
        final target = backTarget(router.routerDelegate.currentConfiguration.uri.path);
        if (target == null) return false; // nothing behind: let Android close the app
        router.go(target);
        return true;
      },
      child: child,
    );
  }
}
