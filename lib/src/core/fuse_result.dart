/// An inclusive `(start, end)` range of matched character indices.
typedef RangeTuple = (int start, int end);

/// Details of where a query matched within one field.
///
/// Present only when `includeMatches` is enabled.
class FuseResultMatch {
  /// Creates a match descriptor.
  const FuseResultMatch({
    required this.indices,
    this.key,
    this.refIndex,
    this.value,
  });

  /// Matched character ranges within [value].
  final List<RangeTuple> indices;

  /// The source key path this match came from.
  final Object? key;

  /// Index within an array-valued field, or `null` for scalar fields.
  final int? refIndex;

  /// The matched field value.
  final String? value;
}

/// A single search result.
class FuseResult<T> {
  /// Creates a result for [item].
  const FuseResult({
    required this.item,
    required this.refIndex,
    this.score,
    this.matches,
  });

  /// The matched document.
  final T item;

  /// The index of [item] in the searched collection.
  final int refIndex;

  /// Relevance score (lower is better); `null` unless `includeScore` is set.
  final double? score;

  /// Per-field match details; `null` unless `includeMatches` is set.
  final List<FuseResultMatch>? matches;
}
