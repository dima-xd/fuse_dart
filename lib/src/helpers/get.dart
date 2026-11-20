import 'types.dart';

/// Reads the value at a key [path] from a document [obj].
typedef GetFunction<T> = Object? Function(T obj, Object path);

/// An indexed array value: the text [v] and the array index [i] it came from.
class SubRecord {
  SubRecord({required this.v, this.i});

  /// The value; a `String` for scalars reached through the default getter,
  /// or a raw object when the key path is exhausted at a non-scalar.
  final Object? v;

  /// The array index this value came from, or `null` for non-array paths.
  final int? i;
}

/// One collected terminal value along a `get` traversal: a coerced `String`,
/// a [SubRecord], or a raw object when the path ended at a non-scalar.
typedef GotValue = Object;

/// Reads the value(s) at [path] from [obj], following nested keys and arrays.
///
/// [path] is a dotted `String` (e.g. `'author.name'`) or a `List<String>` of
/// segments. Scalar values are coerced to `String`. When the path traverses
/// an array, a `List` of collected values is returned; otherwise the single
/// value is returned, or `null` if nothing is found.
Object? get(Object? obj, Object path) {
  final list = <GotValue>[];
  var arr = false;

  void deepGet(Object? current, List<String> path, int index, int? arrayIndex) {
    if (!isDefined(current)) {
      return;
    }

    if (index >= path.length || path[index].isEmpty) {
      // If there's no path left, we've arrived at the object we care about.
      list.add(
        arrayIndex != null ? SubRecord(v: current, i: arrayIndex) : current!,
      );
      return;
    }

    final key = path[index];

    if (current is! Map) {
      return;
    }
    final value = current[key];

    if (!isDefined(value)) {
      return;
    }

    // If we're at the last value in the path, and if it's a string/number/bool,
    // add it to the list
    if (index == path.length - 1 &&
        (value is String || value is num || value is bool || value is BigInt)) {
      list.add(
        arrayIndex != null
            ? SubRecord(v: toStringValue(value), i: arrayIndex)
            : toStringValue(value),
      );
    } else if (value is List) {
      arr = true;
      // Search each item in the array.
      for (var i = 0; i < value.length; i += 1) {
        deepGet(value[i], path, index + 1, i);
      }
    } else if (path.isNotEmpty) {
      // An object. Recurse further.
      deepGet(value, path, index + 1, arrayIndex);
    }
  }

  // Backwards compatibility (since path used to be a string)
  deepGet(
    obj,
    path is String ? path.split('.') : (path as List).cast<String>(),
    0,
    null,
  );

  return arr ? list : list.firstOrNull;
}
