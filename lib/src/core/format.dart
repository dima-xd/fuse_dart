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

    List<FuseResultMatch>? matches;
    if (includeMatches) {
      matches = [];
      for (final match in result.matches) {
        final indices = match.indices;
        if (indices == null || indices.isEmpty) {
          continue;
        }

        matches.add(
          FuseResultMatch(
            indices: [for (final pair in indices) (pair[0], pair[1])],
            value: match.value,
            key: match.key?.src,
            refIndex: (match.idx != null && match.idx! > -1) ? match.idx : null,
          ),
        );
      }
    }

    return FuseResult<T>(
      item: docs[idx],
      refIndex: idx,
      score: includeScore ? result.score : null,
      matches: matches,
    );
  }).toList();
}
