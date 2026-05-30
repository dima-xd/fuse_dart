import 'package:fuse_dart/fuse_dart.dart';
import 'package:test/test.dart';

import 'fixtures/books.dart';

List<int> idx<T>(List<FuseResult<T>> result) =>
    result.map((r) => r.refIndex).toList();

void main() {
  final keys = <Object>['title', 'author.firstName', 'author.lastName'];
  FuseOptions<Map<String, dynamic>> options() => FuseOptions(
        useExtendedSearch: true,
        includeMatches: true,
        includeScore: true,
        threshold: 0.3,
        keys: keys,
      );

  test('createIndex: records and keys exist', () {
    final index = Fuse.createIndex(keys, books);
    expect(index.records, isNotEmpty);
    expect(index.keys, isNotEmpty);
  });

  test('createIndex: keys can be created with key objects', () {
    final index = Fuse.createIndex(
      [
        FuseKey<Map<String, dynamic>>(name: 'title'),
        FuseKey<Map<String, dynamic>>(name: 'author.firstName'),
      ],
      books,
    );
    expect(index.records, isNotEmpty);
    expect(index.keys, isNotEmpty);
  });

  test('createIndex: keys can be created with getFn', () {
    final index = Fuse.createIndex(
      [
        FuseKey<Map<String, dynamic>>(name: 'title', getFn: (b) => b['title']),
        FuseKey<Map<String, dynamic>>(
            name: 'authorName',
            getFn: (b) => (b['author'] as Map)['firstName']),
      ],
      books,
    );
    expect(index.records, isNotEmpty);
    expect(index.keys, isNotEmpty);
  });

  test('parseIndex: index can be exported and reused', () {
    final myIndex = Fuse.createIndex(keys, books);
    expect(myIndex.size(), books.length);

    final data = myIndex.toJson();
    expect(data['records'], isNotNull);
    expect(data['keys'], isNotNull);

    final parsed = Fuse.parseIndex<Map<String, dynamic>>(data);
    expect(parsed.size(), books.length);

    final fuse = Fuse(books, options: options(), index: parsed);
    final result = fuse.search({'title': 'old man'});
    expect(result.length, 1);
    expect(idx(result), [0]);
  });

  test('parseIndex: search with getFn keys', () {
    final fuse = Fuse(
      books,
      options: FuseOptions<Map<String, dynamic>>(
        useExtendedSearch: true,
        includeMatches: true,
        includeScore: true,
        threshold: 0.3,
        keys: [
          FuseKey<Map<String, dynamic>>(
              name: 'bookTitle', getFn: (b) => b['title']),
          FuseKey<Map<String, dynamic>>(
              name: 'authorName',
              getFn: (b) => (b['author'] as Map)['firstName']),
        ],
      ),
    );
    final result = fuse.search({'bookTitle': 'old man'});
    expect(result.length, 1);
    expect(idx(result), [0]);
  });

  test('Fuse can be instantiated with an index', () {
    final myIndex = Fuse.createIndex(keys, books);
    final fuse = Fuse(books, options: options(), index: myIndex);
    final result = fuse.search({'title': 'old man'});
    expect(idx(result), [0]);
    expect(result[0].matches![0].indices, [(0, 2), (4, 6)]);
  });

  test('throws on invalid index format', () {
    expect(
      () => Fuse(books, options: options(), index: <int>[]),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('add object to index', () {
    final data = List<Map<String, dynamic>>.of(books);
    final fuse = Fuse(data, options: options());
    fuse.add({
      'title': 'book',
      'author': {'firstName': 'Kiro', 'lastName': 'Risk'},
    });
    final result = fuse.search('kiro');
    expect(result.length, 1);
    expect(idx(result), [data.length - 1]);
  });

  test('add string to index', () {
    final fruits = <String>['apple', 'orange'];
    final fuse = Fuse<String>(fruits, options: FuseOptions(includeScore: true));
    fuse.add('banana');
    final result = fuse.search('banana');
    expect(result.length, 1);
    expect(idx(result), [2]);
  });

  test('remove string from the index', () {
    final fruits = <String>['apple', 'orange', 'banana', 'pear'];
    final fuse = Fuse<String>(fruits);

    expect(fuse.getIndex().size(), 4);
    final initial = fuse.getIndex().records.cast<StringRecord>();
    expect(initial.map((r) => [r.v, r.i]).toList(), [
      ['apple', 0],
      ['orange', 1],
      ['banana', 2],
      ['pear', 3],
    ]);

    fuse.removeAt(1);
    expect(fuse.getIndex().size(), 3);

    final records = fuse.getIndex().records.cast<StringRecord>();
    expect(records.map((r) => [r.v, r.i]).toList(), [
      ['apple', 0],
      ['banana', 1],
      ['pear', 2],
    ]);

    final removed = fuse.remove((doc, _) => doc == 'banana' || doc == 'pear');
    expect(removed.length, 2);
    expect(fuse.getIndex().size(), 1);

    final remaining = fuse.getIndex().records.cast<StringRecord>();
    expect(remaining.single.v, 'apple');
  });
}
