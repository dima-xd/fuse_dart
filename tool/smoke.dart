import 'package:fuse_dart/fuse_dart.dart';

void main() {
  // Basic string search
  final fuse = Fuse<String>(['Apple', 'Orange', 'Banana']);
  print(fuse.search('nan').map((r) => '${r.item}@${r.refIndex}').toList());
  print('empty query returns: ${fuse.search('').length}');
  print('limit: ${fuse.search('nan', limit: 1).length}');

  // Weighted object search
  final books = [
    {
      'title': "Old Man's War",
      'author': {'firstName': 'John', 'lastName': 'Scalzi'},
    },
    {
      'title': 'The Lock Artist',
      'author': {'firstName': 'Steve', 'lastName': 'Hamilton'},
    },
  ];
  final f2 = Fuse(
    books,
    options: FuseOptions<dynamic>(
      keys: ['title', 'author.firstName'],
      includeScore: true,
    ),
  );
  print(f2.search('Stve').map((r) => r.refIndex).toList());

  // Include matches with indices
  final f3 = Fuse(
    [
      {'name': 'Hello World'}
    ],
    options: FuseOptions<dynamic>(
      keys: ['name'],
      includeMatches: true,
      includeScore: true,
    ),
  );
  final r3 = f3.search('wor');
  print('indices: ${r3[0].matches![0].indices}');

  // Token search
  final f4 = Fuse<String>(
    ['red shirt', 'red hat', 'blue shirt'],
    options:
        FuseOptions(useTokenSearch: true, threshold: 0.2, tokenMatch: 'all'),
  );
  print('token AND: ${f4.search('red shirt').map((r) => r.item).toList()}');

  // Extended search
  final f6 = Fuse<String>(
    ['old man\'s war', 'the lock artist'],
    options: FuseOptions<String>(useExtendedSearch: true),
  );
  print('extended ^lock: ${f6.search('^lock').map((r) => r.item).toList()}');

  // Fuse.match
  print(
      'match: ${Fuse.match('abc', 'abxc', FuseOptions<dynamic>(includeMatches: true)).indices}');

  // Logical search
  final f7 = Fuse(
    books,
    options: FuseOptions<dynamic>(
      keys: ['title', 'author.firstName'],
      useExtendedSearch: true,
      includeScore: true,
    ),
  );
  print('logical: ${f7.search({
            'title': 'old man'
          }).map((r) => r.refIndex).toList()}');
}
