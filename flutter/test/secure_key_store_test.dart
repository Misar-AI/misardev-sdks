import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misardev_flutter/misardev_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('SecureKeyStore saves, loads and deletes the key', () async {
    const store = SecureKeyStore();
    expect(await store.loadApiKey(), isNull);

    await store.saveApiKey('mdk_secure');
    expect(await store.loadApiKey(), 'mdk_secure');
    expect(await const FlutterSecureStorage().read(key: misarDevApiKeyStorageKey), 'mdk_secure');

    await store.deleteApiKey();
    expect(await store.loadApiKey(), isNull);
  });

  test('MisarDev.fromKeyStore reads from secure storage', () async {
    FlutterSecureStorage.setMockInitialValues({misarDevApiKeyStorageKey: 'mdk_from_keychain'});
    final dev = await MisarDev.fromKeyStore(const SecureKeyStore());
    expect(dev.baseUrl, defaultBaseUrl);
    dev.close();
  });
}
