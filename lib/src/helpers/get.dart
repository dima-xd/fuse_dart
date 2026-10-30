import 'types.dart';

/// Reads the value at a key [path] from a document [obj].
typedef GetFunction<T> = Object? Function(T obj, Object path);

void _deepGet(
  Object? current,
  List<String> segments,
  int index,
  List<Object?> out,
) {
  if (current == null) return;

  if (index >= segments.length || segments[index].isEmpty) {
    out.add(current);
    return;
  }

  final key = segments[index];

  if (current is! Map) return;
  final value = current[key];

  if (value == null) return;

  if (index == segments.length - 1 &&
      (value is String || value is num || value is bool)) {
    out.add(toStringValue(value));
  } else if (value is List) {
    for (var i = 0; i < value.length; i += 1) {
      _deepGet(value[i], segments, index + 1, out);
    }
  } else {
    _deepGet(value, segments, index + 1, out);
  }
}

/// Reads the value(s) at [path] from [obj], following nested keys and arrays.
///
/// [path] is a dotted `String` (e.g. `'author.name'`) or a `List<String>` of
/// segments. Scalar values are coerced to `String`. When the path traverses
/// an array, a `List` of the collected values is returned; otherwise the
/// single value is returned, or `null` if nothing is found.
Object? get(Object? obj, Object path) {
  final List<String> segments;
  if (path is String) {
    segments = path.split('.');
  } else if (path is List<String>) {
    segments = path;
  } else {
    segments = (path as List).cast<String>();
  }

  Object? current = obj;

  for (var index = 0; index < segments.length; index += 1) {
    if (current == null) return null;

    final key = segments[index];
    if (key.isEmpty) return current;

    if (current is! Map) return null;
    final value = current[key];

    if (value == null) return null;

    if (index == segments.length - 1 &&
        (value is String || value is num || value is bool)) {
      return toStringValue(value);
    }

    if (value is List) {
      final list = <Object?>[];
      for (var i = 0; i < value.length; i += 1) {
        _deepGet(value[i], segments, index + 1, list);
      }
      return list;
    }

    current = value;
  }

  return current;
}
