import 'package:http/http.dart' as http;

import 'core/env.dart';
import 'core/transport.dart';
import 'errors.dart';
import 'generated/resources.dart';
import 'version.dart';

/// Default API base URL.
const String defaultBaseUrl = 'https://api.misar.io/dev';

/// The MisarDev API client.
///
/// ```dart
/// final dev = MisarDev(apiKey: 'mdk_...'); // or set MISARDEV_API_KEY
/// final projects = await dev.projects.list();
/// dev.close();
/// ```
///
/// Every resource (`projects`, `templates`, `chat`, `usage`, …) is a field
/// inherited from [MisarDevResources]; every method returns the decoded JSON
/// value the API answered with.
class MisarDev extends MisarDevResources {
  MisarDev._(this.transport, this._ownsClient, this._http) : super(transport);

  /// Create a client.
  ///
  /// - [apiKey] — an account API key (`mdk_…`). Falls back to the
  ///   `MISARDEV_API_KEY` environment variable; a missing key throws.
  /// - [baseUrl] — defaults to `MISARDEV_BASE_URL`, then
  ///   `https://api.misar.io/dev`.
  /// - [maxRetries] — total attempts for a retryable failure (default 3).
  /// - [timeout] — per-attempt timeout (default 60 s; builds and AI calls are
  ///   slow).
  /// - [httpClient] — inject an `http.Client` (tests, proxies, platform
  ///   clients). One the caller passes is never closed by [close].
  /// - [headers] — extra headers sent with every request.
  /// - [environment] — where to read `MISARDEV_API_KEY` / `MISARDEV_BASE_URL`;
  ///   defaults to the process environment (none on the web).
  factory MisarDev({
    String? apiKey,
    String? baseUrl,
    int maxRetries = 3,
    Duration timeout = const Duration(seconds: 60),
    http.Client? httpClient,
    Map<String, String>? headers,
    Map<String, String>? environment,
  }) {
    String? env(String name) => environment != null ? environment[name] : readEnvironment(name);

    final key = (apiKey != null && apiKey.isNotEmpty) ? apiKey : env('MISARDEV_API_KEY');
    if (key == null || key.isEmpty) {
      throw MisarDevError(
        0,
        'A MisarDev API key is required. Pass apiKey or set MISARDEV_API_KEY. '
        'Create one at https://www.misar.dev/settings/api-keys.',
        code: 'missing_api_key',
      );
    }
    final envBase = env('MISARDEV_BASE_URL');
    final base = (baseUrl != null && baseUrl.isNotEmpty)
        ? baseUrl
        : (envBase != null && envBase.isNotEmpty ? envBase : defaultBaseUrl);
    final client = httpClient ?? http.Client();
    final transport = Transport(
      apiKey: key,
      baseUrl: base.replaceAll(RegExp(r'/+$'), ''),
      maxRetries: maxRetries < 1 ? 1 : maxRetries,
      timeout: timeout,
      httpClient: client,
      sdkHeader: '$sdkName/$sdkVersion',
      headers: headers ?? const {},
    );
    return MisarDev._(transport, httpClient == null, client);
  }

  /// The transport every resource sends through. Use it for a route the
  /// generated layer does not cover yet: `dev.transport.request('GET', '/x')`.
  final Transport transport;

  final bool _ownsClient;
  final http.Client _http;

  /// The resolved base URL, without a trailing slash.
  String get baseUrl => transport.baseUrl;

  /// Release the underlying HTTP client (only when this client created it).
  void close() {
    if (_ownsClient) _http.close();
  }
}
