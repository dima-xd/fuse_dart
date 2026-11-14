import 'bitap/bitap_search.dart';
import 'extended/extended_search.dart';
import 'searcher.dart';
import 'token/inverted_index.dart';
import 'token/token_search.dart';
import '../core/config.dart';

/// A pluggable searcher: decides when it applies via [condition] and builds
/// itself via [create]. Registered through [Fuse.use]-style registration.
class SearcherPlugin {
  const SearcherPlugin({required this.condition, required this.create});

  final bool Function(String pattern, FuseOptions<dynamic> options) condition;

  final Searcher Function(
    String pattern,
    FuseOptions<dynamic> options,
    InvertedIndexData? invertedIndex,
  ) create;
}

final List<SearcherPlugin> _registeredSearchers = [
  // Mirrors upstream `entry.ts` registration order.
  SearcherPlugin(
    condition: (_, options) => options.useExtendedSearch,
    create: (pattern, options, _) => ExtendedSearch(pattern, options),
  ),
  SearcherPlugin(
    condition: (_, options) => options.useTokenSearch,
    create: (pattern, options, invertedIndex) =>
        TokenSearch(pattern, options, invertedIndex),
  ),
];

/// Registers additional searcher plugins (mirrors Fuse.js `register` /
/// `Fuse.use`).
void registerSearchers(List<SearcherPlugin> plugins) {
  _registeredSearchers.addAll(plugins);
}

/// Builds the searcher for [pattern] under [options], honoring registered
/// plugins before falling back to plain Bitap search.
Searcher createSearcher<T>(
  String pattern,
  FuseOptions<T> options, {
  InvertedIndexData? invertedIndex,
}) {
  for (var i = 0; i < _registeredSearchers.length; i += 1) {
    final plugin = _registeredSearchers[i];
    if (plugin.condition(pattern, options)) {
      return plugin.create(pattern, options, invertedIndex);
    }
  }

  return BitapSearch(pattern, options);
}
