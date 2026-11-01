import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'core/install_referrer.dart';
import 'core/locale_controller.dart';
import 'data/student_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean web addresses like /j/ABCD2345 instead of /#/j/ABCD2345 (needed for QR links).
  usePathUrlStrategy();
  await initializeDateFormatting();

  if (AppConfig.isConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  }
  final locale = await LocaleController.load();
  // Installed from a hostel's "Get the app" page: open straight on that hostel / bed (first launch only).
  String? start;
  if (AppConfig.isConfigured && Supabase.instance.client.auth.currentSession == null &&
      await StudentApi.instance.savedToken() == null) {
    start = await joinRouteFromInstall();
  }
  runApp(MyHostelApp(localeController: locale, initialLocation: start ?? '/'));
}
