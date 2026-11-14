import 'dart:convert';
import 'dart:ffi';

import 'package:fuse_dart/src/core/config.dart';
import 'package:fuse_dart/src/core/error_messages.dart';
import 'package:fuse_dart/src/core/fuse_base.dart';
import 'package:fuse_dart/src/core/fuse_result.dart' show FuseResult;
import 'package:fuse_dart/src/core/query_parser.dart';
import 'package:fuse_dart/src/helpers/get.dart' show GetFunction;
import 'package:fuse_dart/src/helpers/types.dart';
import 'package:fuse_dart/src/search/searcher.dart';
import 'package:fuse_dart/src/search/token/analyzer.dart';
import 'package:fuse_dart/src/tools/fuse_index.dart';
import 'package:fuse_dart/src/tools/key_store.dart' show IndexedKey;
import 'package:fuse_dart/src/search/register.dart' show SearcherPlugin, registerSearchers;

import 'sync_io.dart';

/// JSON-line stdio bridge server for the conformance harness.
///
/// The JS side (`conformance/test/bridge/fuse-bridge.mjs`) forwards every
/// Fuse API call here as one JSON line and reads one response line per
/// request. While an op is being processed the server may emit `call` frames
/// (JS callbacks like getFn/sortFn/tokenize/predicates) and `warn` frames
/// (dev-mode warnings); the JS side services those inline.
///
/// Tagged values (see protocol codec):
///   {"$t":"bigint","v":"..."}        BigInt
///   {"$t":"regexp","source","flags"} RegExp
///   {"$t":"fn","ref":"..."}          JS callback reference
///   {"$t":"undef"}                   JS undefined
///   {"$t":"index","ref":N}           index handle
///   {"$t":"analyzer","ref":N}        analyzer handle
///   {"$t":"searcher","ref":N}        opaque searcher identity

/// Stand-in for JS `undefined` so it survives the JSON round trip
/// distinctly from `null`.
class _JsUndefined {
  const _JsUndefined();
}

const jsUndefined = _JsUndefined();

void main() {
  // The bridge client's FIFOs never report EOF (opened O_RDWR), and test
  // runners kill their workers without running exit handlers — so this
  // process would otherwise outlive the JS side forever. Ask the kernel to
  // SIGTERM us the moment our parent (the JS client or a Dart test) dies.
  // PR_SET_PDEATHSIG = 1, SIGTERM = 15 (Linux).
  final prctl = DynamicLibrary.process()
      .lookupFunction<IntPtr Function(Int32, IntPtr, IntPtr, IntPtr, IntPtr),
          int Function(int, int, int, int, int)>('prctl');
  prctl(1, 15, 0, 0, 0);

  final io = SyncLineIO();
  final server = _BridgeServer(io);
  // Startup handshake: lets the JS client fail fast (watchdog) instead of
  // blocking forever if this process dies before serving requests.
  io.writeLine(jsonEncode({'type': 'ready'}));
  while (true) {
    final line = io.readLine();
    if (line == null) break;
    if (line.trim().isEmpty) continue;
    server.handleLine(line);
  }
}

class _BridgeServer {
  _BridgeServer(this._io);

  final SyncLineIO _io;
  final Map<int, Fuse<dynamic>> _sessions = {};
  final Map<int, Map<String, dynamic>> _sessionRawOptions = {};
  final Map<int, FuseIndex<dynamic>> _indexes = {};
  final Map<int, Analyzer> _analyzers = {};
  int _nextId = 1;
  int _nextCallId = 1;
  void handleLine(String line) {
    Map<String, dynamic> frame;
    try {
      frame = (jsonDecode(line) as Map).cast<String, dynamic>();
    } catch (e) {
      _emit({'type': 'error', 'message': 'bad frame: $e'});
      return;
    }

    final op = frame['op'] as String;
    try {
      final result = _dispatch(op, frame);
      _emit({'type': 'result', 'value': encodeValue(result)});
    } catch (e) {
      _emit({'type': 'error', 'message': _errorMessage(e)});
    }
  }

  String _errorMessage(Object e) {
    if (e is FuseException) return e.message;
    if (e is ArgumentError) return (e.message ?? e.toString()).toString();
    return e.toString();
  }

  void _emit(Map<String, dynamic> frame) {
    _io.writeLine(jsonEncode(frame));
  }

  Object? _dispatch(String op, Map<String, dynamic> frame) {
    switch (op) {
      case 'new':
        return _opNew(frame);
      case 'setCollection':
        return _opSetCollection(frame);
      case 'add':
        return _opAdd(frame);
      case 'remove':
        return _opRemove(frame);
      case 'removeAt':
        return _opRemoveAt(frame);
      case 'search':
        return _opSearch(frame);
      case 'match':
        return _opMatch(frame);
      case 'createIndex':
        return _opCreateIndex(frame);
      case 'parseIndex':
        return _opParseIndex(frame);
      case 'indexToJSON':
        return _opIndexToJSON(frame);
      case 'indexRemoveAt':
        return _opIndexRemoveAt(frame);
      case 'indexRemoveAll':
        return _opIndexRemoveAll(frame);
      case 'getIndexRecords':
        return _opGetIndexRecords(frame);
      case 'getIndexSize':
        return _opGetIndexSize(frame);
      case 'getInvertedIndex':
        return _opGetInvertedIndex(frame);
      case 'getInternal':
        return _opGetInternal(frame);
      case 'getIndex':
        return _opGetIndex(frame);
      case 'getIndexKeys':
        return _opGetIndexKeys(frame);
      case 'use':
        return _opUse(frame);
      case 'analyzer':
        return _opAnalyzer(frame);
      case 'tokenize':
        return _opTokenize(frame);
      case 'parseQuery':
        return _opParseQuery(frame);
      default:
        throw FuseException('unknown op: $op');
    }
  }

  // ── Ops ─────────────────────────────────────────────────────────

  int _opNew(Map<String, dynamic> frame) {
    final id = _nextId++;
    final build = frame['build'] as String? ?? 'full';
    final docs = decodeValue(frame['docs']) as List<Object?>;
    final options = _decodeOptions(frame['options']);
    final index = _resolveIndex(frame['index']);

    if (build == 'basic') {
      if (options.useExtendedSearch) {
        throw FuseException(extendedSearchUnavailable);
      }
      if (options.useTokenSearch) {
        throw FuseException(tokenSearchUnavailable);
      }
      // The basic build registers no extra searchers, so extended/token
      // conditions never fire even if the flags were set another way.
      options.useExtendedSearch = false;
      options.useTokenSearch = false;
    }

    _sessions[id] = index != null
        ? Fuse<dynamic>(docs, options: options, index: index)
        : Fuse<dynamic>(docs, options: options);
    _sessionRawOptions[id] =
        (frame['options'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    return id;
  }

  int _opSetCollection(Map<String, dynamic> frame) {
    final fuse = _session(frame);
    final docs = decodeValue(frame['docs']) as List<Object?>;
    final index = _resolveIndex(frame['index']);
    if (index != null) {
      fuse.setCollection(docs, index);
    } else {
      fuse.setCollection(docs);
    }
    return 0;
  }

  int _opAdd(Map<String, dynamic> frame) {
    _session(frame).add(decodeValue(frame['doc']));
    return 0;
  }

  Map<String, dynamic> _opRemove(Map<String, dynamic> frame) {
    final fuse = _session(frame);
    final ref = ((frame['fnRef'] as Map?)?['ref'] ?? '') as String;
    final indicesToRemove = <int>[];
    final removed = fuse.remove((doc, idx) {
      final result = _callJs(ref, [doc, idx]);
      if (result == true) {
        indicesToRemove.add(idx);
        return true;
      }
      return false;
    });
    return {
      'removed': [for (final doc in removed) encodeValue(doc)],
      'indices': indicesToRemove,
    };
  }

  Object? _opRemoveAt(Map<String, dynamic> frame) {
    return _session(frame).removeAt((frame['idx'] as num).toInt());
  }

  List<Object?> _opSearch(Map<String, dynamic> frame) {
    final fuse = _session(frame);
    final build = frame['build'] as String? ?? 'full';
    final query = decodeValue(frame['query']);
    final limit = (frame['limit'] as num?)?.toInt() ?? -1;

    if (build == 'basic' && query is Map) {
      throw FuseException(logicalSearchUnavailable);
    }

    _activeSessionId = (frame['id'] as num).toInt();
    try {
      final results = fuse.search(query as Object, limit: limit);
      return [
        for (final result in results) _encodeFuseResult(result),
      ];
    } finally {
      _activeSessionId = null;
    }
  }

  Map<String, dynamic> _opMatch(Map<String, dynamic> frame) {
    final build = frame['build'] as String? ?? 'full';
    final options = _decodeOptions(frame['options']);
    // The Fuse.match token-search guard fires in both builds, before any
    // feature gate (mirrors upstream entry.ts).
    if (options.useTokenSearch) {
      throw FuseException(fuseMatchTokenSearchUnsupported);
    }
    if (build == 'basic') {
      if (options.useExtendedSearch) {
        throw FuseException(extendedSearchUnavailable);
      }
      options.useExtendedSearch = false;
    }
    final result = Fuse.match(
      frame['pattern'] as String,
      frame['text'] as String,
      options,
    );
    return {
      'isMatch': result.isMatch,
      'score': result.score,
      if (result.indices != null) 'indices': result.indices,
    };
  }

  int _opCreateIndex(Map<String, dynamic> frame) {
    final handle = _nextId++;
    final options = frame['options'] as Map? ?? const {};
    final getFnRef = options['getFn'];
    final fieldNormWeight =
        (options['fieldNormWeight'] as num?)?.toDouble() ?? 1;
    final keys = (frame['keys'] as List).cast<Object>().toList();
    final docs = decodeValue(frame['docs']) as List<Object?>;

    _indexes[handle] = createFuseIndex<Object?>(
      _decodeKeys(keys),
      docs,
      getFn: getFnRef == null ? null : _getFnFromRef(getFnRef as Object),
      fieldNormWeight: fieldNormWeight,
    );
    return handle;
  }

  int _opParseIndex(Map<String, dynamic> frame) {
    final handle = _nextId++;
    final data = (decodeValue(frame['data']) as Map).cast<String, dynamic>();
    final options = frame['options'] as Map? ?? const {};
    final getFnRef = options['getFn'];
    final fieldNormWeight =
        (options['fieldNormWeight'] as num?)?.toDouble() ?? 1;
    _indexes[handle] = parseFuseIndex<Object?>(
      data,
      getFn: getFnRef == null ? null : _getFnFromRef(getFnRef as Object),
      fieldNormWeight: fieldNormWeight,
    );
    return handle;
  }

  Map<String, dynamic> _opIndexToJSON(Map<String, dynamic> frame) {
    return _resolveIndex(frame['index'])!.toJson();
  }

  int _opIndexRemoveAt(Map<String, dynamic> frame) {
    _resolveIndex(frame['index'])!.removeAt((frame['idx'] as num).toInt());
    return 0;
  }

  int _opIndexRemoveAll(Map<String, dynamic> frame) {
    final raw = decodeValue(frame['indices']) as List<Object?>;
    _resolveIndex(frame['index'])!.removeAll([
      for (final value in raw)
        if (value is num && value is int) value,
    ]);
    return 0;
  }

  List<Object?> _opGetIndexRecords(Map<String, dynamic> frame) {
    final index = frame.containsKey('index')
        ? _resolveIndex(frame['index'])!
        : _session(frame).getIndex();
    return [for (final record in index.records) _encodeRecord(record)];
  }

  int _opGetIndexSize(Map<String, dynamic> frame) {
    final index = frame.containsKey('index')
        ? _resolveIndex(frame['index'])!
        : _session(frame).getIndex();
    return index.size();
  }

  Map<String, dynamic> _opGetInvertedIndex(Map<String, dynamic> frame) {
    final fuse = _session(frame);
    final inv = fuse.invertedIndex;
    if (inv == null) {
      return {
        'fieldCount': 0,
        'df': const <Object?>[],
        'docFieldCount': const <Object?>[],
        'docTermFieldHits': const <Object?>[],
      };
    }
    return {
      'fieldCount': inv.fieldCount,
      'df': [
        for (final entry in inv.df.entries) [entry.key, entry.value],
      ],
      'docFieldCount': [
        for (final entry in inv.docFieldCount.entries)
          [entry.key, entry.value],
      ],
      'docTermFieldHits': [
        for (final entry in inv.docTermFieldHits.entries)
          [
            entry.key,
            [
              for (final term in entry.value.entries)
                [term.key, term.value],
            ],
          ],
      ],
    };
  }

  Object? _opGetInternal(Map<String, dynamic> frame) {
    final fuse = _session(frame);
    switch (frame['key'] as String) {
      case 'lastQuery':
        return fuse.lastQuery;
      case 'lastSearcher':
        final searcher = fuse.lastSearcherId;
        return searcher == null
            ? null
            : {r'$t': 'searcher', 'ref': identityHashCode(searcher)};
      default:
        throw FuseException('unknown internal: ${frame['key']}');
    }
  }

  int _opGetIndex(Map<String, dynamic> frame) {
    final fuse = _session(frame);
    final index = fuse.getIndex();
    // Register (or reuse) a stable handle for this index object.
    for (final entry in _indexes.entries) {
      if (identical(entry.value, index)) {
        return entry.key;
      }
    }
    final handle = _nextId++;
    _indexes[handle] = index;
    return handle;
  }

  List<Object?> _opGetIndexKeys(Map<String, dynamic> frame) {
    final index = frame.containsKey('index')
        ? _resolveIndex(frame['index'])!
        : _session(frame).getIndex();
    return [for (final key in index.keys) _encodeKey(key)];
  }

  Map<String, dynamic> _encodeKey(IndexedKey<dynamic> key) {
    return {
      'path': key.path,
      'id': key.id,
      'weight': key.weight,
      'src': encodeValue(key.src),
    };
  }

  /// Registers a JS-defined searcher plugin. The plugin's static
  /// `condition(pattern, options)` and instance `searchIn(text)` run in JS
  /// via callbacks; the Dart side holds a thin remote wrapper.
  int _opUse(Map<String, dynamic> frame) {
    final ref = ((frame['ref'] as Map)['ref'] ?? '') as String;
    registerSearchers([
      SearcherPlugin(
        condition: (String pattern, FuseOptions<dynamic> options) {
          final result = _callJs(
            '$ref:condition',
            [pattern, _optionsSnapshot(options)],
          );
          return result == true;
        },
        create:
            (String pattern, FuseOptions<dynamic> options, Object? _) {
          final instanceId = _callJs(
            '$ref:create',
            [pattern, _optionsSnapshot(options)],
          );
          return _RemoteSearcher(this, ref, (instanceId as num).toInt());
        },
      ),
    ]);
    return 0;
  }

  /// Re-emits a session's options as a merged JSON map. Function-valued
  /// options (sortFn/getFn/tokenize) stay as tagged `{ref}` markers, which
  /// is what JS callbacks expect to see. The active session id is set by
  /// the op dispatcher around any call that can synchronously create
  /// searchers (search, parseQuery, match, ...).
  Map<String, dynamic> _optionsSnapshot(FuseOptions<dynamic> options) {
    final merged = <String, dynamic>{
      'isCaseSensitive': false,
      'ignoreDiacritics': false,
      'includeScore': false,
      'shouldSort': true,
      'keys': const <Object?>[],
      'includeMatches': false,
      'findAllMatches': false,
      'minMatchCharLength': 1,
      'location': 0,
      'threshold': 0.6,
      'distance': 100,
      'useExtendedSearch': false,
      'useTokenSearch': false,
      'tokenMatch': 'any',
      'ignoreLocation': false,
      'ignoreFieldNorm': false,
      'fieldNormWeight': 1,
    };
    final raw = _activeSessionId == null
        ? null
        : _sessionRawOptions[_activeSessionId];
    if (raw != null) {
      merged.addAll(raw);
    }
    return merged;
  }

  int? _activeSessionId;

  int _opAnalyzer(Map<String, dynamic> frame) {
    final handle = _nextId++;
    final options = frame['options'] as Map? ?? const {};
    final dev = frame['dev'] == true;
    _analyzers[handle] = createAnalyzer(
      isCaseSensitive: options['isCaseSensitive'] == true,
      ignoreDiacritics: options['ignoreDiacritics'] == true,
      tokenize: options['tokenize'] == null
          ? null
          : _decodeTokenize(options['tokenize'] as Object, dev),
    );
    return handle;
  }

  List<Object?> _opTokenize(Map<String, dynamic> frame) {
    final analyzer = _analyzers[(frame['handle'] as num).toInt()]!;
    return analyzer.tokenize(frame['text'] as String);
  }

  Map<String, dynamic> _opParseQuery(Map<String, dynamic> frame) {
    final options = _decodeOptions(frame['options']);
    final auto = frame['auto'] == true;
    final query = decodeValue(frame['query']);
    _activeSessionId = frame.containsKey('id')
        ? (frame['id'] as num).toInt()
        : null;
    try {
      return _serializeNode(parse<Object?>(query as Object, options, auto: auto));
    } finally {
      _activeSessionId = null;
    }
  }

  Map<String, dynamic> _serializeNode(LogicalNode node) {
    if (node is LogicalLeaf) {
      return {
        'keyId': node.keyId,
        'pattern': node.pattern,
        if (node.searcher != null) 'searcher': {r'$t': 'searcher'},
      };
    }
    final expr = node as LogicalExpression;
    return {
      'children': [for (final c in expr.children) _serializeNode(c)],
      'operator': expr.operator,
    };
  }

  // ── Helpers ─────────────────────────────────────────────────────

  Fuse<dynamic> _session(Map<String, dynamic> frame) =>
      _sessions[(frame['id'] as num).toInt()]!;

  FuseIndex<dynamic>? _resolveIndex(Object? ref) {
    if (ref == null) return null;
    final map = ref as Map;
    if (map[r'$t'] != 'index') {
      throw FuseException('expected index handle');
    }
    return _indexes[(map['ref'] as num).toInt()];
  }

  Map<String, dynamic> _encodeFuseResult(FuseResult<dynamic> result) {
    return {
      'item': encodeValue(result.item),
      'refIndex': result.refIndex,
      if (result.score != null) 'score': result.score,
      if (result.matches != null)
        'matches': [
          for (final match in result.matches!)
            {
              'indices': match.indices,
              'value': match.value,
              if (match.key != null) 'key': match.key,
              if (match.refIndex != null) 'refIndex': match.refIndex,
            },
        ],
    };
  }

  Map<String, dynamic> _encodeRecord(FuseRecord record) {
    if (record is StringRecord) {
      return {'v': record.v, 'i': record.i, 'n': record.n};
    }
    final objectRecord = record as ObjectRecord;
    final dollar = <String, dynamic>{};
    objectRecord.entries.forEach((keyIndex, value) {
      if (value is List<RecordValue>) {
        dollar['$keyIndex'] = [
          for (final v in value)
            {
              'v': v.v,
              if (v.i != null) 'i': v.i,
              'n': v.n,
            },
        ];
      } else if (value is RecordValue) {
        dollar['$keyIndex'] = {
          'v': value.v,
          if (value.i != null) 'i': value.i,
          'n': value.n,
        };
      }
    });
    return {'i': record.i, r'$': dollar};
  }

  List<Object> _decodeKeys(List<Object> keys) => [
        for (final key in keys) _decodeKey(key),
      ];

  Object _decodeKey(Object key) {
    if (key is String) return key;
    if (key is List) {
      return [for (final segment in key) segment as String];
    }
    final map = key as Map;
    if (!map.containsKey('name') ||
        map['name'] == null ||
        (map['name'] is Map && (map['name'] as Map)[r'$t'] == 'undef')) {
      throw FuseException(missingKeyProperty('name'));
    }
    final name = decodeValue(map['name']);
    return FuseKey<dynamic>(
      name: name as Object,
      weight: (map['weight'] as num?)?.toDouble() ?? 1,
      getFn: map['getFn'] == null ? null : _keyGetFnFromRef(map['getFn'] as Object),
    );
  }

  FuseOptions<dynamic> _decodeOptions(Object? raw) {
    final merged = FuseOptions<dynamic>();
    if (raw == null) return merged;

    // JS `{ ...defaults, ...options }` spreads carry explicit `undefined`
    // values for unset keys; those mean "absent" upstream. Strip them.
    final source =
        <dynamic, dynamic>{for (final e in (raw as Map).entries) e.key: e.value}
          ..removeWhere((_, v) => v is Map && v[r'$t'] == 'undef');
    final map = source;
    dynamic pick(String key) => map.containsKey(key) ? map[key] : null;

    if (map.containsKey('isCaseSensitive')) {
      merged.isCaseSensitive = pick('isCaseSensitive') == true;
    }
    if (map.containsKey('ignoreDiacritics')) {
      merged.ignoreDiacritics = pick('ignoreDiacritics') == true;
    }
    if (map.containsKey('includeScore')) {
      merged.includeScore = pick('includeScore') == true;
    }
    if (map.containsKey('shouldSort')) {
      merged.shouldSort = pick('shouldSort') == true;
    }
    if (map.containsKey('sortFn')) {
      final ref = (pick('sortFn') as Map)['ref'] as String;
      merged.sortFn = (a, b) {
        final result = _callJs(ref, [_encodeSortArg(a), _encodeSortArg(b)]);
        return (result as num).toInt();
      };
    }
    if (map.containsKey('keys')) {
      merged.keys = _decodeKeys((pick('keys') as List).cast<Object>().toList());
    }
    if (map.containsKey('includeMatches')) {
      merged.includeMatches = pick('includeMatches') == true;
    }
    if (map.containsKey('findAllMatches')) {
      merged.findAllMatches = pick('findAllMatches') == true;
    }
    if (map.containsKey('minMatchCharLength')) {
      merged.minMatchCharLength = (pick('minMatchCharLength') as num).toInt();
    }
    if (map.containsKey('location')) {
      merged.location = (pick('location') as num).toInt();
    }
    if (map.containsKey('threshold')) {
      merged.threshold = (pick('threshold') as num).toDouble();
    }
    if (map.containsKey('distance')) {
      merged.distance = (pick('distance') as num).toInt();
    }
    if (map.containsKey('useExtendedSearch')) {
      merged.useExtendedSearch = pick('useExtendedSearch') == true;
    }
    if (map.containsKey('useTokenSearch')) {
      merged.useTokenSearch = pick('useTokenSearch') == true;
    }
    if (map.containsKey('tokenize')) {
      merged.tokenize = _decodeTokenize(pick('tokenize') as Object, false);
    }
    if (map.containsKey('tokenMatch')) {
      merged.tokenMatch = pick('tokenMatch') as String;
    }
    if (map.containsKey('getFn')) {
      merged.getFn = _getFnFromRef(pick('getFn') as Object);
    }
    if (map.containsKey('ignoreLocation')) {
      merged.ignoreLocation = pick('ignoreLocation') == true;
    }
    if (map.containsKey('ignoreFieldNorm')) {
      merged.ignoreFieldNorm = pick('ignoreFieldNorm') == true;
    }
    if (map.containsKey('fieldNormWeight')) {
      merged.fieldNormWeight = (pick('fieldNormWeight') as num).toDouble();
    }
    return merged;
  }

  Map<String, dynamic> _encodeSortArg(FuseSortFunctionArg arg) {
    return {
      'idx': arg.idx,
      'item': encodeValue(arg.item),
      'score': arg.score,
      if (arg.matches != null)
        'matches': [
          for (final m in arg.matches!)
            {
              'score': m.score,
              'key': m.key,
              'value': m.value,
              if (m.idx != null) 'idx': m.idx,
              if (m.indices != null) 'indices': m.indices,
            },
        ],
    };
  }

  GetFunction<dynamic> _getFnFromRef(Object ref) {
    final fnRef = ((ref as Map)['ref'] ?? '') as String;
    return (Object? obj, Object path) => _callJs(fnRef, [obj, path]);
  }

  KeyGetFunction<dynamic> _keyGetFnFromRef(Object ref) {
    final fnRef = ((ref as Map)['ref'] ?? '') as String;
    return (Object? obj) => _callJs(fnRef, [obj]);
  }

  Object _decodeTokenize(Object ref, bool dev) {
    final map = ref as Map;
    if (map[r'$t'] == 'regexp') {
      final flags = map['flags'] as String? ?? '';
      final regexp = RegExp(
        map['source'] as String,
        multiLine: flags.contains('m'),
        caseSensitive: !flags.contains('i'),
        unicode: flags.contains('u'),
      );
      final global = flags.contains('g');
      return (String text) => _allMatches(regexp, text, global);
    }
    final fnRef = (map['ref'] ?? '') as String;
    var validated = false;
    return (String text) {
      final result = _callJs(fnRef, [text]);
      // Upstream validates only the first call per tokenize closure.
      if (dev && !validated) {
        validated = true;
        if (result is! List) {
          throw FuseException(
            '[Fuse] tokenize function must return string[]; received '
            '${_jsTypeOf(result)}.',
          );
        }
        for (final token in result) {
          if (token is! String) {
            throw FuseException(
              '[Fuse] tokenize function must return string[]; received '
              'array containing non-strings.',
            );
          }
        }
      }
      return [for (final token in result as List) token as String];
    };
  }

  String _jsTypeOf(Object? value) {
    if (value == null || value == jsUndefined) return 'undefined';
    if (value is bool) return 'boolean';
    if (value is num) return 'number';
    if (value is String) return 'string';
    if (value is List) return 'array';
    return 'object';
  }

  List<String> _allMatches(RegExp regexp, String text, bool global) {
    if (!global) {
      final first = regexp.firstMatch(text);
      return first == null ? const [] : [first.group(0)!];
    }
    return [for (final m in regexp.allMatches(text)) m.group(0)!];
  }

  /// Calls a registered JS callback and awaits its reply synchronously.
  Object? _callJs(String ref, List<Object?> args) {
    final callId = _nextCallId++;
    _emit({
      'type': 'call',
      'ref': ref,
      'callId': callId,
      'args': [for (final arg in args) encodeValue(arg)],
    });

    // Read frames until the reply to THIS call arrives (JS replies to the
    // current call before anything else, so a plain scan works).
    while (true) {
      final line = _io.readLine();
      if (line == null) {
        throw FuseException('bridge closed during callback');
      }
      final frame = (jsonDecode(line) as Map).cast<String, dynamic>();
      final type = frame['type'] as String;
      if (type == 'ret' && '${frame['callId']}' == '$callId') {
        return decodeValue(frame['value']);
      }
      if (type == 'callerr' && '${frame['callId']}' == '$callId') {
        throw FuseException(frame['message'] as String? ?? 'callback failed');
      }
      // Anything else while waiting for a reply is a protocol violation.
      throw FuseException('unexpected frame during callback: $type');
    }
  }

}

/// A searcher whose `searchIn` runs in JS (a `Fuse.use` plugin). Each call
/// round-trips through the bridge with the plugin instance id.
class _RemoteSearcher implements Searcher {
  _RemoteSearcher(this._server, this._ref, this._instanceId);

  final _BridgeServer _server;
  final String _ref;
  final int _instanceId;

  @override
  SearchResult searchIn(String text) {
    final value = _server._callJs('$_ref:searchIn', [
      _instanceId,
      text,
    ]);
    final map = value as Map;
    return SearchResult(
      isMatch: map['isMatch'] == true,
      score: (map['score'] as num?)?.toDouble() ?? 1,
      indices: (map['indices'] as List?)
          ?.map((pair) => [(pair as List)[0] as int, pair[1] as int])
          .toList(),
      hasInverse: map['hasInverse'] == true ? true : null,
    );
  }
}

// ── Value codec ───────────────────────────────────────────────────

Object? decodeValue(Object? value) {
  if (value is Map) {
    switch (value[r'$t']) {
      case 'bigint':
        return BigInt.parse(value['v'] as String);
      case 'undef':
        return jsUndefined;
      case 'index':
      case 'fn':
      case 'regexp':
      case 'searcher':
        return value;
      default:
        return {
          for (final entry in value.entries)
            entry.key.toString(): decodeValue(entry.value),
        };
    }
  }
  if (value is List) {
    return [for (final item in value) decodeValue(item)];
  }
  return value;
}

Object? encodeValue(Object? value) {
  if (value == null) return null;
  if (value is bool || value is String) return value;
  if (value == jsUndefined) {
    return {r'$t': 'undef'};
  }
  if (value is BigInt) {
    return {r'$t': 'bigint', 'v': value.toString()};
  }
  if (value is num) return value;
  if (value is RegExp) {
    return {
      r'$t': 'regexp',
      'source': value.pattern,
      'flags': _regexpFlags(value),
    };
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): encodeValue(entry.value),
    };
  }
  if (value is List) return [for (final item in value) encodeValue(item)];
  return value.toString();
}

String _regexpFlags(RegExp regexp) {
  var flags = '';
  if (regexp.isMultiLine) flags += 'm';
  if (!regexp.isCaseSensitive) flags += 'i';
  if (regexp.isUnicode) flags += 'u';
  return flags;
}
