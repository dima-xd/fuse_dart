/// The outcome of matching a pattern against one piece of text.
class SearchResult {
  SearchResult({
    required this.isMatch,
    required this.score,
    this.indices,
    this.hasInverse,
    this.matchedMask,
    this.matchedTerms,
    this.termCount,
  });

  /// Whether the pattern matched.
  bool isMatch;

  /// The match score, where `0` is a perfect match.
  double score;

  /// Matched character ranges, when computed.
  List<List<int>>? indices;

  /// Aggregation flag for extended-search inverse terms.
  bool? hasInverse;

  /// Token-search `tokenMatch: 'all'` coverage for this text: bit `i` ⇒
  /// query term `i` matched here (≤31-term fast path).
  int? matchedMask;

  /// Equivalent coverage set for the ≥32-term fallback.
  Set<int>? matchedTerms;

  /// Query token count; descriptor for the record-level AND gate.
  int? termCount;
}

/// Something that can search for its pattern within a piece of [text].
abstract class Searcher {
  /// Matches this searcher's pattern against [text].
  SearchResult searchIn(String text);
}
