import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/error_messages.dart';
import '../../helpers/types.dart';

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
    // Dodge divide by zero error.
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

  // (i-1 - start) + 1 => i - start
  if (i > 0 && matchmask[i - 1] != 0 && i - start >= minMatchCharLength) {
    indices.add([start, i - 1]);
  }

  return indices;
}

/// Builds the bit mask of the pattern characters, indexed by UTF-16 code unit.
///
/// A flat lookup table is used instead of a `Map<String, int>`: the Bitap
/// inner loop reads one entry per text character, and hashing a freshly
/// allocated one-character string on every step is the dominant cost there.
Uint32List createPatternAlphabet(String pattern) {
  final mask = Uint32List(65536);
  final len = pattern.length;

  for (var i = 0; i < len; i += 1) {
    final char = pattern.codeUnitAt(i);
    mask[char] |= 1 << (len - i - 1);
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

BitapSearchOutput search(
  String text,
  String pattern,
  Uint32List patternAlphabet, {
  int location = 0,
  int distance = 100,
  double threshold = 0.6,
  bool findAllMatches = false,
  int minMatchCharLength = 1,
  bool includeMatches = false,
  bool ignoreLocation = false,
}) {
  if (pattern.length > maxBits) {
    throw FuseException(patternLengthTooLarge(maxBits));
  }

  final patternLen = pattern.length;
  // Set starting location at beginning text and initialize the alphabet.
  final textLen = text.length;
  // Handle the case when location > text.length
  final expectedLocation = math.max(0, math.min(location, textLen));
  // Highest score beyond which we give up.
  var currentThreshold = threshold;
  // Is there a nearby exact match? (speedup)
  var bestLocation = expectedLocation;

  double calcScore(int errors, int currentLocation) {
    final accuracy = errors / patternLen;
    if (ignoreLocation) return accuracy;
    final proximity = (expectedLocation - currentLocation).abs();
    if (distance == 0) return proximity != 0 ? 1.0 : accuracy;
    return accuracy + proximity / distance;
  }

  // Performance: only compute matches when the minMatchCharLength > 1
  // OR if `includeMatches` is true.
  final computeMatches = minMatchCharLength > 1 || includeMatches;
  // A mask of the matches, used for building the indices
  final matchMask = computeMatches ? Uint8List(textLen) : null;

  int index;

  // Get all exact matches, here for speed up
  while ((index = _safeIndexOf(text, pattern, bestLocation)) > -1) {
    final score = calcScore(0, index);

    currentThreshold = math.min(score, currentThreshold);
    bestLocation = index + patternLen;

    if (computeMatches) {
      var i = 0;
      while (i < patternLen) {
        matchMask![index + i] = 1;
        i += 1;
      }
    }
  }

  // Reset the best location
  bestLocation = -1;

  var lastBitArr = Uint32List(0);
  var finalScore = 1.0;
  var bestErrors = 0;
  var binMax = patternLen + textLen;

  final mask = 1 << (patternLen - 1);

  for (var i = 0; i < patternLen; i += 1) {
    // Scan for the best match; each iteration allows for one more error.
    // Run a binary search to determine how far from the match location we can
    // stray at this error level.
    var binMin = 0;
    var binMid = binMax;

    while (binMin < binMid) {
      final score = calcScore(i, expectedLocation + binMid);

      if (score <= currentThreshold) {
        binMin = binMid;
      } else {
        binMax = binMid;
      }

      binMid = binMin + ((binMax - binMin) >> 1);
    }

    // Use the result from this iteration as the maximum for the next.
    binMax = binMid;

    var start = math.max(1, expectedLocation - binMid + 1);
    final finish = findAllMatches
        ? textLen
        : math.min(expectedLocation + binMid, textLen) + patternLen;

    // Initialize the bit array
    final bitArr = Uint32List(finish + 2);

    bitArr[finish + 1] = (1 << i) - 1;

    for (var j = finish; j >= start; j -= 1) {
      final currentLocation = j - 1;
      final charMatch = currentLocation < textLen
          ? patternAlphabet[text.codeUnitAt(currentLocation)]
          : 0;

      // First pass: exact match
      var value = ((bitArr[j + 1] << 1) | 1) & charMatch;

      // Subsequent passes: fuzzy match
      if (i != 0) {
        // The previous row's window is never shorter than this one, so both
        // reads are in bounds.
        final lastNext = lastBitArr[j + 1];
        value |= ((lastNext | lastBitArr[j]) << 1) | 1 | lastNext;
      }

      bitArr[j] = value;

      if ((value & mask) != 0) {
        finalScore = calcScore(i, currentLocation);

        // This match will almost certainly be better than any existing match.
        // But check anyway.
        if (finalScore <= currentThreshold) {
          // Indeed it is
          currentThreshold = finalScore;
          bestLocation = currentLocation;
          bestErrors = i;

          // Already passed `loc`, downhill from here on in.
          if (bestLocation <= expectedLocation) {
            break;
          }

          // When passing `bestLocation`, don't exceed our current distance
          // from `expectedLocation`.
          start = math.max(1, 2 * expectedLocation - bestLocation);
        }
      }
    }

    // No hope for a (better) match at greater error levels.
    final score = calcScore(i + 1, expectedLocation);

    if (score > currentThreshold) {
      break;
    }

    lastBitArr = bitArr;
  }

  // Fill matchMask across the matched window only. Bitap anchors a match at
  // bestLocation (the start), spanning patternLen characters plus up to
  // bestErrors extra characters when errors are text-side insertions. Marking
  // alphabet positions in that window keeps the highlight indices honest
  // about what actually matched, instead of every pattern-alphabet character
  // the scan happened to visit.
  if (computeMatches && bestLocation >= 0) {
    final matchEnd =
        math.min(textLen - 1, bestLocation + patternLen - 1 + bestErrors);
    for (var k = bestLocation; k <= matchEnd; k += 1) {
      if (patternAlphabet[text.codeUnitAt(k)] != 0) {
        matchMask![k] = 1;
      }
    }
  }

  final result = BitapSearchOutput(
    isMatch: bestLocation >= 0,
    // Count exact matches (those with a score of 0) to be "almost" exact
    score: math.max(0.001, finalScore),
  );

  if (computeMatches) {
    final indices = convertMaskToIndices(matchMask!, minMatchCharLength);
    if (indices.isEmpty) {
      result.isMatch = false;
    } else if (includeMatches) {
      result.indices = indices;
    }
  }

  return result;
}
