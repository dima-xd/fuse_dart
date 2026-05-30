import '../tools/key_store.dart';

class MatchData<T> {
  MatchData({
    required this.score,
    required this.value,
    required this.norm,
    this.key,
    this.idx,
    this.indices,
  });

  final double score;
  final String value;
  final double norm;
  final IndexedKey<T>? key;
  final int? idx;
  final List<List<int>>? indices;
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
