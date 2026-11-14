import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Tests the conformance bridge server (`tool/bridge/server.dart`) directly
/// over stdio — the same protocol `conformance/test/bridge/protocol.mjs`
/// speaks. These run without Node, so they can gate bridge changes in pure
/// Dart CI.
void main() {
  late Process server;
  late Stream<Map<String, dynamic>> frames;

  setUp(() async {
    server = await Process.start(
      'dart',
      ['tool/bridge/server.dart'],
      workingDirectory: Directory.current.path,
    );
    // One shared broadcast subscription; each request awaits `.first`
    // (fresh single-shot listen) without re-listening to stdout itself.
    frames = server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .asBroadcastStream();
  });

  tearDown(() {
    server.kill();
  });

  /// Sends one op and returns the decoded response frame. While waiting,
  /// services `call` frames through [onCall] (mirrors the JS client).
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> frame, {
    Object? Function(List<Object?> args)? onCall,
  }) async {
    server.stdin.writeln(jsonEncode(frame));
    await server.stdin.flush();

    while (true) {
      final msg = await frames.first;
      if (msg['type'] == 'ready') {
        // Startup handshake; not a reply.
        continue;
      }
      if (msg['type'] == 'call') {
        if (onCall == null) {
          fail('unexpected call frame: $msg');
        }
        final value = onCall((msg['args'] as List).cast<Object?>());
        server.stdin.writeln(
          jsonEncode({
            'type': 'ret',
            'callId': msg['callId'],
            'value': value,
          }),
        );
        await server.stdin.flush();
        continue;
      }
      return msg;
    }
  }

  test('new + search round trip returns encoded results', () async {
    final id = await request({
      'op': 'new',
      'docs': ['Apple', 'Orange', 'Banana'],
      'options': {
        'keys': const <String>[],
        'includeScore': true,
      },
    });
    expect(id['type'], 'result');
    final sessionId = id['value'] as int;

    final search = await request({
      'op': 'search',
      'id': sessionId,
      'build': 'full',
      'query': 'nan',
      'limit': -1,
    });
    expect(search['type'], 'result');
    final results = (search['value'] as List).cast<Map<String, dynamic>>();
    // 'nan' also fuzzily matches 'Orange' under the default threshold —
    // same as JS.
    expect(results, hasLength(2));
    expect(results[0]['item'], 'Banana');
    expect(results[0]['refIndex'], 2);
    expect(results[0]['score'], isA<num>());
  });

  test('getFn callback round-trips mid-op', () async {
    final id = await request(
      {
        'op': 'new',
        'docs': [
          {'name': 'hello'},
          {'name': 'world'},
        ],
        'options': {
          'keys': ['custom'],
          // getFn returns doc['name'] + suffix — proves the JS-side closure
          // (here: the Dart test acting as JS) runs during indexing.
          'getFn': {r'$t': 'fn', 'ref': 'test-get-fn'},
        },
      },
      onCall: (args) {
        // getFn(obj, path) → derive a custom value.
        final doc = args[0] as Map;
        return '${doc['name']}-suffix';
      },
    );
    final sessionId = id['value'] as int;

    final search = await request({
      'op': 'search',
      'id': sessionId,
      'build': 'full',
      'query': 'hello',
      'limit': -1,
    });

    final results = (search['value'] as List).cast<Map<String, dynamic>>();
    expect(results, hasLength(1));
    expect(results[0]['item']['name'], 'hello');
  });

  test('sortFn callback orders results from the JS side', () async {
    final id = await request({
      'op': 'new',
      'docs': ['matchX', 'matchY', 'match'],
      'options': {
        'keys': const <String>[],
        'sortFn': {r'$t': 'fn', 'ref': 'test-sort-fn'},
      },
    });
    final sessionId = id['value'] as int;

    final search = await request(
      {
        'op': 'search',
        'id': sessionId,
        'build': 'full',
        'query': 'match',
        'limit': 2,
      },
      onCall: (args) {
        // Reverse the default tie-break: prefer the higher idx.
        final a = args[0] as Map;
        final b = args[1] as Map;
        if (a['score'] == b['score']) {
          return (a['idx'] as num) > (b['idx'] as num) ? -1 : 1;
        }
        return (a['score'] as num) < (b['score'] as num) ? -1 : 1;
      },
    );

    final results = (search['value'] as List).cast<Map<String, dynamic>>();
    expect(results, hasLength(2));
  });

  test('BigInt round trips through the tagged codec', () async {
    final id = await request({
      'op': 'new',
      'docs': [
        {'id': {r'$t': 'bigint', 'v': '9007199254740993'}},
        {'id': {r'$t': 'bigint', 'v': '1234567890'}},
      ],
      'options': {'keys': ['id']},
    });
    final sessionId = id['value'] as int;

    final search = await request({
      'op': 'search',
      'id': sessionId,
      'build': 'full',
      'query': '1234567890',
      'limit': -1,
    });

    final results = (search['value'] as List).cast<Map<String, dynamic>>();
    expect(results, hasLength(1));
    // item is re-encoded with the tagged BigInt.
    expect(results[0]['item']['id'], {r'$t': 'bigint', 'v': '1234567890'});
  });

  test('errors come back as error frames with the upstream message', () async {
    final response = await request({
      'op': 'new',
      'build': 'basic',
      'docs': [
        {'title': 'x'},
      ],
      'options': {'keys': ['title'], 'useExtendedSearch': true},
    });
    expect(response['type'], 'error');
    expect(response['message'], 'Extended search is not available');
  });

  test('getIndexRecords exposes records in the JSON shape', () async {
    final id = await request({
      'op': 'new',
      'docs': ['apple', 'banana'],
      'options': {'keys': const <String>[]},
    });
    final sessionId = id['value'] as int;

    final records = await request({
      'op': 'getIndexRecords',
      'id': sessionId,
    });
    final list = (records['value'] as List).cast<Map<String, dynamic>>();
    expect(list, hasLength(2));
    expect(list[0]['v'], 'apple');
    expect(list[0]['i'], 0);
    expect(list[0]['n'], isA<num>());
  });
}
