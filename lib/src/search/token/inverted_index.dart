import '../../tools/fuse_index.dart'
    show FuseRecord, StringRecord, ObjectRecord, RecordValue;
import 'analyzer.dart';

// Stats-only inverted index for token search.
//
// The query path consumes only `df` and `fieldCount` (IDF weighting). The
// per-doc maps exist solely to keep `df` and `fieldCount` correct under
// `add` / `remove` / `removeAt`:
//
//   docFieldCount[doc]    = # distinct fields the doc contributed; subtracted
//                           from `fieldCount` on remove.
//   docTermFieldHits[doc] = Map<term, # fields in which `term` appears for
//                           that doc>; each entry decrements `df[term]` by
//                           that count on remove.
//
// `df` is incremented once per (doc, term, field) at index time. Removing a
// doc decrements `df` by the same count, mirroring the increment exactly.
class InvertedIndexData {
  InvertedIndexData()
      : fieldCount = 0,
        df = {},
        docFieldCount = {},
        docTermFieldHits = {};

  int fieldCount;
  final Map<String, int> df;
  final Map<int, int> docFieldCount;
  final Map<int, Map<String, int>> docTermFieldHits;
}

void _addField(InvertedIndexData index, String text, int docIdx, Analyzer analyzer) {
  final tokens = analyzer.tokenize(text);
  if (tokens.isEmpty) return;

  index.fieldCount++;
  index.docFieldCount[docIdx] = (index.docFieldCount[docIdx] ?? 0) + 1;

  // We count each (doc, term, field) once — repeated occurrences within the
  // same field don't multiply df.
  final distinctTerms = tokens.toSet();

  var perDocTerms = index.docTermFieldHits[docIdx];
  if (perDocTerms == null) {
    perDocTerms = {};
    index.docTermFieldHits[docIdx] = perDocTerms;
  }

  for (final term in distinctTerms) {
    perDocTerms[term] = (perDocTerms[term] ?? 0) + 1;
    index.df[term] = (index.df[term] ?? 0) + 1;
  }
}

void _ingestRecord(
  InvertedIndexData index,
  FuseRecord record,
  int keyCount,
  Analyzer analyzer,
) {
  final docIdx = record.i;

  if (record is StringRecord) {
    _addField(index, record.v, docIdx, analyzer);
    return;
  }

  if (record is! ObjectRecord) return;

  for (var keyIdx = 0; keyIdx < keyCount; keyIdx++) {
    final value = record.entries[keyIdx];
    if (value == null) continue;

    if (value is List<RecordValue>) {
      for (final sub in value) {
        _addField(index, sub.v, docIdx, analyzer);
      }
    } else if (value is RecordValue) {
      _addField(index, value.v, docIdx, analyzer);
    }
  }
}

InvertedIndexData buildInvertedIndex(
  List<FuseRecord> records,
  int keyCount,
  Analyzer analyzer,
) {
  final index = InvertedIndexData();

  for (final record in records) {
    _ingestRecord(index, record, keyCount, analyzer);
  }

  return index;
}

void addToInvertedIndex(
  InvertedIndexData index,
  FuseRecord record,
  int keyCount,
  Analyzer analyzer,
) {
  _ingestRecord(index, record, keyCount, analyzer);
}

void removeFromInvertedIndex(InvertedIndexData index, int docIdx) {
  final fieldCount = index.docFieldCount[docIdx];
  if (fieldCount == null) return;

  index.fieldCount -= fieldCount;
  index.docFieldCount.remove(docIdx);

  final perDocTerms = index.docTermFieldHits[docIdx];
  if (perDocTerms == null) return;

  perDocTerms.forEach((term, hits) {
    final next = (index.df[term] ?? 0) - hits;
    if (next <= 0) {
      index.df.remove(term);
    } else {
      index.df[term] = next;
    }
  });
  index.docTermFieldHits.remove(docIdx);
}

/// Removes the given docIdx entries and renumbers the remaining per-doc maps
/// so they stay in sync with FuseIndex's contiguous renumbering on remove.
void removeAndShiftInvertedIndex(
  InvertedIndexData index,
  List<int> removedIndices,
) {
  if (removedIndices.isEmpty) return;

  // De-dup and sort so the shift computation is O(log k) per lookup.
  final sorted = removedIndices.toSet().toList()..sort();

  for (final idx in sorted) {
    removeFromInvertedIndex(index, idx);
  }

  // For any surviving oldIdx, its new idx is oldIdx minus the number of
  // removed indices strictly less than oldIdx.
  int shift(int oldIdx) {
    var lo = 0;
    var hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >>> 1;
      if (sorted[mid] < oldIdx) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return oldIdx - lo;
  }

  final firstRemoved = sorted[0];

  final shiftedDocFieldCount = <int, int>{};
  index.docFieldCount.forEach((oldKey, count) {
    shiftedDocFieldCount[oldKey > firstRemoved ? shift(oldKey) : oldKey] = count;
  });
  index.docFieldCount
    ..clear()
    ..addAll(shiftedDocFieldCount);

  final shiftedDocTermFieldHits = <int, Map<String, int>>{};
  index.docTermFieldHits.forEach((oldKey, terms) {
    shiftedDocTermFieldHits[oldKey > firstRemoved ? shift(oldKey) : oldKey] =
        terms;
  });
  index.docTermFieldHits
    ..clear()
    ..addAll(shiftedDocTermFieldHits);
}
