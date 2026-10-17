/// Where a Flutter app keeps its MisarDev API key between launches.
///
/// [SecureKeyStore] (Keychain on iOS/macOS, Keystore-backed storage on
/// Android) is the implementation to use in an app; implement this interface
/// yourself for anything else (a test double, a remote config, …).
abstract interface class ApiKeyStore {
  /// The stored key, or null when none has been saved.
  Future<String?> loadApiKey();

  /// Persist [apiKey].
  Future<void> saveApiKey(String apiKey);

  /// Forget the stored key (sign-out).
  Future<void> deleteApiKey();
}
