import 'dart:math' as math;

const int maxBits = 32;

double computeScore(
  String pattern, {
  int errors = 0,
  int currentLocation = 0,
  int expectedLocation = 0,
  int distance = 100,
  bool ignoreLocation = false,
}) {
  final accuracy = errors / pattern.length;

  if (ignoreLocation) {
    return accuracy;
  }

  final proximity = (expectedLocation - currentLocation).abs();

  if (distance == 0) {
    return proximity != 0 ? 1.0 : accuracy;
  }

  return accuracy + proximity / distance;
}

List<List<int>> convertMaskToIndices(
  List<int> matchmask,
  int minMatchCharLength,
) {
  final indices = <List<int>>[];
  var start = -1;
  var end = -1;
  var i = 0;

  for (final len = matchmask.length; i < len; i += 1) {
    final match = matchmask[i];
    if (match != 0 && start == -1) {
      start = i;
    } else if (match == 0 && start != -1) {
      end = i - 1;
      if (end - start + 1 >= minMatchCharLength) {
        indices.add([start, end]);
      }
      start = -1;
    }
  }

  if (matchmask.isNotEmpty &&
      matchmask[i - 1] != 0 &&
      i - start >= minMatchCharLength) {
    indices.add([start, i - 1]);
  }

  return indices;
}

Map<String, int> createPatternAlphabet(String pattern) {
  final mask = <String, int>{};
  final len = pattern.length;

  for (var i = 0; i < len; i += 1) {
    final char = pattern[i];
    mask[char] = (mask[char] ?? 0) | (1 << (len - i - 1));
  }

  return mask;
}

class BitapSearchOutput {
  BitapSearchOutput({required this.isMatch, required this.score, this.indices});

  bool isMatch;
  final double score;
  List<List<int>>? indices;
}

int _safeIndexOf(String text, String pattern, int start) {
  if (start > text.length) {
    return -1;
  }
  return text.indexOf(pattern, start);
}

int _at(List<int> arr, int index) {
  if (index < 0 || index >= arr.length) {
    return 0;
  }
  return arr[index];
}

BitapSearchOutput search(
  String text,
  String pattern,
  Map<String, int> patternAlphabet, {
  int location = 0,
  int distance = 100,
  double threshold = 0.6,
  bool findAllMatches = false,
  int minMatchCharLength = 1,
  bool includeMatches = false,
  bool ignoreLocation = false,
}) {
  final patternLen = pattern.length;
  final textLen = text.length;
  final expectedLocation = math.max(0, math.min(location, textLen));
  var currentThreshold = threshold;
  var bestLocation = expectedLocation;

  final computeMatches = minMatchCharLength > 1 || includeMatches;
  final matchMask = computeMatches ? List<int>.filled(textLen, 0) : <int>[];

  int index;

  while ((index = _safeIndexOf(text, pattern, bestLocation)) > -1) {
    final score = computeScore(
      pattern,
      currentLocation: index,
      expectedLocation: expectedLocation,
      distance: distance,
      ignoreLocation: ignoreLocation,
    );

    currentThreshold = math.min(score, currentThreshold);
    bestLocation = index + patternLen;

    if (computeMatches) {
      var i = 0;
      while (i < patternLen) {
        matchMask[index + i] = 1;
        i += 1;
      }
    }
  }

  bestLocation = -1;

  var lastBitArr = <int>[];
  var finalScore = 1.0;
  var binMax = patternLen + textLen;

  final mask = 1 << (patternLen - 1);

  for (var i = 0; i < patternLen; i += 1) {
    var binMin = 0;
    var binMid = binMax;

    while (binMin < binMid) {
      final score = computeScore(
        pattern,
        errors: i,
        currentLocation: expectedLocation + binMid,
        expectedLocation: expectedLocation,
        distance: distance,
        ignoreLocation: ignoreLocation,
      );

      if (score <= currentThreshold) {
        binMin = binMid;
      } else {
        binMax = binMid;
      }

      binMid = ((binMax - binMin) / 2).floor() + binMin;
    }

    binMax = binMid;

    var start = math.max(1, expectedLocation - binMid + 1);
    final finish = findAllMatches
        ? textLen
        : math.min(expectedLocation + binMid, textLen) + patternLen;

    final bitArr = List<int>.filled(finish + 2, 0);

    bitArr[finish + 1] = (1 << i) - 1;

    for (var j = finish; j >= start; j -= 1) {
      final currentLocation = j - 1;
      final char = currentLocation < textLen ? text[currentLocation] : '';
      final charMatch = patternAlphabet[char] ?? 0;

      if (computeMatches && currentLocation < textLen) {
        matchMask[currentLocation] = charMatch != 0 ? 1 : 0;
      }

      bitArr[j] = ((bitArr[j + 1] << 1) | 1) & charMatch;

      if (i != 0) {
        bitArr[j] |= ((_at(lastBitArr, j + 1) | _at(lastBitArr, j)) << 1) |
            1 |
            _at(lastBitArr, j + 1);
      }

      if ((bitArr[j] & mask) != 0) {
        finalScore = computeScore(
          pattern,
          errors: i,
          currentLocation: currentLocation,
          expectedLocation: expectedLocation,
          distance: distance,
          ignoreLocation: ignoreLocation,
        );

        if (finalScore <= currentThreshold) {
          currentThreshold = finalScore;
          bestLocation = currentLocation;

          if (bestLocation <= expectedLocation) {
            break;
          }

          start = math.max(1, 2 * expectedLocation - bestLocation);
        }
      }
    }

    final score = computeScore(
      pattern,
      errors: i + 1,
      currentLocation: expectedLocation,
      expectedLocation: expectedLocation,
      distance: distance,
      ignoreLocation: ignoreLocation,
    );

    if (score > currentThreshold) {
      break;
    }

    lastBitArr = bitArr;
  }

  final result = BitapSearchOutput(
    isMatch: bestLocation >= 0,
    score: math.max(0.001, finalScore),
  );

  if (computeMatches) {
    final indices = convertMaskToIndices(matchMask, minMatchCharLength);
    if (indices.isEmpty) {
      result.isMatch = false;
    } else if (includeMatches) {
      result.indices = indices;
    }
  }

  return result;
}
