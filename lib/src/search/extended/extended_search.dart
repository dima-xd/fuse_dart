import '../../helpers/diacritics.dart';
import '../searcher.dart';
import 'matchers.dart';

final RegExp _spaceRe = RegExp(r' +(?=(?:[^"]*"[^"]*")*[^"]*$)');
const String _orToken = '|';

List<List<BaseMatch>> parseQuery(String pattern, ExtendedMatchOptions options) {
  return pattern.split(_orToken).map((item) {
    final query = item
        .trim()
        .split(_spaceRe)
        .where((s) => s.isNotEmpty && s.trim().isNotEmpty)
        .toList();

    final results = <BaseMatch>[];

    for (final queryItem in query) {
      var found = false;

      for (final searcher in searchers) {
        final token = getMatch(queryItem, searcher.multiRegex);
        if (token != null && token.isNotEmpty) {
          results.add(searcher.create(token, options));
          found = true;
          break;
        }
      }

      if (found) {
        continue;
      }

      for (final searcher in searchers) {
        final token = getMatch(queryItem, searcher.singleRegex);
        if (token != null && token.isNotEmpty) {
          results.add(searcher.create(token, options));
          break;
        }
      }
    }

    return results;
  }).toList();
}

class ExtendedSearch implements Searcher {
  ExtendedSearch(
    String pattern,
    ExtendedMatchOptions options,
  ) : _options = options {
    var normalized = options.isCaseSensitive ? pattern : pattern.toLowerCase();
    normalized =
        options.ignoreDiacritics ? stripDiacritics(normalized) : normalized;
    this.pattern = normalized;
    _query = parseQuery(this.pattern, options);
  }

  final ExtendedMatchOptions _options;
  late final String pattern;
  late final List<List<BaseMatch>> _query;

  @override
  SearchResult searchIn(String text) {
    var normalized = _options.isCaseSensitive ? text : text.toLowerCase();
    normalized =
        _options.ignoreDiacritics ? stripDiacritics(normalized) : normalized;

    for (final searchersGroup in _query) {
      var allIndices = <List<int>>[];
      var numMatches = 0;
      var totalScore = 0.0;

      for (final searcher in searchersGroup) {
        final result = searcher.searchIn(normalized);

        if (result.isMatch) {
          numMatches += 1;
          totalScore += result.score;
          if (_options.includeMatches) {
            final indices = result.indices;
            if (indices != null) {
              if (multiMatchSet.contains(searcher.type)) {
                allIndices = [...allIndices, ...indices];
              } else {
                allIndices.add(indices.first);
              }
            }
          }
        } else {
          numMatches = 0;
          allIndices = [];
          break;
        }
      }

      if (numMatches != 0) {
        return SearchResult(
          isMatch: true,
          score: totalScore / numMatches,
          indices: _options.includeMatches ? allIndices : null,
        );
      }
    }

    return SearchResult(isMatch: false, score: 1);
  }
}
