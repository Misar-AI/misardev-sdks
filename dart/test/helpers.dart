import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:misardev/misardev.dart';

/// One request the stub received.
class Call {
  Call(this.method, this.url, this.headers, this.body);

  final String method;
  final String url;
  final Map<String, String> headers;
  final Object? body;
}

/// Builds a fresh response each time it is served.
typedef Responder = http.StreamedResponse Function();

/// An `http.Client` that records calls and answers from a queue. The last
/// queued answer repeats once the others are used up; an [Exception] in the
/// queue is thrown instead of answering.
class Recorder {
  Recorder(List<Object> answers) : _queue = [...answers];

  final List<Object> _queue;
  final List<Call> calls = [];

  late final MockClient client = MockClient.streaming((request, bodyStream) async {
    final bytes = await bodyStream.toBytes();
    calls.add(Call(
      request.method,
      request.url.toString(),
      request.headers,
      bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes)),
    ));
    final next = _queue.length > 1 ? _queue.removeAt(0) : (_queue.isEmpty ? json({'ok': true}) : _queue.first);
    if (next is Exception) throw next;
    return (next as Responder)();
  });
}

Responder json(Object? body, {int status = 200, Map<String, String> headers = const {}}) => () => http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json', ...headers},
    );

Responder text(String body, {int status = 200, Map<String, String> headers = const {}}) =>
    () => http.StreamedResponse(Stream.value(utf8.encode(body)), status, headers: headers);

/// Each piece is its own chunk, so a frame boundary can straddle two reads.
Responder sse(List<String> pieces, {int status = 200}) => () => http.StreamedResponse(
      Stream.fromIterable(pieces.map(utf8.encode)),
      status,
      headers: {'content-type': 'text/event-stream'},
    );

const testBaseUrl = 'https://api.test/dev';

({MisarDev dev, Recorder rec}) client(List<Object> answers, {int maxRetries = 3}) {
  final rec = Recorder(answers);
  final dev = MisarDev(
    apiKey: 'mdk_test_key',
    baseUrl: testBaseUrl,
    maxRetries: maxRetries,
    httpClient: rec.client,
    environment: const {},
  );
  return (dev: dev, rec: rec);
}

const planLimitBody = <String, dynamic>{
  'error': 'API access requires the Pro plan or higher.',
  'code': 'plan_limit_exceeded',
  'requiredPlan': 'pro',
  'upgrade': {
    'product': 'dev',
    'product_name': 'Misar.Dev',
    'reason': 'feature_locked',
    'feature': 'api_access',
    'feature_label': 'API access',
    'headline': "API access isn't included in your Starter plan.",
    'usage': null,
    'current_plan': {'slug': 'starter', 'name': 'Starter'},
    'recommended_plan': 'pro',
    'plans': <Object>[],
    'topup': null,
    'overage': null,
    'trial': null,
    'cross_sell': <Object>[],
    'urls': {
      'pricing': 'https://www.misar.dev/pricing',
      'billing': 'https://www.misar.dev/settings/billing',
      'docs': 'https://docs.misar.io/dev/api',
      'compare': 'https://www.misar.dev/pricing#compare',
    },
    'cta': 'Upgrade to Pro to continue.',
  },
};

/// The fixture as a spent quota (429, `quota_exhausted`).
Map<String, dynamic> quotaBody() {
  final body = jsonDecode(jsonEncode(planLimitBody)) as Map<String, dynamic>;
  (body['upgrade'] as Map<String, dynamic>)['reason'] = 'quota_exhausted';
  return body;
}
