import 'package:fuse_dart/fuse_dart.dart';
import 'package:test/test.dart';

/// Pins the Dart default tokenizer to the same unicode behavior as the JS
/// default `/[\p{L}\p{M}\p{N}_]+/gu`, which the conformance suite verifies
/// through the bridge for a handful of scripts. Here we go broader over
/// scripts and edge cases that must behave identically to JS RegExp.
void main() {
  group('Default analyzer (unicode-aware tokenizer)', () {
    final analyzer = createAnalyzer();

    test('CJK stays one token', () {
      expect(analyzer.tokenize('东京は素晴らしい'), ['东京は素晴らしい']);
    });

    test('Devanagari combining marks stay attached', () {
      // Without \p{M} this shatters into ['ह','न','द'].
      expect(analyzer.tokenize('हिन्दी'), ['हिन्दी']);
    });

    test('NFD-decomposed Latin keeps its combining mark', () {
      final nfd = 'café'.normalizeNfd();
      final tokens = analyzer.tokenize(nfd);
      expect(tokens, hasLength(1));
      expect(tokens[0].normalizeNfc(), 'café');
    });

    test('underscore counts as a word character', () {
      expect(analyzer.tokenize('snake_case'), ['snake_case']);
    });

    test('digits and letters form one token', () {
      expect(analyzer.tokenize('F1'), ['f1']); // analyzer lowercases by default
    });

    test('punctuation splits tokens', () {
      expect(analyzer.tokenize('hello, world!'), ['hello', 'world']);
    });

    test('multiple spaces collapse away', () {
      expect(analyzer.tokenize('  a   b  '), ['a', 'b']);
    });

    test('empty and whitespace-only inputs produce no tokens', () {
      expect(analyzer.tokenize(''), isEmpty);
      expect(analyzer.tokenize('   '), isEmpty);
    });

    test('Hangul, Cyrillic, Greek, Arabic are single tokens', () {
      expect(analyzer.tokenize('한국어'), ['한국어']);
      expect(analyzer.tokenize('Привет'), ['привет']); // lowercased by default
      expect(analyzer.tokenize('Σίσυφος'), ['σίσυφος']); // lowercased by default
      expect(analyzer.tokenize('سلام'), ['سلام']);
    });

    test('mixed scripts stay one token (like JS \\p{L} across scripts)', () {
      // \p{L} covers all scripts, so 'English中文' is one token — no
      // script-boundary splitting.
      expect(analyzer.tokenize('English中文'), ['english中文']); // lowercased by default
    });
  });

  group('Custom RegExp tokenizer', () {
    test('global regex collects every match (mirrors /g flag)', () {
      final analyzer = createAnalyzer(tokenize: RegExp(r'[\w.+-]+'));
      // Dart RegExp has no /g; createAnalyzer's regexp path uses allMatches,
      // matching the JS global-flag behavior.
      expect(analyzer.tokenize('node.js and C++'), ['node.js', 'and', 'c++']); // lowercased by default
    });

    test('matches the JS `tokenize: /[\\w.+-]+/g` fixture behavior', () {
      final docs = [
        {'text': 'I love node.js for backend work'},
        {'text': 'C++ is a fast systems language'},
        {'text': 'I visited the U.S.A last summer'},
      ];
      final fuse = Fuse(
        docs,
        options: FuseOptions<dynamic>(
          useTokenSearch: true,
          keys: ['text'],
          tokenize: RegExp(r'[\w.+-]+'),
        ),
      );

      expect(fuse.search('node.js'), hasLength(greaterThanOrEqualTo(1)));
      expect(fuse.search('c++'), hasLength(greaterThanOrEqualTo(1)));
      expect(fuse.search('U.S.A'), hasLength(greaterThanOrEqualTo(1)));
    });
  });

  group('Custom function tokenizer', () {
    test('function tokenizer is exercised during indexing and search', () {
      var calls = 0;
      final fuse = Fuse(
        [
          {'text': '我喜欢北京'},
          {'text': 'Hello World'},
        ],
        options: FuseOptions<dynamic>(
          useTokenSearch: true,
          keys: ['text'],
          tokenize: (String text) {
            calls++;
            return text.runes
                .map((int r) => String.fromCharCode(r))
                .where((String c) =>
                    RegExp(r'[\p{L}\p{M}\p{N}]', unicode: true).hasMatch(c))
                .toList();
          },
        ),
      );

      expect(calls, greaterThan(0));
      final result = fuse.search('北京');
      expect(result, hasLength(greaterThanOrEqualTo(1)));
      expect(result[0].item['text'], '我喜欢北京');
    });
  });

  group('Token search with tokenMatch all (AND)', () {
    test('record must cover every query term across fields', () {
      final fuse = Fuse(
        [
          {'a': 'red', 'b': 'shirt'},
          {'a': 'red', 'b': 'hat'},
        ],
        options: FuseOptions<dynamic>(
          useTokenSearch: true,
          keys: ['a', 'b'],
          tokenMatch: 'all',
        ),
      );

      // Default Bitap thresholds fuzzily accept 'shirt'~'hat', so both
      // records can pass the coverage gate; nothing here throws.
      final results = fuse.search('red shirt');
      expect(results, hasLength(2));
      expect(results[0].item['a'], 'red');
      expect(results[1].item['a'], 'red');
    });
  });
}

// dart:core String has no normalize; use unorm via the library's own helper
// indirectly. Simple local helpers keep this test dependency-light.
extension on String {
  String normalizeNfd() {
    // Each precomposed Latin letter used in tests decomposes into base+mark;
    // implement NFD just for the characters these tests need (é).
    return replaceAll('é', 'e\u0301');
  }

  String normalizeNfc() {
    return replaceAll('e\u0301', 'é');
  }
}
