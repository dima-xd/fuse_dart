import 'package:fuse_dart/fuse_dart.dart';
import 'package:fuse_dart/src/helpers/types.dart' show FuseException;
import 'package:test/test.dart';

/// A document type unrelated to Map/String, so type mismatches are real.
class Def {
  Def(this.id, this.description);
  final String id;
  final String description;
}

/// Regression tests for the generic-variance bug in `createKey<T>` and
/// pins for how mismatched custom getters degrade.
///
/// Dart generics are covariant with runtime checks: reading a
/// T-dependent function member (getFn) through a covariant supertype view
/// (`FuseKey<dynamic>`) inserts an implicit subtype check that throws for
/// closures built for a narrower document type. `createKey` must never
/// perform that erase-at-read; the tests below hold that contract down for
/// every key shape (typed FuseKey, dynamic FuseKey, mismatched FuseKey,
/// map keys, and non-key objects).
void main() {
  final defs = [
    Def('one', 'alpha definition'),
    Def('two', 'beta definition'),
  ];

  final maps = [
    {'title': 'apple pie'},
    {'title': 'banana split'},
  ];

  group('createKey: typed FuseKey<T> (the variance regression)', () {
    test('FuseKey<Def> drives Fuse<Def> — getFn value is indexed, not the path',
        () {
      final fuse = Fuse<Def>(
        defs,
        options: FuseOptions<Def>(
          keys: [
            // getFn returns strings unrelated to any field value, so a hit
            // can only come from the custom getter.
            FuseKey<Def>(
              name: 'id',
              getFn: (d) => d.id == 'one' ? 'xxxyyzzz' : 'aaabbbccc',
            ),
          ],
        ),
      );

      expect(fuse.search('xxxyyzzz').first.item.id, 'one');
      expect(fuse.search('aaabbbccc').first.item.id, 'two');

      // The raw field values are gone from the index entirely.
      expect(fuse.search('one'), isEmpty);
      expect(fuse.search('two'), isEmpty);
    });
  });

  group('createKey: FuseKey<dynamic> keeps its getFn', () {
    test('a dynamic getter stays active under a typed Fuse', () {
      final fuse = Fuse<Map<String, dynamic>>(
        maps,
        options: FuseOptions<Map<String, dynamic>>(
          keys: [
            FuseKey<dynamic>(
              name: 'title',
              getFn: (d) =>
                  (d as Map)['title'] == 'apple pie' ? 'uqzxejwm' : 'rlkvhnpc',
            ),
          ],
        ),
      );

      expect(fuse.search('uqzxejwm').first.item['title'], 'apple pie');
      expect(fuse.search('rlkvhnpc').first.item['title'], 'banana split');
      // The real field values are not indexed: the getter replaced them.
      // (Tokens share no ordered subsequence with these queries, so no
      // threshold-boundary fuzzy match can sneak in.)
      expect(fuse.search('apple'), isEmpty);
      expect(fuse.search('banana'), isEmpty);
    });
  });

  group('createKey: mismatched FuseKey<Other> degrades to path lookup', () {
    test('no crash; path fallback indexes the real value; getFn output ignored',
        () {
      final fuse = Fuse<Map<String, dynamic>>(
        maps,
        options: FuseOptions<Map<String, dynamic>>(
          keys: [
            FuseKey<String>(name: 'title', getFn: (s) => 'zzzzzzzzz'),
          ],
        ),
      );

      // Falls back to the 'title' path: the real text is searchable.
      expect(fuse.search('apple pie').first.item['title'], 'apple pie');
      // The getFn output would have been 'zzzzzzzzz' — proves it was dropped.
      expect(fuse.search('zzzzzzzzz'), isEmpty);
    });

    test('name/weight are still honored from the mismatched key', () {
      final fuse = Fuse<Map<String, dynamic>>(
        [
          {'title': 'apple pie', 'body': 'apple apple'},
          {'title': 'banana split', 'body': 'apple'},
        ],
        options: FuseOptions<Map<String, dynamic>>(
          includeScore: true,
          keys: [
            FuseKey<String>(name: 'title', weight: 10, getFn: (s) => 'zzz'),
            'body',
          ],
        ),
      );

      // With title weighted 10x, the title hit must outrank the double
      // body hit despite fuzzy equality of the other dimension.
      final top = fuse.search('apple').first;
      expect(top.item['title'], 'apple pie');
    });
  });

  group('createKey: map-key getFn mismatch is a silent drop (documented)', () {
    test('mismatched closure falls back to the path without crashing', () {
      final fuse = Fuse<Map<String, dynamic>>(
        maps,
        options: FuseOptions<Map<String, dynamic>>(
          keys: [
            {
              'name': 'title',
              'getFn': (String s) => 'zzzzzzzzz',
            },
          ],
        ),
      );

      expect(fuse.search('apple pie').first.item['title'], 'apple pie');
      expect(fuse.search('zzzzzzzzz'), isEmpty);
    });
  });

  group('createKey: options reused across document types', () {
    test(
        'one options object serves Fuse<String> and Fuse<dynamic> without crashing',
        () {
      final options = FuseOptions<String>(
        keys: [
          FuseKey<String>(name: 'title', getFn: (s) => 'NEVER-$s'),
        ],
      );

      // Fuse<String> over string docs whose "path" is the whole string.
      final strFuse = Fuse<String>(['apple pie'], options: options);
      // FuseKey<String> is exact for T=String: getFn drives the value.
      expect(strFuse.search('NEVER-apple').first.item, 'apple pie');

      // Same options under a different doc type: FuseOptions<String> is a
      // valid FuseOptions<dynamic> (covariance), and the mismatched key
      // degrades to path lookup instead of throwing.
      final mapFuse = Fuse<dynamic>(maps, options: options);
      expect(mapFuse.search('apple pie').first.item['title'], 'apple pie');
      expect(mapFuse.search('zzzzzzzzz'), isEmpty);
    });
  });

  group('createKey: invalid inputs', () {
    test('a non-key object raises FuseException with a clear message', () {
      expect(
        () => Fuse<Def>(
          defs,
          options: FuseOptions<Def>(keys: [42]),
        ),
        throwsA(
          isA<FuseException>().having(
            (e) => e.toString(),
            'message',
            contains('Invalid key type'),
          ),
        ),
      );
    });

    test('zero-weight FuseKey (exact T) still raises invalidKeyWeightValue',
        () {
      expect(
        () => Fuse<Def>(
          defs,
          options: FuseOptions<Def>(
            keys: [FuseKey<Def>(name: 'id', weight: 0)],
          ),
        ),
        throwsA(
          isA<FuseException>().having(
            (e) => e.toString(),
            'message',
            contains("Property 'weight' in key 'id'"),
          ),
        ),
      );
    });

    test('zero-weight mismatched FuseKey still raises invalidKeyWeightValue',
        () {
      expect(
        () => Fuse<Map<String, dynamic>>(
          maps,
          options: FuseOptions<Map<String, dynamic>>(
            keys: [FuseKey<String>(name: 'title', weight: 0, getFn: (s) => s)],
          ),
        ),
        throwsA(isA<FuseException>()),
      );
    });
  });

  group('global Fuse.config.getFn flows through FuseOptions<T>', () {
    // Pins the `globalFuseConfig.getFn as GetFunction<T>` fallback sites
    // (config.dart, fuse_index.dart): the global default must serve every
    // document type, since its declared type accepts anything.
    final saved = Fuse.config.getFn;

    tearDown(() {
      Fuse.config.getFn = saved;
    });

    test('a custom global getter drives a Fuse built without one', () {
      // The getter maps each doc to a token unrelated to any field value,
      // so hits can only come through the global getter. Map docs, since
      // the default path helper can't read custom-class fields by name.
      Fuse.config.getFn = (Object? obj, Object path) =>
          get(obj, path) == 'apple pie' ? 'uqzxejwm' : 'rlkvhnpc';

      final fuse = Fuse<Map<String, dynamic>>(
        maps,
        options: FuseOptions<Map<String, dynamic>>(keys: ['title']),
      );

      expect(fuse.search('uqzxejwm').first.item['title'], 'apple pie');
      expect(fuse.search('rlkvhnpc').first.item['title'], 'banana split');
      expect(fuse.search('apple'), isEmpty);
    });

    test('createFuseIndex falls back to the global getter when none is passed',
        () {
      Fuse.config.getFn = (Object? obj, Object path) =>
          get(obj, path) == 'apple pie' ? 'uqzxejwm' : 'rlkvhnpc';

      // Exercises the fallback cast inside createFuseIndex directly.
      final index = createFuseIndex<Map<String, dynamic>>(['title'], maps);
      final fuse = Fuse<Map<String, dynamic>>(maps, index: index);

      expect(fuse.search('uqzxejwm').first.item['title'], 'apple pie');
    });
  });
}
