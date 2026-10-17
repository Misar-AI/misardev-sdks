/// The MisarDev API client for Dart.
///
/// ```dart
/// import 'package:misardev/misardev.dart';
///
/// final dev = MisarDev(); // reads MISARDEV_API_KEY
/// final project = await dev.projects.create({'name': 'my-app'});
/// ```
library;

export 'src/client.dart' show MisarDev, defaultBaseUrl;
export 'src/core/pagination.dart' show itemsOf, paginate;
export 'src/core/sse.dart' show SseEvent;
export 'src/core/transport.dart' show Transport;
export 'src/errors.dart';
export 'src/generated/resources.dart';
export 'src/version.dart' show sdkVersion;
