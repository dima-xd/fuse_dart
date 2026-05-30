import '../core/config.dart';
import '../core/error_messages.dart';

/// A processed search key stored in a [FuseIndex].
///
/// Produced from a `String`/`List<String>` path or a [FuseKey]; holds the
/// resolved path, id, normalized weight, and original source.
class IndexedKey<T> {
  /// Creates an indexed key.
  IndexedKey({
    required this.path,
    required this.id,
    required this.weight,
    required this.src,
    this.getFn,
  });

  /// The key path split into segments.
  final List<String> path;

  /// The key id (the path joined by `.`).
  final String id;

  /// The weight of this key, normalized across all keys.
  double weight;

  /// The original key source (`String` or `List<String>`).
  final Object src;

  /// Optional custom getter for this key's value.
  final KeyGetFunction<T>? getFn;

  /// Serializes this key to JSON.
  Map<String, dynamic> toJson() => {
        'path': path,
        'id': id,
        'weight': weight,
        'src': src,
      };

  /// Rebuilds a key from its JSON form.
  factory IndexedKey.fromJson(Map<String, dynamic> json) {
    final src = json['src'] as Object;
    return IndexedKey<T>(
      path: (json['path'] as List).cast<String>(),
      id: json['id'] as String,
      weight: (json['weight'] as num).toDouble(),
      src: src,
    );
  }
}

List<String> createKeyPath(Object key) =>
    key is List ? key.cast<String>() : (key as String).split('.');

String createKeyId(Object key) =>
    key is List ? key.cast<String>().join('.') : key as String;

IndexedKey<T> createKey<T>(Object key) {
  if (key is String || key is List) {
    return IndexedKey<T>(
      path: createKeyPath(key),
      id: createKeyId(key),
      weight: 1,
      src: key,
    );
  }

  Object name;
  double weight = 1;
  KeyGetFunction<T>? getFn;

  if (key is FuseKey<T>) {
    name = key.name;
    weight = key.weight;
    final fn = key.getFn;
    getFn = fn == null ? null : (T obj) => fn(obj);
    if (weight <= 0) {
      throw ArgumentError(invalidKeyWeightValue(createKeyId(name)));
    }
  } else if (key is FuseKey) {
    final dynamic dynamicKey = key;
    name = dynamicKey.name as Object;
    weight = (dynamicKey.weight as num).toDouble();
    final dynamic fn = dynamicKey.getFn;
    getFn = fn == null ? null : (T obj) => fn(obj) as Object?;
    if (weight <= 0) {
      throw ArgumentError(invalidKeyWeightValue(createKeyId(name)));
    }
  } else if (key is Map) {
    if (!key.containsKey('name')) {
      throw ArgumentError(missingKeyProperty('name'));
    }
    name = key['name'] as Object;
    if (key.containsKey('weight')) {
      weight = (key['weight'] as num).toDouble();
      if (weight <= 0) {
        throw ArgumentError(invalidKeyWeightValue(createKeyId(name)));
      }
    }
    final fn = key['getFn'];
    if (fn is KeyGetFunction<T>) {
      getFn = fn;
    }
  } else {
    throw ArgumentError(missingKeyProperty('name'));
  }

  return IndexedKey<T>(
    path: createKeyPath(name),
    id: createKeyId(name),
    weight: weight,
    src: name,
    getFn: getFn,
  );
}

class KeyStore<T> {
  KeyStore(List<Object> keys) {
    var totalWeight = 0.0;

    for (final key in keys) {
      final obj = createKey<T>(key);
      _keys.add(obj);
      _keyMap[obj.id] = obj;
      totalWeight += obj.weight;
    }

    for (final key in _keys) {
      key.weight /= totalWeight;
    }
  }

  final List<IndexedKey<T>> _keys = [];
  final Map<String, IndexedKey<T>> _keyMap = {};

  IndexedKey<T>? get(String keyId) => _keyMap[keyId];

  List<IndexedKey<T>> keys() => _keys;
}
