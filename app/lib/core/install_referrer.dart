// Install referrer (Android only). The web build uses a stub so the Android plugin isn't compiled for web.
import 'install_referrer_android.dart' if (dart.library.js_interop) 'install_referrer_web.dart';

/// Join route from the Play Store install referrer on the first launch (see install_referrer_android.dart).
Future<String?> joinRouteFromInstall() => joinRouteFromInstallImpl();
