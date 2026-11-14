# fuse_dart

A pure Dart port of [Fuse.js](https://fusejs.io) — a lightweight fuzzy-search
library. This version targets **Fuse.js v7.5.0**: the Bitap approximate-
matching algorithm with identical scoring and ranking, weighted keys, nested
and array key paths, extended (Unix-like) search syntax, logical `$and`/`$or`
queries, **token (TF-IDF) search**, pluggable searchers via `Fuse.use`, and
`Fuse.match` / `Fuse.config`.

Parity is not approximate: the **unmodified upstream Fuse.js test suite**
(304 tests) runs against this library through a JS↔Dart bridge and passes
with the same scores, indices, and snapshots. See
[Conformance](#conformance-how-parity-is-verified).

The library runs everywhere Dart runs — Flutter (Android, iOS, web, desktop),
the Dart VM, and AOT-compiled binaries.

## Install

```yaml
dependencies:
  fuse_dart: ^2.0.0
```

```dart
import 'package:fuse_dart/fuse_dart.dart';
```

## Quick start

### A list of strings

```dart
final fuse = Fuse<String>(['Apple', 'Orange', 'Banana']);
final results = fuse.search('nan');
print(results.map((r) => r.item)); // (Banana, Orange)
```

### A list of objects (maps)

The default value accessor reads `Map` values by key path, so JSON-like data
works out of the box.

```dart
final books = <Map<String, dynamic>>[
  {'title': "Old Man's War", 'author': {'firstName': 'John', 'lastName': 'Scalzi'}},
  {'title': 'The Lock Artist', 'author': {'firstName': 'Steve', 'lastName': 'Hamilton'}},
];

final fuse = Fuse(
  books,
  options: FuseOptions<Map<String, dynamic>>(
    keys: ['title', 'author.firstName'],
    threshold: 0.3,
    includeScore: true,
    includeMatches: true,
  ),
);

for (final result in fuse.search('Stve')) {
  print('${result.item['title']}  score=${result.score}');
  for (final match in result.matches!) {
    print('  ${match.key} -> ${match.indices}'); // e.g. [[0, 4]]
  }
}
```

### Typed models

Dart has no runtime reflection on Flutter/web, so for your own classes
provide a `getFn` per key. Use `FuseKey<T>` so the accessor is strongly typed.

```dart
class Book {
  const Book(this.title, this.author);
  final String title;
  final String author;
}

final fuse = Fuse<Book>(
  books,
  options: FuseOptions<Book>(
    keys: [
      FuseKey<Book>(name: 'title', getFn: (b) => b.title),
      FuseKey<Book>(name: 'author', getFn: (b) => b.author),
    ],
  ),
);
```

## API mapping: Fuse.js → fuse_dart

Read the [Fuse.js docs](https://fusejs.io/api/options.html) and translate:

| Fuse.js | fuse_dart | Notes |
| --- | --- | --- |
| `new Fuse(list, options, index)` | `Fuse(list, options: ..., index: ...)` | options are named parameters |
| `fuse.search(query, { limit })` | `fuse.search(query, limit: n)` | default `-1` (no limit) |
| `fuse.add(doc)` | `fuse.add(doc)` | |
| `fuse.remove((doc, idx) => ...)` | `fuse.remove((doc, idx) => ...)` | returns removed docs |
| `fuse.removeAt(idx)` | `fuse.removeAt(idx)` | returns the removed doc |
| `fuse.setCollection(list, index?)` | `fuse.setCollection(list, index)` | |
| `fuse.getIndex()` | `fuse.getIndex()` | returns `FuseIndex` |
| `Fuse.version` | `Fuse.version` | `'7.5.0'` |
| `Fuse.config` | `Fuse.config` | global mutable defaults (snapshot per instance) |
| `Fuse.createIndex(keys, docs, options)` | `Fuse.createIndex(keys, docs, getFn: ..., fieldNormWeight: ...)` | |
| `Fuse.parseIndex(data, options)` | `Fuse.parseIndex(data, getFn: ..., fieldNormWeight: ...)` | |
| `Fuse.parseQuery(query, options, { auto })` | `Fuse.parseQuery(query, options, auto: false)` | |
| `Fuse.match(pattern, text, options)` | `Fuse.match(pattern, text, options)` | returns `SearchResult` |
| `Fuse.use(MySearcher)` | `Fuse.use([SearcherPlugin(condition: ..., create: ...)])` | Dart has no static methods on instances — see below |
| `index.records` / `index.keys` | `index.records` / `index.keys` | |
| `index.size()` / `index.toJSON()` | `index.size()` / `index.toJson()` | Dart naming |
| `{ item, refIndex, score, matches }` | `FuseResult<T>` with the same fields | |
| `{ indices, value, key, refIndex }` | `FuseResultMatch` with the same fields | |
| `(int start, int end)` | `List<int>` (`RangeTuple = List<int>`) | `[start, end]` |

### Custom searchers (`Fuse.use`)

In JS a plugin is a class with a static `condition` and a `searchIn` method.
Dart has no static polymorphism, so the same plugin is expressed as a
`SearcherPlugin` with two callbacks:

```dart
class AlwaysMatch {
  final String pattern;
  AlwaysMatch(this.pattern);
  SearchResult searchIn(String text) =>
      SearchResult(isMatch: true, score: 0.5, indices: [[0, 0]]);
}

Fuse.use([
  SearcherPlugin(
    condition: (pattern, options) => options.useAlwaysMatch == true,
    create: (pattern, options, invertedIndex) => AlwaysMatch(pattern),
  ),
]);
```

### `Fuse.config` (global defaults)

```dart
Fuse.config.threshold = 0.4;             // affects new instances only
final fuse = Fuse(books);                // snapshot taken at construction
```

Instances snapshot the config at construction — the exact JS semantics of
`{ ...Config, ...options }`.

## Options

Every [Fuse.js option](https://fusejs.io/api/options.html) is available with
the same name and default:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `isCaseSensitive` | `bool` | `false` | Case-sensitive comparison. |
| `ignoreDiacritics` | `bool` | `false` | Ignore accents. |
| `includeScore` | `bool` | `false` | Include a `score` in each result. |
| `includeMatches` | `bool` | `false` | Include match `indices` for highlighting. |
| `shouldSort` | `bool` | `true` | Sort by ascending score. |
| `sortFn` | `FuseSortFunction` | by score then index | Custom sort comparator. |
| `keys` | `List<Object>` | `[]` | Keys: `String`, `List<String>`, or `FuseKey`. |
| `findAllMatches` | `bool` | `false` | Keep scanning after a perfect match. |
| `minMatchCharLength` | `int` | `1` | Minimum matched-run length to report. |
| `location` | `int` | `0` | Approximate expected match position. |
| `threshold` | `double` | `0.6` | `0.0` perfect match, `1.0` matches anything. |
| `distance` | `int` | `100` | How far a match may stray from `location`. |
| `useExtendedSearch` | `bool` | `false` | Enable Unix-like search operators. |
| `useTokenSearch` | `bool` | `false` | Enable token search with TF-IDF ranking. |
| `tokenize` | `RegExp` / function | unicode-aware default | Tokenizer for token search. |
| `tokenMatch` | `'any'`/`'all'` | `'any'` | How multi-word token queries combine. |
| `getFn` | `GetFunction<T>` | `get` | Custom global value accessor `(obj, path)`. |
| `ignoreLocation` | `bool` | `false` | Ignore `location`/`distance`. |
| `ignoreFieldNorm` | `bool` | `false` | Ignore the field-length norm in scoring. |
| `fieldNormWeight` | `double` | `1` | Field-length norm strength. |

## Token search (new in 7.5.0 parity)

```dart
final fuse = Fuse<String>(
  ['red shirt', 'red hat', 'blue shirt'],
  options: FuseOptions<String>(
    useTokenSearch: true,
    tokenMatch: 'all', // every query word must match (AND); default 'any'
  ),
);
fuse.search('red shirt'); // matches ['red shirt']
```

The default tokenizer is unicode-aware (`/[\p{L}\p{M}\p{N}_]+/gu`): CJK,
Devanagari (combining marks), and NFD-decomposed Latin stay single tokens.
Pass a `RegExp` or a `(String) => List<String>` function via `tokenize`.

## Extended search

Enable with `useExtendedSearch: true`. Whitespace separates AND terms; `|`
separates OR groups. Quoted tokens (`="hello world"`) keep inner spaces.

| Token | Match type | Description |
| --- | --- | --- |
| `jscript` | fuzzy | Fuzzy match `jscript`. |
| `=scheme` | exact | Exactly `scheme`. |
| `'python` | include | Includes `python`. |
| `!ruby` | inverse-exact | Does not include `ruby`. |
| `^java` | prefix-exact | Starts with `java`. |
| `!^erlang` | inverse-prefix | Does not start with `erlang`. |
| `.js$` | suffix-exact | Ends with `.js`. |
| `!.go$` | inverse-suffix | Does not end with `.go`. |

```dart
final fuse = Fuse(items, options: FuseOptions(useExtendedSearch: true, keys: ['name']));
fuse.search("^core go\$ | rb\$ | py\$");
```

## Logical search

Pass a query map instead of a string:

```dart
fuse.search({
  r'$and': [
    {'title': 'old man'},
    {r'$or': [
      {'author.firstName': 'john'},
      {'author.lastName': 'scalzi'},
    ]},
  ],
});
```

Use `$path`/`$val` when a key name itself contains dots:

```dart
fuse.search({r'$path': ['author', 'first.name'], r'$val': 'jon'});
```

## Pre-built and serialized indexes

```dart
final index = Fuse.createIndex<Map<String, dynamic>>(['title', 'author.firstName'], books);
final fuse = Fuse(books, options: options, index: index);

final json = index.toJson();
final restored = Fuse.parseIndex<Map<String, dynamic>>(json);
```

## Demo

`example/demo.dart` is a terminal version of the [fusejs.io demo](https://fusejs.io/demo.html):
same 19-book corpus, same keys, and the same toggles (`threshold` slider,
`includeScore`, `includeMatches`, `ignoreLocation`, `useExtendedSearch`,
`useTokenSearch`), with score + highlighted matches per result.

```bash
dart run example/demo.dart                # interactive REPL
dart run example/demo.dart "old man"      # one-shot
dart run example/demo.dart "ste ham" --threshold=0.4 --useTokenSearch
```

## Conformance: how parity is verified

The upstream Fuse.js vitest suite is pinned **byte-unmodified** in the
conformance submodule's `Fuse/` submodule (`conformance/Fuse/test/`) and
runs twice:

- **Unshimmed** against the real Fuse.js 7.5.0 dist builds — validates the
  harness itself (baseline).
- **Bridged** (`FUSE_BRIDGE=dart`) — every Fuse API call is forwarded to a
  persistent Dart process (`tool/bridge/server.dart`) over a synchronous
  JSON-line stdio protocol; JS callbacks (`getFn`, `sortFn`, `tokenize`,
  `remove` predicates, `Fuse.use` plugins) round-trip mid-op, and BigInts
  cross the boundary through a tagged-value codec.

```bash
cd conformance
npx vitest run                     # real Fuse.js (baseline)
FUSE_BRIDGE=dart npx vitest run    # fuse_dart through the bridge
```

Both runs pass (304 upstream tests; bridge mode adds 14 harness tests that
guard the bridge infrastructure itself — process lifecycle, leak and
deadlock regressions, shim fidelity). The Dart-side unit tests (`dart test`)
cover Dart-specific edges (UTF-16 code-unit indexing, the 32-bit pattern
alphabet, tokenizer equivalence) and the bridge protocol itself. Run
everything with `just check`.

## Behavior and compatibility notes

- Scoring, ranking, and match indices match Fuse.js **v7.5.0**, including
  the 7.5.x fixes: field-norm word separators (#830), key-weight
  normalization (#833), limit tie-breaking via the MaxHeap top-N (#835),
  exact-match `minMatchCharLength` (#831), the highlight window fix (#792),
  and inverse-pattern ALL-keys aggregation (#712).
- Match `indices` are `List<int>` pairs `[start, end]` in **UTF-16 code
  units** — the same offsets JS string indexing uses, so they can be fed
  directly to `String.substring` / Flutter's `TextSpan`s.
- `ignoreDiacritics` uses full Unicode NFD normalization (via `unorm_dart`)
  plus explicit mappings for characters NFD cannot decompose (ł, ß, ø, đ,
  ħ, ŧ, ı).
- Like JS, `Fuse` keeps the caller's collection **by reference**: `add`
  mutates the list you passed in.

## Performance

The library avoids unnecessary allocations (cached field-length norms,
typed bit-mask rows, lazy match-mask computation). See `benchmark/`:

```bash
just bench           # Dart-only suite (perf_suite.dart)
just bench-compare   # native fuse_dart vs native Fuse.js, side by side
```

`bench-compare` times both libraries natively (never through the test
bridge) on **identical datasets** — the driver (shared with the Go port,
living in the conformance repo's `benchmark/`) asserts order-insensitive
canonical dataset parity between `perf_suite.dart` and the JS twin before
running. Each workload runs `--warmup` untimed runs, then the median of
`--samples` timed runs is reported. The Dart side is AOT-compiled
(`dart compile exe`, cached under `.dart_tool/fuse_bench/`, rebuilt
automatically when sources change); pass `--jit` to compare JIT Dart
instead.

Measured results (AMD Ryzen 5 5600H, Dart SDK 3.11 AOT, Node v24, Nov 2026;
absolute numbers vary by machine, ratios are representative):

| workload (10k docs) | fuse_dart (AOT) | Fuse.js 7.5.0 | dart/js |
| --- | --- | --- | --- |
| index_build | 8.5 ms | 11.7 ms | 1.4× |
| fuzzy_obj_hit | 44.6 ms | 137 ms | 3.1× |
| fuzzy_obj_miss | 22.1 ms | 78.3 ms | 3.5× |
| fuzzy_str_hit | 25.0 ms | 63.7 ms | 2.6× |
| extended | 6.1 ms | 9.1 ms | 1.5× |
| logical | 14.0 ms | 28.0 ms | 2.0× |
| include_matches | 50.6 ms | 109 ms | 2.2× |
| sorted_limit | 36.2 ms | 133 ms | 3.7× |

Geomean across all ten workloads: **2.25× faster** at 10k docs (~2.8× at
1k docs, ~2.1× at 100k docs — the 100k ratio swings with CPU frequency
across the long run). fuse_dart is never slower on any workload.

The shared driver also runs a per-workload **memory pass** (peak
incremental RSS, one fresh process per workload). Note the semantics:
go/js force a full GC before every read, so their columns approximate
retained footprint — Dart exposes no way to force a GC, so its column is
a peak-including-uncollected-garbage upper bound and can read low when
the VM reuses freed pages. All memory numbers are cross-port ballparks.

## Testing

```bash
dart test                          # Dart-only + bridge protocol tests
cd conformance && npx vitest run   # baseline
FUSE_BRIDGE=dart npx vitest run    # conformance through the bridge
```

## License

Apache License 2.0. This is a derivative work of Fuse.js
(Copyright Kiro Risk), which is also licensed under Apache 2.0.
