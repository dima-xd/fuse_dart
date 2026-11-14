import 'dart:math' as math;

import '../../core/config.dart';
import '../../helpers/merge_indices.dart';
import '../bitap/bitap_search.dart';
import '../searcher.dart';
import 'analyzer.dart';
import 'inverted_index.dart';

// `tokenMatch: 'all'` packs per-term coverage into a bitmask. JS bitwise ops
// are 32-bit *signed*, so bit 31 is the sign bit — only bits 0..30 are safe.
// Queries with more than this many terms fall back to a Set (no bit limit).
const int maxMaskTerms = 31;

class TokenSearch implements Searcher {
  /// `tokenMatch: 'all'` (AND) coverage. When true, searchIn reports which
  /// query terms matched each text so the core loop can require record-level
  /// coverage of every term. Bitmask is the ≤31-term fast path; Set is the
  /// ≥32-term fallback.
  TokenSearch(String pattern, FuseOptions<dynamic> options,
      InvertedIndexData? invertedIndex)
      : _options = options,
        _analyzer = createAnalyzer(
          isCaseSensitive: options.isCaseSensitive,
          ignoreDiacritics: options.ignoreDiacritics,
          tokenize: options.tokenize,
        ) {
    final queryTerms = _analyzer.tokenize(pattern);
    final df = invertedIndex?.df;
    final fieldCount = invertedIndex?.fieldCount;

    _termSearchers = [];
    _idfWeights = [];

    for (final term in queryTerms) {
      _termSearchers.add(
        BitapSearch(
          term,
          FuseOptions<dynamic>(
            location: options.location,
            threshold: options.threshold,
            distance: options.distance,
            includeMatches: options.includeMatches,
            findAllMatches: options.findAllMatches,
            minMatchCharLength: options.minMatchCharLength,
            isCaseSensitive: options.isCaseSensitive,
            ignoreDiacritics: options.ignoreDiacritics,
            ignoreLocation: true,
          ),
        ),
      );

      final docFreq = df?[term] ?? 0;
      final idf =
          math.log(1 + ((fieldCount ?? 0) - docFreq + 0.5) / (docFreq + 0.5));
      _idfWeights.add(idf);
    }

    _combineAll = options.tokenMatch == 'all';
    _numTerms = _termSearchers.length;
    _useMask = _numTerms <= maxMaskTerms;
  }

  final FuseOptions<dynamic> _options;
  final Analyzer _analyzer;
  late final List<BitapSearch> _termSearchers;
  late final List<double> _idfWeights;
  late final bool _combineAll;
  late final int _numTerms;
  late final bool _useMask;

  @override
  SearchResult searchIn(String text) {
    if (_termSearchers.isEmpty) {
      return SearchResult(isMatch: false, score: 1);
    }

    final allIndices = <List<int>>[];
    var weightedScore = 0.0;
    var maxPossibleScore = 0.0;
    var matchedCount = 0;

    // `tokenMatch: 'all'` coverage for this text (untouched in the default
    // 'any' path, so it allocates nothing there).
    var matchedMask = 0;
    final Set<int>? matchedTerms = _combineAll && !_useMask ? <int>{} : null;

    for (var i = 0; i < _termSearchers.length; i++) {
      final result = _termSearchers[i].searchIn(text);
      final idf = _idfWeights[i];

      maxPossibleScore += idf;

      if (result.isMatch) {
        matchedCount++;
        weightedScore += idf * (1 - result.score);

        final indices = result.indices;
        if (indices != null) {
          allIndices.addAll(indices);
        }

        if (_combineAll) {
          if (_useMask) {
            matchedMask |= 1 << i;
          } else {
            matchedTerms!.add(i);
          }
        }
      }
    }

    if (matchedCount == 0) {
      return SearchResult(isMatch: false, score: 1);
    }

    final normalized =
        maxPossibleScore > 0 ? 1 - weightedScore / maxPossibleScore : 0.0;

    final searchResult = SearchResult(
      isMatch: true,
      score: math.max(0.001, normalized),
    );

    if (_options.includeMatches && allIndices.isNotEmpty) {
      searchResult.indices = mergeIndices(allIndices);
    }

    // Report term coverage so the core loop can enforce record-level AND.
    if (_combineAll) {
      if (_useMask) {
        searchResult.matchedMask = matchedMask;
      } else {
        searchResult.matchedTerms = matchedTerms!;
      }
      searchResult.termCount = _numTerms;
    }

    return searchResult;
  }
}
