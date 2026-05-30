# fuse_dart

A pure Dart port of [Fuse.js](https://fusejs.io) — a lightweight fuzzy-search
library with no runtime dependencies. It reproduces Fuse.js v7.1.0 behavior:
the Bitap approximate-matching algorithm, the same relevance scoring and
ranking, weighted keys, nested/array key paths, extended (Unix-like) search
syntax, and logical `$and`/`$or` queries.

`fuse_dart` is null-safe, generic, and runs everywhere Dart runs: Flutter,
Android, iOS, Windows, Linux, macOS, and the web.

## Features

- Fuzzy matching via the Bitap algorithm, byte-for-byte compatible scoring.
- Weighted keys and nested key paths (`'author.firstName'` or
  `['author', 'first.name']`).
- Searching into arrays of strings and arrays of objects.
- Extended search operators: `'include`, `=exact`, `^prefix`, `suffix$`,
  `!inverse`, and `|` for OR.
- Logical queries with `$and`, `$or`, `$path`, and `$val`.
- `includeScore` and `includeMatches` (match indices for highlighting).
- Pre-built and serializable indexes (`createIndex` / `parseIndex`).
- Configurable `threshold`, `distance`, `location`, `ignoreLocation`,
  `ignoreFieldNorm`, `fieldNormWeight`, `minMatchCharLength`, `findAllMatches`,
  `isCaseSensitive`, and `ignoreDiacritics`.
- No external dependencies.

## Install

```yaml
dependencies:
  fuse_dart: ^1.0.0
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
    print('  ${match.key} -> ${match.indices}'); // e.g. (0, 4)
  }
}
```

### Typed models

Dart has no runtime reflection on Flutter/web, so for your own classes provide
a `getFn` per key. Use `FuseKey<T>` so the accessor is strongly typed.

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

## Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `isCaseSensitive` | `bool` | `false` | Case-sensitive comparison. |
| `ignoreDiacritics` | `bool` | `false` | Ignore accents (see notes below). |
| `includeScore` | `bool` | `false` | Include a `score` in each result. |
| `includeMatches` | `bool` | `false` | Include match `indices` in each result. |
| `shouldSort` | `bool` | `true` | Sort by ascending score. |
| `sortFn` | `FuseSortFunction` | by score then index | Custom sort comparator. |
| `keys` | `List<Object>` | `[]` | Keys to search: `String`, `List<String>`, or `FuseKey`. |
| `findAllMatches` | `bool` | `false` | Keep scanning after a perfect match. |
| `minMatchCharLength` | `int` | `1` | Minimum matched-run length to report. |
| `location` | `int` | `0` | Approximate expected match position. |
| `threshold` | `double` | `0.6` | `0.0` requires a perfect match, `1.0` matches anything. |
| `distance` | `int` | `100` | How far a match may stray from `location`. |
| `useExtendedSearch` | `bool` | `false` | Enable Unix-like search operators. |
| `ignoreLocation` | `bool` | `false` | Ignore `location`/`distance`. |
| `ignoreFieldNorm` | `bool` | `false` | Ignore the field-length norm in scoring. |
| `fieldNormWeight` | `double` | `1` | How much the field-length norm affects scoring. |
| `pathGetFn` | `GetFunction<T>` | `get` | Custom global value accessor `(obj, path)`. |

## Extended search

Enable with `useExtendedSearch: true`. Whitespace separates AND terms; `|`
separates OR groups.

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

## Behavior and compatibility notes

- Scoring, ranking, and match indices match Fuse.js v7.1.0; the test suite is
  ported from Fuse.js and verified against its reference snapshots.
- The Bitap algorithm uses 32-bit-style bitwise arithmetic. Dart's integer
  semantics produce identical results on native and web targets because the
  algorithm has no right shifts and masks every accumulation with the pattern
  alphabet.
- Match `indices` are exposed as Dart records `(int start, int end)`.
- `ignoreDiacritics` removes accents for Latin scripts (Latin-1 Supplement and
  Latin Extended-A) and strips Unicode combining marks. Dart's core library has
  no Unicode NFD normalization, so non-Latin precomposed characters are not
  decomposed; this covers the practical use of diacritics removal without
  pulling in a dependency.

## Performance

The library avoids unnecessary allocations (cached field-length norms, reused
bit arrays, lazy match-mask computation). See `benchmark/fuse_benchmark.dart`:

```bash
dart run benchmark/fuse_benchmark.dart
```

## Testing

```bash
dart test
```

## License

Apache License 2.0. This is a derivative work of Fuse.js
(Copyright Kiro Risk), which is also licensed under Apache 2.0.
