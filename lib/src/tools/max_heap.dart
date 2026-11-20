import '../core/results.dart';

/// Comparator over internal results; negative means `a` sorts before `b`.
typedef ResultComparator<T> = int Function(
  InternalResult<T> a,
  InternalResult<T> b,
);

/// Max-heap by the sort comparator: keeps the worst result (the one that
/// sorts last) at the root so we can evict it when a better result arrives.
/// Ordering by the comparator instead of the raw score keeps the retained
/// top-N identical to a full sort followed by a slice, including the
/// tie-break and a custom sortFn.
class MaxHeap<T> {
  MaxHeap(this.limit, this.comparator);

  final int limit;
  final ResultComparator<T> comparator;
  final List<InternalResult<T>> heap = [];

  int get size => heap.length;

  /// Insert while keeping at most [limit] items: fill until full, then
  /// replace the root only when the incoming item sorts ahead of it. The
  /// guard makes a separate shouldInsert() check redundant.
  void insert(InternalResult<T> item) {
    if (size < limit) {
      heap.add(item);
      _bubbleUp(size - 1);
    } else if (comparator(item, heap[0]) < 0) {
      heap[0] = item;
      _sinkDown(0);
    }
  }

  List<InternalResult<T>> extractSorted() {
    heap.sort(comparator);
    return heap;
  }

  void _bubbleUp(int i) {
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (comparator(heap[i], heap[parent]) <= 0) break;
      final tmp = heap[i];
      heap[i] = heap[parent];
      heap[parent] = tmp;
      i = parent;
    }
  }

  void _sinkDown(int i) {
    final len = heap.length;
    var largest = i;
    do {
      i = largest;
      final left = 2 * i + 1;
      final right = 2 * i + 2;
      if (left < len && comparator(heap[left], heap[largest]) > 0) {
        largest = left;
      }
      if (right < len && comparator(heap[right], heap[largest]) > 0) {
        largest = right;
      }
      if (largest != i) {
        final tmp = heap[i];
        heap[i] = heap[largest];
        heap[largest] = tmp;
      }
    } while (largest != i);
  }
}
