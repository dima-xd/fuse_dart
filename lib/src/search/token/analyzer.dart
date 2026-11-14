import '../../helpers/diacritics.dart';

typedef TokenizeFunction = List<String> Function(String text);

class Analyzer {
  Analyzer(this._tokenizeFn);

  final List<String> Function(String) _tokenizeFn;

  List<String> tokenize(String text) => _tokenizeFn(text);
}

// Includes \p{M} (Mark) so combining marks stay attached to their base
// letter — without it, scripts like Devanagari and NFD-normalized Latin
// shatter (e.g. 'हिन्दी' → ['ह','न','द'], 'café'.normalize('NFD') → ['cafe']).
final RegExp _defaultToken = RegExp(r'[\p{L}\p{M}\p{N}_]+', unicode: true);

List<String> Function(String) _resolveTokenize(Object? tokenize) {
  if (tokenize is TokenizeFunction) {
    return tokenize;
  }
  if (tokenize is List<String> Function(String)) {
    return tokenize;
  }
  if (tokenize is RegExp) {
    return (text) => tokenize.allMatches(text).map((m) => m.group(0)!).toList();
  }
  return (text) =>
      _defaultToken.allMatches(text).map((m) => m.group(0)!).toList();
}

Analyzer createAnalyzer({
  bool isCaseSensitive = false,
  bool ignoreDiacritics = false,
  Object? tokenize,
}) {
  final tokenizeFn = _resolveTokenize(tokenize);
  return Analyzer((text) {
    if (!isCaseSensitive) {
      text = text.toLowerCase();
    }
    if (ignoreDiacritics) {
      text = stripDiacritics(text);
    }
    return tokenizeFn(text);
  });
}
