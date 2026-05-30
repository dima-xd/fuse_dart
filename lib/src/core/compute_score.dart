import 'dart:math' as math;

import '../helpers/types.dart';
import 'results.dart';

void computeScore<T>(
  List<InternalResult<T>> results, {
  bool ignoreFieldNorm = false,
}) {
  for (final result in results) {
    var totalScore = 1.0;

    for (final match in result.matches) {
      final weight = match.key?.weight;

      final base = match.score == 0 && weight != null ? epsilon : match.score;
      final exponent = (weight ?? 1) * (ignoreFieldNorm ? 1 : match.norm);

      totalScore *= math.pow(base, exponent).toDouble();
    }

    result.score = totalScore;
  }
}
