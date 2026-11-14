import 'package:fuse_dart/fuse_dart.dart';
import 'package:test/test.dart';

/// Dart-specific edge cases for the Bitap core that the JS conformance
/// suite can't reach: UTF-16 code-unit indexing, the 32-bit pattern
/// alphabet, and long-pattern chunking.
///
/// Dart strings are UTF-16 like JS, so match indices are code-unit offsets
/// — a surrogate pair counts as 2. These tests pin that contract down.
void main() {
  group('Bitap: UTF-16 code-unit indexing', () {
    test('match indices are code-unit offsets, surrogate pairs count as 2', () {
      // '😀😀 ' is 2+2+1 = 5 code units, so "needle" starts at 5 and spans 6.
      final result = Fuse.match(
        'needle',
        '😀😀 needle 😀😀',
        FuseOptions<dynamic>(includeMatches: true),
      );

      expect(result.isMatch, isTrue);
      expect(result.indices, [
        [5, 10]
      ]);
    });

    test('emoji inside the query are searched as surrogate pairs', () {
      // The pattern alphabet is indexed by UTF-16 code unit, so an emoji
      // pattern is two 1-unit "characters" — same as JS charAt behavior.
      final result = Fuse.match(
        '😀',
        'find the 😀 here',
        FuseOptions<dynamic>(includeMatches: true),
      );

      expect(result.isMatch, isTrue);
      // 'find the ' is 9 code units; the emoji spans 2.
      expect(result.indices, [
        [9, 10]
      ]);
    });

    test('highlight indices align with code units for cutting substrings', () {
      final fuse = Fuse(['a😀b needle c'], options: FuseOptions<dynamic>(
        includeMatches: true,
      ));
      final result = fuse.search('needle');

      expect(result, hasLength(1));
      final value = result[0].matches![0].value as String;
      final range = result[0].matches![0].indices[0];
      // Cutting the value by code units must yield exactly "needle".
      expect(value.substring(range[0], range[1] + 1), 'needle');
    });
  });

  group('Bitap: pattern alphabet and MAX_BITS', () {
    test('exact 32-char pattern matches (MAX_BITS boundary)', () {
      final pattern = 'a' * 32;
      final result = Fuse.match(
        pattern,
        'x' * 10 + pattern + 'y' * 10,
        FuseOptions<dynamic>(includeMatches: true),
      );
      expect(result.isMatch, isTrue);
      // Same score JS produces (location 10 vs expected 0 contributes
      // proximity/distance = 10/100, refined by the fuzzy loop).
      expect(result.score, 0.16375);
      expect(result.indices, [
        [10, 41]
      ]);
    });

    test('33+ char patterns are chunked and indices merge without duplicates',
        () {
      final pattern = 'a' * 40;
      final text = 'z' * 5 + pattern + 'z' * 5;
      final result = Fuse.match(
        pattern,
        text,
        FuseOptions<dynamic>(includeMatches: true, threshold: 0.1),
      );

      expect(result.isMatch, isTrue);
      final indices = result.indices!;
      // Verified against Fuse.js 7.5.0: the chunked search converges on this
      // window, not the full 40-char span.
      expect(indices, [
        [5, 39]
      ]);
    });

    test('duplicate pattern characters OR into one mask bit per position', () {
      // 'banana' has repeated 'a'/'n' — the alphabet must not double-count.
      final result = Fuse.match(
        'banana',
        'a banana split',
        FuseOptions<dynamic>(includeMatches: true),
      );
      expect(result.isMatch, isTrue);
      final value = 'a banana split';
      final range = result.indices![0];
      expect(value.substring(range[0], range[1] + 1), 'banana');
    });
  });

  group('Bitap: minMatchCharLength', () {
    test('exact match shorter than minMatchCharLength is rejected', () {
      final result = Fuse.match(
        'abc',
        'abc',
        FuseOptions<dynamic>(minMatchCharLength: 5),
      );
      expect(result.isMatch, isFalse);
    });

    test('fuzzy match spans are filtered by minMatchCharLength', () {
      final result = Fuse.match(
        'test',
        'a restless sea',
        FuseOptions<dynamic>(includeMatches: true, minMatchCharLength: 4),
      );
      if (result.isMatch) {
        for (final range in result.indices!) {
          expect(range[1] - range[0] + 1, greaterThanOrEqualTo(4));
        }
      }
    });
  });
}
