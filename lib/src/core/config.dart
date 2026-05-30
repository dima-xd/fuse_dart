import '../helpers/get.dart';

typedef KeyGetFunction<T> = Object? Function(T obj);

class FuseKey<T> {
  FuseKey({required this.name, this.weight = 1, this.getFn});

  final Object name;
  final double weight;
  final KeyGetFunction<T>? getFn;
}

class FuseSortFunctionMatch {
  const FuseSortFunctionMatch({
    required this.score,
    required this.key,
    required this.value,
    this.idx,
    this.indices,
  });

  final double score;
  final String key;
  final String value;
  final int? idx;
  final List<List<int>>? indices;
}

class FuseSortFunctionArg {
  const FuseSortFunctionArg({
    required this.idx,
    required this.score,
    this.item,
    this.matches,
  });

  final int idx;
  final double score;
  final Object? item;
  final List<FuseSortFunctionMatch>? matches;
}

typedef FuseSortFunction = int Function(
  FuseSortFunctionArg a,
  FuseSortFunctionArg b,
);

int defaultSortFn(FuseSortFunctionArg a, FuseSortFunctionArg b) {
  if (a.score == b.score) {
    return a.idx < b.idx ? -1 : 1;
  }
  return a.score < b.score ? -1 : 1;
}

class FuseOptions<T> {
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

  final bool isCaseSensitive;
  final bool ignoreDiacritics;
  final bool includeScore;
  final bool shouldSort;
  final FuseSortFunction sortFn;
  final List<Object> keys;
  final bool includeMatches;
  final bool findAllMatches;
  final int minMatchCharLength;
  final int location;
  final double threshold;
  final int distance;
  final bool useExtendedSearch;
  final GetFunction<T> getFn;
  final bool ignoreLocation;
  final bool ignoreFieldNorm;
  final double fieldNormWeight;
}
