/// The outcome of matching a pattern against one piece of text.
class SearchResult {
  /// Creates a search result.
  SearchResult({required this.isMatch, required this.score, this.indices});

  /// Whether the pattern matched.
  final bool isMatch;

  /// The match score, where `0` is a perfect match.
  final double score;

  /// Matched character ranges, when computed.
  final List<List<int>>? indices;
}

/// Something that can search for its pattern within a piece of [text].
abstract class Searcher {
  /// Matches this searcher's pattern against [text].
  SearchResult searchIn(String text);
}
