/// App configuration, passed in at build time with --dart-define.
///
/// Android emulator: the default 10.0.2.2 points at your computer.
/// Physical phone: use your computer's Wi-Fi IP, e.g.
///   flutter run --dart-define=BACKEND_URL=http://192.168.1.20:8787
class AppConfig {
  static const backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://10.0.2.2:8787',
  );
  static const appToken = String.fromEnvironment('APP_TOKEN', defaultValue: '');
}
