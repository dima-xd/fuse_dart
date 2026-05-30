import 'dart:math' as math;

final RegExp _space = RegExp(r'[^ ]+');

class Norm {
  Norm({double weight = 1, int mantissa = 3})
      : _weight = weight,
        _m = math.pow(10, mantissa).toInt();

  final double _weight;
  final int _m;
  final Map<int, double> _cache = {};

  double get(String value) {
    final numTokens = _space.allMatches(value).length;

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
