const double epsilon = 2.220446049250313e-16;

/// Stand-in for JS `undefined` so it survives the JSON round trip in the
/// conformance bridge distinctly from `null`.
class JsUndefined {
  const JsUndefined();
}

const jsUndefined = JsUndefined();

/// JS `undefined` and `null` are both "not defined" for Fuse purposes.
bool isDefined(Object? value) =>
    value != null && value is! JsUndefined;

bool isBlank(String value) => value.trim().isEmpty;

/// A search error carrying a clean message, mirroring `new Error(msg)` in
/// Fuse.js. [toString] returns the bare message so error-message assertions
/// behave identically across the JS and Dart implementations.
class FuseException implements Exception {
  FuseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Adapted from lodash's `baseToString`, matching JavaScript's
/// `String(value)` coercion (including the `-0` special case).
String toStringValue(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is BigInt) return value.toString();
  if (value is num) {
    if (value == 0 && value.isNegative) return '-0';
    return value.toString();
  }
  return value.toString();
}
