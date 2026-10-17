import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/key_store.dart';

/// Storage key the API key is saved under.
const String misarDevApiKeyStorageKey = 'misardev_api_key';

/// Persists the MisarDev API key in the platform's secure storage via
/// [FlutterSecureStorage] — the Keychain on iOS and macOS, encrypted storage
/// backed by the Keystore on Android.
///
/// ```dart
/// const store = SecureKeyStore();
/// await store.saveApiKey('mdk_...');
/// final dev = await MisarDev.fromKeyStore(store);
/// ```
class SecureKeyStore implements ApiKeyStore {
  /// Wrap [storage], or a default [FlutterSecureStorage].
  const SecureKeyStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> loadApiKey() => _storage.read(key: misarDevApiKeyStorageKey);

  @override
  Future<void> saveApiKey(String apiKey) => _storage.write(key: misarDevApiKeyStorageKey, value: apiKey);

  @override
  Future<void> deleteApiKey() => _storage.delete(key: misarDevApiKeyStorageKey);
}
