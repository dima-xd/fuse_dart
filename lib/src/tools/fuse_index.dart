import '../helpers/get.dart';
import '../helpers/types.dart';
import 'key_store.dart';
import 'norm.dart';

/// One indexed string value, with its field-length norm.
class RecordValue {
  /// Creates an indexed value [v] with norm [n] and optional array index [i].
  RecordValue({required this.v, required this.n, this.i});

  /// The stored text.
  final String v;

  /// The field-length norm for [v].
  final double n;

  /// The array index this value came from, or `null` for scalar fields.
  final int? i;

  /// Serializes this value to JSON.
  Map<String, dynamic> toJson() => {
        'v': v,
        if (i != null) 'i': i,
        'n': n,
      };

  /// Rebuilds a value from its JSON form.
  factory RecordValue.fromJson(Map<String, dynamic> json) => RecordValue(
        v: json['v'] as String,
        n: (json['n'] as num).toDouble(),
        i: json['i'] as int?,
      );
}

/// Base class for an indexed document record.
abstract class FuseRecord {
  /// Creates a record referencing collection index [i].
  FuseRecord(this.i);

  /// Index of the source document in the collection.
  int i;

  /// Serializes this record to JSON.
  Map<String, dynamic> toJson();
}

/// An indexed record for a plain string document.
class StringRecord extends FuseRecord {
  /// Creates a string record for [v] at index [i] with norm [n].
  StringRecord({required this.v, required int i, required this.n}) : super(i);

  /// The stored text.
  final String v;

  /// The field-length norm for [v].
  final double n;

  @override
  Map<String, dynamic> toJson() => {'v': v, 'i': i, 'n': n};
}

/// An indexed record for an object document, keyed by key index.
class ObjectRecord extends FuseRecord {
  /// Creates an object record at index [i] with optional indexed [entries].
  ObjectRecord({required int i, Map<int, Object>? entries})
      : entries = entries ?? {},
        super(i);

  /// Indexed values per key, mapping key index to a [RecordValue] or a
  /// `List<RecordValue>` for array-valued keys.
  final Map<int, Object> entries;

  @override
  Map<String, dynamic> toJson() {
    final dollar = <String, dynamic>{};
    entries.forEach((keyIndex, value) {
      if (value is List<RecordValue>) {
        dollar['$keyIndex'] = value.map((v) => v.toJson()).toList();
      } else if (value is RecordValue) {
        dollar['$keyIndex'] = value.toJson();
      }
    });
    return {'i': i, '\$': dollar};
  }
}

/// A precomputed search index over a collection of documents.
///
/// Created internally by [Fuse], or directly via [createFuseIndex] /
/// [parseFuseIndex] to share across instances.
class FuseIndex<T> {
  /// Creates an empty index.
  ///
  /// [getFn] reads values from documents; [fieldNormWeight] tunes the
  /// field-length norm.
  FuseIndex({GetFunction<T>? getFn, double fieldNormWeight = 1})
      : _norm = Norm(weight: fieldNormWeight),
        _getFn = getFn ?? ((T obj, Object path) => get(obj, path));

  final Norm _norm;
  final GetFunction<T> _getFn;

  /// Whether [create] has already run.
  bool isCreated = false;

  /// The source documents.
  List<T> docs = [];

  /// The indexed records.
  List<FuseRecord> records = [];

  /// The indexed keys.
  List<IndexedKey<T>> keys = [];
  final Map<String, int> _keysMap = {};

  /// Sets the source [docs] without indexing them.
  void setSources(List<T> docs) {
    this.docs = docs;
  }

  /// Replaces the index [records] directly (e.g. when restoring from JSON).
  void setIndexRecords(List<FuseRecord> records) {
    this.records = records;
  }

  /// Sets the [keys] to index and rebuilds the key lookup map.
  void setKeys(List<IndexedKey<T>> keys) {
    this.keys = keys;
    _keysMap.clear();
    for (var idx = 0; idx < keys.length; idx += 1) {
      _keysMap[keys[idx].id] = idx;
    }
  }

  /// Indexes every document in [docs]. No-op if already created or empty.
  void create() {
    if (isCreated || docs.isEmpty) {
      return;
    }

    isCreated = true;

    if (docs.first is String) {
      for (var docIndex = 0; docIndex < docs.length; docIndex += 1) {
        _addString(docs[docIndex] as String, docIndex);
      }
    } else {
      for (var docIndex = 0; docIndex < docs.length; docIndex += 1) {
        _addObject(docs[docIndex], docIndex);
      }
    }

    _norm.clear();
  }

  /// Indexes [doc] and appends it to the records.
  void add(T doc) {
    final idx = size();
    if (doc is String) {
      _addString(doc, idx);
    } else {
      _addObject(doc, idx);
    }
  }

  /// Removes the record at [idx] and shifts later document indices down.
  void removeAt(int idx) {
    records.removeAt(idx);
    for (var i = idx, len = size(); i < len; i += 1) {
      records[i].i -= 1;
    }
  }

  /// Returns the indexed value(s) for [keyId] within an object record's
  /// [item] entry map.
  Object? getValueForItemAtKeyId(Map<int, Object> item, String keyId) =>
      item[_keysMap[keyId]];

  /// The number of records in the index.
  int size() => records.length;

  void _addString(String doc, int docIndex) {
    if (isBlank(doc)) {
      return;
    }
    records.add(StringRecord(v: doc, i: docIndex, n: _norm.get(doc)));
  }

  void _addObject(T doc, int docIndex) {
    final record = ObjectRecord(i: docIndex);

    for (var keyIndex = 0; keyIndex < keys.length; keyIndex += 1) {
      final key = keys[keyIndex];
      final value = key.getFn != null ? key.getFn!(doc) : _getFn(doc, key.path);

      if (value == null) {
        continue;
      }

      if (value is List) {
        final subRecords = <RecordValue>[];
        final stack = <_StackItem>[_StackItem(-1, value)];

        while (stack.isNotEmpty) {
          final item = stack.removeLast();
          final nestedArrIndex = item.nestedArrIndex;
          final stackValue = item.value;

          if (stackValue == null) {
            continue;
          }

          if (stackValue is String && !isBlank(stackValue)) {
            subRecords.add(
              RecordValue(
                v: stackValue,
                i: nestedArrIndex,
                n: _norm.get(stackValue),
              ),
            );
          } else if (stackValue is List) {
            for (var k = 0; k < stackValue.length; k += 1) {
              stack.add(_StackItem(k, stackValue[k]));
            }
          }
        }

        record.entries[keyIndex] = subRecords;
      } else if (value is String && !isBlank(value)) {
        record.entries[keyIndex] = RecordValue(v: value, n: _norm.get(value));
      }
    }

    records.add(record);
  }

  /// Serializes the index (keys and records) to JSON for later reuse via
  /// [parseFuseIndex].
  Map<String, dynamic> toJson() => {
        'keys': keys.map((k) => k.toJson()).toList(),
        'records': records.map((r) => r.toJson()).toList(),
      };
}

class _StackItem {
  _StackItem(this.nestedArrIndex, this.value);
  final int nestedArrIndex;
  final Object? value;
}

/// Builds and populates a [FuseIndex] for [docs] over [keys].
FuseIndex<T> createFuseIndex<T>(
  List<Object> keys,
  List<T> docs, {
  GetFunction<T>? getFn,
  double fieldNormWeight = 1,
}) {
  final index = FuseIndex<T>(getFn: getFn, fieldNormWeight: fieldNormWeight);
  index.setKeys(keys.map((k) => createKey<T>(k)).toList());
  index.setSources(docs);
  index.create();
  return index;
}

/// Rebuilds a [FuseIndex] from JSON [data] produced by [FuseIndex.toJson].
FuseIndex<T> parseFuseIndex<T>(
  Map<String, dynamic> data, {
  GetFunction<T>? getFn,
  double fieldNormWeight = 1,
}) {
  final index = FuseIndex<T>(getFn: getFn, fieldNormWeight: fieldNormWeight);

  final keys = (data['keys'] as List)
      .map((k) => IndexedKey<T>.fromJson((k as Map).cast<String, dynamic>()))
      .toList();
  index.setKeys(keys);

  final records = <FuseRecord>[];
  for (final raw in data['records'] as List) {
    final map = (raw as Map).cast<String, dynamic>();
    if (map.containsKey('v')) {
      records.add(
        StringRecord(
          v: map['v'] as String,
          i: map['i'] as int,
          n: (map['n'] as num).toDouble(),
        ),
      );
    } else {
      final entries = <int, Object>{};
      final dollar = (map['\$'] as Map).cast<String, dynamic>();
      dollar.forEach((keyIndex, value) {
        final idx = int.parse(keyIndex);
        if (value is List) {
          entries[idx] = value
              .map((v) =>
                  RecordValue.fromJson((v as Map).cast<String, dynamic>()))
              .toList();
        } else {
          entries[idx] =
              RecordValue.fromJson((value as Map).cast<String, dynamic>());
        }
      });
      records.add(ObjectRecord(i: map['i'] as int, entries: entries));
    }
  }
  index.setIndexRecords(records);

  return index;
}
