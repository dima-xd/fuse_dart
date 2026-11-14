import 'dart:math' as math;

import '../helpers/types.dart';
import 'results.dart';

/// Scores one result by folding its per-key matches, mirroring Fuse.js
/// `computeScoreSingle`. `score == 0` with a key weight present becomes
/// [epsilon] so a perfect match never multiplies everything to zero.
double computeScoreSingle<T>(
  List<MatchData<T>> matches, {
  bool ignoreFieldNorm = false,
}) {
  var totalScore = 1.0;

  for (final match in matches) {
    final weight = match.key?.weight;

    final base = match.score == 0 && weight != null ? epsilon : match.score;
    final exponent = (weight ?? 1) * (ignoreFieldNorm ? 1 : match.norm);

    totalScore *= _pow(base, exponent).toDouble();
  }

  return totalScore;
}

void computeScore<T>(
  List<InternalResult<T>> results, {
  bool ignoreFieldNorm = false,
}) {
  for (final result in results) {
    result.score =
        computeScoreSingle<T>(result.matches, ignoreFieldNorm: ignoreFieldNorm);
  }
}

// dart:math's `pow` on an int base/int exponent would take an integer path;
// JS `Math.pow` is always double. Use double inputs explicitly.
double _pow(num base, num exponent) =>
    math.pow(base.toDouble(), exponent.toDouble()).toDouble();
