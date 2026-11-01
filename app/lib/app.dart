import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config.dart';
import 'core/locale_controller.dart';
import 'l10n/gen/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

class MyHostelApp extends StatefulWidget {
  const MyHostelApp({super.key, required this.localeController, this.initialLocation = '/'});
  final LocaleController localeController;
  final String initialLocation;

  @override
  State<MyHostelApp> createState() => _MyHostelAppState();
}

class _MyHostelAppState extends State<MyHostelApp> {
  late final router = buildRouter(initialLocation: widget.initialLocation);

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isConfigured) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              // Developer-only message (shown when the build has no Supabase settings).
              child: Text('Missing SUPABASE_URL / SUPABASE_ANON_KEY. See README.md.'),
            ),
          ),
        ),
      );
    }
    return LocaleScope(
      controller: widget.localeController,
      child: ListenableBuilder(
        listenable: widget.localeController,
        builder: (context, _) => MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appName,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          locale: widget.localeController.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
  }
}
