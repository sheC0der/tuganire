import 'package:flutter/foundation.dart';

/// App configuration, passed in at build time with --dart-define.
///
/// Web: the backend serves the app, so API calls go to the same origin.
/// Phone and desktop: pass your Railway URL, e.g.
///   flutter run --dart-define=BACKEND_URL=https://tuganire-production.up.railway.app
/// Local development: point BACKEND_URL at your computer instead, e.g.
///   flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:8787
///   flutter run --dart-define=BACKEND_URL=http://192.168.1.20:8787   (phone on the same Wi-Fi)
class AppConfig {
  /// Replace this with your Railway URL (Railway > service > Settings > Networking)
  /// if you'd rather not pass --dart-define=BACKEND_URL on every phone build.
  static const railwayUrlPlaceholder = 'https://YOUR-SERVICE.up.railway.app';

  static const _backendUrlDefine = String.fromEnvironment('BACKEND_URL');

  static String get backendUrl {
    if (_backendUrlDefine.isNotEmpty) return _withoutTrailingSlash(_backendUrlDefine);
    if (kIsWeb) return Uri.base.origin;
    return railwayUrlPlaceholder;
  }

  static bool get backendUrlIsPlaceholder => backendUrl == railwayUrlPlaceholder;

  /// From Supabase > Project Settings > API Keys. The publishable key is meant to be
  /// public; never pass the secret or service_role key to the app.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get supabaseConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  static String _withoutTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
