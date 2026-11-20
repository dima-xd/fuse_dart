/// A pure Dart port of [Fuse.js](https://fusejs.io), a lightweight
/// fuzzy-search library.
///
/// Create a [Fuse] over a list of strings or objects, then call
/// [Fuse.search]. Searching supports approximate (Bitap) matching, weighted
/// keys, nested key paths, extended (unix-like) search syntax, logical
/// `$and`/`$or` queries, and token (TF-IDF) search.
///
/// ```dart
/// final fuse = Fuse<String>(['Apple', 'Orange', 'Banana']);
/// final results = fuse.search('aple');
/// print(results.first.item); // Apple
/// ```
library;

export 'src/core/config.dart'
    show
        FuseOptions,
        FuseConfig,
        FuseKey,
        KeyGetFunction,
        TokenizeFunction,
        FuseSortFunction,
        FuseSortFunctionArg,
        FuseSortFunctionMatch,
        defaultSortFn;
export 'src/core/fuse_base.dart' show Fuse;
export 'src/core/fuse_result.dart' show FuseResult, FuseResultMatch, RangeTuple;
export 'src/core/query_parser.dart'
    show LogicalNode, LogicalLeaf, LogicalExpression;
export 'src/helpers/get.dart' show get, GetFunction, SubRecord;
export 'src/search/register.dart' show SearcherPlugin, registerSearchers;
export 'src/search/searcher.dart' show SearchResult;
export 'src/search/token/analyzer.dart' show Analyzer, createAnalyzer;
export 'src/tools/fuse_index.dart'
    show
        FuseIndex,
        FuseRecord,
        StringRecord,
        ObjectRecord,
        RecordValue,
        createFuseIndex,
        parseFuseIndex;
export 'src/tools/max_heap.dart' show MaxHeap;
