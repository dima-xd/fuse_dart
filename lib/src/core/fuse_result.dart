typedef RangeTuple = (int start, int end);

class FuseResultMatch {
  const FuseResultMatch({
    required this.indices,
    this.key,
    this.refIndex,
    this.value,
  });

  final List<RangeTuple> indices;
  final Object? key;
  final int? refIndex;
  final String? value;
}

class FuseResult<T> {
  const FuseResult({
    required this.item,
    required this.refIndex,
    this.score,
    this.matches,
  });

  final T item;
  final int refIndex;
  final double? score;
  final List<FuseResultMatch>? matches;
}
