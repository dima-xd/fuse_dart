import '../helpers/get.dart';
import '../helpers/types.dart';
import '../search/register.dart';
import '../search/searcher.dart';import '../search/token/analyzer.dart';
import '../search/token/inverted_index.dart';
import '../search/token/token_search.dart' show maxMaskTerms;
import '../tools/fuse_index.dart';
import '../tools/key_store.dart';
import '../tools/max_heap.dart';
import 'compute_score.dart';
import 'config.dart';
import 'error_messages.dart';
import 'format.dart';
import 'fuse_result.dart';
import 'query_parser.dart';
import 'results.dart';

class _HeapSearchOptions<T> {
  const _HeapSearchOptions({this.heap, this.ignoreFieldNorm = false});

  final MaxHeap<T>? heap;
  final bool ignoreFieldNorm;
}

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
  Fuse(List<T> docs, {FuseOptions<T>? options, FuseIndex<T>? index})
      : options = (options ?? FuseOptions<T>()).snapshot() {
    _keyStore = KeyStore<T>(this.options.keys);
    _docs = docs;
    setCollection(docs, index);
    _lastQuery = null;
    _lastSearcher = null;
  }

  /// The options this instance was created with.
  final FuseOptions<T> options;
  late final KeyStore<T> _keyStore;
  late List<T> _docs;
  late FuseIndex<T> _myIndex;
  InvertedIndexData? _invertedIndex;
  String? _lastQuery;
  Searcher? _lastSearcher;

  /// The Fuse.js version this port targets.
  static const String version = '7.5.0';

  /// Global mutable defaults (the Dart equivalent of JS `Fuse.config`).
  ///
  /// Values changed here become the defaults for every subsequently created
  /// [Fuse], and for [match], [createIndex] and [parseIndex]. Instances
  /// snapshot the config at construction, so later mutations don't affect
  /// existing ones — exactly like `{ ...Config, ...options }` in JS.
  static FuseConfig get config => globalFuseConfig;

  Searcher _getSearcher(String query) {
    if (_lastQuery == query) {
      return _lastSearcher!;
    }
    final searcher =
        createSearcher(query, options, invertedIndex: _invertedIndex);
    _lastQuery = query;
    _lastSearcher = searcher;
    return searcher;
  }

  /// Replaces the searched collection with [docs], rebuilding the index.
  ///
  /// Pass an existing [index] to reuse it instead of rebuilding.
  void setCollection(List<T> docs, [FuseIndex<T>? index]) {
    _docs = docs;

    _myIndex = index ??
        createFuseIndex<T>(
          options.keys,
          _docs,
          getFn: options.getFn,
          fieldNormWeight: options.fieldNormWeight,
        );

    if (options.useTokenSearch) {
      final analyzer = createAnalyzer(
        isCaseSensitive: options.isCaseSensitive,
        ignoreDiacritics: options.ignoreDiacritics,
        tokenize: options.tokenize,
      );
      _invertedIndex =
          buildInvertedIndex(_myIndex.records, _myIndex.keys.length, analyzer);
    } else {
      _invertedIndex = null;
    }

    _invalidateSearcherCache();
  }

  /// Appends [doc] to the collection and indexes it.
  void add(T doc) {
    if (!isDefined(doc)) {
      return;
    }

    _docs.add(doc);
    final record = _myIndex.add(doc, _docs.length - 1);

    // Skip inverted-index bookkeeping when no record was appended (blank
    // strings produce null). Reading `records.last` unconditionally would
    // re-ingest the previous doc on `add("")`.
    if (_invertedIndex != null && record != null) {
      final analyzer = createAnalyzer(
        isCaseSensitive: options.isCaseSensitive,
        ignoreDiacritics: options.ignoreDiacritics,
        tokenize: options.tokenize,
      );
      addToInvertedIndex(_invertedIndex!, record, _myIndex.keys.length, analyzer);
    }

    _invalidateSearcherCache();
  }

  /// Removes every document for which [predicate] returns `true`.
  ///
  /// Returns the removed documents in their original order.
  List<T> remove(bool Function(T doc, int idx) predicate) {
    final results = <T>[];
    final indicesToRemove = <int>[];

    for (var i = 0, len = _docs.length; i < len; i += 1) {
      if (predicate(_docs[i], i)) {
        results.add(_docs[i]);
        indicesToRemove.add(i);
      }
    }

    if (indicesToRemove.isNotEmpty) {
      if (_invertedIndex != null) {
        removeAndShiftInvertedIndex(_invertedIndex!, indicesToRemove);
      }

      // Filter docs in a single pass instead of reverse-splicing
      final toRemove = indicesToRemove.toSet();
      _docs = [
        for (var i = 0; i < _docs.length; i += 1)
          if (!toRemove.contains(i)) _docs[i],
      ];
      _myIndex.removeAll(indicesToRemove);

      _invalidateSearcherCache();
    }

    return results;
  }

  /// Removes the document at [idx] from the collection and the index.
  ///
  /// Returns the removed document. Validates before any mutation.
  T removeAt(int idx) {
    if (idx < 0 || idx >= _docs.length) {
      throw FuseException(invalidDocIndex);
    }

    if (_invertedIndex != null) {
      removeAndShiftInvertedIndex(_invertedIndex!, [idx]);
    }
    final doc = _docs.removeAt(idx);
    _myIndex.removeAt(idx);
    _invalidateSearcherCache();
    return doc;
  }

  void _invalidateSearcherCache() {
    _lastQuery = null;
    _lastSearcher = null;
  }

  /// Returns the token-search inverted index when `useTokenSearch` is set.
  InvertedIndexData? get invertedIndex => _invertedIndex;

  /// Returns the underlying search index.
  FuseIndex<T> getIndex() => _myIndex;

  /// The cached query, if a searcher is cached (mirrors `_lastQuery`).
  String? get lastQuery => _lastQuery;

  /// An opaque handle for the cached searcher, or `null`. Stable while the
  /// cache is untouched (used by the conformance bridge for identity
  /// assertions).
  Object? get lastSearcherId => _lastSearcher;

  /// FuseIndex.keys carries raw user weights; only KeyStore normalizes them
  /// to sum to 1. Scoring off the raw weights underflows for large values
  /// and diverges from the keyed logical path. Resolve each key to its
  /// normalized counterpart by id (kept aligned to item[keyIndex]), once per
  /// search.
  List<IndexedKey<T>> _normalizedKeys() {
    return [
      for (final key in _myIndex.keys) _keyStore.get(key.id) ?? key,
    ];
  }

  /// Searches the collection for [query] and returns ranked results.
  ///
  /// [query] is a `String` for plain/extended search, or a `Map` for a
  /// logical `$and`/`$or` query. Pass [limit] to cap the number of results
  /// (`-1` means no limit). Throws [FuseException] for an unsupported query.
  List<FuseResult<T>> search(Object query, {int limit = -1}) {
    final includeMatches = options.includeMatches;
    final includeScore = options.includeScore;
    final shouldSort = options.shouldSort;
    final sortFn = options.sortFn;
    final ignoreFieldNorm = options.ignoreFieldNorm;

    // Empty string query returns all docs (useful for search UIs)
    if (query is String && query.trim().isEmpty) {
      var docs = [
        for (var idx = 0; idx < _docs.length; idx += 1)
          FuseResult<T>(item: _docs[idx], refIndex: idx),
      ];
      if (limit > -1) {
        docs = docs.sublist(0, limit < docs.length ? limit : docs.length);
      }
      return docs;
    }

    // The heap selects a sorted top-N, so it only applies when sorting is on.
    // With `shouldSort: false` we must keep the collection-order-then-slice
    // path so `search(query, { limit })` still equals
    // `search(query).slice(0, limit)`.
    final useHeap = shouldSort && limit > 0 && query is String;

    // Canonical tie-break for string/object search: break comparator ties by
    // item index so heap selection and the full sort agree. Both then equal a
    // full sort under this idx tie-break, sliced to the limit. This only
    // bites when a custom sortFn returns 0 for distinct results (the default
    // sortFn and any total-order comparator decide every pair). Applying it
    // to the unlimited sort too keeps the contract even when an index's
    // records are not in idx order (e.g. via Fuse.parseIndex), where a raw
    // stable sort would instead preserve scan order. Logical search has no
    // heap path, so it keeps the raw comparator.
    int compare(InternalResult<T> a, InternalResult<T> b) =>
        sortFn(_toArg(a), _toArg(b));
    int stable(InternalResult<T> a, InternalResult<T> b) {
      final byComparator = compare(a, b);
      return byComparator != 0 ? byComparator : a.idx.compareTo(b.idx);
    }

    List<InternalResult<T>> results;

    if (useHeap) {
      final stringQuery = query;
      final heap = MaxHeap<T>(limit, stable);
      if (_docs.isNotEmpty && _docs[0] is String) {
        _searchStringList(
          stringQuery,
          _HeapSearchOptions<T>(
            heap: heap,
            ignoreFieldNorm: ignoreFieldNorm,
          ),
        );
      } else {
        _searchObjectList(
          stringQuery,
          _HeapSearchOptions<T>(
            heap: heap,
            ignoreFieldNorm: ignoreFieldNorm,
          ),
        );
      }
      results = heap.extractSorted();
    } else {
      results = query is String
          ? (_docs.isNotEmpty && _docs[0] is String
              ? _searchStringList(query)
              : _searchObjectList(query))
          : _searchLogical(query);

      computeScore<T>(results, ignoreFieldNorm: ignoreFieldNorm);

      if (shouldSort) {
        results.sort(query is String ? stable : compare);
      }

      if (limit > -1) {
        results = results.sublist(
            0, limit < results.length ? limit : results.length);
      }
    }

    return format<T>(
      results,
      _docs,
      includeMatches: includeMatches,
      includeScore: includeScore,
    );
  }

  FuseSortFunctionArg _toArg(InternalResult<T> r) => FuseSortFunctionArg(
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
      );

  List<InternalResult<T>> _searchStringList(
    String query, [
    _HeapSearchOptions<T>? heapOptions,
  ]) {
    final heap = heapOptions?.heap;
    final ignoreFieldNorm = heapOptions?.ignoreFieldNorm ?? false;
    final searcher = _getSearcher(query);
    final requireAllTokens =
        options.useTokenSearch && options.tokenMatch == 'all';
    final records = _myIndex.records;
    final results = <InternalResult<T>>[];

    // Iterate over every string in the index
    for (final record in records) {
      if (record is! StringRecord) {
        continue;
      }

      final text = record.v;
      final searchResult = searcher.searchIn(text);

      if (searchResult.isMatch) {
        final match = MatchData<T>(
          score: searchResult.score,
          value: text,
          norm: record.n,
          indices: searchResult.indices,
          matchedMask: searchResult.matchedMask,
          matchedTerms: searchResult.matchedTerms,
          termCount: searchResult.termCount,
        );
        final matches = [match];

        // Record-level AND gate (token search `tokenMatch: 'all'`), applied
        // before heap insertion so `limit` returns the same top-N as
        // unlimited.
        if (!requireAllTokens || _coversAllTokens(matches)) {
          final result = InternalResult<T>(
            idx: record.i,
            item: text,
            matches: matches,
          );

          if (heap != null) {
            result.score = computeScoreSingle<T>(
              result.matches,
              ignoreFieldNorm: ignoreFieldNorm,
            );
            heap.insert(result);
          } else {
            results.add(result);
          }
        }
      }
    }

    return results;
  }

  List<InternalResult<T>> _searchLogical(Object query) {
    final expression = parse<T>(query, options);

    // Keyless leaves fan out across all keys; normalized weights keep their
    // scores consistent with string and keyed queries.
    final keys = _normalizedKeys();

    List<InternalResult<T>> evaluate(
      LogicalNode node,
      Map<int, Object> item,
      int idx,
    ) {
      if (node is LogicalLeaf) {
        List<MatchData<T>> matches;

        if (node.keyId == null) {
          // Keyless entry: search across all keys
          matches = [];
          for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
            matches.addAll(
              _findMatches(
                key: keys[keyIndex],
                value: item[keyIndex],
                searcher: node.searcher!,
              ),
            );
          }
        } else {
          matches = _findMatches(
            key: _keyStore.get(node.keyId!),
            value: _myIndex.getValueForItemAtKeyId(item, node.keyId!),
            searcher: node.searcher!,
          );
        }

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

    final records = _myIndex.records;
    final resultMap = <int, InternalResult<T>>{};
    final results = <InternalResult<T>>[];

    for (final record in records) {
      if (record is! ObjectRecord) {
        continue;
      }

      final item = record.entries;
      final idx = record.i;

      final expResults = evaluate(expression, item, idx);

      if (expResults.isNotEmpty) {
        // Dedupe when adding
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

  // When a search involves inverse patterns (e.g. !Syrup), the aggregation
  // across keys switches from "ANY key matches" to "ALL keys must match."
  // This is signaled by hasInverse on the SearchResult from ExtendedSearch.
  //
  // For mixed patterns like "^hello !Syrup", a key failure is ambiguous —
  // it could be the positive or inverse term that failed. In that case we
  // conservatively exclude the item, which is strictly better than the old
  // behavior of including it. See: https://github.com/krisk/Fuse/issues/712
  List<InternalResult<T>> _searchObjectList(
    String query, [
    _HeapSearchOptions<T>? heapOptions,
  ]) {
    final heap = heapOptions?.heap;
    final ignoreFieldNorm = heapOptions?.ignoreFieldNorm ?? false;
    final searcher = _getSearcher(query);
    final requireAllTokens =
        options.useTokenSearch && options.tokenMatch == 'all';
    final records = _myIndex.records;
    final keys = _normalizedKeys();
    final results = <InternalResult<T>>[];

    // List is Array<Object>
    for (final record in records) {
      if (record is! ObjectRecord) {
        continue;
      }

      final item = record.entries;
      final idx = record.i;

      final matches = <MatchData<T>>[];
      var anyKeyFailed = false;
      var hasInverse = false;

      // Iterate over every key (i.e, path), and fetch the value at that key
      for (var keyIndex = 0; keyIndex < keys.length; keyIndex += 1) {
        final keyMatches = _findMatches(
          key: keys[keyIndex],
          value: item[keyIndex],
          searcher: searcher,
        );

        if (keyMatches.isNotEmpty) {
          matches.addAll(keyMatches);
          if (keyMatches[0].hasInverse == true) {
            hasInverse = true;
          }
        } else {
          anyKeyFailed = true;
        }
      }

      // If the search involves inverse patterns, ALL keys must match
      if (hasInverse && anyKeyFailed) {
        continue;
      }

      // Record-level AND gate (token search `tokenMatch: 'all'`): every
      // query term must be covered across the record's field/array-element
      // matches. Applied before heap insertion so `limit` returns the same
      // top-N.
      if (matches.isNotEmpty &&
          (!requireAllTokens || _coversAllTokens(matches))) {
        final result =
            InternalResult<T>(idx: idx, item: item, matches: matches);

        if (heap != null) {
          result.score = computeScoreSingle<T>(
            result.matches,
            ignoreFieldNorm: ignoreFieldNorm,
          );
          heap.insert(result);
        } else {
          results.add(result);
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
    if (!isDefined(value)) {
      return [];
    }

    final matches = <MatchData<T>>[];

    if (value is List) {
      for (final rv in value) {
        if (rv is! RecordValue) {
          continue;
        }
        final searchResult = searcher.searchIn(rv.v);

        if (searchResult.isMatch) {
          matches.add(
            MatchData<T>(
              score: searchResult.score,
              key: key,
              value: rv.v,
              idx: rv.i,
              norm: rv.n,
              indices: searchResult.indices,
              hasInverse: searchResult.hasInverse,
              matchedMask: searchResult.matchedMask,
              matchedTerms: searchResult.matchedTerms,
              termCount: searchResult.termCount,
            ),
          );
        }
      }
    } else if (value is RecordValue) {
      final searchResult = searcher.searchIn(value.v);

      if (searchResult.isMatch) {
        matches.add(
          MatchData<T>(
            score: searchResult.score,
            key: key,
            value: value.v,
            norm: value.n,
            indices: searchResult.indices,
            hasInverse: searchResult.hasInverse,
            matchedMask: searchResult.matchedMask,
            matchedTerms: searchResult.matchedTerms,
            termCount: searchResult.termCount,
          ),
        );
      }
    }

    return matches;
  }

  // Record-level AND gate for token search (`tokenMatch: 'all'`). Returns
  // true unless the matched terms across ALL of a record's
  // field/array-element matches fail to cover every query term. `termCount`
  // is only set by TokenSearch in 'all' mode, so non-token / 'any' searches
  // always pass.
  bool _coversAllTokens(List<MatchData<T>> matches) {
    final termCount = matches.isNotEmpty ? matches[0].termCount : null;
    if (termCount == null) {
      return true;
    }

    if (termCount <= maxMaskTerms) {
      var coverage = 0;
      for (final match in matches) {
        coverage |= match.matchedMask ?? 0;
      }
      return coverage == (1 << termCount) - 1;
    }

    final coverage = <int>{};
    for (final match in matches) {
      final terms = match.matchedTerms;
      if (terms != null) {
        coverage.addAll(terms);
      }
    }
    return coverage.length == termCount;
  }

  /// Registers additional searcher plugins (mirrors Fuse.js `Fuse.use`).
  static void use(List<SearcherPlugin> plugins) => registerSearchers(plugins);

  /// Builds a reusable [FuseIndex] for [docs] over [keys].
  ///
  /// Build once and pass to multiple [Fuse] instances to avoid re-indexing.
  static FuseIndex<U> createIndex<U>(
    List<Object> keys,
    List<U> docs, {
    GetFunction<U>? getFn,
    double? fieldNormWeight,
  }) =>
      createFuseIndex<U>(keys, docs,
          getFn: getFn, fieldNormWeight: fieldNormWeight);

  /// Rebuilds a [FuseIndex] from previously serialized [data].
  ///
  /// [data] is the JSON produced by [FuseIndex.toJson].
  static FuseIndex<U> parseIndex<U>(
    Map<String, dynamic> data, {
    GetFunction<U>? getFn,
    double? fieldNormWeight,
  }) =>
      parseFuseIndex<U>(data, getFn: getFn, fieldNormWeight: fieldNormWeight);

  /// Parses a logical [query] into a [LogicalNode] tree.
  ///
  /// When [auto] is `true`, a searcher is attached to each leaf.
  static LogicalNode parseQuery<U>(
    Object query,
    FuseOptions<U> options, {
    bool auto = true,
  }) =>
      parse<U>(query, options, auto: auto);

  /// Matches a single [pattern] against a single [text] without building a
  /// corpus or index. Rejects token search, which needs corpus statistics.
  static SearchResult match(
    String pattern,
    String text, [
    FuseOptions<dynamic>? options,
  ]) {
    // Mirror JS `createSearcher(pattern, { ...Config, ...options })` —
    // unset options resolve against the live Fuse.config.
    final merged = (options ?? FuseOptions<dynamic>()).snapshot();
    if (merged.useTokenSearch) {
      throw FuseException(fuseMatchTokenSearchUnsupported);
    }
    final searcher = createSearcher(pattern, merged);
    return searcher.searchIn(text);
  }
}
