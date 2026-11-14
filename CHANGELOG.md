# Changelog

## 2.0.0

Full behavioral parity with **Fuse.js 7.5.0**, verified by running the
unmodified upstream Fuse.js test suite (304 tests) against the Dart engine
through a JS↔Dart bridge (`conformance/`). This is a breaking release:
scoring, ranking, and several result shapes changed as part of adopting the
7.5.x behavior changes.

Ported 7.1.0 → 7.5.0 upstream changes:

- Field-length norm counts words by common word separators (#830).
- Key weights are normalized (`KeyStore`) so relative weights sum to 1;
  `FuseIndex.keys` carries raw user weights (#833).
- `limit` returns the same top-N as an unlimited search via a comparator-
  ordered MaxHeap, with a canonical idx tie-break (#835).
- Bitap exact matches honor `minMatchCharLength` (#831), and match indices
  are restricted to the actual matched window instead of bleeding across
  the scan range (#792).
- Extended search supports quoted multi-match tokens (`="hello world"`),
  escaped pipes (`\|`), and inverse-pattern ALL-keys aggregation (#712).
- Index bookkeeping rewritten: `add(doc, docIndex)` returns the appended
  record (or `null` for blank strings), `removeAt`/`removeAll` shift
  doc indices, blank documents are skipped at record creation, and
  `removeAt` validates atomically.
- `get` handles `null` returns and BigInt values; BigInt docs are searchable.
- New in 7.5.0: token search (TF-IDF with `tokenMatch: 'any'`/`'all'` and a
  unicode-aware default tokenizer), `Fuse.match`, `Fuse.use` (pluggable
  searchers), `Fuse.parseQuery`, searcher caching with invalidation, and
  `Fuse.config` global defaults.

API changes vs 1.x:

- Match indices are `List<int>` pairs `[start, end]` (UTF-16 code units),
  not `(int, int)` records.
- `FuseOptions` fields resolve against a global mutable `Fuse.config`
  (snapshot at construction, matching JS `{...Config, ...options}`).
- `Fuse.search` is generic over the document type and returns
  `FuseResult<T>` objects with `item`, `refIndex`, `score?`, `matches?`.
- `Fuse.use` takes `SearcherPlugin` records (condition + factory callbacks)
  instead of JS-style classes.
- pubspec version bumped to 2.0.0.

New development infrastructure (see `AGENTS.md`):

- `conformance/`: vendored upstream vitest suite running byte-unmodified in
  two modes — against the real Fuse.js 7.5.0 dist builds (baseline) and
  through a synchronous JSON-line bridge to the Dart engine
  (`FUSE_BRIDGE=dart`). Both pass 304/304. JS-only tests (Web Workers, CJS,
  TS typings) are excluded by design.
- `tool/bridge/`: the synchronous stdio bridge server (libc FFI IO; mid-op
  callback round trips for getFn/sortFn/tokenize/remove/plugins; tagged
  BigInt/RegExp/undefined codec).
- `test/dart/`: Dart-only tests for UTF-16 code-unit indexing, the 32-bit
  pattern alphabet / MAX_BITS chunking, and tokenizer unicode equivalence.
- `test/bridge/`: pure-Dart tests of the bridge protocol.
- `example/demo.dart`: terminal version of the fusejs.io demo (same data,
  toggles, scores, and highlight ranges).
- `unorm_dart` dependency for full Unicode NFD in `ignoreDiacritics`,
  replacing the Latin-only implementation; adds explicit mappings for
  characters NFD cannot decompose (ł, Ł, ß, ø, Ø, đ, Ħ, ħ, ŧ, Ŧ, ı).
- Removed the old hand-ported 1.x test suite and ported-test artifacts
  (`norm.dart`, `create_searcher.dart`); `benchmark/golden.dart` updated for
  the new result shapes.
- `conformance/harness/harness.test.js`: JS-only tests guarding the bridge
  infrastructure itself (14 tests, bridge mode only) — process lifecycle and
  leak regressions, watchdog fail-fast on a server that cannot start, and
  shim-fidelity regressions (by-reference docs, item identity, searcher
  cache identity, BigInt, explicit-undefined options, callbacks, plugins).
- Cross-language benchmarks: native fuse_dart vs native Fuse.js 7.5.0
  (`just bench-compare`), asserting identical dataset generation on both
  sides and timing the libraries natively — fuse_dart AOT is ~2.25× faster
  (geomean, 10k docs), never slower on any workload. `justfile` added.
  The driver now also runs a per-workload peak-RSS memory pass (fresh
  process per workload; Dart's column is a garbage-inclusive upper bound
  since Dart cannot force a GC) and defaults to 1k/10k/100k dataset
  sizes.
  (The shared driver and JS twin now live in the conformance repo's
  `benchmark/`, used by all Fuse.js ports; this repo keeps only
  `benchmark/perf_suite.dart`.)

## 1.0.2

- Speed up fuzzy matching by several times: the Bitap kernel now uses a flat
  code-unit lookup table and typed bit-mask rows instead of per-character
  strings and maps.
- Speed up index construction by several times with direct token counting and
  an allocation-free scalar path lookup.
- Add `benchmark/perf_suite.dart` and `benchmark/golden.dart` for repeatable
  performance and behaviour comparisons; results are in
  `benchmark/EXPERIMENTS.md`.

## 1.0.1

- Add dartdoc comments across the entire public API (100% coverage).
- Add pub.dev `topics` and bump `lints` to `^6.0.0`.

## 1.0.0

- Initial release: a pure Dart port of Fuse.js v7.1.0.
- Bitap fuzzy matching with Fuse.js-compatible scoring and ranking.
- Weighted keys, nested key paths, and array-of-strings/objects search.
- Extended search syntax (`'`, `=`, `^`, `$`, `!`, `|`).
- Logical queries (`$and`, `$or`, `$path`, `$val`).
- `includeScore` and `includeMatches` with `(int, int)` match indices.
- Pre-built and serializable indexes via `createIndex`/`parseIndex`.
- Configurable threshold, distance, location, diacritics handling, and
  field-length norm options.
- Ported Fuse.js test suite verified against reference snapshots.
- Benchmark suite under `benchmark/`.
