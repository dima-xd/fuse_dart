import 'dart:typed_data';

import '../../helpers/diacritics.dart';
import '../searcher.dart';
import 'search.dart';

class _Chunk {
  _Chunk(this.pattern, this.alphabet, this.startIndex);
  final String pattern;
  final Uint32List alphabet;
  final int startIndex;
}

class BitapSearch implements Searcher {
  BitapSearch(
    String pattern, {
    this.location = 0,
    this.threshold = 0.6,
    this.distance = 100,
    this.includeMatches = false,
    this.findAllMatches = false,
    this.minMatchCharLength = 1,
    this.isCaseSensitive = false,
    this.ignoreDiacritics = false,
    this.ignoreLocation = false,
  }) {
    var normalized = isCaseSensitive ? pattern : pattern.toLowerCase();
    normalized = ignoreDiacritics ? stripDiacritics(normalized) : normalized;
    this.pattern = normalized;

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
  final List<_Chunk> _chunks = [];

  @override
  SearchResult searchIn(String text) {
    var normalized = isCaseSensitive ? text : text.toLowerCase();
    normalized = ignoreDiacritics ? stripDiacritics(normalized) : normalized;

    if (pattern == normalized) {
      return SearchResult(
        isMatch: true,
        score: 0,
        indices: includeMatches
            ? [
                [0, normalized.length - 1]
              ]
            : null,
      );
    }

    var allIndices = <List<int>>[];
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
        allIndices = [...allIndices, ...result.indices!];
      }
    }

    return SearchResult(
      isMatch: hasMatches,
      score: hasMatches ? totalScore / _chunks.length : 1,
      indices: hasMatches && includeMatches ? allIndices : null,
    );
  }
}
