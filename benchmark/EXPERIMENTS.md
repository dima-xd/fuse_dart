# Experiment log — fuse_dart

One row per hypothesis, appended in order. Numbers come from AOT builds of
`benchmark/perf_suite.dart`, measured with the interleaved A/B driver from the
opticoder skill (7 runs per side, 2 measured samples per process, 1 warmup).

## Environment

| Field | Value |
| --- | --- |
| Date | 2026-10-30 |
| Machine / CPU | AMD Ryzen 5 5600H, 6 cores |
| OS | Windows 10.0.26200 (x64) |
| Toolchain | Dart SDK 3.11.5, `dart compile exe` (AOT) |
| Workload | `benchmark/perf_suite.dart --size 10000` (dataset from `generateDataset`) |
| Metric | median wall time of the whole process / in-process workload median |

The per-process A/B timings include dataset generation, index construction and
process start-up, so they *understate* the gains of the individual in-process
workloads. Both columns are reported below.

## Experiments

| # | Hypothesis | Diff | Correctness | Baseline | Result | Decision |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | String-keyed alphabet + `String[]` char access dominate Bitap | `search.dart`, `bitap_search.dart` | golden byte-identical, 92/92 tests | fuzzy hit 0.817 s | 0.306 s (−62.6%) | accepted |
| 2 | Default sort wastes time on per-result objects | `fuse_base.dart` | golden ok | sorted_limit 0.402 s | 0.404 s (−0.4%) | rejected |
| 3 | Reusing two row buffers avoids allocations | `search.dart` | golden ok | fuzzy hit 0.323 s | 0.366 s (−13.4%) | rejected |
| 4 | Splitting the out-of-text tail removes a branch | `search.dart` | golden ok | fuzzy hit 0.332 s | 0.341 s (−2.8%) | rejected |
| 5 | Removing per-record result/list allocations | `search.dart`, `fuse_base.dart` | golden ok | fuzzy hit 0.225 s | 0.226 s (−0.5%) | rejected |
| 6 | `RegExp` token counting dominates index build | `norm.dart` | golden ok, 92/92 | index 0.318 s | 0.155 s (−51.3%) | accepted |
| 7 | Path traversal allocates a list + closure per field | `get.dart` | golden ok, 92/92 | index 0.187 s | 0.158 s (−15.6%) | accepted |
| 8 | Inlining `computeScore` in the hot loops | `search.dart` | golden ok | fuzzy hit 0.222 s | 0.236 s (−6.5%) | rejected |

## Notes per experiment

### 1 — Bitap kernel (accepted)

- **Hypothesis:** the inner loop is dominated by allocating one-character
  strings and hashing them in `Map<String, int>`, plus boxed `List<int>` rows.
- **Change:** pattern alphabet is a flat `Uint32List` indexed by UTF-16 code
  unit; text is read with `codeUnitAt`; bit rows are `Uint32List`; mask rows
  are `Uint8List`; array division replaced by a shift.
- **Correctness:** `golden.dart` byte-identical over 30 configurations
  (fuzzy, extended, logical, weighted keys, `includeMatches`, diacritics,
  case-sensitive, `ignoreLocation`, limits), plus 30,000 randomized
  differential kernel cases (patterns up to 32 code units, random
  location/distance/threshold/options) identical to the baseline. 92/92 tests.
- **Measurements (A vs B, process median):**

  | Workload | A | B | Gain |
  | --- | --- | --- | --- |
  | fuzzy_obj_hit | 0.817 s | 0.306 s | 62.6% |
  | fuzzy_obj_miss | 0.566 s | 0.249 s | 56.0% |
  | fuzzy_obj_short | 0.418 s | 0.272 s | 34.8% |
  | fuzzy_str_hit | 0.599 s | 0.318 s | 46.9% |
  | include_matches | 0.750 s | 0.314 s | 58.1% |
  | sorted_limit | 0.894 s | 0.319 s | 64.3% |
  | logical | 0.292 s | 0.216 s | 26.1% |
  | extended | 0.189 s | 0.184 s | 3.0% |

- **Decision:** accepted; all fuzzy workloads beat the 2% threshold with
  non-overlapping 95% CIs. `index_build` was unchanged (−3.8%, rejected as
  noise; no index code was touched).

### 2 — Default-sort fast path (rejected)

- **Hypothesis:** building `FuseSortFunctionArg` + a match list per result is a
  measurable part of sorting.
- **Result:** sorted_limit −0.4%, fuzzy hit +1.2% (CI overlap), include_matches
  +8.3% but overlapping CIs.
- **Decision:** rejected — below threshold / statistical tie. Reverted.

### 3 — Two reusable row buffers (rejected)

- **Hypothesis:** 11 typed-array allocations per record dominate.
- **Result:** 8.8–20.7% slower. Sized fresh rows let the compiler eliminate
  bounds checks; a shared buffer does not.
- **Decision:** rejected. Reverted.

### 4 — Out-of-text tail specialization (rejected)

- **Hypothesis:** positions past `text.length` always have a zero character
  mask, so a separate loop can drop work and a branch.
- **Result:** 2.8–22.7% slower (bounds checks no longer provable).
- **Decision:** rejected. Reverted.

### 5 — Per-record allocation removal (rejected)

- **Hypothesis:** `BitapSearchOutput`, `SearchResult` and one throwaway list
  per key per document add measurable overhead.
- **Result:** only `fuzzy_obj_short` passed (+3.3%); the rest were ties or
  slightly negative (`fuzzy_str_hit` −2.6%).
- **Decision:** rejected — not a consistent ≥2% win. Reverted.

### 6 — Token counting without `RegExp` (accepted)

- **Change:** `Norm.get` counts runs of non-space UTF-16 code units directly
  instead of `RegExp('[^ ]+').allMatches(value).length`.
- **Correctness:** byte-identical golden scores.
- **Result:** index build 0.318 s → 0.155 s (51.3%) at 10k; 2.267 s → 1.196 s
  (47.2%) at 100k.
- **Decision:** accepted.

### 7 — Iterative `get` fast path (accepted)

- **Change:** the common scalar path walks segments without allocating a
  result list or a recursive closure; only array-valued paths fall back to the
  collector. `List<String>` paths are used without a `cast` view.
- **Correctness:** byte-identical golden output; all array/nested-key tests pass,
  plus 60,000 randomized differential cases against the original `get`.
- **Result:** index build 0.187 s → 0.158 s (15.6%).
- **Decision:** accepted.

### 8 — Inlined scoring (rejected)

- **Hypothesis:** ~1M `computeScore` calls per search are call/division overhead.
- **Result:** 0.04–6.5% slower across all fuzzy workloads.
- **Decision:** rejected. Reverted.

## Summary

**Accepted changes**

1. Flat `Uint32List` Bitap alphabet + `codeUnitAt` + typed mask rows.
2. Manual token counting in `Norm`.
3. Iterative scalar fast path in `get`.

**Rejected changes:** default-sort shortcut, row-buffer reuse, tail
specialization, allocation bundle, inlined scoring — each failed the 2%
and/or non-overlapping-CI rule.

**Final in-process speedups (AOT, 10k documents)**| Workload | Before | After | Speedup |
| --- | --- | --- | --- |
| Index build | 34.9 ms | 6.5 ms | 5.4× |
| Fuzzy object search (hit) | 215.0 ms | 44.3 ms | 4.9× |
| Fuzzy object search (miss) | 192.7 ms | 25.1 ms | 7.7× |
| Fuzzy object search (short) | 66.2 ms | 18.8 ms | 3.5× |
| Fuzzy string list | 148.8 ms | 20.9 ms | 7.1× |
| Extended search | 9.0 ms | 6.4 ms | 1.4× |
| Logical search | 59.9 ms | 12.3 ms | 4.9× |
| `includeMatches` | 289.0 ms | 45.2 ms | 6.4× |
| Sorted + limit | 335.4 ms | 42.6 ms | 7.9× |

At 100k documents: index build 486.9 → 131.4 ms (3.7×), fuzzy object hit
3316.8 → 675.5 ms (4.9×), miss 1962.1 → 420.6 ms (4.7×).

**Remaining bottleneck:** the Bitap inner loop itself (~85% of a fuzzy
search). The next lever would be caching normalized (lower-cased / diacritic-
stripped) field text in the index: the measured upper bound for default
options is ~2.5% (0.4 ms per 10k full-text lower-casings), so it was not
pursued. Parallelising across isolates would change the synchronous API.
