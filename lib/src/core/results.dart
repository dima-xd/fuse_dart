import '../tools/key_store.dart';

/// Internal per-field match data.
class MatchData<T> {
  MatchData({
    required this.score,
    required this.value,
    required this.norm,
    this.key,
    this.idx,
    this.indices,
    this.hasInverse,
    this.matchedMask,
    this.matchedTerms,
    this.termCount,
  });

  final double score;

  /// The key this match came from, carrying its (normalized) weight.
  final IndexedKey<T>? key;

  final String value;
  final double norm;
  final int? idx;
  final List<List<int>>? indices;

  /// Set by extended search when an inverse pattern matched; drives the
  /// switch from "ANY key matches" to "ALL keys must match" aggregation.
  final bool? hasInverse;

  /// Token-search `tokenMatch: 'all'` coverage: bit `i` ⇒ query term `i`
  /// matched here (≤31-term fast path).
  final int? matchedMask;

  /// Equivalent coverage set for the ≥32-term fallback.
  final Set<int>? matchedTerms;

  /// Query token count; descriptor for the record-level AND gate.
  final int? termCount;
}

class InternalResult<T> {
  InternalResult({
    required this.idx,
    required this.item,
    required this.matches,
    this.score = 0,
  });

  final int idx;
  final Object? item;
  final List<MatchData<T>> matches;
  double score;
}
