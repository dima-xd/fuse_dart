import '../helpers/get.dart';
import '../search/create_searcher.dart';
import '../search/searcher.dart';
import '../tools/fuse_index.dart';
import '../tools/key_store.dart';
import 'compute_score.dart';
import 'config.dart';
import 'error_messages.dart';
import 'format.dart';
import 'fuse_result.dart';
import 'query_parser.dart';
import 'results.dart';

/// Fuzzy searcher over a collection of [docs].
///
/// [T] is the document type — typically `String` for a list of strings or
/// `Map<String, dynamic>` for objects. Configure behavior with [options].
///
/// ```dart
/// final fuse = Fuse(books, options: FuseOptions(keys: ['title', 'author']));
/// final results = fuse.search('old man war');
/// ```
class Fuse<T> {
  /// Creates a searcher over [docs].
  ///
  /// Pass [options] to configure keys, threshold, and other behavior. Pass a
  /// prebuilt [index] (a [FuseIndex]) to skip indexing; it must match [docs].
  Fuse(List<T> docs, {FuseOptions<T>? options, Object? index})
      : options = options ?? FuseOptions<T>() {
    _keyStore = KeyStore<T>(this.options.keys);
    setCollection(docs, index);
  }

  /// The options this instance was created with.
  final FuseOptions<T> options;
  late final KeyStore<T> _keyStore;
  late List<T> _docs;
  late FuseIndex<T> _myIndex;

  /// The Fuse.js version this port targets.
  static const String version = '7.1.0';

  /// Replaces the searched collection with [docs], rebuilding the index.
  ///
  /// Pass an existing [index] to reuse it instead of rebuilding.
  void setCollection(List<T> docs, [Object? index]) {
    _docs = docs;

    if (index != null && index is! FuseIndex<T>) {
      throw ArgumentError(incorrectIndexType);
    }

    _myIndex = (index as FuseIndex<T>?) ??
        createFuseIndex<T>(
          options.keys,
          _docs,
          getFn: options.getFn,
          fieldNormWeight: options.fieldNormWeight,
        );
  }

  /// Appends [doc] to the collection and indexes it.
  void add(T doc) {
    _docs.add(doc);
    _myIndex.add(doc);
  }

  /// Removes every document for which [predicate] returns `true`.
  ///
  /// Returns the removed documents in their original order.
  List<T> remove(bool Function(T doc, int idx) predicate) {
    final results = <T>[];

    for (var i = 0, len = _docs.length; i < len; i += 1) {
      final doc = _docs[i];
      if (predicate(doc, i)) {
        removeAt(i);
        i -= 1;
        len -= 1;
        results.add(doc);
      }
    }

    return results;
  }

  /// Removes the document at [idx] from the collection and the index.
  void removeAt(int idx) {
    _docs.removeAt(idx);
    _myIndex.removeAt(idx);
  }

  /// Returns the underlying search index.
  FuseIndex<T> getIndex() => _myIndex;

  /// Searches the collection for [query] and returns ranked results.
  ///
  /// [query] is a `String` for plain/extended search, or a `Map` for a
  /// logical `$and`/`$or` query. Pass [limit] to cap the number of results
  /// (`-1` means no limit). Throws [ArgumentError] for an unsupported query.
  List<FuseResult<T>> search(Object query, {int limit = -1}) {
    List<InternalResult<T>> results;

    if (query is String) {
      results = _docs.isNotEmpty && _docs.first is String
          ? _searchStringList(query)
          : _searchObjectList(query);
    } else if (query is Map) {
      results = _searchLogical(query);
    } else {
      throw ArgumentError(logicalSearchInvalidQueryForKey(query.toString()));
    }

    computeScore<T>(results, ignoreFieldNorm: options.ignoreFieldNorm);

    if (options.shouldSort) {
      final args = [
        for (final r in results)
          FuseSortFunctionArg(
            idx: r.idx,
            score: r.score,
            item: r.item,
            matches: [
              for (final m in r.matches)
                FuseSortFunctionMatch(
                  score: m.score,
                  key: m.key?.id ?? '',
                  value: m.value,
                  idx: m.idx,
                  indices: m.indices,
                ),
            ],
          ),
      ];

      final order = List<int>.generate(results.length, (i) => i);
      order.sort((a, b) => options.sortFn(args[a], args[b]));
      results = [for (final i in order) results[i]];
    }

    if (limit > -1) {
      results =
          results.sublist(0, limit < results.length ? limit : results.length);
    }

    return format<T>(
      results,
      _docs,
      includeMatches: options.includeMatches,
      includeScore: options.includeScore,
    );
  }

  List<InternalResult<T>> _searchStringList(String query) {
    final searcher = createSearcher<T>(query, options);
    final results = <InternalResult<T>>[];

    for (final record in _myIndex.records) {
      if (record is! StringRecord) {
        continue;
      }

      final result = searcher.searchIn(record.v);

      if (result.isMatch) {
        results.add(
          InternalResult<T>(
            idx: record.i,
            item: record.v,
            matches: [
              MatchData<T>(
                score: result.score,
                value: record.v,
                norm: record.n,
                indices: result.indices,
              ),
            ],
          ),
        );
      }
    }

    return results;
  }

  List<InternalResult<T>> _searchObjectList(String query) {
    final searcher = createSearcher<T>(query, options);
    final keys = _myIndex.keys;
    final results = <InternalResult<T>>[];

    for (final record in _myIndex.records) {
      if (record is! ObjectRecord) {
        continue;
      }

      final item = record.entries;
      final matches = <MatchData<T>>[];

      for (var keyIndex = 0; keyIndex < keys.length; keyIndex += 1) {
        matches.addAll(
          _findMatches(
            key: keys[keyIndex],
            value: item[keyIndex],
            searcher: searcher,
          ),
        );
      }

      if (matches.isNotEmpty) {
        results.add(
            InternalResult<T>(idx: record.i, item: item, matches: matches));
      }
    }

    return results;
  }

  List<InternalResult<T>> _searchLogical(Map query) {
    final expression = parse<T>(query, options);

    List<InternalResult<T>> evaluate(
      LogicalNode node,
      Map<int, Object> item,
      int idx,
    ) {
      if (node is LogicalLeaf) {
        final matches = _findMatches(
          key: _keyStore.get(node.keyId),
          value: _myIndex.getValueForItemAtKeyId(item, node.keyId),
          searcher: node.searcher!,
        );

        if (matches.isNotEmpty) {
          return [InternalResult<T>(idx: idx, item: item, matches: matches)];
        }

        return [];
      }

      final expr = node as LogicalExpression;
      final res = <InternalResult<T>>[];

      for (final child in expr.children) {
        final result = evaluate(child, item, idx);
        if (result.isNotEmpty) {
          res.addAll(result);
        } else if (expr.operator == logicalAnd) {
          return [];
        }
      }

      return res;
    }

    final resultMap = <int, InternalResult<T>>{};
    final results = <InternalResult<T>>[];

    for (final record in _myIndex.records) {
      if (record is! ObjectRecord) {
        continue;
      }

      final item = record.entries;
      final idx = record.i;

      final expResults = evaluate(expression, item, idx);

      if (expResults.isNotEmpty) {
        var entry = resultMap[idx];
        if (entry == null) {
          entry = InternalResult<T>(idx: idx, item: item, matches: []);
          resultMap[idx] = entry;
          results.add(entry);
        }
        for (final r in expResults) {
          entry.matches.addAll(r.matches);
        }
      }
    }

    return results;
  }

  List<MatchData<T>> _findMatches({
    required IndexedKey<T>? key,
    required Object? value,
    required Searcher searcher,
  }) {
    if (value == null) {
      return [];
    }

    final matches = <MatchData<T>>[];

    if (value is List<RecordValue>) {
      for (final rv in value) {
        final result = searcher.searchIn(rv.v);
        if (result.isMatch) {
          matches.add(
            MatchData<T>(
              score: result.score,
              key: key,
              value: rv.v,
              idx: rv.i,
              norm: rv.n,
              indices: result.indices,
            ),
          );
        }
      }
    } else if (value is RecordValue) {
      final result = searcher.searchIn(value.v);
      if (result.isMatch) {
        matches.add(
          MatchData<T>(
            score: result.score,
            key: key,
            value: value.v,
            norm: value.n,
            indices: result.indices,
          ),
        );
      }
    }

    return matches;
  }

  /// Builds a reusable [FuseIndex] for [docs] over [keys].
  ///
  /// Build once and pass to multiple [Fuse] instances to avoid re-indexing.
  static FuseIndex<U> createIndex<U>(
    List<Object> keys,
    List<U> docs, {
    GetFunction<U>? getFn,
    double fieldNormWeight = 1,
  }) =>
      createFuseIndex<U>(keys, docs,
          getFn: getFn, fieldNormWeight: fieldNormWeight);

  /// Rebuilds a [FuseIndex] from previously serialized [data].
  ///
  /// [data] is the JSON produced by [FuseIndex.toJson].
  static FuseIndex<U> parseIndex<U>(
    Map<String, dynamic> data, {
    GetFunction<U>? getFn,
    double fieldNormWeight = 1,
  }) =>
      parseFuseIndex<U>(data, getFn: getFn, fieldNormWeight: fieldNormWeight);

  /// Parses a logical [query] into a [LogicalNode] tree.
  ///
  /// When [auto] is `true`, a searcher is attached to each leaf.
  static LogicalNode parseQuery<U>(
    Map query,
    FuseOptions<U> options, {
    bool auto = true,
  }) =>
      parse<U>(query, options, auto: auto);
}
