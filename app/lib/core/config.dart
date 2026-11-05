/// Build-time settings: pass with --dart-define.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:3000');
  static const useMocks = bool.fromEnvironment('USE_MOCKS', defaultValue: true);
  static const linkHost = String.fromEnvironment('LINK_HOST', defaultValue: 'keys.app');
  // Placeholders until Legal signs off final documents (XFR-08.1).
  static const termsUrl = String.fromEnvironment('TERMS_URL', defaultValue: 'https://keys.app/legal/terms');
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL', defaultValue: 'https://keys.app/legal/privacy');
  static const safetyUrl = String.fromEnvironment('SAFETY_URL', defaultValue: 'https://keys.app/legal/safety');
}
