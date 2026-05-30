# Changelog

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
