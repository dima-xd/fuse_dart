import 'results.dart';
import 'fuse_result.dart';

List<FuseResultMatch> formatMatches<T>(InternalResult<T> result) {
  final matches = <FuseResultMatch>[];

  for (final match in result.matches) {
    final indices = match.indices;
    if (indices == null || indices.isEmpty) {
      continue;
    }

    // `key.id` is the canonical dotted-string identity (array paths joined
    // with '.'); `key.src` is the raw user input and can be a String[].
    final key = match.key?.id;

    matches.add(
      FuseResultMatch(
        indices: [
          for (final pair in indices) [pair[0], pair[1]]
        ],
        value: match.value,
        key: key,
        refIndex: match.idx != null && match.idx! > -1 ? match.idx : null,
      ),
    );
  }

  return matches;
}
