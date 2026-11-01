import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 1 languages. Tamil, Marathi, Kannada and Bengali come in Phase 3.
const appLanguages = <String, String>{
  'en': 'English',
  'hi': 'हिन्दी',
  'te': 'తెలుగు',
};

class LocaleController extends ChangeNotifier {
  LocaleController._(this._locale);
  Locale _locale;
  Locale get locale => _locale;

  static const _key = 'app_language';

  static Future<LocaleController> load() async {
    String code = 'en';
    try {
      final prefs = await SharedPreferences.getInstance();
      code = prefs.getString(_key) ?? 'en';
    } catch (_) {}
    if (!appLanguages.containsKey(code)) code = 'en';
    return LocaleController._(Locale(code));
  }

  Future<void> setLanguage(String code) async {
    if (!appLanguages.containsKey(code) || code == _locale.languageCode) return;
    _locale = Locale(code);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, code);
    } catch (_) {}
  }
}

class LocaleScope extends InheritedWidget {
  const LocaleScope({super.key, required this.controller, required super.child});
  final LocaleController controller;

  static LocaleController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocaleScope>()!.controller;

  @override
  bool updateShouldNotify(LocaleScope oldWidget) => oldWidget.controller != controller;
}
