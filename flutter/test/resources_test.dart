/// Every operation in sdks/manifest.json is reachable through the generated
/// client, and builds the exact verb + path the server routes. Each one is
/// invoked for real (through the generated `dispatchOperation` table) against
/// a recording stub — nothing is declared.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:misardev_flutter/misardev_flutter.dart';
import 'package:misardev_flutter/src/generated/dispatch.dart';

import 'helpers.dart';

List<String> _strings(Object? v) => (v as List? ?? const []).cast<String>();

class _Op {
  _Op(this.resource, Map<String, dynamic> m, {this.stream = false})
      : name = m['name'] as String,
        verb = m['verb'] as String,
        path = m['path'] as String,
        pathParams = _strings(m['pathParams']),
        requiredQuery = stream ? const [] : _strings(m['requiredQuery']),
        queryParams = stream ? const [] : _strings(m['queryParams']),
        hasBody = m['hasBody'] == true;

  final String resource;
  final String name;
  final String verb;
  final String path;
  final List<String> pathParams;
  final List<String> requiredQuery;
  final List<String> queryParams;
  final bool hasBody;
  final bool stream;

  String get id => '$resource.$name';

  List<Object?> get args => [
        for (final p in pathParams) '$p-1',
        for (final q in requiredQuery) '$q-v',
        if (hasBody) <String, dynamic>{'probe': true},
        if (queryParams.any((q) => !requiredQuery.contains(q))) <String, Object?>{},
      ];

  String get expectedUrl {
    var p = path;
    for (final name in pathParams) {
      p = p.replaceFirst(':$name', '$name-1');
    }
    final qs = requiredQuery.map((q) => '$q=$q-v').join('&');
    return '$testBaseUrl$p${qs.isEmpty ? '' : '?$qs'}';
  }
}

void main() {
  final manifest = jsonDecode(File('../manifest.json').readAsStringSync()) as Map<String, dynamic>;
  final resources = manifest['resources'] as Map<String, dynamic>;
  final ops = [
    for (final entry in resources.entries)
      for (final m in ((entry.value as Map)['methods'] as List).cast<Map<String, dynamic>>()) _Op(entry.key, m),
  ];
  final streams = [
    for (final s in ((manifest['streams'] as Map)['sse'] as List).cast<Map<String, dynamic>>())
      _Op(s['resource'] as String, s, stream: true),
  ];

  test('generated resources cover every manifest operation', () {
    expect(operationCount, ops.length + streams.length);
  });

  group('method', () {
    for (final op in ops) {
      test(op.id, () async {
        final c = client([
          json({'ok': true})
        ]);
        final result = dispatchOperation(c.dev, op.id, op.args);
        expect(result, isA<Future<dynamic>>());
        await (result as Future<dynamic>);
        final call = c.rec.calls.single;
        expect(call.method, op.verb);
        expect(call.url, op.expectedUrl);
        if (op.hasBody) expect(call.body, containsPair('probe', true));
      });
    }
  });

  group('stream', () {
    for (final op in streams) {
      test(op.id, () async {
        final c = client([
          sse(['data: {"x":1}\n\n']),
        ]);
        final result = dispatchOperation(c.dev, op.id, op.args);
        expect(result, isA<Stream<SseEvent>>());
        final events = await (result as Stream<SseEvent>).toList();
        expect(events, hasLength(1));
        expect(events.single.data, {'x': 1});
        final call = c.rec.calls.single;
        expect(call.method, op.verb);
        expect(call.url, op.expectedUrl);
        expect(call.headers['Accept'], 'text/event-stream');
      });
    }
  });

  test('an unknown operation is rejected', () {
    final c = client([]);
    expect(() => dispatchOperation(c.dev, 'projects.nope', const []), throwsArgumentError);
  });
}
