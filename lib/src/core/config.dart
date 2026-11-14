import '../helpers/get.dart';

/// Extracts the searchable value for a key directly from a document [obj].
///
/// Used as the per-key `getFn` to bypass path-based lookup.
typedef KeyGetFunction<T> = Object? Function(T obj);

/// A search key with an optional [weight] and custom value getter.
///
/// Use this object form when you need a non-default weight or a custom
/// [getFn]; otherwise a plain `String`/`List<String>` path works as a key.
class FuseKey<T> {
  /// Creates a key for [name] with the given [weight] (must be positive).
  ///
  /// [name] is a key path: a dotted `String` (e.g. `'author.name'`) or a
  /// `List<String>` of path segments. [getFn] overrides path-based lookup.
  FuseKey({required this.name, this.weight = 1, this.getFn});

  /// The key path, as a dotted `String` or a `List<String>` of segments.
  final Object name;

  /// Relative importance of this key; weights are normalized across all keys.
  final double weight;

  /// Optional custom getter that returns the value to index for this key.
  final KeyGetFunction<T>? getFn;
}

/// A single field match passed to a [FuseSortFunction].
class FuseSortFunctionMatch {
  /// Creates a match descriptor for sorting.
  const FuseSortFunctionMatch({
    required this.score,
    required this.key,
    required this.value,
    this.idx,
    this.indices,
  });

  /// The match score, where `0` is a perfect match.
  final double score;

  /// The id of the key this match came from.
  final Object? key;

  /// The matched field value.
  final String value;

  /// The index within an array-valued field, or `null` for scalar fields.
  final int? idx;

  /// The matched character ranges, when match indices were computed.
  final List<List<int>>? indices;
}

/// A candidate result passed to a [FuseSortFunction].
class FuseSortFunctionArg {
  /// Creates a sort argument for one result.
  const FuseSortFunctionArg({
    required this.idx,
    required this.score,
    this.item,
    this.matches,
  });

  /// The index of the item in the original collection.
  final int idx;

  /// The combined relevance score, where lower is better.
  final double score;

  /// The matched item.
  final Object? item;

  /// The per-key matches that produced this result.
  final List<FuseSortFunctionMatch>? matches;
}

/// Comparator used to order search results; mirrors `List.sort`'s contract.
typedef FuseSortFunction = int Function(
  FuseSortFunctionArg a,
  FuseSortFunctionArg b,
);

/// Default result ordering: ascending [FuseSortFunctionArg.score], then
/// ascending [FuseSortFunctionArg.idx] to break ties stably.
int defaultSortFn(FuseSortFunctionArg a, FuseSortFunctionArg b) {
  if (a.score == b.score) {
    return a.idx < b.idx ? -1 : 1;
  }
  return a.score < b.score ? -1 : 1;
}

/// How the words of a multi-word query combine when token search is enabled:
/// `'any'` (OR, the default) or `'all'` (AND, record must cover every term).
typedef TokenMatch = String; // 'any' | 'all'

/// Tokenizer accepted by token search: a [RegExp], or a function returning
/// the term list for a text.
typedef TokenizeFunction = List<String> Function(String text);

/// The global mutable defaults, exposed as `Fuse.config`.
///
/// This is the Dart equivalent of Fuse.js's `Fuse.config` object: mutate a
/// field here and every subsequently created [Fuse] (and `Fuse.match`,
/// `Fuse.createIndex`, `Fuse.parseIndex`) picks it up as the default for
/// any option you don't pass explicitly. Instances snapshot the config at
/// construction, exactly like Fuse.js's `{ ...Config, ...options }`.
class FuseConfig {
  FuseConfig()
      : isCaseSensitive = false,
        ignoreDiacritics = false,
        includeScore = false,
        shouldSort = true,
        sortFn = defaultSortFn,
        keys = const [],
        includeMatches = false,
        findAllMatches = false,
        minMatchCharLength = 1,
        location = 0,
        threshold = 0.6,
        distance = 100,
        useExtendedSearch = false,
        useTokenSearch = false,
        tokenize = null,
        tokenMatch = 'any',
        ignoreLocation = false,
        ignoreFieldNorm = false,
        fieldNormWeight = 1;

  /// Whether comparisons are case-sensitive.
  bool isCaseSensitive;

  /// Whether to strip diacritics (accents) before comparing.
  bool ignoreDiacritics;

  /// Whether to include each result's score in the output.
  bool includeScore;

  /// Whether to sort results by score.
  bool shouldSort;

  /// Comparator used when [shouldSort] is `true`.
  FuseSortFunction sortFn;

  /// Keys to search; each is a `String`/`List<String>` path or a [FuseKey].
  List<Object> keys;

  /// Whether to include matched character ranges in the output.
  bool includeMatches;

  /// Whether to keep matching to the end of the input after a perfect match.
  bool findAllMatches;

  /// Minimum number of characters a match must span to count.
  int minMatchCharLength;

  /// Approximate position in the text where a match is expected.
  int location;

  /// Match cutoff in `0.0`–`1.0`; `0.0` requires a perfect match, `1.0`
  /// matches anything.
  double threshold;

  /// How far a match may stray from [location] before scoring as a mismatch.
  int distance;

  /// Whether to enable the extended (unix-like) search syntax.
  bool useExtendedSearch;

  /// Whether to enable token search with TF-IDF scoring.
  bool useTokenSearch;

  /// Tokenizer for token search: a [RegExp] or a [TokenizeFunction].
  /// Defaults to the unicode-aware `/[\p{L}\p{M}\p{N}_]+/gu`.
  Object? tokenize;

  /// How multi-word token-search queries combine: `'any'` (OR) or `'all'`.
  TokenMatch tokenMatch;

  /// Function used to read a value from a document at a key path.
  Object? Function(Object? obj, Object path) getFn =
      (Object? obj, Object path) => get(obj, path);

  /// Whether to ignore [location]/[distance] so position does not matter.
  bool ignoreLocation;

  /// Whether to ignore the field-length norm when scoring.
  bool ignoreFieldNorm;

  /// How strongly the field-length norm affects scoring.
  double fieldNormWeight;
}

final FuseConfig _globalConfig = FuseConfig();

/// The process-wide mutable defaults, exposed to callers as `Fuse.config`.
FuseConfig get globalFuseConfig => _globalConfig;

/// Configuration for a [Fuse] instance.
///
/// Every option corresponds to a Fuse.js option; options you leave unset
/// resolve against `Fuse.config` when the [Fuse] is constructed.
/// See <https://fusejs.io/api/options.html> for background.
class FuseOptions<T> {
  /// Creates a set of options. All parameters are optional; anything left
  /// unset falls back to `Fuse.config` at construction time.
  FuseOptions({
    bool? isCaseSensitive,
    bool? ignoreDiacritics,
    bool? includeScore,
    bool? shouldSort,
    FuseSortFunction? sortFn,
    List<Object>? keys,
    bool? includeMatches,
    bool? findAllMatches,
    int? minMatchCharLength,
    int? location,
    double? threshold,
    int? distance,
    bool? useExtendedSearch,
    bool? useTokenSearch,
    Object? tokenize,
    TokenMatch? tokenMatch,
    GetFunction<T>? getFn,
    bool? ignoreLocation,
    bool? ignoreFieldNorm,
    double? fieldNormWeight,
  })  : _isCaseSensitive = isCaseSensitive,
        _ignoreDiacritics = ignoreDiacritics,
        _includeScore = includeScore,
        _shouldSort = shouldSort,
        _sortFn = sortFn,
        _keys = keys,
        _includeMatches = includeMatches,
        _findAllMatches = findAllMatches,
        _minMatchCharLength = minMatchCharLength,
        _location = location,
        _threshold = threshold,
        _distance = distance,
        _useExtendedSearch = useExtendedSearch,
        _useTokenSearch = useTokenSearch,
        _tokenize = tokenize,
        _tokenMatch = tokenMatch,
        _getFn = getFn,
        _ignoreLocation = ignoreLocation,
        _ignoreFieldNorm = ignoreFieldNorm,
        _fieldNormWeight = fieldNormWeight;

  bool? _isCaseSensitive;
  bool? _ignoreDiacritics;
  bool? _includeScore;
  bool? _shouldSort;
  FuseSortFunction? _sortFn;
  List<Object>? _keys;
  bool? _includeMatches;
  bool? _findAllMatches;
  int? _minMatchCharLength;
  int? _location;
  double? _threshold;
  int? _distance;
  bool? _useExtendedSearch;
  bool? _useTokenSearch;
  Object? _tokenize;
  TokenMatch? _tokenMatch;
  GetFunction<T>? _getFn;
  bool? _ignoreLocation;
  bool? _ignoreFieldNorm;
  double? _fieldNormWeight;

  /// Whether comparisons are case-sensitive.
  bool get isCaseSensitive => _isCaseSensitive ?? _globalConfig.isCaseSensitive;
  set isCaseSensitive(bool value) => _isCaseSensitive = value;

  /// Whether to strip diacritics (accents) before comparing.
  bool get ignoreDiacritics =>
      _ignoreDiacritics ?? _globalConfig.ignoreDiacritics;
  set ignoreDiacritics(bool value) => _ignoreDiacritics = value;

  /// Whether to include each result's score in the output.
  bool get includeScore => _includeScore ?? _globalConfig.includeScore;
  set includeScore(bool value) => _includeScore = value;

  /// Whether to sort results by score.
  bool get shouldSort => _shouldSort ?? _globalConfig.shouldSort;
  set shouldSort(bool value) => _shouldSort = value;

  /// Comparator used when [shouldSort] is `true`.
  FuseSortFunction get sortFn => _sortFn ?? _globalConfig.sortFn;
  set sortFn(FuseSortFunction value) => _sortFn = value;

  /// Keys to search; each is a `String`/`List<String>` path or a [FuseKey].
  List<Object> get keys => _keys ?? _globalConfig.keys;
  set keys(List<Object> value) => _keys = value;

  /// Whether to include matched character ranges in the output.
  bool get includeMatches => _includeMatches ?? _globalConfig.includeMatches;
  set includeMatches(bool value) => _includeMatches = value;

  /// Whether to keep matching to the end of the input after a perfect match.
  bool get findAllMatches => _findAllMatches ?? _globalConfig.findAllMatches;
  set findAllMatches(bool value) => _findAllMatches = value;

  /// Minimum number of characters a match must span to count.
  int get minMatchCharLength =>
      _minMatchCharLength ?? _globalConfig.minMatchCharLength;
  set minMatchCharLength(int value) => _minMatchCharLength = value;

  /// Approximate position in the text where a match is expected.
  int get location => _location ?? _globalConfig.location;
  set location(int value) => _location = value;

  /// Match cutoff in `0.0`–`1.0`; `0.0` requires a perfect match, `1.0`
  /// matches anything.
  double get threshold => _threshold ?? _globalConfig.threshold;
  set threshold(double value) => _threshold = value;

  /// How far a match may stray from [location] before scoring as a mismatch.
  int get distance => _distance ?? _globalConfig.distance;
  set distance(int value) => _distance = value;

  /// Whether to enable the extended (unix-like) search syntax.
  bool get useExtendedSearch =>
      _useExtendedSearch ?? _globalConfig.useExtendedSearch;
  set useExtendedSearch(bool value) => _useExtendedSearch = value;

  /// Whether to enable token search with TF-IDF scoring.
  bool get useTokenSearch => _useTokenSearch ?? _globalConfig.useTokenSearch;
  set useTokenSearch(bool value) => _useTokenSearch = value;

  /// Tokenizer for token search: a [RegExp] or a [TokenizeFunction].
  /// Defaults to the unicode-aware `/[\p{L}\p{M}\p{N}_]+/gu`.
  Object? get tokenize => _tokenize ?? _globalConfig.tokenize;
  set tokenize(Object? value) => _tokenize = value;

  /// How multi-word token-search queries combine: `'any'` (OR) or `'all'`.
  TokenMatch get tokenMatch => _tokenMatch ?? _globalConfig.tokenMatch;
  set tokenMatch(TokenMatch value) => _tokenMatch = value;

  /// Function used to read a value from a document at a key path.
  ///
  /// The fallback cast is safe for any T: the global field's declared type
  /// is `Object? Function(Object?, Object)`, a subtype of `GetFunction<T>`
  /// for every T (T is always assignable to `Object?`).
  GetFunction<T> get getFn => _getFn ?? (_globalConfig.getFn as GetFunction<T>);
  set getFn(GetFunction<T> value) => _getFn = value;

  /// Whether to ignore [location]/[distance] so position does not matter.
  bool get ignoreLocation => _ignoreLocation ?? _globalConfig.ignoreLocation;
  set ignoreLocation(bool value) => _ignoreLocation = value;

  /// Whether to ignore the field-length norm when scoring.
  bool get ignoreFieldNorm => _ignoreFieldNorm ?? _globalConfig.ignoreFieldNorm;
  set ignoreFieldNorm(bool value) => _ignoreFieldNorm = value;

  /// How strongly the field-length norm affects scoring.
  double get fieldNormWeight =>
      _fieldNormWeight ?? _globalConfig.fieldNormWeight;
  set fieldNormWeight(double value) => _fieldNormWeight = value;

  /// Materializes every option so later `Fuse.config` mutations don't leak
  /// into this instance (mirrors `{ ...Config, ...options }` in JS).
  FuseOptions<T> snapshot() {
    final resolved = FuseOptions<T>();
    resolved._isCaseSensitive = isCaseSensitive;
    resolved._ignoreDiacritics = ignoreDiacritics;
    resolved._includeScore = includeScore;
    resolved._shouldSort = shouldSort;
    resolved._sortFn = sortFn;
    resolved._keys = keys;
    resolved._includeMatches = includeMatches;
    resolved._findAllMatches = findAllMatches;
    resolved._minMatchCharLength = minMatchCharLength;
    resolved._location = location;
    resolved._threshold = threshold;
    resolved._distance = distance;
    resolved._useExtendedSearch = useExtendedSearch;
    resolved._useTokenSearch = useTokenSearch;
    resolved._tokenize = tokenize;
    resolved._tokenMatch = tokenMatch;
    resolved._getFn = getFn;
    resolved._ignoreLocation = ignoreLocation;
    resolved._ignoreFieldNorm = ignoreFieldNorm;
    resolved._fieldNormWeight = fieldNormWeight;
    return resolved;
  }
}
