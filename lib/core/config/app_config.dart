class AppConfig {
  const AppConfig._();

  static const defaultBackendUrl = 'https://agent.milanapremium.uz';

  static const backendUrl = String.fromEnvironment(
    'MILA_BACKEND_URL',
    defaultValue: defaultBackendUrl,
  );

  static const hasBundledGeminiKey =
      String.fromEnvironment('GEMINI_API_KEY') != '';

  static const legacyBackendUrl = String.fromEnvironment(
    'MILA_OPENAI_ACCOUNT_URL',
  );

  static String configuredBackendUrl(String? storedUrl) {
    final stored = storedUrl?.trim() ?? '';
    if (stored.isNotEmpty) return stored;
    if (backendUrl.trim().isNotEmpty) return backendUrl;
    return legacyBackendUrl;
  }
}
