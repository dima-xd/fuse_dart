import 'dart:math' as math;

/// Counts runs of non-space characters, matching the `[^ ]+` pattern used by
/// the reference implementation.
int _countTokens(String value) {
  var count = 0;
  var inToken = false;

  for (var i = 0; i < value.length; i += 1) {
    if (value.codeUnitAt(i) == 0x20) {
      inToken = false;
    } else if (!inToken) {
      inToken = true;
      count += 1;
    }
  }

  return count;
}

class Norm {
  Norm({double weight = 1, int mantissa = 3})
      : _weight = weight,
        _m = math.pow(10, mantissa).toInt();

  final double _weight;
  final int _m;
  final Map<int, double> _cache = {};

  double get(String value) {
    final numTokens = _countTokens(value);

    final cached = _cache[numTokens];
    if (cached != null) {
      return cached;
    }

    final norm = 1 / math.pow(numTokens, 0.5 * _weight);
    final n = (norm * _m).round() / _m;

    _cache[numTokens] = n;

    return n;
  }

  void clear() => _cache.clear();
}
