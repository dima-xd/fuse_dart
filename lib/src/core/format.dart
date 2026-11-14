import 'format_matches.dart';
import 'fuse_result.dart';
import 'results.dart';

List<FuseResult<T>> format<T>(
  List<InternalResult<T>> results,
  List<T> docs, {
  bool includeMatches = false,
  bool includeScore = false,
}) {
  return results.map((result) {
    final idx = result.idx;

    final data = FuseResult<T>(
      item: docs[idx],
      refIndex: idx,
    );

    if (includeMatches) data.matches = formatMatches(result);
    if (includeScore) data.score = result.score;

    return data;
  }).toList();
}
