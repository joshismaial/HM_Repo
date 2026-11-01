/// App settings passed at build time, e.g.
/// flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=... \
///   --dart-define=PUBLIC_APP_URL=https://myhostel.app
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Where the student web pages are hosted (used in join links and QR codes).
  static const publicAppUrl = String.fromEnvironment('PUBLIC_APP_URL', defaultValue: 'https://myhostel.app');

  static String functionUrl(String name) => '$supabaseUrl/functions/v1/$name';

  static String joinLink(String joinCode) => '$publicAppUrl/j/$joinCode';

  /// Android app id on Google Play (change before publishing, e.g. --dart-define=ANDROID_PACKAGE=in.myhostel.app).
  static const androidPackage = String.fromEnvironment('ANDROID_PACKAGE', defaultValue: 'com.example.my_hostel');

  /// Play Store page for the app. The join code / bed go in the install referrer, so the app
  /// opens straight on that hostel or bed after it is installed.
  static String playStoreUrl({required String joinCode, String? bedId, String? bookingCode}) {
    final ref = 'join=$joinCode${bedId != null ? '&bed=$bedId' : ''}${bookingCode != null ? '&k=$bookingCode' : ''}';
    return 'https://play.google.com/store/apps/details?id=$androidPackage&referrer=${Uri.encodeComponent(ref)}';
  }

  /// TESTING ONLY: lets the student joining pages run in a web browser (Chrome) instead of showing
  /// "Get the app". run-app.bat turns it on with --dart-define=STUDENT_WEB=true. Never use it for the real web build.
  static const studentWeb = bool.fromEnvironment('STUDENT_WEB');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
