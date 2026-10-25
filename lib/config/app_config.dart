class AppConfig {
  const AppConfig({required this.baseUrl, required this.apiKey});

  final String baseUrl;
  final String apiKey;

  bool get looksConfigured =>
      baseUrl.isNotEmpty &&
      !baseUrl.contains('your-hermes.example.com') &&
      apiKey.isNotEmpty &&
      apiKey != 'change-me';

  AppConfig copyWith({String? baseUrl, String? apiKey}) {
    return AppConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  static String normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String maskApiKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return 'Not set';
    }
    if (trimmed.length <= 4) {
      return 'Saved';
    }
    return '••••${trimmed.substring(trimmed.length - 4)}';
  }
}
