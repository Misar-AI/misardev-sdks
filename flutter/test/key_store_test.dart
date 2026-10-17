import 'package:flutter_test/flutter_test.dart';
import 'package:misardev_flutter/misardev_flutter.dart';

import 'helpers.dart';

/// An in-memory [ApiKeyStore], standing in for the platform keystore.
class MemoryKeyStore implements ApiKeyStore {
  String? key;

  @override
  Future<String?> loadApiKey() async => key;

  @override
  Future<void> saveApiKey(String apiKey) async => key = apiKey;

  @override
  Future<void> deleteApiKey() async => key = null;
}

void main() {
  test('fromKeyStore builds a client with the stored key', () async {
    final store = MemoryKeyStore();
    await store.saveApiKey('mdk_stored');
    final rec = Recorder([json({'ok': true})]);

    final dev = await MisarDev.fromKeyStore(store, baseUrl: testBaseUrl, httpClient: rec.client);
    await dev.usage.plan();

    expect(rec.calls.single.headers['Authorization'], 'Bearer mdk_stored');
    expect(rec.calls.single.headers['X-Misar-SDK'], 'misardev-flutter/$sdkVersion');
    expect(rec.calls.single.url, '$testBaseUrl/usage/plan');
  });

  test('fromKeyStore throws when the store is empty', () async {
    final store = MemoryKeyStore();
    await store.saveApiKey('mdk_x');
    await store.deleteApiKey();

    await expectLater(
      MisarDev.fromKeyStore(store),
      throwsA(isA<MisarDevError>()
          .having((e) => e.code, 'code', 'missing_api_key')
          .having((e) => e.message, 'message', contains('https://www.misar.dev/settings/api-keys'))),
    );
  });
}
