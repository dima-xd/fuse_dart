class SearchResult {
  SearchResult({required this.isMatch, required this.score, this.indices});

  final bool isMatch;
  final double score;
  final List<List<int>>? indices;
}

abstract class Searcher {
  SearchResult searchIn(String text);
}
