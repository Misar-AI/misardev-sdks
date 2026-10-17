/// The MisarDev API client for Flutter.
///
/// ```dart
/// import 'package:misardev_flutter/misardev_flutter.dart';
///
/// final dev = await MisarDev.fromKeyStore(const SecureKeyStore());
/// final project = await dev.projects.create({'name': 'my-app'});
/// ```
library;

export 'src/client.dart' show MisarDev, defaultBaseUrl;
export 'src/core/key_store.dart' show ApiKeyStore;
export 'src/core/pagination.dart' show itemsOf, paginate;
export 'src/core/sse.dart' show SseEvent;
export 'src/core/transport.dart' show Transport;
export 'src/errors.dart';
export 'src/generated/resources.dart';
export 'src/secure_key_store.dart' show SecureKeyStore, misarDevApiKeyStorageKey;
export 'src/version.dart' show sdkVersion;
