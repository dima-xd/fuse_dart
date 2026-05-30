import 'types.dart';

/// Reads the value at a key [path] from a document [obj].
typedef GetFunction<T> = Object? Function(T obj, Object path);

/// Reads the value(s) at [path] from [obj], following nested keys and arrays.
///
/// [path] is a dotted `String` (e.g. `'author.name'`) or a `List<String>` of
/// segments. Scalar values are coerced to `String`. When the path traverses
/// an array, a `List` of the collected values is returned; otherwise the
/// single value is returned, or `null` if nothing is found.
Object? get(Object? obj, Object path) {
  final list = <Object?>[];
  var arr = false;
  final segments =
      path is String ? path.split('.') : (path as List).cast<String>();

  void deepGet(Object? current, int index) {
    if (current == null) return;

    if (index >= segments.length || segments[index].isEmpty) {
      list.add(current);
      return;
    }

    final key = segments[index];

    if (current is! Map) return;
    final value = current[key];

    if (value == null) return;

    if (index == segments.length - 1 &&
        (value is String || value is num || value is bool)) {
      list.add(toStringValue(value));
    } else if (value is List) {
      arr = true;
      for (var i = 0; i < value.length; i += 1) {
        deepGet(value[i], index + 1);
      }
    } else {
      deepGet(value, index + 1);
    }
  }

  deepGet(obj, 0);

  return arr ? list : (list.isEmpty ? null : list.first);
}
