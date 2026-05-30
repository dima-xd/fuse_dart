import 'package:fuse_dart/fuse_dart.dart';
import 'package:test/test.dart';

Fuse<T> setup<T>(List<T> list, [FuseOptions<T>? options]) =>
    Fuse<T>(list, options: options);

void main() {
  group('Flat list of strings: ["Apple", "Orange", "Banana"]', () {
    late Fuse<String> fuse;
    setUp(() => fuse = Fuse<String>(['Apple', 'Orange', 'Banana']));

    test('search "Apple" returns 1 item at index 0', () {
      final result = fuse.search('Apple');
      expect(result, hasLength(1));
      expect(result[0].refIndex, 0);
    });

    test('fuzzy "ran" returns [Orange, Banana]', () {
      final result = fuse.search('ran');
      expect(result, hasLength(2));
      expect(result[0].refIndex, 1);
      expect(result[1].refIndex, 2);
    });

    test('fuzzy "nan" returns [Banana, Orange]', () {
      final result = fuse.search('nan');
      expect(result, hasLength(2));
      expect(result[0].refIndex, 2);
      expect(result[1].refIndex, 1);
    });

    test('fuzzy "nan" with limit 1 returns [Banana]', () {
      final result = fuse.search('nan', limit: 1);
      expect(result, hasLength(1));
      expect(result[0].refIndex, 2);
    });
  });

  group('Deep key search ["title", "author.firstName"]', () {
    final books = <Map<String, dynamic>>[
      {
        'title': "Old Man's War",
        'author': {'firstName': 'John', 'lastName': 'Scalzi'},
      },
      {
        'title': 'The Lock Artist',
        'author': {'firstName': 'Steve', 'lastName': 'Hamilton'},
      },
      {'title': 'HTML5'},
      {
        'title': 'A History of England',
        'author': {'firstName': 1066, 'lastName': 'Hastings'},
      },
    ];

    late Fuse<Map<String, dynamic>> fuse;
    setUp(() => fuse = Fuse(
          books,
          options: FuseOptions(keys: ['title', 'author.firstName']),
        ));

    test('search "Stve" matches The Lock Artist', () {
      final result = fuse.search('Stve');
      expect(result.length, greaterThanOrEqualTo(1));
      final item = result[0].item;
      expect(item['title'], 'The Lock Artist');
      expect(item['author']['firstName'], 'Steve');
      expect(item['author']['lastName'], 'Hamilton');
    });

    test('search "106" matches numeric firstName', () {
      final result = fuse.search('106');
      expect(result, hasLength(1));
      final item = result[0].item;
      expect(item['title'], 'A History of England');
      expect(item['author']['firstName'], 1066);
      expect(item['author']['lastName'], 'Hastings');
    });
  });

  group('Custom path getFn', () {
    final books = <Map<String, dynamic>>[
      {
        'title': "Old Man's War",
        'author': {'firstName': 'John', 'lastName': 'Scalzi'},
      },
      {
        'title': 'The Lock Artist',
        'author': {'firstName': 'Steve', 'lastName': 'Hamilton'},
      },
    ];

    Fuse<Map<String, dynamic>> build() => Fuse(
          books,
          options: FuseOptions(
            keys: ['title', 'author.firstName'],
            pathGetFn: (obj, path) => (obj['author'] as Map)['lastName'],
          ),
        );

    test('search "Hmlt" matches by last name', () {
      final result = build().search('Hmlt');
      expect(result.length, greaterThanOrEqualTo(1));
      final item = result[0].item;
      expect(item['title'], 'The Lock Artist');
      expect(item['author']['firstName'], 'Steve');
      expect(item['author']['lastName'], 'Hamilton');
    });

    test('search "Stve" returns 0 items', () {
      expect(build().search('Stve'), hasLength(0));
    });
  });

  group('Include score', () {
    late Fuse<String> fuse;
    setUp(() => fuse = Fuse<String>(
          ['Apple', 'Orange', 'Banana'],
          options: FuseOptions(includeScore: true),
        ));

    test('exact match has score 0', () {
      final result = fuse.search('Apple');
      expect(result, hasLength(1));
      expect(result[0].refIndex, 0);
      expect(result[0].score, 0);
    });

    test('fuzzy "ran" returns non-zero scores', () {
      final result = fuse.search('ran');
      expect(result, hasLength(2));
      expect(result[0].refIndex, 1);
      expect(result[0].score, isNot(0));
      expect(result[1].refIndex, 2);
      expect(result[1].score, isNot(0));
    });
  });

  group('Recurse into arrays', () {
    final books = <Map<String, dynamic>>[
      {
        'ISBN': '0765348276',
        'tags': ['fiction']
      },
      {
        'ISBN': '0312696957',
        'tags': ['fiction']
      },
      {
        'ISBN': '0321784421',
        'tags': ['web development', 'nonfiction'],
      },
    ];

    late Fuse<Map<String, dynamic>> fuse;
    setUp(() => fuse = Fuse(
          books,
          options: FuseOptions(
            keys: ['tags'],
            threshold: 0,
            includeMatches: true,
          ),
        ));

    test('search "nonfiction" finds the third book with match metadata', () {
      final result = fuse.search('nonfiction');
      expect(result, hasLength(1));
      expect(result[0].item['ISBN'], '0321784421');

      final match = result[0].matches!.first;
      expect(match.indices, [(0, 9)]);
      expect(match.value, 'nonfiction');
      expect(match.key, 'tags');
      expect(match.refIndex, 1);
    });
  });

  group('Recurse into objects in arrays with null entries', () {
    final books = <Map<String, dynamic>>[
      {
        'ISBN': '0765348276',
        'title': "Old Man's War",
        'author': {
          'name': 'John Scalzi',
          'tags': [
            {'value': 'American'},
            null,
          ],
        },
      },
      {
        'ISBN': '0312696957',
        'title': 'The Lock Artist',
        'author': {
          'name': 'Steve Hamilton',
          'tags': [
            {'value': 'American'},
          ],
        },
      },
      {
        'ISBN': '0321784421',
        'title': 'HTML5',
        'author': {
          'name': 'Remy Sharp',
          'tags': [
            {'value': 'British'},
            null,
          ],
        },
      },
    ];

    test('search "British" finds the correct book', () {
      final fuse = Fuse(
        books,
        options: FuseOptions(keys: ['author.tags.value'], threshold: 0),
      );
      final result = fuse.search('British');
      expect(result, hasLength(1));
      expect(result[0].item['ISBN'], '0321784421');
    });
  });

  group('setCollection', () {
    test('replacing the list re-indexes', () {
      final fuse = Fuse<String>(['Apple', 'Orange', 'Banana']);
      fuse.setCollection(['Onion', 'Lettuce', 'Broccoli']);
      final result = fuse.search('Lettuce');
      expect(result, hasLength(1));
      expect(result[0].refIndex, 1);
    });
  });

  group('Weighted search', () {
    final books = <Map<String, dynamic>>[
      {
        'title': "Old Man's War fiction",
        'author': 'John X',
        'tags': ['war']
      },
      {
        'title': 'Right Ho Jeeves',
        'author': 'P.D. Mans',
        'tags': ['fiction', 'war'],
      },
      {
        'title': 'The life of Jane',
        'author': 'John Smith',
        'tags': ['john', 'smith'],
      },
      {
        'title': 'John Smith',
        'author': 'Steve Pearson',
        'tags': ['steve', 'pearson'],
      },
    ];

    test('invalid key weight throws', () {
      expect(
        () => Fuse(
          books,
          options: FuseOptions(keys: [
            FuseKey<Map<String, dynamic>>(name: 'title', weight: -10),
            FuseKey<Map<String, dynamic>>(name: 'author', weight: 0.7),
          ]),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('missing key name throws', () {
      expect(
        () => Fuse(
          books,
          options: FuseOptions(keys: [
            {'weight': 10},
            FuseKey<Map<String, dynamic>>(name: 'author', weight: 0.7),
          ]),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    void expectItem(
      FuseResult<dynamic> result, {
      required int refIndex,
      required String title,
      required String author,
      required List<String> tags,
    }) {
      final item = result.item as Map<String, dynamic>;
      expect(result.refIndex, refIndex);
      expect(item['title'], title);
      expect(item['author'], author);
      expect(item['tags'], tags);
    }

    test('author weighted higher prefers the John Smith author', () {
      final fuse = Fuse(
        books,
        options: FuseOptions(keys: [
          FuseKey<Map<String, dynamic>>(name: 'title', weight: 0.3),
          FuseKey<Map<String, dynamic>>(name: 'author', weight: 0.7),
        ]),
      );
      final result = fuse.search('John Smith');
      expectItem(
        result[0],
        refIndex: 2,
        title: 'The life of Jane',
        author: 'John Smith',
        tags: ['john', 'smith'],
      );
    });

    test('mixed key types', () {
      final fuse = Fuse(
        books,
        options: FuseOptions(keys: [
          'title',
          FuseKey<Map<String, dynamic>>(name: 'author', weight: 2),
        ]),
      );
      final result = fuse.search('John Smith');
      expectItem(
        result[0],
        refIndex: 2,
        title: 'The life of Jane',
        author: 'John Smith',
        tags: ['john', 'smith'],
      );
    });

    test('mixed key types throw when a key has no name', () {
      expect(
        () => Fuse(
          books,
          options: FuseOptions(keys: [
            'title',
            {'weight': 2},
          ]),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('title weighted higher prefers the John Smith title', () {
      final fuse = Fuse(
        books,
        options: FuseOptions(keys: [
          FuseKey<Map<String, dynamic>>(name: 'title', weight: 0.7),
          FuseKey<Map<String, dynamic>>(name: 'author', weight: 0.3),
        ]),
      );
      final result = fuse.search('John Smith');
      expectItem(
        result[0],
        refIndex: 3,
        title: 'John Smith',
        author: 'Steve Pearson',
        tags: ['steve', 'pearson'],
      );
    });

    test('"Man" with author weighted higher prefers P.D. Mans', () {
      final fuse = Fuse(
        books,
        options: FuseOptions(keys: [
          FuseKey<Map<String, dynamic>>(name: 'title', weight: 0.3),
          FuseKey<Map<String, dynamic>>(name: 'author', weight: 0.7),
        ]),
      );
      final result = fuse.search('Man');
      expectItem(
        result[0],
        refIndex: 1,
        title: 'Right Ho Jeeves',
        author: 'P.D. Mans',
        tags: ['fiction', 'war'],
      );
    });

    test('"Man" with title weighted higher prefers Old Man\'s War', () {
      final fuse = Fuse(
        books,
        options: FuseOptions(keys: [
          FuseKey<Map<String, dynamic>>(name: 'title', weight: 0.7),
          FuseKey<Map<String, dynamic>>(name: 'author', weight: 0.3),
        ]),
      );
      final result = fuse.search('Man');
      expectItem(
        result[0],
        refIndex: 0,
        title: "Old Man's War fiction",
        author: 'John X',
        tags: ['war'],
      );
    });

    test('tags weighted highest for "War"', () {
      final fuse = Fuse(
        books,
        options: FuseOptions(keys: [
          FuseKey<Map<String, dynamic>>(name: 'title', weight: 0.4),
          FuseKey<Map<String, dynamic>>(name: 'author', weight: 0.1),
          FuseKey<Map<String, dynamic>>(name: 'tags', weight: 0.5),
        ]),
      );
      final result = fuse.search('War');
      expectItem(
        result[0],
        refIndex: 0,
        title: "Old Man's War fiction",
        author: 'John X',
        tags: ['war'],
      );
    });
  });

  group('Search location', () {
    test('"wor" against "Hello World" yields expected indices', () {
      final fuse = Fuse(
        [
          {'name': 'Hello World'},
        ],
        options: FuseOptions(
          keys: ['name'],
          includeScore: true,
          includeMatches: true,
        ),
      );
      final matches = fuse.search('wor')[0].matches!;
      expect(matches[0].indices[0], (4, 4));
      expect(matches[0].indices[1], (6, 8));
      expect(matches[0].value, 'Hello World');
    });
  });

  group('Match indices with default options', () {
    test('"test" yields 4 match ranges, first single char', () {
      final fuse = Fuse<String>(
        ['t te tes test tes te t'],
        options: FuseOptions(includeMatches: true),
      );
      final indices = fuse.search('test')[0].matches![0].indices;
      expect(indices, hasLength(4));
      expect(indices[0], (0, 0));
    });
  });

  group('findAllMatches', () {
    test('"test" yields 7 match ranges', () {
      final fuse = Fuse<String>(
        ['t te tes test tes te t'],
        options: FuseOptions(includeMatches: true, findAllMatches: true),
      );
      final indices = fuse.search('test')[0].matches![0].indices;
      expect(indices, hasLength(7));
      expect(indices[0], (0, 0));
    });
  });

  group('minMatchCharLength', () {
    test('"test" yields 3 ranges, first starting at 2', () {
      final fuse = Fuse<String>(
        ['t te tes test tes te t'],
        options: FuseOptions(includeMatches: true, minMatchCharLength: 2),
      );
      final indices = fuse.search('test')[0].matches![0].indices;
      expect(indices, hasLength(3));
      expect(indices[0], (2, 3));
    });

    test('query shorter than minMatchCharLength yields no results', () {
      final fuse = Fuse<String>(
        ['t te tes test tes te t'],
        options: FuseOptions(includeMatches: true, minMatchCharLength: 2),
      );
      expect(fuse.search('t'), hasLength(0));
    });
  });

  group('Field length norm', () {
    final books = <Map<String, dynamic>>[
      {'ISBN': '0312696957', 'title': 'The Lock war Artist nonficon'},
      {'ISBN': '0765348276', 'title': "Old Man's War"},
    ];

    test('shorter field appears first', () {
      final fuse = Fuse(books, options: FuseOptions(keys: ['title']));
      final result = fuse.search('war');
      expect(result.length, 2);
      expect(result[0].item['ISBN'], '0765348276');
      expect(result[1].item['ISBN'], '0312696957');
    });
  });

  group('Ignore location and field length norm', () {
    final list = [
      'beforeEach',
      'async beforeEach test',
      'assert.async in beforeEach',
      'Module with Promise-aware beforeEach',
      'Promise-aware return values without beforeEach/afterEach',
      'Module with Promise-aware afterEach',
      'before',
      'before (skip)',
    ];

    test('ignored: ordering matches Fuse.js snapshot', () {
      final fuse = Fuse<String>(
        list,
        options: FuseOptions(
          includeScore: true,
          ignoreLocation: true,
          ignoreFieldNorm: true,
        ),
      );
      final result = fuse.search('promiseawarebeforeEach');
      expect(result.map((r) => r.refIndex).toList(), [3, 5, 4, 1, 2, 0]);
      const expectedScores = [
        0.09090909090909091,
        0.2727272727272727,
        0.4090909090909091,
        0.5,
        0.5,
        0.5454545454545454,
      ];
      for (var i = 0; i < expectedScores.length; i += 1) {
        expect(result[i].score, closeTo(expectedScores[i], 1e-9));
      }
    });

    test('not ignored: ordering matches Fuse.js snapshot', () {
      final fuse = Fuse<String>(list, options: FuseOptions(includeScore: true));
      final result = fuse.search('beforeEach');
      expect(result.map((r) => r.refIndex).toList(), [0, 1, 6, 2, 7, 3, 4]);
      const expectedScores = [
        0.0,
        0.1972392177586917,
        0.4,
        0.4493775633055149,
        0.5231863610884103,
        0.5916079783099616,
        0.699819425905295,
      ];
      for (var i = 0; i < expectedScores.length; i += 1) {
        expect(result[i].score, closeTo(expectedScores[i], 1e-9));
      }
    });
  });

  group('Standard dotted keys', () {
    test('array key path matches', () {
      final list = <Map<String, dynamic>>[
        {
          'title': 'HTML5',
          'author': {'firstName': 'Remy'},
        },
        {
          'title': 'Angels & Demons',
          'author': {'firstName': 'rmy'},
        },
      ];
      final fuse = Fuse(
        list,
        options: FuseOptions(
          keys: [
            'title',
            ['author', 'firstName']
          ],
          includeMatches: true,
          includeScore: true,
        ),
      );
      expect(fuse.search('remy'), hasLength(2));
    });
  });

  group('Breaking values', () {
    test('booleans are processed', () {
      final fuse = Fuse(
        [
          {'first': false},
        ],
        options: FuseOptions(keys: ['first']),
      );
      expect(fuse.search('fa'), hasLength(1));
    });

    test('object values are ignored', () {
      final fuse = Fuse(
        [
          {'a': 'hello'},
          {'a': <String, dynamic>{}},
        ],
        options: FuseOptions(keys: ['a']),
      );
      expect(fuse.search('hello'), hasLength(1));
    });
  });

  group('Ignore diacritics', () {
    final list = [
      {'text': 'déjà'},
      {'text': 'cafe'},
    ];
    final fuse = Fuse(
      list,
      options: FuseOptions(
        ignoreDiacritics: true,
        threshold: 0,
        keys: ['text'],
      ),
    );

    test('query with diacritics, list with diacritics', () {
      final result = fuse.search('déjà');
      expect(result, hasLength(1));
      expect(result[0].refIndex, 0);
    });

    test('query without diacritics, list with diacritics', () {
      final result = fuse.search('deja');
      expect(result, hasLength(1));
      expect(result[0].refIndex, 0);
    });

    test('query with diacritics, list without diacritics', () {
      final result = fuse.search('café');
      expect(result, hasLength(1));
      expect(result[0].refIndex, 1);
    });

    test('query without diacritics, list without diacritics', () {
      final result = fuse.search('cafe');
      expect(result, hasLength(1));
      expect(result[0].refIndex, 1);
    });
  });

  group('Include both ID and score', () {
    final books = <Map<String, dynamic>>[
      {'ISBN': '0765348276', 'title': "Old Man's War", 'author': 'John Scalzi'},
      {
        'ISBN': '0312696957',
        'title': 'The Lock Artist',
        'author': 'Steve Hamilton',
      },
    ];
    final fuse = Fuse(
      books,
      options: FuseOptions<Map<String, dynamic>>(
        keys: ['title', 'author'],
        includeScore: true,
      ),
    );

    test('"Stve" returns the matching ISBN with a non-zero score', () {
      final result = fuse.search('Stve');
      expect(result, hasLength(1));
      expect(result[0].item['ISBN'], '0312696957');
      expect(result[0].score, isNot(0));
    });
  });

  group('Search when IDs are numbers', () {
    final books = <Map<String, dynamic>>[
      {'ISBN': 1111, 'title': "Old Man's War", 'author': 'John Scalzi'},
      {'ISBN': 2222, 'title': 'The Lock Artist', 'author': 'Steve Hamilton'},
    ];
    final fuse = Fuse(
      books,
      options: FuseOptions<Map<String, dynamic>>(
        keys: ['title', 'author'],
        includeScore: true,
      ),
    );

    test('"Stve" returns numeric ISBN 2222 with a non-zero score', () {
      final result = fuse.search('Stve');
      expect(result, hasLength(1));
      expect(result[0].item['ISBN'], 2222);
      expect(result[0].score, isNot(0));
    });
  });

  group('Recurse into objects in arrays', () {
    final books = <Map<String, dynamic>>[
      {
        'ISBN': '0765348276',
        'author': {
          'name': 'John Scalzi',
          'tags': [
            {'value': 'American'},
          ],
        },
      },
      {
        'ISBN': '0312696957',
        'author': {
          'name': 'Steve Hamilton',
          'tags': [
            {'value': 'American'},
          ],
        },
      },
      {
        'ISBN': '0321784421',
        'author': {
          'name': 'Remy Sharp',
          'tags': [
            {'value': 'British'},
          ],
        },
      },
    ];

    test('"British" finds the correct book', () {
      final fuse = Fuse(
        books,
        options: FuseOptions<Map<String, dynamic>>(
          keys: ['author.tags.value'],
          threshold: 0,
        ),
      );
      final result = fuse.search('British');
      expect(result, hasLength(1));
      expect(result[0].item['ISBN'], '0321784421');
    });
  });

  group('minMatchCharLength main functionality', () {
    final list = <Map<String, dynamic>>[
      {
        'title': 'HTML5',
        'author': {'firstName': 'Remy', 'lastName': 'Sharp'},
      },
      {
        'title': 'Angels & Demons',
        'author': {'firstName': 'Dan', 'lastName': 'Brown'},
      },
    ];
    final fuse = Fuse(
      list,
      options: FuseOptions<Map<String, dynamic>>(
        keys: ['title', 'author.firstName'],
        includeMatches: true,
        includeScore: true,
        minMatchCharLength: 3,
      ),
    );

    test('"remy" returns one result with one match', () {
      final result = fuse.search('remy');
      expect(result, hasLength(1));
      expect(result[0].matches, hasLength(1));
    });
  });

  group('minMatchCharLength with pattern larger than machine word size', () {
    final list = [
      'Apple pie is a tasty treat that is always best made by mom! But we '
          'love store bought too.',
      'Banana splits are what you want from DQ on a hot day.  But a parfait '
          'is even better.',
      'Orange sorbet is just a strange yet satisfying snack.  Chocolate seems '
          'to be more of a favourite though.',
    ];
    final fuse = Fuse<String>(
      list,
      options: FuseOptions(
        includeMatches: true,
        findAllMatches: true,
        includeScore: true,
        minMatchCharLength: 20,
        threshold: 0.6,
        distance: 30,
      ),
    );

    test('long query returns exactly the first item with one match', () {
      final result = fuse.search(
        'American as apple pie is odd treatment of something made by mom',
      );
      expect(result, hasLength(1));
      expect(result[0].refIndex, 0);
      expect(result[0].matches, hasLength(1));
    });
  });

  group('Sorted search results', () {
    final list = <Map<String, dynamic>>[
      {
        'title': 'Right Ho Jeeves',
        'author': {'firstName': 'P.D', 'lastName': 'Woodhouse'},
      },
      {
        'title': 'The Code of the Wooster',
        'author': {'firstName': 'P.D', 'lastName': 'Woodhouse'},
      },
      {
        'title': 'Thank You Jeeves',
        'author': {'firstName': 'P.D', 'lastName': 'Woodhouse'},
      },
    ];
    final fuse = Fuse(
      list,
      options: FuseOptions<Map<String, dynamic>>(
        keys: ['title', 'author.firstName', 'author.lastName'],
      ),
    );

    test('"wood" returns results in the expected order', () {
      final result = fuse.search('wood');
      expect(result[0].item['title'], 'The Code of the Wooster');
      expect(result[1].item['title'], 'Right Ho Jeeves');
      expect(result[2].item['title'], 'Thank You Jeeves');
    });
  });

  group('Searching using large strings', () {
    final list = <Map<String, dynamic>>[
      {'text': 'pizza'},
      {'text': 'feast'},
      {'text': 'where in the world is carmen san diego'},
    ];
    final options = FuseOptions<Map<String, dynamic>>(
      shouldSort: true,
      includeScore: true,
      threshold: 0.6,
      keys: ['text'],
    );

    test('matches even when the pattern is longer than 32 characters', () {
      final fuse = Fuse(list, options: options);
      final result =
          fuse.search('where exctly is carmen in the world san diego');
      expect(result.length, 1);
      expect(result[0].item['text'], list[2]['text']);
    });

    test('very long patterns of repeated characters find no matches', () {
      final fuse = Fuse(list, options: options);
      final patterns = [for (var i = 0; i < 66; i += 1) 'w' * i];
      bool none(String pattern) => fuse.search(pattern).isEmpty;
      expect(none(patterns[32]), isTrue);
      expect(none(patterns[33]), isTrue);
      expect(none(patterns[34]), isTrue);
      expect(none(patterns[64]), isTrue);
      expect(none(patterns[65]), isTrue);
    });

    test('with hyphens', () {
      const searchText = 'leverage-streams-to';
      final fuse = Fuse(
        [
          {
            'name': 'Streaming Service',
            'description': 'Leverage-streams-to-ingest, analyze, monitor.',
            'tag': 'Free',
          },
        ],
        options: FuseOptions<Map<String, dynamic>>(
          distance: 1000,
          includeScore: true,
          includeMatches: true,
          keys: ['name', 'tag', 'description'],
          minMatchCharLength: (searchText.length * 0.6).floor(),
          shouldSort: false,
        ),
      );
      final matches = fuse.search(searchText)[0].matches!;
      expect(matches, hasLength(1));
      expect(matches[0].indices, [(0, 18)]);
      expect(matches[0].key, 'description');
      expect(matches[0].value, 'Leverage-streams-to-ingest, analyze, monitor.');
    });

    test('with spaces', () {
      const searchText = 'leverage streams to';
      final fuse = Fuse(
        [
          {
            'name': 'Streaming Service',
            'description': 'Leverage streams to ingest, analyze, monitor.',
            'tag': 'Free',
          },
        ],
        options: FuseOptions<Map<String, dynamic>>(
          distance: 1000,
          includeScore: true,
          includeMatches: true,
          keys: ['name', 'tag', 'description'],
          minMatchCharLength: (searchText.length * 0.6).floor(),
          shouldSort: false,
        ),
      );
      final matches = fuse.search(searchText)[0].matches!;
      expect(matches, hasLength(1));
      expect(matches[0].indices, [(0, 18)]);
      expect(matches[0].key, 'description');
      expect(matches[0].value, 'Leverage streams to ingest, analyze, monitor.');
    });
  });

  group('Field length precedence with weights', () {
    final list = <Map<String, dynamic>>[
      {
        'ISBN': '0312696957',
        'title': 'The Lock war Artist nonficon',
        'author': 'Steve Hamilton',
        'tags': ['fiction war hello no way'],
      },
      {
        'ISBN': '0765348276',
        'title': "Old Man's War",
        'author': 'John Scalzi',
        'tags': ['fiction no'],
      },
    ];

    test('weighted entries keep high precedence', () {
      final fuse = Fuse(
        list,
        options: FuseOptions<Map<String, dynamic>>(
          keys: [
            FuseKey<Map<String, dynamic>>(name: 'tags', weight: 0.8),
            FuseKey<Map<String, dynamic>>(name: 'title', weight: 0.2),
          ],
        ),
      );
      final result = fuse.search('war');
      expect(result.length, 2);
      expect(result[0].item['ISBN'], '0312696957');
      expect(result[1].item['ISBN'], '0765348276');
    });
  });

  group('Standard dotted keys (extended)', () {
    test('dotted key name segments resolve via array path', () {
      final list = <Map<String, dynamic>>[
        {
          'title': 'HTML5',
          'author': {'first.name': 'Remy', 'last.name': 'Sharp'},
        },
        {
          'title': 'Angels & Demons',
          'author': {'first.name': 'rmy', 'last.name': 'Brown'},
        },
      ];
      final fuse = Fuse(
        list,
        options: FuseOptions<Map<String, dynamic>>(
          keys: [
            'title',
            ['author', 'first.name']
          ],
          includeMatches: true,
          includeScore: true,
        ),
      );
      expect(fuse.search('remy'), hasLength(2));
    });

    test('keys with weights via array path', () {
      final list = <Map<String, dynamic>>[
        {
          'title': 'HTML5',
          'author': {'firstName': 'Remy', 'lastName': 'Sharp'},
        },
        {
          'title': 'Angels & Demons',
          'author': {'firstName': 'rmy', 'lastName': 'Brown'},
        },
      ];
      final fuse = Fuse(
        list,
        options: FuseOptions<Map<String, dynamic>>(
          keys: [
            FuseKey<Map<String, dynamic>>(name: 'title'),
            FuseKey<Map<String, dynamic>>(name: ['author', 'firstName']),
          ],
          includeMatches: true,
          includeScore: true,
        ),
      );
      expect(fuse.search('remy'), hasLength(2));
    });
  });
}
