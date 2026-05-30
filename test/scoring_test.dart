import 'package:fuse_dart/fuse_dart.dart';
import 'package:test/test.dart';

void main() {
  final list = ['Stove', 'My good friend Steve from college'];

  group('Fuzzy search for "Steve"', () {
    test('ignoreFieldNorm off: Stove ranks first', () {
      final fuse = Fuse<String>(list);
      final result = fuse.search('Steve');
      expect(result, hasLength(2));
      expect(result[0].refIndex, 0);
      expect(result[1].refIndex, 1);
    });

    test('ignoreFieldNorm on: long field ranks first', () {
      final fuse = Fuse<String>(
        list,
        options: FuseOptions(ignoreFieldNorm: true),
      );
      final result = fuse.search('Steve');
      expect(result, hasLength(2));
      expect(result[0].refIndex, 1);
      expect(result[1].refIndex, 0);
    });

    test('decreased fieldNormWeight: long field ranks first', () {
      final fuse = Fuse<String>(
        list,
        options: FuseOptions(fieldNormWeight: 0.15),
      );
      final result = fuse.search('Steve');
      expect(result, hasLength(2));
      expect(result[0].refIndex, 1);
      expect(result[1].refIndex, 0);
    });
  });
}
