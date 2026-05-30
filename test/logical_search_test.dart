import 'package:fuse_dart/fuse_dart.dart';
import 'package:test/test.dart';

import 'fixtures/books.dart';

List<int> idx<T>(List<FuseResult<T>> result) =>
    result.map((r) => r.refIndex).toList();

void main() {
  group('Logical parser', () {
    final options = FuseOptions<Map<String, dynamic>>(
      useExtendedSearch: true,
      includeMatches: true,
      includeScore: true,
      keys: ['title', 'author.firstName', 'author.lastName'],
    );

    test('Tree structure', () {
      final root = Fuse.parseQuery(
        {
          r'$and': [
            {'title': 'old war'},
            {
              r'$or': [
                {'title': '!arts'},
                {'title': '^lock'},
              ],
            },
          ],
        },
        options,
        auto: false,
      ) as LogicalExpression;

      expect(root.operator, r'$and');
      expect(root.children, hasLength(2));

      final first = root.children[0] as LogicalLeaf;
      expect(first.keyId, 'title');
      expect(first.pattern, 'old war');

      final second = root.children[1] as LogicalExpression;
      expect(second.operator, r'$or');
      expect((second.children[0] as LogicalLeaf).pattern, '!arts');
      expect((second.children[1] as LogicalLeaf).pattern, '^lock');
    });

    test('Implicit operations', () {
      final root = Fuse.parseQuery(
        {
          r'$and': [
            {'title': 'old war'},
            {
              r'$or': [
                {'title': '!arts', 'tags': 'kiro'},
                {'title': '^lock'},
              ],
            },
          ],
        },
        options,
        auto: false,
      ) as LogicalExpression;

      expect(root.operator, r'$and');
      expect(root.children, hasLength(2));

      final first = root.children[0] as LogicalLeaf;
      expect(first.keyId, 'title');
      expect(first.pattern, 'old war');

      final orNode = root.children[1] as LogicalExpression;
      expect(orNode.operator, r'$or');
      expect(orNode.children, hasLength(2));

      final implicitAnd = orNode.children[0] as LogicalExpression;
      expect(implicitAnd.operator, r'$and');
      expect(implicitAnd.children, hasLength(2));
      final andLeaf0 = implicitAnd.children[0] as LogicalLeaf;
      expect(andLeaf0.keyId, 'title');
      expect(andLeaf0.pattern, '!arts');
      final andLeaf1 = implicitAnd.children[1] as LogicalLeaf;
      expect(andLeaf1.keyId, 'tags');
      expect(andLeaf1.pattern, 'kiro');

      final orLeaf = orNode.children[1] as LogicalLeaf;
      expect(orLeaf.keyId, 'title');
      expect(orLeaf.pattern, '^lock');
    });
  });

  group('Searching using logical search', () {
    final fuse = Fuse(
      books,
      options: FuseOptions<Map<String, dynamic>>(
        useExtendedSearch: true,
        includeMatches: true,
        includeScore: true,
        keys: ['title', 'author.firstName', 'author.lastName'],
      ),
    );

    test('implicit AND', () {
      final result = fuse.search({'title': 'old man'});
      expect(result.length, 1);
      expect(result[0].refIndex, 0);
      expect(result[0].matches![0].indices, [(0, 2), (4, 6)]);
    });

    test('AND with single item', () {
      final result = fuse.search({
        r'$and': [
          {'title': 'old man'},
        ],
      });
      expect(result.length, 1);
      expect(idx(result), [0]);
      expect(result[0].matches![0].indices, [(0, 2), (4, 6)]);
    });

    test('AND with multiple entries', () {
      final result = fuse.search({
        r'$and': [
          {'author.lastName': 'Woodhose'},
          {'title': 'the'},
        ],
      });
      expect(result.length, 2);
      expect(idx(result), [4, 5]);
    });

    test('AND with multiple entries + exact match', () {
      final result = fuse.search({
        r'$and': [
          {'author.lastName': 'Woodhose'},
          {'title': "'The"},
        ],
      });
      expect(result.length, 1);
      expect(idx(result), [4]);
    });

    test('OR with multiple entries', () {
      final result = fuse.search({
        r'$or': [
          {'title': 'angls'},
          {'title': 'incmpetnce'},
        ],
      });
      expect(idx(result), [14, 7, 0]);
    });

    test('OR with nested AND', () {
      final result = fuse.search({
        r'$or': [
          {'title': 'angls'},
          {
            r'$and': [
              {'title': '!dwarf'},
              {'title': 'bakwrds'},
            ],
          },
        ],
      });
      expect(idx(result), [7, 0]);
    });
  });

  group('Multiple nested conditions', () {
    final list1 = [
      {
        'title': "Old Man's War",
        'author': {'firstName': 'John', 'lastName': 'Scalzi', 'age': '61'},
      },
    ];

    final list2 = [
      ...list1,
      {
        'title': "Old Man's War",
        'author': {'firstName': 'John', 'lastName': 'Scalzi', 'age': '62'},
      },
    ];

    final fuse1 = Fuse(
      list1,
      options: FuseOptions<Map<String, dynamic>>(
        includeScore: true,
        useExtendedSearch: true,
        keys: ['title', 'author.firstName', 'author.lastName', 'author.age'],
      ),
    );

    final fuse2 = Fuse(
      list2,
      options: FuseOptions<Map<String, dynamic>>(
        includeScore: true,
        useExtendedSearch: true,
        keys: ['title', 'author.firstName', 'author.lastName', 'author.age'],
      ),
    );

    test('nested AND + OR returns nothing when age mismatches', () {
      final result = fuse1.search({
        r'$and': [
          {'title': 'old'},
          {
            r'$or': [
              {'author.firstName': 'j'},
              {'author.lastName': 'Sa'},
            ],
          },
          {
            r'$or': [
              {'author.age': "'62"},
            ],
          },
        ],
      });
      expect(result.length, 0);
    });

    test('deep nested AND + OR matches with positive score', () {
      final result = fuse1.search({
        r'$and': [
          {'title': 'old'},
          {
            r'$or': [
              {'author.firstName': 'jon'},
              {'author.lastName': 'Sazi'},
            ],
          },
          {
            r'$or': [
              {'author.age': "'62"},
              {
                r'$and': [
                  {'title': 'old'},
                  {'author.age': "'61"},
                ],
              },
            ],
          },
        ],
      });
      expect(result.length, 1);
      expect(result[0].score, greaterThan(0));
    });

    test('deep nested AND + OR over two documents', () {
      final result = fuse2.search({
        r'$and': [
          {'title': 'old'},
          {
            r'$and': [
              {'author.firstName': 'jon'},
              {'author.lastName': 'Sazi'},
            ],
          },
          {
            r'$or': [
              {'author.age': "'62"},
              {
                r'$and': [
                  {'title': 'old'},
                  {'author.age': "'62"},
                ],
              },
            ],
          },
        ],
      });
      expect(result.length, 1);
      expect(result[0].score, greaterThan(0));
    });
  });

  group('Logical search with dotted keys', () {
    final list = [
      {
        'title': "Old Man's War",
        'author': {'first.name': 'John', 'last.name': 'Scalzi', 'age': '61'},
      },
    ];

    final fuse = Fuse(
      list,
      options: FuseOptions<Map<String, dynamic>>(
        useExtendedSearch: true,
        includeScore: true,
        keys: [
          'title',
          ['author', 'first.name'],
          ['author', 'last.name'],
          'author.age',
        ],
      ),
    );

    test('path-based query', () {
      final result = fuse.search({
        r'$and': [
          {
            r'$path': ['author', 'first.name'],
            r'$val': 'jon'
          },
          {
            r'$path': ['author', 'last.name'],
            r'$val': 'scazi'
          },
        ],
      });
      expect(result.length, 1);
    });
  });

  group('Logical OR same query across fields', () {
    final fuse = Fuse(
      books,
      options: FuseOptions<Map<String, dynamic>>(
        keys: ['title', 'author.lastName'],
      ),
    );

    test('"wood" top three results', () {
      final result = fuse.search({
        r'$or': [
          {'title': 'wood'},
          {'author.lastName': 'wood'},
        ],
      });
      expect(idx(result.sublist(0, 3)), [4, 3, 5]);
    });
  });
}
