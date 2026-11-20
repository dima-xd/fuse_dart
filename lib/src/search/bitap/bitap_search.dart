import 'dart:typed_data';

import '../../core/config.dart';
import '../../helpers/diacritics.dart';
import '../../helpers/merge_indices.dart';
import '../searcher.dart';
import 'search.dart';

class _Chunk {
  _Chunk(this.pattern, this.alphabet, this.startIndex);

  final String pattern;
  final Uint32List alphabet;
  final int startIndex;
}

class BitapSearch implements Searcher {
  BitapSearch(String pattern, FuseOptions<dynamic> options)
      : location = options.location,
        threshold = options.threshold,
        distance = options.distance,
        includeMatches = options.includeMatches,
        findAllMatches = options.findAllMatches,
        minMatchCharLength = options.minMatchCharLength,
        isCaseSensitive = options.isCaseSensitive,
        ignoreDiacritics = options.ignoreDiacritics,
        ignoreLocation = options.ignoreLocation {
    var normalized = isCaseSensitive ? pattern : pattern.toLowerCase();
    normalized = ignoreDiacritics ? stripDiacritics(normalized) : normalized;
    this.pattern = normalized;

    _chunks = [];

    if (this.pattern.isEmpty) {
      return;
    }

    void addChunk(String chunkPattern, int startIndex) {
      _chunks.add(
        _Chunk(chunkPattern, createPatternAlphabet(chunkPattern), startIndex),
      );
    }

    final len = this.pattern.length;

    if (len > maxBits) {
      var i = 0;
      final remainder = len % maxBits;
      final end = len - remainder;

      while (i < end) {
        addChunk(this.pattern.substring(i, i + maxBits), i);
        i += maxBits;
      }

      if (remainder != 0) {
        final startIndex = len - maxBits;
        addChunk(this.pattern.substring(startIndex), startIndex);
      }
    } else {
      addChunk(this.pattern, 0);
    }
  }

  final int location;
  final double threshold;
  final int distance;
  final bool includeMatches;
  final bool findAllMatches;
  final int minMatchCharLength;
  final bool isCaseSensitive;
  final bool ignoreDiacritics;
  final bool ignoreLocation;

  late final String pattern;
  late final List<_Chunk> _chunks;

  @override
  SearchResult searchIn(String text) {
    var normalized = isCaseSensitive ? text : text.toLowerCase();
    normalized = ignoreDiacritics ? stripDiacritics(normalized) : normalized;

    // Exact match
    if (pattern == normalized) {
      // The whole string is the match, so enforce minMatchCharLength here
      // too, mirroring convertMaskToIndices on the fuzzy path.
      if (normalized.length < minMatchCharLength) {
        return SearchResult(isMatch: false, score: 1);
      }

      final result = SearchResult(isMatch: true, score: 0);

      if (includeMatches) {
        result.indices = [
          [0, normalized.length - 1]
        ];
      }

      return result;
    }

    // Otherwise, use Bitap algorithm
    final allIndices = <List<int>>[];
    var totalScore = 0.0;
    var hasMatches = false;

    for (final chunk in _chunks) {
      final result = search(
        normalized,
        chunk.pattern,
        chunk.alphabet,
        location: location + chunk.startIndex,
        distance: distance,
        threshold: threshold,
        findAllMatches: findAllMatches,
        minMatchCharLength: minMatchCharLength,
        includeMatches: includeMatches,
        ignoreLocation: ignoreLocation,
      );

      if (result.isMatch) {
        hasMatches = true;
      }

      totalScore += result.score;

      if (result.isMatch && result.indices != null) {
        allIndices.addAll(result.indices!);
      }
    }

    final result = SearchResult(
      isMatch: hasMatches,
      score: hasMatches ? totalScore / _chunks.length : 1,
    );

    if (hasMatches && includeMatches) {
      result.indices = mergeIndices(allIndices);
    }

    return result;
  }
}
