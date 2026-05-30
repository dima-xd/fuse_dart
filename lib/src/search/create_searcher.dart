import '../core/config.dart';
import 'bitap/bitap_search.dart';
import 'extended/extended_search.dart';
import 'extended/matchers.dart';
import 'searcher.dart';

Searcher createSearcher<T>(String pattern, FuseOptions<T> options) {
  if (options.useExtendedSearch) {
    return ExtendedSearch(
      pattern,
      ExtendedMatchOptions(
        isCaseSensitive: options.isCaseSensitive,
        ignoreDiacritics: options.ignoreDiacritics,
        includeMatches: options.includeMatches,
        minMatchCharLength: options.minMatchCharLength,
        findAllMatches: options.findAllMatches,
        ignoreLocation: options.ignoreLocation,
        location: options.location,
        threshold: options.threshold,
        distance: options.distance,
      ),
    );
  }

  return BitapSearch(
    pattern,
    location: options.location,
    threshold: options.threshold,
    distance: options.distance,
    includeMatches: options.includeMatches,
    findAllMatches: options.findAllMatches,
    minMatchCharLength: options.minMatchCharLength,
    isCaseSensitive: options.isCaseSensitive,
    ignoreDiacritics: options.ignoreDiacritics,
    ignoreLocation: options.ignoreLocation,
  );
}
