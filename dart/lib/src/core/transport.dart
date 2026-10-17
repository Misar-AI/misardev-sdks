/// HTTP transport shared by the generated resource layer.
///
/// Everything the SDK does goes through here, and it authenticates exactly one
/// way: the account API key (`mdk_…`), sent as a bearer token. There is no
/// second credential path. What a key may do — and how much of it — is decided
/// server-side from the subscription behind that key; the SDK carries the key
/// and surfaces the answer rather than deciding locally what a plan allows.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;

import '../errors.dart';
import 'query.dart';
import 'sse.dart';

/// Statuses worth retrying. A 429 only when it is NOT a plan limit.
const Set<int> retryableStatuses = {429, 500, 502, 503, 504};

/// A 5xx or a dropped connection on a POST may already have done its work —
/// started a build, charged an allowance. Only requests that are safe to
/// repeat are retried on those; a 429 is always safe because the server
/// refused it before doing anything.
const Set<String> idempotentMethods = {'GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE'};

/// Upper bound for any single wait between attempts.
const Duration maxBackoff = Duration(seconds: 60);

final math.Random _jitter = math.Random();

/// How long to wait before attempt `attempt + 1`.
///
/// Honours `Retry-After` (seconds, or an HTTP-date) when the server sent it;
/// otherwise exponential `250ms * 2^attempt` plus up to 25% jitter. Always
/// capped at [maxBackoff].
Duration backoffDelay(int attempt, String? retryAfter) {
  if (retryAfter != null && retryAfter.trim().isNotEmpty) {
    final value = retryAfter.trim();
    final seconds = double.tryParse(value);
    if (seconds != null && seconds >= 0) {
      return _cap(Duration(milliseconds: (seconds * 1000).round()));
    }
    final date = _tryParseDate(value);
    if (date != null) {
      final wait = date.difference(DateTime.now().toUtc());
      return _cap(wait.isNegative ? Duration.zero : wait);
    }
  }
  final base = 250 * math.pow(2, attempt).toDouble();
  final ms = base + _jitter.nextDouble() * base * 0.25;
  return _cap(Duration(milliseconds: ms.round()));
}

Duration _cap(Duration d) => d > maxBackoff ? maxBackoff : d;

DateTime? _tryParseDate(String value) {
  try {
    return parseHttpDate(value);
  } on FormatException {
    return null;
  }
}

/// `Retry-After` as whole seconds (an HTTP-date is converted), or null.
int? retryAfterSeconds(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final seconds = double.tryParse(value.trim());
  if (seconds != null) return seconds < 0 ? 0 : seconds.ceil();
  final date = _tryParseDate(value.trim());
  if (date == null) return null;
  final wait = date.difference(DateTime.now().toUtc()).inMilliseconds;
  return wait <= 0 ? 0 : (wait / 1000).ceil();
}

/// Pull a human message out of the API's several error shapes.
String messageOf(Object? body, String fallback) {
  if (body is Map) {
    final error = body['error'];
    if (error is String) return error;
    // /v1/* answers in the OpenAI shape: { error: { message, type, code } }
    if (error is Map && error['message'] is String) return error['message'] as String;
    if (body['message'] is String) return body['message'] as String;
  }
  if (body is String && body.trim().isNotEmpty) {
    final text = body.trim();
    return text.length > 500 ? text.substring(0, 500) : text;
  }
  return fallback;
}

/// The machine-readable error code: `body.code`, else `body.error.code`.
String? codeOf(Object? body) {
  if (body is! Map) return null;
  if (body['code'] is String) return body['code'] as String;
  final error = body['error'];
  if (error is Map && error['code'] is String) return error['code'] as String;
  return null;
}

/// True when [body] is the plan-limit refusal (`code: "plan_limit_exceeded"`).
bool isPlanLimitBody(Object? body) => body is Map && body['code'] == 'plan_limit_exceeded';

/// Map an error response to the right typed error. Plan limits first, by
/// `code` — never by status.
MisarDevError errorFor(
  int status,
  Map<String, String> headers,
  Object? body, [
  String? reasonPhrase,
]) {
  final requestId = headers['x-request-id'];
  final reason = (reasonPhrase == null || reasonPhrase.isEmpty) ? 'HTTP $status' : reasonPhrase;
  final message = messageOf(body, reason);
  final code = codeOf(body);

  if (isPlanLimitBody(body)) {
    final upgrade = (body as Map)['upgrade'];
    return PlanLimitError(
      status,
      message,
      body: body,
      requestId: requestId,
      offer: upgrade is Map ? upgrade.cast<String, dynamic>() : null,
      retryAfter: retryAfterSeconds(headers['retry-after']),
    );
  }
  if (status == 400 || status == 422) {
    return ValidationError(status, message, code: code, body: body, requestId: requestId);
  }
  if (status == 401) {
    return AuthenticationError(status, message, code: code, body: body, requestId: requestId);
  }
  if (status == 403) {
    return PermissionDeniedError(status, message, code: code, body: body, requestId: requestId);
  }
  if (status == 404) {
    return NotFoundError(status, message, code: code, body: body, requestId: requestId);
  }
  if (status == 409) {
    return ConflictError(status, message, code: code, body: body, requestId: requestId);
  }
  if (status == 429) {
    return RateLimitError(
      status,
      message,
      code: code,
      body: body,
      requestId: requestId,
      retryAfter: retryAfterSeconds(headers['retry-after']),
    );
  }
  if (status >= 500) {
    return ServerError(status, message, code: code, body: body, requestId: requestId);
  }
  return MisarDevError(status, message, code: code, body: body, requestId: requestId);
}

/// Decode a response body: empty → null, JSON → its value (map, list, …),
/// anything else → the raw text.
Object? decodeBody(int status, List<int> bytes) {
  if (status == 204 || bytes.isEmpty) return null;
  final text = utf8.decode(bytes, allowMalformed: true);
  if (text.trim().isEmpty) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

/// Sends every request the generated resources make.
class Transport {
  Transport({
    required String apiKey,
    required this.baseUrl,
    required this.maxRetries,
    required this.timeout,
    required http.Client httpClient,
    required this.sdkHeader,
    Map<String, String> headers = const {},
  })  : _apiKey = apiKey,
        _http = httpClient,
        _extraHeaders = Map.unmodifiable(headers);

  /// Base URL with no trailing slash, e.g. `https://api.misar.io/dev`.
  final String baseUrl;

  /// Total attempts for a retryable failure (at least 1).
  final int maxRetries;

  /// Per-attempt timeout.
  final Duration timeout;

  /// Value of the `X-Misar-SDK` header, e.g. `misardev-dart/1.0.0`.
  final String sdkHeader;

  final String _apiKey;
  final http.Client _http;
  final Map<String, String> _extraHeaders;

  Map<String, String> _headers(String accept) => {
        'Authorization': 'Bearer $_apiKey',
        'Accept': accept,
        'Content-Type': 'application/json',
        'X-Misar-SDK': sdkHeader,
        ..._extraHeaders,
      };

  http.Request _build(String verb, String path, Map<String, Object?>? query, Object? body, String accept) {
    final request = http.Request(verb, Uri.parse('$baseUrl$path${encodeQuery(query)}'));
    request.headers.addAll(_headers(accept));
    // bodyBytes, not body: the `body` setter rewrites Content-Type.
    if (body != null) request.bodyBytes = utf8.encode(jsonEncode(body));
    return request;
  }

  /// Send one request, retrying throttles and (for idempotent verbs)
  /// transient failures. Returns the decoded JSON value, the raw text for a
  /// non-JSON body, or null for an empty one.
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
  }) async {
    final verb = method.toUpperCase();
    final attempts = math.max(1, maxRetries);

    for (var attempt = 0;; attempt++) {
      final last = attempt >= attempts - 1;
      final http.Response response;
      try {
        response = await _send(_build(verb, path, query, body, 'application/json'));
      } on Exception catch (e) {
        if (!last && idempotentMethods.contains(verb)) {
          await Future<void>.delayed(backoffDelay(attempt, null));
          continue;
        }
        throw NetworkError(e is TimeoutException ? 'Request timed out after $timeout' : e.toString(), cause: e);
      }

      final status = response.statusCode;
      final decoded = decodeBody(status, response.bodyBytes);
      if (status >= 200 && status < 300) return decoded;

      // Read the body BEFORE deciding to retry: a 429 from the rate limiter
      // and a 429 from a spent plan allowance share a status, and only the
      // first is worth retrying.
      final error = errorFor(status, response.headers, decoded, response.reasonPhrase);
      if (error is PlanLimitError) throw error;

      final retryable = retryableStatuses.contains(status) && (status == 429 || idempotentMethods.contains(verb));
      if (retryable && !last) {
        await Future<void>.delayed(backoffDelay(attempt, response.headers['retry-after']));
        continue;
      }
      throw error;
    }
  }

  Future<http.Response> _send(http.Request request) =>
      _http.send(request).then(http.Response.fromStream).timeout(timeout);

  /// Open a Server-Sent Events stream and yield each event.
  ///
  /// Never retried: a stream that fails mid-flight cannot be replayed without
  /// duplicating what the caller already consumed. A frame carrying
  /// `code: "plan_limit_exceeded"` is raised as a [PlanLimitError], exactly as
  /// the same refusal on a plain request would be. Iteration stops at a frame
  /// whose data equals [terminator] (`null` reads to end of stream).
  Stream<SseEvent> stream(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    String? terminator,
  }) async* {
    final request = _build(method.toUpperCase(), path, query, body, 'text/event-stream');
    final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(timeout);
    } on Exception catch (e) {
      throw NetworkError(e is TimeoutException ? 'Request timed out after $timeout' : e.toString(), cause: e);
    }

    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      final bytes = await response.stream.toBytes();
      throw errorFor(status, response.headers, decodeBody(status, bytes), response.reasonPhrase);
    }

    await for (final event in parseSse(response.stream, terminator: terminator)) {
      // Other error frames are the stream's own business (the build stream
      // reports a failed step and carries on), so only the plan refusal —
      // which no amount of reading further will fix — is raised.
      if (isPlanLimitBody(event.data)) {
        final upgrade = (event.data as Map)['upgrade'];
        final reason = upgrade is Map ? upgrade['reason'] : null;
        throw errorFor(reason == 'quota_exhausted' ? 429 : 402, response.headers, event.data);
      }
      yield event;
    }
  }
}
