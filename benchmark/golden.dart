import 'dart:convert';

import 'package:fuse_dart/fuse_dart.dart';

import 'fuse_benchmark.dart' show generateDataset;

/// Emits a deterministic JSON snapshot of search behaviour.
///
/// Used to prove that an optimization changes speed but not results: run the
/// same file from the old and the new revision and diff the output.
void main() {
  final data = generateDataset(500);
  final strings = [
    for (final doc in data) doc['title'] as String,
    'Ápple pie',
    'Über Straße',
    '  ',
    'Old Man War',
  ];

  final out = <Object?>[];

  void run<T>(String label, List<FuseResult<T>> results) {
    out.add({
      'case': label,
      'results': [
        for (final r in results)
          {
            'idx': r.refIndex,
            'score': r.score?.toStringAsFixed(17),
            'item': r.item is Map ? (r.item! as Map)['id'] : r.item,
            'matches': r.matches == null
                ? null
                : [
                    for (final m in r.matches!)
                      {
                        'key': m.key,
                        'value': m.value,
                        'ref': m.refIndex,
                        'indices': m.indices
                            .map((range) => [range.$1, range.$2])
                            .toList(),
                      },
                  ],
          },
      ],
    });
  }

  const queries = [
    'Old Man War',
    'old man war',
    'scalzi',
    'qzxvbnm',
    'old',
    'War',
    'maine',
  ];

  for (final query in queries) {
    run(
      'obj:$query',
      Fuse(
        data,
        options: FuseOptions<Map<String, dynamic>>(
          keys: ['title', 'author.firstName', 'author.lastName'],
          includeScore: true,
          includeMatches: true,
        ),
      ).search(query),
    );
  }

  run(
    'keys:weights',
    Fuse(
      data,
      options: FuseOptions<Map<String, dynamic>>(
        keys: [
          FuseKey<Map<String, dynamic>>(name: 'title', weight: 3),
          FuseKey<Map<String, dynamic>>(
            name: 'author.lastName',
            weight: 1,
          ),
        ],
        includeScore: true,
      ),
    ).search('old'),
  );

  run(
    'ignoreLocation',
    Fuse(
      data,
      options: FuseOptions<Map<String, dynamic>>(
        keys: ['title'],
        includeScore: true,
        ignoreLocation: true,
      ),
    ).search('old man'),
  );

  run(
    'caseSensitive',
    Fuse(
      data,
      options: FuseOptions<Map<String, dynamic>>(
        keys: ['title'],
        includeScore: true,
        isCaseSensitive: true,
      ),
    ).search('Old'),
  );

  run(
    'diacritics',
    Fuse(
      strings,
      options: FuseOptions<String>(
        includeScore: true,
        ignoreDiacritics: true,
      ),
    ).search('apple pie'),
  );

  run(
    'noSort',
    Fuse(
      data,
      options: FuseOptions<Map<String, dynamic>>(
        keys: ['title'],
        includeScore: true,
        shouldSort: false,
      ),
    ).search('old'),
  );

  final extended = Fuse(
    data,
    options: FuseOptions<Map<String, dynamic>>(
      keys: ['title', 'author.lastName'],
      useExtendedSearch: true,
      includeScore: true,
      includeMatches: true,
    ),
  );
  for (final query in [
    "'Old ^War | =Scalzi",
    '!old',
    '^Old',
    'War\$',
    '=Scalzi',
    '"old man"',
  ]) {
    run('ext:$query', extended.search(query));
  }

  final logical = Fuse(
    data,
    options: FuseOptions<Map<String, dynamic>>(
      keys: ['title', 'author.lastName'],
      includeScore: true,
    ),
  );
  run(
    r'logical:and',
    logical.search({
      r'$and': [
        {'title': 'Old'},
        {'author.lastName': 'Grant'},
      ],
    }),
  );
  run(
    r'logical:or',
    logical.search({
      r'$or': [
        {'title': 'War'},
        {'author.lastName': 'Scalzi'},
      ],
    }),
  );

  run(
    'stringList',
    Fuse(
      strings,
      options: FuseOptions<String>(includeScore: true),
    ).search('old'),
  );

  print(const JsonEncoder.withIndent('  ').convert(out));
}
