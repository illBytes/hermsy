import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

abstract class ConnectionVault {
  Future<({String? baseUrl, String? apiKey})> read();
  Future<void> write({required String baseUrl, required String apiKey});
}

class SecureConnectionVault implements ConnectionVault {
  SecureConnectionVault({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const urlKey = 'frank.hermes_base_url';
  static const apiKeyKey = 'frank.hermes_api_key';

  final FlutterSecureStorage _storage;

  @override
  Future<({String? baseUrl, String? apiKey})> read() async {
    return (
      baseUrl: await _storage.read(key: urlKey),
      apiKey: await _storage.read(key: apiKeyKey),
    );
  }

  @override
  Future<void> write({required String baseUrl, required String apiKey}) async {
    await _storage.write(key: urlKey, value: baseUrl);
    await _storage.write(key: apiKeyKey, value: apiKey);
  }
}

class MemoryConnectionVault implements ConnectionVault {
  MemoryConnectionVault({String? baseUrl, String? apiKey})
    : _baseUrl = baseUrl,
      _apiKey = apiKey;

  String? _baseUrl;
  String? _apiKey;

  @override
  Future<({String? baseUrl, String? apiKey})> read() async {
    return (baseUrl: _baseUrl, apiKey: _apiKey);
  }

  @override
  Future<void> write({required String baseUrl, required String apiKey}) async {
    _baseUrl = baseUrl;
    _apiKey = apiKey;
  }
}

/// The Hermes address and key, kept in secure storage. The app starts with
/// none: a person scans the QR code from `hermes-spawn connect` or types
/// them in Settings › Hermes. No build carries a server or key.
class ConnectionStore extends ChangeNotifier {
  ConnectionStore({
    AppConfig bundled = const AppConfig(baseUrl: '', apiKey: ''),
    ConnectionVault? vault,
  }) : _bundled = bundled,
       _vault = vault ?? SecureConnectionVault();

  /// Used until a server is saved (tests start with one).
  final AppConfig _bundled;
  final ConnectionVault _vault;
  AppConfig current = const AppConfig(baseUrl: '', apiKey: '');

  Future<void> load() async {
    final stored = await _vault.read();
    final url = stored.baseUrl?.trim() ?? '';
    final key = stored.apiKey?.trim() ?? '';
    current = AppConfig(
      baseUrl: AppConfig.normalizeBaseUrl(
        url.isNotEmpty ? url : _bundled.baseUrl,
      ),
      apiKey: key.isNotEmpty ? key : _bundled.apiKey,
    );
    notifyListeners();
  }

  Future<void> save(AppConfig next) async {
    current = AppConfig(
      baseUrl: AppConfig.normalizeBaseUrl(next.baseUrl),
      apiKey: next.apiKey.trim(),
    );
    await _vault.write(baseUrl: current.baseUrl, apiKey: current.apiKey);
    notifyListeners();
  }
}
