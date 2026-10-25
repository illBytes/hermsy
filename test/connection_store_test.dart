import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/services/connection_store.dart';

void main() {
  test('normalizes a URL and masks an API key', () {
    expect(
      AppConfig.normalizeBaseUrl('https://hermes.example.com/'),
      'https://hermes.example.com',
    );
    expect(AppConfig.maskApiKey('abcd1234xyz'), '••••4xyz');
    expect(AppConfig.maskApiKey(''), 'Not set');
  });

  test('a saved server wins over the starting one', () async {
    final store = ConnectionStore(
      bundled: const AppConfig(
        baseUrl: 'https://bundled.example',
        apiKey: 'bundled-key',
      ),
      vault: MemoryConnectionVault(
        baseUrl: 'https://spawn-two.example/',
        apiKey: 'spawn-two-key',
      ),
    );
    await store.load();
    expect(store.current.baseUrl, 'https://spawn-two.example');
    expect(store.current.apiKey, 'spawn-two-key');
  });

  test('falls back to bundled values when nothing is saved', () async {
    final store = ConnectionStore(
      bundled: const AppConfig(
        baseUrl: 'https://bundled.example',
        apiKey: 'bundled-key',
      ),
      vault: MemoryConnectionVault(),
    );
    await store.load();
    expect(store.current.baseUrl, 'https://bundled.example');
    expect(store.current.apiKey, 'bundled-key');
  });

  test('persists a new connection', () async {
    final vault = MemoryConnectionVault();
    final store = ConnectionStore(
      bundled: const AppConfig(
        baseUrl: 'https://bundled.example',
        apiKey: 'bundled-key',
      ),
      vault: vault,
    );
    await store.load();
    await store.save(
      const AppConfig(
        baseUrl: 'https://other.example/',
        apiKey: ' new-key ',
      ),
    );
    expect(store.current.baseUrl, 'https://other.example');
    expect(store.current.apiKey, 'new-key');
    expect((await vault.read()).apiKey, 'new-key');
  });
}
