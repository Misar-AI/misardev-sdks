import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:misardev_flutter/misardev_flutter.dart';
import 'package:misardev_flutter/src/core/query.dart';
import 'package:misardev_flutter/src/core/sse.dart';
import 'package:misardev_flutter/src/core/transport.dart';

import 'helpers.dart';

void main() {
  group('client', () {
    test('sends bearer auth, SDK header and JSON headers to the default base URL', () async {
      final rec = Recorder([
        json({'plan': 'pro'})
      ]);
      final dev = MisarDev(apiKey: 'mdk_test_key', httpClient: rec.client, environment: const {});

      expect(dev.baseUrl, 'https://api.misar.io/dev');
      final res = await dev.usage.plan();

      expect(res, {'plan': 'pro'});
      final call = rec.calls.single;
      expect(call.method, 'GET');
      expect(call.url, 'https://api.misar.io/dev/usage/plan');
      expect(call.headers['Authorization'], 'Bearer mdk_test_key');
      expect(call.headers['X-Misar-SDK'], 'misardev-flutter/$sdkVersion');
      expect(call.headers['Accept'], 'application/json');
      expect(call.headers['Content-Type'], 'application/json');
      expect(call.body, isNull);
    });

    test('falls back to MISARDEV_API_KEY and MISARDEV_BASE_URL', () async {
      final rec = Recorder([json({})]);
      final dev = MisarDev(
        httpClient: rec.client,
        environment: const {'MISARDEV_API_KEY': 'mdk_from_env', 'MISARDEV_BASE_URL': 'https://env.test/dev/'},
      );

      await dev.builds.list();

      expect(rec.calls.single.headers['Authorization'], 'Bearer mdk_from_env');
      expect(rec.calls.single.url, 'https://env.test/dev/builds');
    });

    test('an empty key also falls back to the environment', () {
      final dev = MisarDev(apiKey: '', environment: const {'MISARDEV_API_KEY': 'mdk_env'});
      expect(dev.baseUrl, defaultBaseUrl);
      dev.close();
    });

    test('a missing key throws, pointing at the API keys page', () {
      expect(
        () => MisarDev(environment: const {}),
        throwsA(isA<MisarDevError>()
            .having((e) => e.code, 'code', 'missing_api_key')
            .having((e) => e.message, 'message', contains('https://www.misar.dev/settings/api-keys'))),
      );
    });

    test('extra headers are sent', () async {
      final rec = Recorder([json({})]);
      final dev = MisarDev(
        apiKey: 'mdk_k',
        httpClient: rec.client,
        headers: const {'X-Trace': 'abc'},
        environment: const {},
      );
      await dev.audit.list();
      expect(rec.calls.single.headers['X-Trace'], 'abc');
    });

    test('sdkVersion matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
      expect(sdkVersion, version);
    });
  });

  group('plan limits', () {
    test('402 feature_locked raises PlanLimitError with the full offer, one request', () async {
      final c = client([
        json(planLimitBody, status: 402, headers: {'x-request-id': 'req_123'}),
      ]);

      final error = await c.dev.projects.list().then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<PlanLimitError>());
      final e = error! as PlanLimitError;
      expect(e.status, 402);
      expect(e.code, 'plan_limit_exceeded');
      expect(e.message, 'API access requires the Pro plan or higher.');
      expect(e.requestId, 'req_123');
      expect(e.reason, 'feature_locked');
      expect(e.feature, 'api_access');
      expect(e.currentPlan, 'starter');
      expect(e.recommendedPlan, 'pro');
      expect(e.upgradeUrl, 'https://www.misar.dev/settings/billing');
      expect(e.offer!['headline'], "API access isn't included in your Starter plan.");
      expect(e.offer!['cta'], 'Upgrade to Pro to continue.');
      expect(e.offer!.keys, containsAll(<String>['topup', 'overage', 'trial', 'cross_sell', 'usage', 'plans']));
      expect(e.retryAfter, isNull);
      expect(e, isA<MisarDevError>());
      expect(c.rec.calls, hasLength(1));
    });

    test('upgradeUrl falls back to pricing', () {
      final e = PlanLimitError(402, 'x', offer: const {
        'urls': {'pricing': 'https://www.misar.dev/pricing'},
      });
      expect(e.upgradeUrl, 'https://www.misar.dev/pricing');
    });

    test('429 quota_exhausted is a PlanLimitError and is never retried', () async {
      final c = client([
        json(quotaBody(), status: 429, headers: {'retry-after': '3600'}),
        json({'ok': true}),
      ]);

      await expectLater(
        c.dev.chat.completions({'messages': <Object>[]}),
        throwsA(isA<PlanLimitError>()
            .having((e) => e.status, 'status', 429)
            .having((e) => e.reason, 'reason', 'quota_exhausted')
            .having((e) => e.retryAfter, 'retryAfter', 3600)),
      );
      expect(c.rec.calls, hasLength(1));
    });

    test('a plan refusal on a GET is not retried either', () async {
      final c = client([
        json(quotaBody(), status: 429, headers: {'retry-after': '0'})
      ]);
      await expectLater(c.dev.usage.list(), throwsA(isA<PlanLimitError>()));
      expect(c.rec.calls, hasLength(1));
    });
  });

  group('retries', () {
    test('an ordinary 429 is retried (any verb) and then succeeds', () async {
      final c = client([
        json({'error': 'slow down'}, status: 429, headers: {'retry-after': '0'}),
        json({'id': 'p1'}),
      ]);
      expect(await c.dev.projects.create({'name': 'x'}), {'id': 'p1'});
      expect(c.rec.calls, hasLength(2));
    });

    test('a persistent 429 raises RateLimitError after maxRetries attempts', () async {
      final c = client([
        json({'error': 'slow down'}, status: 429, headers: {'retry-after': '0'}),
      ]);
      await expectLater(
        c.dev.templates.list(),
        throwsA(isA<RateLimitError>()
            .having((e) => e.retryAfter, 'retryAfter', 0)
            .having((e) => e.message, 'message', 'slow down')),
      );
      expect(c.rec.calls, hasLength(3));
    });

    test('503 is retried on GET', () async {
      final c = client([
        json({'error': 'down'}, status: 503, headers: {'retry-after': '0'}),
        json(['a', 'b']),
      ]);
      expect(await c.dev.skills.list(), ['a', 'b']);
      expect(c.rec.calls, hasLength(2));
    });

    test('503 is NOT retried on POST', () async {
      final c = client([
        json({'error': 'down'}, status: 503, headers: {'retry-after': '0'}),
        json({'ok': true}),
      ]);
      await expectLater(c.dev.projects.deploy('p1'), throwsA(isA<ServerError>()));
      expect(c.rec.calls, hasLength(1));
    });

    test('network errors are retried on GET and raised as NetworkError on POST', () async {
      final get = client([
        http.ClientException('reset'),
        json({'ok': true})
      ]);
      expect(await get.dev.github.getConnection(), {'ok': true});
      expect(get.rec.calls, hasLength(2));

      final post = client([
        http.ClientException('reset'),
        json({'ok': true})
      ]);
      await expectLater(
        post.dev.reports.create({'reason': 'spam'}),
        throwsA(isA<NetworkError>().having((e) => e.status, 'status', 0)),
      );
      expect(post.rec.calls, hasLength(1));
    });

    test('maxRetries: 1 makes a single attempt', () async {
      final c = client([json({}, status: 500)], maxRetries: 1);
      await expectLater(c.dev.audit.list(), throwsA(isA<ServerError>()));
      expect(c.rec.calls, hasLength(1));
    });

    test('backoff honours Retry-After seconds and dates, capped at 60s', () {
      expect(backoffDelay(0, '2'), const Duration(seconds: 2));
      expect(backoffDelay(0, '3600'), const Duration(seconds: 60));
      final soon = HttpDate.format(DateTime.now().toUtc().add(const Duration(seconds: 30)));
      expect(backoffDelay(0, soon).inSeconds, inInclusiveRange(28, 30));
      final past = HttpDate.format(DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
      expect(backoffDelay(0, past), Duration.zero);
      expect(backoffDelay(0, null).inMilliseconds, inInclusiveRange(250, 313));
      expect(backoffDelay(3, null).inMilliseconds, inInclusiveRange(2000, 2500));
      expect(backoffDelay(20, null), const Duration(seconds: 60));
      expect(retryAfterSeconds('5'), 5);
      expect(retryAfterSeconds('nonsense'), isNull);
    });
  });

  group('errors', () {
    test('401 → AuthenticationError', () async {
      final c = client([
        json({'error': 'Invalid API key'}, status: 401)
      ]);
      await expectLater(
        c.dev.projects.list(),
        throwsA(isA<AuthenticationError>().having((e) => e.message, 'message', 'Invalid API key')),
      );
    });

    test('404 → NotFoundError, with the request id', () async {
      final c = client([
        json({'message': 'No such project', 'code': 'not_found'}, status: 404, headers: {'x-request-id': 'r1'}),
      ]);
      await expectLater(
        c.dev.projects.get('nope'),
        throwsA(isA<NotFoundError>()
            .having((e) => e.message, 'message', 'No such project')
            .having((e) => e.code, 'code', 'not_found')
            .having((e) => e.requestId, 'requestId', 'r1')),
      );
    });

    test('OpenAI-shaped 400 → ValidationError with its message and code', () async {
      final c = client([
        json({
          'error': {'message': 'messages is required', 'type': 'invalid_request_error', 'code': 'missing_messages'},
        }, status: 400),
      ]);
      await expectLater(
        c.dev.chat.completions(),
        throwsA(isA<ValidationError>()
            .having((e) => e.message, 'message', 'messages is required')
            .having((e) => e.code, 'code', 'missing_messages')),
      );
    });

    test('403, 409, 422 and other statuses map to their classes', () async {
      Future<Object?> fail(int status) async {
        final c = client([
          json({'error': 'e$status'}, status: status)
        ]);
        return c.dev.audit.list().then<Object?>((_) => null, onError: (Object e) => e);
      }

      expect(await fail(403), isA<PermissionDeniedError>());
      expect(await fail(409), isA<ConflictError>());
      expect(await fail(422), isA<ValidationError>());
      final other = await fail(418);
      expect(other, isA<MisarDevError>());
      expect(other, isNot(isA<ValidationError>()));
    });

    test('a non-JSON error body becomes the message', () async {
      final c = client([text('Bad Gateway from proxy', status: 502)], maxRetries: 1);
      await expectLater(
        c.dev.audit.list(),
        throwsA(isA<ServerError>().having((e) => e.message, 'message', 'Bad Gateway from proxy')),
      );
    });
  });

  group('request shape', () {
    test('path params are segment-encoded; required query is always sent', () async {
      final c = client([
        json({'available': true})
      ]);
      await c.dev.projects.checkSubdomain('a b/c', 'my-app');
      expect(c.rec.calls.single.url, '$testBaseUrl/projects/a%20b%2Fc/subdomain/check?value=my-app');
      expect(c.rec.calls.single.method, 'GET');
    });

    test('optional query drops nulls and lowercases booleans', () async {
      final c = client([
        json({'templates': <Object>[]})
      ]);
      await c.dev.templates.list({'limit': 10, 'offset': null, 'featured': true, 'search': 'a&b'});
      expect(c.rec.calls.single.url, '$testBaseUrl/templates?limit=10&featured=true&search=a%26b');
    });

    test('required and optional query combine', () async {
      final c = client([json({})]);
      await c.dev.rag.search('proj 1', {'query': 'auth', 'stats': false});
      expect(c.rec.calls.single.url, '$testBaseUrl/rag?query=auth&stats=false&projectId=proj+1');
    });

    test('the body is sent as JSON', () async {
      final c = client([
        json({'id': 'p1'})
      ]);
      await c.dev.projects.writeFiles('p1', {
        'files': [
          {'path': 'index.html', 'content': '<h1>hi</h1>'},
        ],
      });
      final call = c.rec.calls.single;
      expect(call.method, 'POST');
      expect(call.url, '$testBaseUrl/projects/p1/files');
      expect(call.body, {
        'files': [
          {'path': 'index.html', 'content': '<h1>hi</h1>'},
        ],
      });
    });

    test('a body method called without one sends {}', () async {
      final c = client([json({})]);
      await c.dev.projects.create();
      expect(c.rec.calls.single.body, <String, dynamic>{});
    });

    test('204 → null, arrays decode, non-JSON → raw text', () async {
      final empty = client([text('', status: 204)]);
      expect(await empty.dev.projects.delete('p1'), isNull);

      final list = client([
        json([1, 2, 3])
      ]);
      expect(await list.dev.skills.list(), [1, 2, 3]);

      final raw = client([text('zip-bytes-as-text')]);
      expect(await raw.dev.projects.export('p1'), 'zip-bytes-as-text');
    });

    test('encodeQuery and encodePathSegment', () {
      expect(encodeQuery(null), '');
      expect(encodeQuery({'a': null}), '');
      expect(encodeQuery({'a': false, 'b': 2}), '?a=false&b=2');
      expect(encodePathSegment('a b/c'), 'a%20b%2Fc');
    });
  });

  group('SSE', () {
    test('completionsStream sets stream: true, yields chunks and stops at [DONE]', () async {
      final c = client([
        sse([
          'data: {"choices":[{"delta":{"content":"Hel"}}]}\n',
          '\ndata: {"choices":[{"delta":{"content":"lo"}}]}\n\n',
          'data: [DONE]\n\n',
          'data: {"choices":[{"delta":{"content":"never"}}]}\n\n',
        ]),
      ]);

      final content = <String>[];
      await for (final ev in c.dev.chat.completionsStream({
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      })) {
        content.add(((ev.data as Map)['choices'] as List).first['delta']['content'] as String);
      }

      expect(content, ['Hel', 'lo']);
      final call = c.rec.calls.single;
      expect(call.method, 'POST');
      expect(call.url, '$testBaseUrl/v1/chat/completions');
      expect(call.headers['Accept'], 'text/event-stream');
      expect((call.body! as Map)['stream'], isTrue);
      expect((call.body! as Map)['messages'], isNotEmpty);
    });

    test('named events, multi-line data, ids, comments, CRLF and a trailing frame', () async {
      final c = client([
        sse([
          ': keep-alive\n\n',
          'event: step\r\nid: 7\r\ndata: line one\r\ndata: line two\r\n\r\n',
          'event: log\ndata:no-space\n\n',
          'data: {"done":true}',
        ]),
      ]);

      final events = await c.dev.projects.buildStream('p 1').toList();

      expect(c.rec.calls.single.url, '$testBaseUrl/projects/p%201/build-stream');
      expect(c.rec.calls.single.method, 'GET');
      expect(events, hasLength(3));
      expect(events[0].event, 'step');
      expect(events[0].id, '7');
      expect(events[0].data, 'line one\nline two');
      expect(events[1].event, 'log');
      expect(events[1].data, 'no-space');
      expect(events[2].event, isNull);
      expect(events[2].data, {'done': true});
    });

    test('a stream with no terminator reads [DONE] as data until EOF', () async {
      final c = client([
        sse(['data: [DONE]\n\n', 'data: after\n\n']),
      ]);
      final events = await c.dev.chat.studioStream({'message': 'hi'}).toList();
      expect(events.map((e) => e.data), ['[DONE]', 'after']);
      expect(c.rec.calls.single.body, {'message': 'hi'});
    });

    test('a plan-limit frame raises PlanLimitError', () async {
      final c = client([
        sse([
          'data: {"type":"text","text":"ok"}\n\n',
          'data: {"type":"error","code":"plan_limit_exceeded","error":"Out of credits","upgrade":{"reason":"quota_exhausted","feature":"ai_credits","urls":{"billing":"https://www.misar.dev/settings/billing"}}}\n\n',
          'data: {"type":"text","text":"never"}\n\n',
        ]),
      ]);

      final seen = <Object?>[];
      await expectLater(
        () async {
          await for (final ev in c.dev.chat.studioStream({'message': 'hi'})) {
            seen.add(ev.data);
          }
        }(),
        throwsA(isA<PlanLimitError>()
            .having((e) => e.status, 'status', 429)
            .having((e) => e.feature, 'feature', 'ai_credits')
            .having((e) => e.message, 'message', 'Out of credits')),
      );
      expect(seen, hasLength(1));
    });

    test('a non-2xx stream is typed and never retried', () async {
      final plan = client([json(planLimitBody, status: 402)]);
      await expectLater(plan.dev.chat.completionsStream().toList(), throwsA(isA<PlanLimitError>()));
      expect(plan.rec.calls, hasLength(1));

      final down = client([
        json({'error': 'down'}, status: 503, headers: {'retry-after': '0'})
      ]);
      await expectLater(down.dev.projects.buildStream('p1').toList(), throwsA(isA<ServerError>()));
      expect(down.rec.calls, hasLength(1));
    });

    test('parseSseFrame', () {
      final f = parseSseFrame('event: x\ndata: a\ndata:  b\nid: 1\nretry: 5');
      expect(f.event, 'x');
      expect(f.data, 'a\n b');
      expect(f.id, '1');
      expect(parseSseFrame(': only a comment').data, isNull);
    });
  });

  group('pagination', () {
    test('walks pages until a short one', () async {
      final offsets = <int>[];
      final pages = <Object>[
        ['a', 'b'],
        {
          'total': 5,
          'items': ['c', 'd'],
        },
        ['e'],
      ];
      final items = await paginate((offset, limit) async {
        offsets.add(offset);
        expect(limit, 2);
        return pages[offsets.length - 1];
      }, pageSize: 2)
          .toList();
      expect(items, ['a', 'b', 'c', 'd', 'e']);
      expect(offsets, [0, 2, 4]);
    });

    test('stops at maxItems and drives a real list method', () async {
      final c = client([
        json({
          'templates': [
            {'id': 1},
            {'id': 2},
          ],
        }),
      ]);
      final items = await paginate(
        (offset, limit) => c.dev.templates.list({'offset': offset, 'limit': limit}),
        pageSize: 2,
        maxItems: 3,
      ).toList();
      expect(items, hasLength(3));
      expect(c.rec.calls.map((x) => x.url), [
        '$testBaseUrl/templates?offset=0&limit=2',
        '$testBaseUrl/templates?offset=2&limit=2',
      ]);
    });

    test('itemsOf', () {
      expect(itemsOf(null), isEmpty);
      expect(itemsOf({'n': 1}), isEmpty);
      expect(itemsOf([1]), [1]);
    });
  });
}
