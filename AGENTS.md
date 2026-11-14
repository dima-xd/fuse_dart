# AGENTS.md

Instructions for AI agents (and humans) working on **fuse_dart** — a pure
Dart port of [Fuse.js](https://github.com/krisk/Fuse).

fuse_dart targets **Fuse.js 7.5.0** with verified behavioral parity: the
upstream vitest suite runs byte-unmodified against the Dart engine through a
JS↔Dart bridge. Read this file before porting changes or bumping the target
version.

## Before committing

Run **`nix fmt`** at the repo root before every commit. It formats the
whole repo via treefmt (dart format for `.dart`, nixfmt for `.nix`,
prettier for everything else). Formatting is also enforced by the
`checks.formatting` check in `nix flake check`. The `conformance/`
submodule is excluded — it carries its own treefmt setup.

If you change formatting configuration (`treefmt.nix`, `flake.nix`),
keep the formatting run and the tooling change in separate commits so
diffs stay reviewable.

## Repository map

| Path | What it is |
| --- | --- |
| `lib/fuse_dart.dart` | Public export surface. Keep it aligned with Fuse.js's public API (see `README.md` § "API mapping"). |
| `lib/src/core/` | `fuse_base.dart` (the `Fuse` class — port of upstream `src/core/index.ts`), `config.dart` (`FuseOptions` + `Fuse.config` global), `compute_score.dart`, `format.dart`, `format_matches.dart`, `fuse_result.dart`, `query_parser.dart` (upstream `queryParser.ts`), `error_messages.dart` (must match upstream strings exactly). |
| `lib/src/search/` | `bitap/` (`search.dart` = upstream bitap core, `bitap_search.dart` = the Searcher wrapper with chunking), `extended/` (extended-search matchers + `ExtendedSearch`), `token/` (`analyzer.dart`, `inverted_index.dart`, `token_search.dart`), `register.dart` (upstream `core/register.ts`), `searcher.dart` (`SearchResult` / `Searcher` interface). |
| `lib/src/tools/` | `fuse_index.dart` (upstream `FuseIndex.ts` incl. `createIndex`/`parseIndex`), `key_store.dart` (upstream `KeyStore.ts`), `field_norm.dart` (upstream `fieldNorm.ts`), `max_heap.dart` (upstream `MaxHeap.ts`). |
| `lib/src/helpers/` | `get.dart` (upstream `helpers/get.ts`), `types.dart` (`isDefined`, `epsilon`, `FuseException`), `diacritics.dart` (NFD via `unorm_dart` + non-decomposable map), `merge_indices.dart`. |
| `tool/bridge/` | The conformance bridge server (`server.dart`) and its synchronous stdio (`sync_io.dart`). |
| `tool/smoke.dart` | Manual smoke test of all major code paths. |
| `conformance/` | The shared conformance harness (git submodule; see below). |
| `test/` | Dart-only tests: `test/dart/` (engine edges JS tests can't reach) and `test/bridge/` (bridge protocol, pure Dart). |
| `example/` | Terminal port of the fusejs.io demo. |
| `benchmark/` | Perf suite + experiment log (`EXPERIMENTS.md`). |

Upstream reference: the pinned `Fuse/` submodule inside `conformance/`
carries the upstream repo at the pinned tag — sources, dist builds, and
tests. The dist builds come from the upstream **repo**, not the npm
package (npm's `fuse.basic.mjs` ships with feature gates enabled; the repo
build gates them, which is what the tests expect).

## The one rule of porting

**Behavioral parity is defined by the upstream test suite, not by intuition.**
When porting a change from Fuse.js:

1. Diff the upstream commit (`src/` changes + its new tests).
2. Port the source change into the mapped Dart file.
3. Run the unshimmed baseline, then the bridge run (both must be green —
   including any NEW upstream test files that arrive with the pin bump).
4. Never hand-edit anything inside `conformance/Fuse/` (tests, fixtures,
   snapshots, dist). If a vendored test fails, the Dart code is wrong.

### Version-bump procedure (e.g. targeting 7.6.0)

1. In `conformance/Fuse`, diff the upstream tag (`CHANGELOG.md` and `src/`
   changes + its new tests) against the previous pin.
2. Port every portable change (all of `src/` except Web-Worker infra —
   `FuseWorker` is JS-only and intentionally not ported).
3. Bump the submodule pin: `git -C conformance/Fuse fetch && git -C
   conformance/Fuse checkout vX.Y.Z && git add conformance` (the
   `__VERSION__` define reads `Fuse/package.json`). Check whether
   upstream's `vitest.config.ts`-level assumptions changed (new test
   files, renamed builds) before trusting the suite.
4. Update `Fuse.version` in `lib/src/core/fuse_base.dart` and the pubspec
   version (major bump if scoring/output shapes change — see 2.0.0 notes
   in `CHANGELOG.md`).
5. Run: unshimmed vitest → bridge vitest → `dart test` → `dart analyze lib
   tool test`. All green before committing.

## Conformance harness

The conformance harness is **shared** with other Fuse.js ports: it is
vendored here as the `conformance/` git submodule (pinned to
forgejo@forge.xela.codes:xela/fusejs-conformance.git; init recursively —
it carries its own pinned upstream `Fuse/` submodule — and run
`npm install` inside it once). It contains the upstream test suite
(pinned, unmodified), dist builds, shims, and the generalized bridge
client (`bridges.mjs` selects the server per `FUSE_BRIDGE` value). Run it
through the justfile, which exports `FUSE_REPO_ROOT` so the client can
find this repo.

```
conformance/                      (git submodule, pinned)
  Fuse/                           upstream Fuse.js submodule, pinned; never modified
  dist → Fuse/dist, src → Fuse/src
  bridges.mjs                     bridge registry (dart/go spawn commands)
  dist/fuse.mjs, fuse.basic.mjs   upstream repo builds (baseline engine, via the symlink)
  src/core/errorMessages.ts       upstream: tests import error strings
  src/search/token/analyzer.ts    upstream: tokenizer tests import it directly
  src/helpers/diacritics.ts       upstream dep of analyzer.ts
  test/                           this repo's own additions only (bridge shims)
  Fuse/test/                      upstream vitest suite, byte-unmodified
  test/bridge/                    JS-side bridge shims (see below)
  vitest.config.ts                mode-gated import aliases
```

JS-only test files are excluded in both modes (Web Workers / CJS / TS
typings): `fuse-worker`, `workers`, `worker-url`, `cjs-interop`,
`internals`, `package-types`, `typings`. Everything else must pass in both
modes — currently 304/304.

Run from `conformance/`:

```bash
npx vitest run                   # baseline: real Fuse.js
FUSE_BRIDGE=dart npx vitest run  # fuse_dart through the bridge
```

Bridge mode additionally runs `harness/harness.test.js` — JS-only tests for
the harness infrastructure itself (not part of the vendored suite): server
lifecycle and leak regressions (clean `dispose()`, PDEATHSIG reaping a
SIGKILLed client, watchdog fail-fast on a server that cannot start), and
shim-fidelity regressions (by-reference docs arrays, search-result item
identity, searcher cache identity, BigInt round trips, explicit-undefined
option values, callback round trips, `Fuse.use` plugins, upstream error
messages). If you change the bridge protocol or client, `just harness`
must stay green.

## Bridge protocol

`tool/bridge/server.dart` is a **synchronous** JSON-line stdio server; the JS
client (`conformance/test/bridge/protocol.mjs`) speaks the same protocol.
It must stay synchronous because Dart `sortFn`/`getFn`/`tokenize` closures
are synchronous and the tests are synchronous — Dart async stdout buffers
writes until the event loop runs, which deadlocks mid-op callback round
trips. That's why `sync_io.dart` uses libc `read`/`write` via FFI on fds
0/1 (requires the `ffi` dev dependency), and why the JS side communicates
over mkfifo'd FIFOs (Node's child-process pipes are O_NONBLOCK, so
`fs.readSync` would return EAGAIN instead of blocking).

Frame shapes:

- Request (JS→Dart): one JSON line `{"op": "<op>", ...}`.
- Response (Dart→JS): exactly one `{"type":"result","value":...}` or
  `{"type":"error","message":...}` per request.
- Mid-op callback (Dart→JS): `{"type":"call","ref","callId","args"}` — JS
  must reply `{"type":"ret","callId","value"}` (or `callerr`) before
  anything else. The Dart side blocks until it arrives.
- `{"type":"warn","message"}` routes to `console.warn` (dev-mode tests).
- Startup: the server emits `{"type":"ready"}`; both clients skip it.

Ops: `new` (per-session Fuse; `build: 'full'|'basic'` — basic emulates the
gated dist build by throwing `*_UNAVAILABLE` and clearing the flags),
`setCollection`, `add`, `remove`, `removeAt`, `search`, `match`,
`createIndex`, `parseIndex`, `indexToJSON`, `indexRemoveAt`,
`indexRemoveAll`, `getIndexRecords`, `getIndexKeys`, `getIndexSize`,
`getIndex`, `getInvertedIndex`, `getInternal` (`lastQuery`/`lastSearcher`),
`use` (Fuse.use plugins), `analyzer`, `tokenize`, `parseQuery`.

### Value codec

JSON can't carry everything the tests push through, so values are tagged
with a `$t` discriminator (encode in `protocol.mjs` `encode`, decode in
`server.dart` `decodeValue`/`encodeValue` — keep them symmetric):

- `{"$t":"bigint","v":"<decimal>"}` — BigInt.
- `{"$t":"undef"}` — JS `undefined` (distinct from `null`; decoded to
  `jsUndefined` in Dart and excluded by `isDefined`). Option decoding
  strips tagged-undef values (JS `{...defaults}` spreads carry explicit
  undefined = "absent").
- `{"$t":"fn","ref":"fnN"}` — JS callback registry reference; the Dart side
  calls back with `call` frames (sortFn args are `{idx,item,score,matches?}`).
- `{"$t":"regexp","source","flags"}` — RegExp; Dart emulates the JS `g`
  flag (allMatches vs firstMatch).
- `{"$t":"index","ref":N}` / `{"$t":"searcher","ref":N}` / `{"$t":"plugin",
  "ref":"pN"}` — handles. Searcher handles decode to **stable marker
  objects** on the JS side so `toBe(cached)` identity assertions hold.

### Result shapes (JS-side fidelity)

- Search results: `{item, refIndex, score?, matches?: [{indices, value,
  key?, refIndex?}]}` — omit null fields so `toBeUndefined` assertions
  hold. `item` is remapped on the JS side from a mirror of the caller's
  collection (indexed by `refIndex`) so object identity is preserved.
  Note: upstream keeps the caller's array **by reference** (`add` mutates
  it) — the shim must alias, not copy.
- Index records: string docs `{v, i, n}`; object docs `{i, $: {"<keyIdx>":
  {v, n, i?} | [...]}}`.
- parseQuery trees: leaves `{keyId, pattern}` (omit `searcher` when
  `auto: false`), operators `{children, operator}`.
- `key` in matches is `key.id` (the dotted path string).
- Scores are JSON doubles; they must round-trip exactly (they do).

### Bridge gotchas (learned the hard way)

- The JS client opens its FIFOs **O_RDWR**, so neither side ever sees EOF:
  a dead Dart process would hang `fs.readSync` forever, and conversely the
  Dart server would outlive the JS client (test runners kill workers
  without running `exit` handlers). Mitigations to keep in place:
  - the server emits a `ready` handshake at boot;
  - a **watchdog worker** (in `protocol.mjs`) polls the Dart pid and
    SIGTERMs the test process if it dies — it must kill **from the worker
    thread** (`process.kill(workerData.selfPid, ...)`), because the main
    thread is blocked inside `fs.readSync` and cannot run `postMessage`
    callbacks;
  - `kill(pid, 0)` **succeeds for zombies**, and the parent may be blocked
    and unable to reap the child — the watchdog therefore also checks the
    process state in `/proc/<pid>/stat` (Linux) and treats `Z` as dead;
  - the worker is created with `execArgv: []` — an eval'd worker inherits
    parent flags, and `--input-type=module` (from `node -e` or test
    runners) makes it parse the CJS watchdog source as ESM, where
    `require` is undefined and the worker dies silently;
  - the watchdog's timer must NOT be `unref()`ed — an unref'd timer drains
    the worker's event loop and it exits without ever polling;
  - `dispose()` must disarm the watchdog (`lifecycle.disposed` flag +
    `watchdog.terminate()`) before killing the server, or the watchdog
    treats a deliberate shutdown as a crash;
  - the server calls `prctl(PR_SET_PDEATHSIG, SIGTERM)` at startup so the
    kernel reaps it when its parent dies.
  All of these are regression-tested by the harness suite (`just harness`);
  check for orphaned `server.dart` processes if you touch this area.
- `dart run` spawns a wrapper process; spawn `dart tool/bridge/server.dart`
  directly (cwd = repo root) so liveness polling tracks the real process.
- `fileParallelism: false` + sequential execution in bridge mode: one Dart
  process serves every test file (each vitest worker gets its own process,
  fine — state must not leak between sessions; only `Fuse.use` plugins are
  intentionally global, matching upstream's module-global registry).

## Dart-side tests

- `test/dart/` — edges the JS suite can't reach: UTF-16 code-unit indexing
  (surrogate pairs count as 2), the 32-bit pattern alphabet and MAX_BITS
  chunking, tokenizer unicode equivalence beyond the vendored tests.
- `test/bridge/` — drives `server.dart` directly over stdio (ops, callback
  round trips, BigInt codec, error frames) without needing Node.
- When you change the protocol or codec, update **both** the JS client and
  these tests.

## Cross-language benchmarks

`just bench-compare` times **native** fuse_dart (AOT) against **native**
Fuse.js 7.5.0 (`conformance/dist/fuse.mjs`) — never through the bridge,
which would measure IPC, not the libraries.

- The shared machinery (compare driver, per-language registry, JS
  perf-suite twin) lives in the conformance repo's `benchmark/`;
  fuse_dart keeps only its native suite, `benchmark/perf_suite.dart`.
  The Go port has a twin suite with the same dataset generator. Default
  dataset sizes are 1k / 10k / 100k docs (`--size` overrides).
- `perf_suite.dart` and the JS twin are workload-identical: same
  workloads, same dataset generator, same methodology (median of
  `--samples` after `--warmup` untimed runs). If you add or change a
  workload or the dataset, update **both** files; the driver asserts
  dataset parity (identical order-insensitive canonical JSON from
  `--dump-dataset`) before trusting any timings.
- Memory: the driver's memory pass runs each suite with `--workload`
  (one fresh process per workload) and reports the peak incremental RSS
  per workload. Dart has no way to force a GC, so its column is a
  garbage-inclusive upper bound; go/js report post-GC retained state.
  `--no-mem` skips the pass.
- The Dart binary is AOT-compiled and cached in `.dart_tool/fuse_bench/`;
  it rebuilds automatically when `lib/` or `benchmark/` sources change.
  `--jit` compares JIT Dart instead (ignored for go/js). `--json` emits
  machine-readable output.
- The conformance repo's `just bench` runs all three implementations
  together (default: every detectable language + js) and reports each
  language's geomean vs Fuse.js; `--langs dart,go` selects a subset.

## Conventions

- **Use the justfile**: `just check` (analyze + dart tests + baseline +
  bridge conformance) before committing; `just harness` for bridge
  infrastructure tests; `just --list` for everything else.
- Never modify files inside `conformance/Fuse/` (upstream suite, dist
  builds) — they change only via the pin-bump procedure.
- Upstream strings (error messages, warning texts) must match **exactly** —
  tests match on substrings of them.
- Prefer porting structure 1:1 from upstream files; keep file names mapped
  (see table above) so future diffs apply cleanly.
- Dart-side naming follows Dart style (`toJson` not `toJSON`, named
  parameters for options); the README's API-mapping table is the contract
  for JS-doc readers.
- `dart analyze lib tool test` must stay at 0 issues; formatting runs
  through `nix fmt` (treefmt: dart format + prettier + nixfmt) before
  committing — see "Before committing" above.
- The `unorm_dart` dependency exists for full Unicode NFD in
  `ignoreDiacritics` and the non-decomposable map (ł, ß, ø, đ, ħ, ŧ, ı).
- flixur integration (future): the Go port (`~/Documents/fusego`) reuses the
  shared bridge protocol so golden outputs are shared across Dart/Go/JS.
