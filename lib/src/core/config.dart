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
  final String key;

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

/// Configuration for a [Fuse] instance.
///
/// All options have sensible defaults matching Fuse.js; override only what
/// you need. See <https://fusejs.io/api/options.html> for background.
class FuseOptions<T> {
  /// Creates a set of options. All parameters are optional.
  ///
  /// Pass [sortFn] to customize result ordering (defaults to [defaultSortFn]).
  /// Pass [pathGetFn] to override how values are read from documents.
  FuseOptions({
    this.isCaseSensitive = false,
    this.ignoreDiacritics = false,
    this.includeScore = false,
    this.shouldSort = true,
    FuseSortFunction? sortFn,
    this.keys = const [],
    this.includeMatches = false,
    this.findAllMatches = false,
    this.minMatchCharLength = 1,
    this.location = 0,
    this.threshold = 0.6,
    this.distance = 100,
    this.useExtendedSearch = false,
    KeyGetFunction<T>? getFn,
    GetFunction<T>? pathGetFn,
    this.ignoreLocation = false,
    this.ignoreFieldNorm = false,
    this.fieldNormWeight = 1,
  })  : sortFn = sortFn ?? defaultSortFn,
        getFn = pathGetFn ?? ((T obj, Object path) => get(obj, path));

  /// Whether comparisons are case-sensitive.
  final bool isCaseSensitive;

  /// Whether to strip diacritics (accents) before comparing.
  final bool ignoreDiacritics;

  /// Whether to include each result's score in the output.
  final bool includeScore;

  /// Whether to sort results by score.
  final bool shouldSort;

  /// Comparator used when [shouldSort] is `true`.
  final FuseSortFunction sortFn;

  /// Keys to search; each is a `String`/`List<String>` path or a [FuseKey].
  final List<Object> keys;

  /// Whether to include matched character ranges in the output.
  final bool includeMatches;

  /// Whether to keep matching to the end of the input after a perfect match.
  final bool findAllMatches;

  /// Minimum number of characters a match must span to count.
  final int minMatchCharLength;

  /// Approximate position in the text where a match is expected.
  final int location;

  /// Match cutoff in `0.0`–`1.0`; `0.0` requires a perfect match, `1.0`
  /// matches anything.
  final double threshold;

  /// How far a match may stray from [location] before scoring as a mismatch.
  final int distance;

  /// Whether to enable the extended (unix-like) search syntax.
  final bool useExtendedSearch;

  /// Function used to read a value from a document at a key path.
  final GetFunction<T> getFn;

  /// Whether to ignore [location]/[distance] so position does not matter.
  final bool ignoreLocation;

  /// Whether to ignore the field-length norm when scoring.
  final bool ignoreFieldNorm;

  /// How strongly the field-length norm affects scoring.
  final double fieldNormWeight;
}
