import 'dart:math' as math;

typedef RangeTuple = List<int>;

/// Sorts [indices] by start (then end) and merges overlapping or adjacent
/// ranges in place, mirroring Fuse.js `mergeIndices`.
List<List<int>> mergeIndices(List<List<int>> indices) {
  if (indices.length <= 1) return indices;

  indices.sort((a, b) {
    final byStart = a[0].compareTo(b[0]);
    return byStart != 0 ? byStart : a[1].compareTo(b[1]);
  });

  final merged = <List<int>>[indices[0]];

  for (var i = 1; i < indices.length; i += 1) {
    final last = merged[merged.length - 1];
    final curr = indices[i];
    if (curr[0] <= last[1] + 1) {
      last[1] = math.max(last[1], curr[1]);
    } else {
      merged.add(curr);
    }
  }

  return merged;
}
