import '../core/config.dart';
import '../core/error_messages.dart';
import '../helpers/types.dart';

/// A processed search key stored in a [FuseIndex].
///
/// Produced from a `String`/`List<String>` path or a [FuseKey]; holds the
/// resolved path, id, weight, and original source. Weights on index keys are
/// the raw user values; only [KeyStore] normalizes them to sum to 1.
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

  /// The weight of this key.
  double weight;

  /// The original key source (`String` or `List<String>`).
  final Object src;

  /// Optional custom getter for this key's value.
  final KeyGetFunction<T>? getFn;

  /// Serializes this key to JSON (getFn stripped).
  Map<String, dynamic> toJson() => {
        'path': path,
        'id': id,
        'weight': weight,
        'src': src,
      };

  /// Rebuilds a key from its JSON form.
  factory IndexedKey.fromJson(Map<String, dynamic> json) {
    return IndexedKey<T>(
      path: (json['path'] as List).cast<String>(),
      id: json['id'] as String,
      weight: (json['weight'] as num).toDouble(),
      src: json['src'] as Object,
    );
  }
}

List<String> createKeyPath(Object key) =>
    key is List ? key.cast<String>() : (key as String).split('.');

String createKeyId(Object key) =>
    key is List ? key.cast<String>().join('.') : key as String;

IndexedKey<T> createKey<T>(Object key) {
  List<String>? path;
  String? id;
  Object? src;
  double weight = 1;
  KeyGetFunction<T>? getFn;

  if (key is String || key is List) {
    src = key;
    path = createKeyPath(key);
    id = createKeyId(key);
  } else {
    if (key is Map) {
      if (!key.containsKey('name')) {
        throw FuseException(missingKeyProperty('name'));
      }

      final name = key['name'] as Object;
      src = name;

      if (key.containsKey('weight') && key['weight'] != null) {
        weight = (key['weight'] as num).toDouble();

        if (weight <= 0) {
          throw FuseException(invalidKeyWeightValue(createKeyId(name)));
        }
      }

      path = createKeyPath(name);
      id = createKeyId(name);
      final fn = key['getFn'];
      if (fn is KeyGetFunction<T>) {
        getFn = fn;
      }
    } else {
      final fuseKey = key as FuseKey<dynamic>;
      final name = fuseKey.name;
      src = name;

      weight = fuseKey.weight;

      if (weight <= 0) {
        throw FuseException(invalidKeyWeightValue(createKeyId(name)));
      }

      path = createKeyPath(name);
      id = createKeyId(name);
      getFn = fuseKey.getFn;
    }
  }

  return IndexedKey<T>(
    path: path,
    id: id,
    weight: weight,
    src: src,
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

    // Normalize weights so that their sum is equal to 1
    for (final key in _keys) {
      key.weight /= totalWeight;
    }
  }

  final List<IndexedKey<T>> _keys = [];
  final Map<String, IndexedKey<T>> _keyMap = {};

  IndexedKey<T>? get(String keyId) => _keyMap[keyId];

  List<IndexedKey<T>> keys() => _keys;
}
