import '../helpers/get.dart';
import '../helpers/types.dart';
import 'key_store.dart';
import 'norm.dart';

class RecordValue {
  RecordValue({required this.v, required this.n, this.i});

  final String v;
  final double n;
  final int? i;

  Map<String, dynamic> toJson() => {
        'v': v,
        if (i != null) 'i': i,
        'n': n,
      };

  factory RecordValue.fromJson(Map<String, dynamic> json) => RecordValue(
        v: json['v'] as String,
        n: (json['n'] as num).toDouble(),
        i: json['i'] as int?,
      );
}

abstract class FuseRecord {
  FuseRecord(this.i);
  int i;
  Map<String, dynamic> toJson();
}

class StringRecord extends FuseRecord {
  StringRecord({required this.v, required int i, required this.n}) : super(i);

  final String v;
  final double n;

  @override
  Map<String, dynamic> toJson() => {'v': v, 'i': i, 'n': n};
}

class ObjectRecord extends FuseRecord {
  ObjectRecord({required int i, Map<int, Object>? entries})
      : entries = entries ?? {},
        super(i);

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

class FuseIndex<T> {
  FuseIndex({GetFunction<T>? getFn, double fieldNormWeight = 1})
      : _norm = Norm(weight: fieldNormWeight),
        _getFn = getFn ?? ((T obj, Object path) => get(obj, path));

  final Norm _norm;
  final GetFunction<T> _getFn;

  bool isCreated = false;
  List<T> docs = [];
  List<FuseRecord> records = [];
  List<IndexedKey<T>> keys = [];
  final Map<String, int> _keysMap = {};

  void setSources(List<T> docs) {
    this.docs = docs;
  }

  void setIndexRecords(List<FuseRecord> records) {
    this.records = records;
  }

  void setKeys(List<IndexedKey<T>> keys) {
    this.keys = keys;
    _keysMap.clear();
    for (var idx = 0; idx < keys.length; idx += 1) {
      _keysMap[keys[idx].id] = idx;
    }
  }

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

  void add(T doc) {
    final idx = size();
    if (doc is String) {
      _addString(doc, idx);
    } else {
      _addObject(doc, idx);
    }
  }

  void removeAt(int idx) {
    records.removeAt(idx);
    for (var i = idx, len = size(); i < len; i += 1) {
      records[i].i -= 1;
    }
  }

  Object? getValueForItemAtKeyId(Map<int, Object> item, String keyId) =>
      item[_keysMap[keyId]];

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
