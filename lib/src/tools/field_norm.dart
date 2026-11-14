import 'dart:math' as math;

/// Char codes we treat as word separators: the common ASCII whitespace
/// (tab 9, LF 10, VT 11, FF 12, CR 13, space 32) plus NBSP (160). This is
/// deliberately narrower than the full Unicode whitespace set; it skips
/// rarer separators like the ideographic space, which the field-norm
/// heuristic is too coarse to benefit from distinguishing.
bool _isWordSeparator(int code) =>
    (code >= 9 && code <= 13) || code == 32 || code == 160;

/// Field-length norm: the shorter the field, the higher the weight.
/// Set to 3 decimals to reduce index size.
class FieldNorm {
  FieldNorm({double weight = 1, int mantissa = 3})
      : _weight = weight,
        _m = math.pow(10, mantissa).toInt();

  final double _weight;
  final int _m;
  final Map<int, double> _cache = {};

  double get(String value) {
    // Count words by tallying word-starts (transitions from separator/start
    // to non-separator). This avoids allocating a regex match array and
    // correctly handles leading and trailing separators. A separator here is
    // common ASCII whitespace (space, tab, newline, CR, vertical tab, form
    // feed) plus NBSP, not the full Unicode set.
    var numTokens = 0;
    var inWord = false;
    for (var i = 0; i < value.length; i++) {
      if (!_isWordSeparator(value.codeUnitAt(i))) {
        if (!inWord) {
          numTokens++;
          inWord = true;
        }
      } else {
        inWord = false;
      }
    }
    // Empty strings and all-whitespace strings have no real words; treat
    // them as a single token so the formula never divides by zero.
    if (numTokens == 0) numTokens = 1;

    final cached = _cache[numTokens];
    if (cached != null) {
      return cached;
    }

    // Default function is 1/sqrt(x), weight makes that variable
    final n = (math.pow(numTokens, 0.5 * _weight)).toDouble();
    final normalized = (_m / n).round() / _m;

    _cache[numTokens] = normalized;

    return normalized;
  }

  void clear() => _cache.clear();
}
