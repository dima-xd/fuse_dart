import 'package:fuse_dart/fuse_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Extended search', () {
    final list = <Map<String, dynamic>>[
      {'text': 'hello word'},
      {'text': 'how are you'},
      {'text': 'indeed fine hello foo'},
      {'text': 'I am fine'},
      {'text': 'smithee'},
      {'text': 'smith'},
    ];

    final fuse = Fuse(
      list,
      options: FuseOptions<Map<String, dynamic>>(
        useExtendedSearch: true,
        includeMatches: true,
        includeScore: true,
        threshold: 0.5,
        minMatchCharLength: 4,
        keys: ['text'],
      ),
    );

    List<int> idx(List<FuseResult<Map<String, dynamic>>> r) =>
        r.map((e) => e.refIndex).toList();

    void expectScores(
      List<FuseResult<Map<String, dynamic>>> r,
      List<double> expected,
    ) {
      expect(r, hasLength(expected.length));
      for (var i = 0; i < expected.length; i += 1) {
        expect(r[i].score, closeTo(expected[i], expected[i].abs() * 1e-6 + 1e-12));
      }
    }

    const eps = 2.220446049250313e-16;
    const sHello = 8.569061098350962e-12;
    const sFine = 9.287439764962262e-10;
    const sIndeed = 1.4901161193847656e-8;

    test('exact-match =smith', () {
      final result = fuse.search('=smith');
      expect(idx(result), [5]);
      expect(result[0].matches!.first.indices, [(0, 4)]);
      expectScores(result, [eps]);
    });

    test('include-match \'hello', () {
      final result = fuse.search("'hello");
      expect(idx(result), [0, 2]);
      expect(result[0].matches!.first.indices, [(0, 4)]);
      expect(result[1].matches!.first.indices, [(12, 16)]);
      expectScores(result, [sHello, sIndeed]);
    });

    test('prefix-exact-match ^hello', () {
      final result = fuse.search('^hello');
      expect(idx(result), [0]);
      expect(result[0].matches!.first.indices, [(0, 4)]);
      expectScores(result, [sHello]);
    });

    test('suffix-exact-match fine\$', () {
      final result = fuse.search(r'fine$');
      expect(idx(result), [3]);
      expect(result[0].matches!.first.indices, [(5, 8)]);
      expectScores(result, [sFine]);
    });

    test('inverse-exact-match !indeed', () {
      final result = fuse.search('!indeed');
      expect(idx(result), [4, 5, 0, 1, 3]);
      expectScores(result, [eps, eps, sHello, sFine, sFine]);
    });

    test('inverse-prefix-exact-match !^hello', () {
      final result = fuse.search('!^hello');
      expect(idx(result), [4, 5, 1, 3, 2]);
      expectScores(result, [eps, eps, sFine, sFine, sIndeed]);
    });

    test('inverse-suffix-exact-match !foo\$', () {
      final result = fuse.search(r'!foo$');
      expect(idx(result), [4, 5, 0, 1, 3]);
      expectScores(result, [eps, eps, sHello, sFine, sFine]);
    });

    test('combined !foo\$ !^how', () {
      final result = fuse.search(r'!foo$ !^how');
      expect(idx(result), [4, 5, 0, 3]);
      expect(result[0].matches!.first.indices, [(0, 6), (0, 6)]);
      expectScores(result, [eps, eps, sHello, sFine]);
    });

    test('single literal match', () {
      final result = fuse.search('\'"indeed fine"');
      expect(idx(result), [2]);
      expect(result[0].matches!.first.indices, [(0, 10)]);
      expectScores(result, [sIndeed]);
    });

    test('literal match with regular match', () {
      final result = fuse.search('\'"indeed fine" foo\$ | \'are');
      expect(idx(result), [1, 2]);
      expect(result[0].matches!.first.indices, [(4, 6)]);
      expect(result[1].matches!.first.indices, [(0, 10), (18, 20)]);
      expectScores(result, [sFine, sIndeed]);
    });

    test('literal match with fuzzy match', () {
      final result = fuse.search('\'"indeed fine" foo\$ | helol');
      expect(idx(result), [2, 0]);
      expect(result[0].matches!.first.indices, [(0, 10), (18, 20)]);
      expectScores(result, [sIndeed, 0.3205001277290518]);
    });
  });

  group('ignoreLocation with extended search', () {
    test('finds the apple near the end of a long document', () {
      final list = <Map<String, dynamic>>[
        {
          'document':
              'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do '
                  'eiusmod tempor incididunt ut labore et dolore magna aliqua. '
                  'Ut enim ad minim veniam, quis nostrud exercitation ullamco '
                  'laboris nisi ut aliquip ex ea commodo consequat. Duis aute '
                  'irure dolor in reprehenderit in voluptate velit esse cillum '
                  'dolore eu fugiat nulla pariatur. Excepteur sint occaecat '
                  'cupidatat non proident, sunt in culpa qui officia deserunt '
                  'mollit anim id est laborum apple.',
        },
      ];
      final fuse = Fuse(
        list,
        options: FuseOptions<Map<String, dynamic>>(
          threshold: 0.2,
          useExtendedSearch: true,
          ignoreLocation: true,
          keys: ['document'],
        ),
      );
      expect(fuse.search('Apple'), hasLength(1));
    });
  });

  group('Extended search ignoring diacritics', () {
    final list = <Map<String, dynamic>>[
      {'text': 'déjà'},
      {'text': 'cafe'},
    ];
    final fuse = Fuse(
      list,
      options: FuseOptions<Map<String, dynamic>>(
        useExtendedSearch: true,
        ignoreDiacritics: true,
        threshold: 0,
        keys: ['text'],
      ),
    );

    test('déjà matches déjà', () {
      final result = fuse.search('déjà');
      expect(result, hasLength(1));
      expect(result[0].refIndex, 0);
    });

    test('deja matches déjà', () {
      final result = fuse.search('deja');
      expect(result, hasLength(1));
      expect(result[0].refIndex, 0);
    });

    test('café matches cafe', () {
      final result = fuse.search('café');
      expect(result, hasLength(1));
      expect(result[0].refIndex, 1);
    });

    test('cafe matches cafe', () {
      final result = fuse.search('cafe');
      expect(result, hasLength(1));
      expect(result[0].refIndex, 1);
    });
  });
}
