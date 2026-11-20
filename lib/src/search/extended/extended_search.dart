import '../../core/config.dart';
import '../../helpers/diacritics.dart';
import '../../helpers/merge_indices.dart';
import '../searcher.dart';
import 'matchers.dart';

const String _escapedPipe = '\u0000'; // placeholder for escaped \|
const String _orToken = '|';

// Tokenize a query string into individual search terms.
// Respects multi-match quoted tokens like ="said "test"" or ^"hello world"$
// where inner spaces and quotes are part of the token.
List<String> tokenize(String pattern) {
  final tokens = <String>[];
  final len = pattern.length;
  var i = 0;

  while (i < len) {
    // Skip spaces
    while (i < len && pattern[i] == ' ') {
      i++;
    }
    if (i >= len) break;

    // Scan past prefix characters (=, !, ^, ') to see if a quote follows
    var j = i;
    while (j < len && pattern[j] != ' ' && pattern[j] != '"') {
      j++;
    }

    if (j < len && pattern[j] == '"') {
      // Multi-match token: prefix + "content" (possibly with inner quotes)
      // Find the closing " that ends this token:
      // it must be followed by optional $, then space or end-of-string
      j++; // skip opening quote
      while (j < len) {
        if (pattern[j] == '"') {
          // Check if this is the closing quote
          final next = j + 1;
          if (next >= len || pattern[next] == ' ') {
            j++; // include closing quote
            break;
          }
          if (pattern[next] == r'$' &&
              (next + 1 >= len || pattern[next + 1] == ' ')) {
            j += 2; // include "$
            break;
          }
        }
        j++;
      }
      tokens.add(pattern.substring(i, j));
      i = j;
    } else {
      // Regular (unquoted) token: read until space or end
      while (j < len && pattern[j] != ' ') {
        j++;
      }
      tokens.add(pattern.substring(i, j));
      i = j;
    }
  }

  return tokens;
}

// Return a 2D array representation of the query, for simpler parsing.
// Example:
// "^core go$ | rb$ | py$ xy$" => [["^core", "go$"], ["rb$"], ["py$", "xy$"]]
List<List<BaseMatch>> parseQuery(String pattern, ExtendedMatchOptions options) {
  // Replace escaped \| with placeholder before splitting on |
  final escaped = pattern.replaceAll(r'\|', _escapedPipe);

  return escaped.split(_orToken).map((item) {
    // Restore escaped pipes in each OR group
    final restored = item.replaceAll(_escapedPipe, '|');
    final query = tokenize(restored.trim())
        .where((item) => item.isNotEmpty && item.trim().isNotEmpty)
        .toList();

    final results = <BaseMatch>[];
    for (var i = 0, len = query.length; i < len; i += 1) {
      final queryItem = query[i];

      // 1. Handle multiple query match (i.e, ones that are quoted, like
      //    `"hello world"`)
      var found = false;
      var idx = -1;
      while (!found && ++idx < searchers.length) {
        final def = searchers[idx];
        final token = getMatch(queryItem, def.multiRegex);
        if (token != null) {
          results.add(def.create(token, options));
          found = true;
        }
      }

      if (found) {
        continue;
      }

      // 2. Handle single query matches (i.e, ones that are *not* quoted)
      idx = -1;
      while (++idx < searchers.length) {
        final def = searchers[idx];
        final token = getMatch(queryItem, def.singleRegex);
        if (token != null) {
          results.add(def.create(token, options));
          break;
        }
      }
    }

    return results;
  }).toList();
}

class ExtendedSearch implements Searcher {
  ExtendedSearch(String pattern, FuseOptions<dynamic> options)
      : _options = options {
    var normalized = options.isCaseSensitive ? pattern : pattern.toLowerCase();
    normalized =
        options.ignoreDiacritics ? stripDiacritics(normalized) : normalized;
    this.pattern = normalized;
    _query = parseQuery(
        this.pattern,
        ExtendedMatchOptions(
          location: options.location,
          threshold: options.threshold,
          distance: options.distance,
          includeMatches: options.includeMatches,
          findAllMatches: options.findAllMatches,
          minMatchCharLength: options.minMatchCharLength,
          isCaseSensitive: options.isCaseSensitive,
          ignoreDiacritics: options.ignoreDiacritics,
          ignoreLocation: options.ignoreLocation,
        ));
  }

  final FuseOptions<dynamic> _options;
  late final String pattern;
  late final List<List<BaseMatch>> _query;

  // Note: searchIn operates on a single text value and sets hasInverse on the
  // result when inverse patterns are involved. _searchObjectList uses this to
  // switch from "ANY key" to "ALL keys" aggregation. See #712.
  @override
  SearchResult searchIn(String text) {
    final query = _query;

    if (query.isEmpty) {
      return SearchResult(isMatch: false, score: 1);
    }

    var normalized = _options.isCaseSensitive ? text : text.toLowerCase();
    normalized =
        _options.ignoreDiacritics ? stripDiacritics(normalized) : normalized;

    var numMatches = 0;
    var totalScore = 0.0;
    var hasInverse = false;

    // ORs
    for (var i = 0, qLen = query.length; i < qLen; i += 1) {
      final searchersGroup = query[i];

      // Reset indices
      final allIndices = <List<int>>[];
      numMatches = 0;
      totalScore = 0;
      hasInverse = false;

      // ANDs
      for (var j = 0, pLen = searchersGroup.length; j < pLen; j += 1) {
        final matcher = searchersGroup[j];
        final result = matcher.searchIn(normalized);

        if (result.isMatch) {
          numMatches += 1;
          totalScore += result.score;

          if (isInverse(matcher.type)) {
            hasInverse = true;
          }

          if (_options.includeMatches) {
            final indices = result.indices;
            if (indices != null) {
              if (multiMatchSet.contains(matcher.type)) {
                allIndices.addAll(indices);
              } else {
                allIndices.add(indices.first);
              }
            }
          }
        } else {
          totalScore = 0;
          numMatches = 0;
          allIndices.clear();
          hasInverse = false;
          break;
        }
      }

      // OR condition, so if TRUE, return
      if (numMatches != 0) {
        final result = SearchResult(
          isMatch: true,
          score: totalScore / numMatches,
        );

        if (hasInverse) {
          result.hasInverse = true;
        }

        if (_options.includeMatches) {
          result.indices = mergeIndices(allIndices);
        }

        return result;
      }
    }

    // Nothing was matched
    return SearchResult(isMatch: false, score: 1);
  }
}
