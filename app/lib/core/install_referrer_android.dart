import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// After a student installs the app from the "Get the app" page, the Play Store passes the
/// hostel join code (and the held bed) as the install referrer, e.g. "join=7KQ2AB&bed=…&k=…".
/// On the very first launch this returns the matching join route so the app opens straight on
/// that hostel / bed. Read only once per install; null on web, iPhone or a normal install.
Future<String?> joinRouteFromInstallImpl() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('install_referrer_read') == true) return null;
    await prefs.setBool('install_referrer_read', true);
    final details = await PlayInstallReferrer.installReferrer.timeout(const Duration(seconds: 4));
    final raw = details.installReferrer;
    if (raw == null || raw.isEmpty) return null;
    final q = Uri.splitQueryString(raw.contains('%') ? Uri.decodeComponent(raw) : raw);
    final join = (q['join'] ?? '').toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(join)) return null;
    final bed = q['bed'];
    final k = q['k'];
    if (bed != null && k != null && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(bed) && RegExp(r'^[0-9a-fA-F]{12,40}$').hasMatch(k)) {
      return '/j/$join?bed=$bed&k=$k';
    }
    return '/j/$join';
  } catch (_) {
    return null; // no Play Store / not installed from Play: normal start
  }
}
