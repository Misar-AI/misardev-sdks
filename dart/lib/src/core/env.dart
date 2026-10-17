/// Environment lookup that also compiles for the web, where there is no
/// process environment (every lookup answers null there).
library;

export 'env_stub.dart' if (dart.library.io) 'env_io.dart';
