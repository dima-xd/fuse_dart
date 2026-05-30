import '../bitap/bitap_search.dart';
import '../searcher.dart';

class ExtendedMatchOptions {
  const ExtendedMatchOptions({
    this.location = 0,
    this.threshold = 0.6,
    this.distance = 100,
    this.includeMatches = false,
    this.findAllMatches = false,
    this.minMatchCharLength = 1,
    this.isCaseSensitive = false,
    this.ignoreDiacritics = false,
    this.ignoreLocation = false,
  });

  final int location;
  final double threshold;
  final int distance;
  final bool includeMatches;
  final bool findAllMatches;
  final int minMatchCharLength;
  final bool isCaseSensitive;
  final bool ignoreDiacritics;
  final bool ignoreLocation;
}

abstract class BaseMatch implements Searcher {
  BaseMatch(this.pattern);
  final String pattern;
  String get type;
}

String? getMatch(String pattern, RegExp exp) =>
    exp.firstMatch(pattern)?.group(1);

class ExactMatch extends BaseMatch {
  ExactMatch(super.pattern);

  static const String typeName = 'exact';
  static final RegExp multiRegex = RegExp(r'^="(.*)"$');
  static final RegExp singleRegex = RegExp(r'^=(.*)$');

  @override
  String get type => typeName;

  @override
  SearchResult searchIn(String text) {
    final isMatch = text == pattern;
    return SearchResult(
      isMatch: isMatch,
      score: isMatch ? 0 : 1,
      indices: [
        [0, pattern.length - 1]
      ],
    );
  }
}

class IncludeMatch extends BaseMatch {
  IncludeMatch(super.pattern);

  static const String typeName = 'include';
  static final RegExp multiRegex = RegExp("^'\"(.*)\"\$");
  static final RegExp singleRegex = RegExp("^'(.*)\$");

  @override
  String get type => typeName;

  @override
  SearchResult searchIn(String text) {
    var location = 0;
    int index;
    final indices = <List<int>>[];
    final patternLen = pattern.length;

    while ((index = text.indexOf(pattern, location)) > -1) {
      location = index + patternLen;
      indices.add([index, location - 1]);
    }

    final isMatch = indices.isNotEmpty;

    return SearchResult(
      isMatch: isMatch,
      score: isMatch ? 0 : 1,
      indices: indices,
    );
  }
}

class PrefixExactMatch extends BaseMatch {
  PrefixExactMatch(super.pattern);

  static const String typeName = 'prefix-exact';
  static final RegExp multiRegex = RegExp(r'^\^"(.*)"$');
  static final RegExp singleRegex = RegExp(r'^\^(.*)$');

  @override
  String get type => typeName;

  @override
  SearchResult searchIn(String text) {
    final isMatch = text.startsWith(pattern);
    return SearchResult(
      isMatch: isMatch,
      score: isMatch ? 0 : 1,
      indices: [
        [0, pattern.length - 1]
      ],
    );
  }
}

class InversePrefixExactMatch extends BaseMatch {
  InversePrefixExactMatch(super.pattern);

  static const String typeName = 'inverse-prefix-exact';
  static final RegExp multiRegex = RegExp(r'^!\^"(.*)"$');
  static final RegExp singleRegex = RegExp(r'^!\^(.*)$');

  @override
  String get type => typeName;

  @override
  SearchResult searchIn(String text) {
    final isMatch = !text.startsWith(pattern);
    return SearchResult(
      isMatch: isMatch,
      score: isMatch ? 0 : 1,
      indices: [
        [0, text.length - 1]
      ],
    );
  }
}

class SuffixExactMatch extends BaseMatch {
  SuffixExactMatch(super.pattern);

  static const String typeName = 'suffix-exact';
  static final RegExp multiRegex = RegExp(r'^"(.*)"\$$');
  static final RegExp singleRegex = RegExp(r'^(.*)\$$');

  @override
  String get type => typeName;

  @override
  SearchResult searchIn(String text) {
    final isMatch = text.endsWith(pattern);
    return SearchResult(
      isMatch: isMatch,
      score: isMatch ? 0 : 1,
      indices: [
        [text.length - pattern.length, text.length - 1]
      ],
    );
  }
}

class InverseSuffixExactMatch extends BaseMatch {
  InverseSuffixExactMatch(super.pattern);

  static const String typeName = 'inverse-suffix-exact';
  static final RegExp multiRegex = RegExp(r'^!"(.*)"\$$');
  static final RegExp singleRegex = RegExp(r'^!(.*)\$$');

  @override
  String get type => typeName;

  @override
  SearchResult searchIn(String text) {
    final isMatch = !text.endsWith(pattern);
    return SearchResult(
      isMatch: isMatch,
      score: isMatch ? 0 : 1,
      indices: [
        [0, text.length - 1]
      ],
    );
  }
}

class InverseExactMatch extends BaseMatch {
  InverseExactMatch(super.pattern);

  static const String typeName = 'inverse-exact';
  static final RegExp multiRegex = RegExp(r'^!"(.*)"$');
  static final RegExp singleRegex = RegExp(r'^!(.*)$');

  @override
  String get type => typeName;

  @override
  SearchResult searchIn(String text) {
    final index = text.indexOf(pattern);
    final isMatch = index == -1;
    return SearchResult(
      isMatch: isMatch,
      score: isMatch ? 0 : 1,
      indices: [
        [0, text.length - 1]
      ],
    );
  }
}

class FuzzyMatch extends BaseMatch {
  FuzzyMatch(super.pattern, ExtendedMatchOptions options)
      : _bitapSearch = BitapSearch(
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

  static const String typeName = 'fuzzy';
  static final RegExp multiRegex = RegExp(r'^"(.*)"$');
  static final RegExp singleRegex = RegExp(r'^(.*)$');

  final BitapSearch _bitapSearch;

  @override
  String get type => typeName;

  @override
  SearchResult searchIn(String text) => _bitapSearch.searchIn(text);
}

class MatcherDescriptor {
  const MatcherDescriptor({
    required this.type,
    required this.multiRegex,
    required this.singleRegex,
    required this.create,
  });

  final String type;
  final RegExp multiRegex;
  final RegExp singleRegex;
  final BaseMatch Function(String token, ExtendedMatchOptions options) create;
}

final List<MatcherDescriptor> searchers = [
  MatcherDescriptor(
    type: ExactMatch.typeName,
    multiRegex: ExactMatch.multiRegex,
    singleRegex: ExactMatch.singleRegex,
    create: (token, _) => ExactMatch(token),
  ),
  MatcherDescriptor(
    type: IncludeMatch.typeName,
    multiRegex: IncludeMatch.multiRegex,
    singleRegex: IncludeMatch.singleRegex,
    create: (token, _) => IncludeMatch(token),
  ),
  MatcherDescriptor(
    type: PrefixExactMatch.typeName,
    multiRegex: PrefixExactMatch.multiRegex,
    singleRegex: PrefixExactMatch.singleRegex,
    create: (token, _) => PrefixExactMatch(token),
  ),
  MatcherDescriptor(
    type: InversePrefixExactMatch.typeName,
    multiRegex: InversePrefixExactMatch.multiRegex,
    singleRegex: InversePrefixExactMatch.singleRegex,
    create: (token, _) => InversePrefixExactMatch(token),
  ),
  MatcherDescriptor(
    type: InverseSuffixExactMatch.typeName,
    multiRegex: InverseSuffixExactMatch.multiRegex,
    singleRegex: InverseSuffixExactMatch.singleRegex,
    create: (token, _) => InverseSuffixExactMatch(token),
  ),
  MatcherDescriptor(
    type: SuffixExactMatch.typeName,
    multiRegex: SuffixExactMatch.multiRegex,
    singleRegex: SuffixExactMatch.singleRegex,
    create: (token, _) => SuffixExactMatch(token),
  ),
  MatcherDescriptor(
    type: InverseExactMatch.typeName,
    multiRegex: InverseExactMatch.multiRegex,
    singleRegex: InverseExactMatch.singleRegex,
    create: (token, _) => InverseExactMatch(token),
  ),
  MatcherDescriptor(
    type: FuzzyMatch.typeName,
    multiRegex: FuzzyMatch.multiRegex,
    singleRegex: FuzzyMatch.singleRegex,
    create: (token, options) => FuzzyMatch(token, options),
  ),
];

const Set<String> multiMatchSet = {FuzzyMatch.typeName, IncludeMatch.typeName};
