/// Server-Sent Events parsing.
///
/// Frames are separated by a blank line (`\n\n` or `\r\n\r\n`) and may span
/// several `data:` lines, which are joined with newlines per the SSE spec.
/// Comment lines (`:`) are keep-alives and are skipped. The terminator payload
/// — `[DONE]` on the OpenAI-compatible `/v1/chat/completions` stream — ends
/// iteration and is never yielded, so callers can simply read to completion.
library;

import 'dart:convert';

/// One Server-Sent Event.
class SseEvent {
  const SseEvent({this.event, this.data, this.id});

  /// The `event:` name, when the server sends one.
  final String? event;

  /// JSON-decoded `data:` payload (map, list, number, …), or the raw string
  /// when it is not JSON.
  final dynamic data;

  /// The `id:` field, when present.
  final String? id;

  @override
  String toString() => 'SseEvent(event: $event, id: $id, data: $data)';
}

/// The fields of one frame, before the data is decoded.
class SseFrame {
  const SseFrame({this.event, this.data, this.id});

  /// The `event:` field.
  final String? event;

  /// Every `data:` line joined with `\n`, or null when the frame had none.
  final String? data;

  /// The `id:` field.
  final String? id;
}

final RegExp _lineBreak = RegExp(r'\r?\n');
final RegExp _frameBreak = RegExp(r'\r?\n\r?\n');

/// Parse one complete frame (the text between blank lines).
SseFrame parseSseFrame(String frame) {
  String? event;
  String? id;
  final data = <String>[];
  for (final line in frame.split(_lineBreak)) {
    if (line.isEmpty || line.startsWith(':')) continue;
    final idx = line.indexOf(':');
    final field = idx == -1 ? line : line.substring(0, idx);
    var value = idx == -1 ? '' : line.substring(idx + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        data.add(value);
      case 'event':
        event = value;
      case 'id':
        id = value;
    }
  }
  return SseFrame(event: event, data: data.isEmpty ? null : data.join('\n'), id: id);
}

/// JSON-decode [raw] when it is JSON, else return it unchanged.
dynamic decodeSseData(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return raw;
  }
}

/// Iterate the events of a `text/event-stream` byte stream.
///
/// Stops — without yielding — at a frame whose data equals [terminator]
/// (`[DONE]` for chat completions). Pass `null` to read to end of stream. A
/// final frame with no trailing blank line is still delivered at EOF.
Stream<SseEvent> parseSse(Stream<List<int>> bytes, {String? terminator = '[DONE]'}) async* {
  var buffer = '';
  await for (final chunk in bytes.transform(utf8.decoder)) {
    buffer += chunk;
    while (true) {
      final match = _frameBreak.firstMatch(buffer);
      if (match == null) break;
      final frame = parseSseFrame(buffer.substring(0, match.start));
      buffer = buffer.substring(match.end);
      final data = frame.data;
      if (data == null) continue;
      if (terminator != null && data.trim() == terminator) return;
      yield SseEvent(event: frame.event, data: decodeSseData(data), id: frame.id);
    }
  }
  final last = parseSseFrame(buffer);
  final data = last.data;
  if (data != null && !(terminator != null && data.trim() == terminator)) {
    yield SseEvent(event: last.event, data: decodeSseData(data), id: last.id);
  }
}
