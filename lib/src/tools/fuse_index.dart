import '../core/error_messages.dart';
import '../core/config.dart' show globalFuseConfig;
import '../helpers/get.dart';
import '../helpers/types.dart';
import 'field_norm.dart';
import 'key_store.dart';

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
      : _norm = FieldNorm(weight: fieldNormWeight),
        _getFn = getFn ?? ((T obj, Object path) => get(obj, path));

  final FieldNorm _norm;
  final GetFunction<T> _getFn;

  /// Whether [create] has already run.
  bool isCreated = false;

  /// The source documents.
  List<T> docs = [];

  /// The indexed records.
  List<FuseRecord> records = [];

  /// The indexed keys. Weights are the raw user values; scoring must resolve
  /// them through [KeyStore], which normalizes them to sum to 1.
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

    final len = docs.length;
    final built = <FuseRecord>[];

    // List is Array<String>
    if (docs.first is String) {
      for (var i = 0; i < len; i++) {
        final record = _createStringRecord(docs[i] as String, i);
        if (record != null) {
          built.add(record);
        }
      }
    } else {
      // List is Array<Object>
      for (var i = 0; i < len; i++) {
        built.add(_createObjectRecord(docs[i], i));
      }
    }

    records = built;
    _norm.clear();
  }

  /// Appends a record for [doc] at [docIndex] (the doc's position in the
  /// source array). Returns the appended record, or `null` when [doc] is a
  /// blank string (those are skipped at record creation). Callers use the
  /// return value to gate downstream bookkeeping like the inverted index.
  FuseRecord? add(T doc, int docIndex) {
    if (docIndex < 0) {
      throw FuseException(invalidDocIndex);
    }

    if (doc is String) {
      final record = _createStringRecord(doc, docIndex);
      if (record != null) {
        records.add(record);
      }
      return record;
    }

    final record = _createObjectRecord(doc, docIndex);
    records.add(record);
    return record;
  }

  /// Removes the record for the doc at the specified source-array (docs)
  /// index. Blank string docs have no record; callers may pass such an index
  /// and the splice is a no-op, but subsequent records still need their `.i`
  /// decremented to track the docs array the caller is splicing in parallel.
  void removeAt(int idx) {
    if (idx < 0) {
      throw FuseException(invalidDocIndex);
    }

    // Find and remove the record at this doc-index, if one exists. Records
    // are typically sorted by .i but the algorithm doesn't depend on it —
    // parsed indexes via setIndexRecords may arrive in arbitrary order.
    for (var i = 0; i < records.length; i += 1) {
      if (records[i].i == idx) {
        records.removeAt(i);
        break;
      }
    }

    // Decrement every record whose source-array index is now stale.
    for (var i = 0; i < records.length; i += 1) {
      if (records[i].i > idx) {
        records[i].i -= 1;
      }
    }
  }

  /// Removes records for the docs at the specified source-array indices, then
  /// shifts every surviving record's `.i` down by the count of removed
  /// indices strictly less than it. Invalid entries (negative) in [indices]
  /// are dropped silently — removeAll's natural use case is "caller passed a
  /// list of matched doc indices".
  void removeAll(List<int> indices) {
    final toRemove = <int>{for (final v in indices) if (v >= 0) v};

    if (toRemove.isEmpty) {
      return;
    }

    records.removeWhere((r) => toRemove.contains(r.i));

    final sorted = toRemove.toList()..sort();
    for (final record in records) {
      // shift = count of removed indices strictly less than record.i
      var lo = 0;
      var hi = sorted.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (sorted[mid] < record.i) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      record.i -= lo;
    }
  }

  /// Returns the indexed value(s) for [keyId] within an object record's
  /// [item] entry map.
  Object? getValueForItemAtKeyId(Map<int, Object> item, String keyId) =>
      item[_keysMap[keyId]];

  /// The number of records in the index.
  int size() => records.length;

  StringRecord? _createStringRecord(String doc, int docIndex) {
    if (!isDefined(doc) || isBlank(doc)) {
      return null;
    }

    return StringRecord(v: doc, i: docIndex, n: _norm.get(doc));
  }

  ObjectRecord _createObjectRecord(T doc, int docIndex) {
    final record = ObjectRecord(i: docIndex);

    // Iterate over every key (i.e, path), and fetch the value at that key
    for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
      final key = keys[keyIndex];
      final value =
          key.getFn != null ? key.getFn!(doc) : _getFn(doc, key.path);

      if (!isDefined(value)) {
        continue;
      }

      if (value is List) {
        final subRecords = <RecordValue>[];

        for (var i = 0; i < value.length; i += 1) {
          final item = value[i];

          if (!isDefined(item)) {
            continue;
          }

          if (item is String) {
            // Custom getFn returning plain string array (backward compat)
            if (!isBlank(item)) {
              subRecords.add(
                RecordValue(v: item, i: i, n: _norm.get(item)),
              );
            }
          } else if (item is SubRecord && isDefined(item.v)) {
            // Default get() returns {v, i} objects with original array
            // indices
            final text = item.v is String ? item.v as String : toStringValue(item.v);
            if (!isBlank(text)) {
              subRecords.add(
                RecordValue(v: text, i: item.i, n: _norm.get(text)),
              );
            }
          }
        }

        record.entries[keyIndex] = subRecords;
      } else if (value is String && !isBlank(value)) {
        record.entries[keyIndex] =
            RecordValue(v: value, n: _norm.get(value));
      }
    }

    return record;
  }

  /// Serializes the index (keys and records) to JSON for later reuse via
  /// [parseFuseIndex].
  Map<String, dynamic> toJson() => {
        'keys': keys.map((k) => k.toJson()).toList(),
        'records': records.map((r) => r.toJson()).toList(),
      };
}

/// Builds and populates a [FuseIndex] for [docs] over [keys].
FuseIndex<T> createFuseIndex<T>(
  List<Object> keys,
  List<T> docs, {
  GetFunction<T>? getFn,
  double? fieldNormWeight,
}) {
  // Upstream reads live `Config` defaults at call time.
  // Safe for any T: the field's declared type is
  // `Object? Function(Object?, Object)`, a subtype of GetFunction<T> for
  // every T (T is always assignable to Object?).
  getFn ??= globalFuseConfig.getFn as GetFunction<T>;
  fieldNormWeight ??= globalFuseConfig.fieldNormWeight;
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
  double? fieldNormWeight,
}) {
  // Safe for any T: the field's declared type is
  // `Object? Function(Object?, Object)`, a subtype of GetFunction<T> for
  // every T (T is always assignable to Object?).
  getFn ??= globalFuseConfig.getFn as GetFunction<T>;
  fieldNormWeight ??= globalFuseConfig.fieldNormWeight;
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
