import 'package:fuse_dart/fuse_dart.dart';

class Book {
  const Book(this.title, this.author);
  final String title;
  final String author;
}

void main() {
  final fruits = ['Apple', 'Orange', 'Banana'];
  final stringFuse = Fuse<String>(fruits);
  print('Fuzzy "nan": ${stringFuse.search('nan').map((r) => r.item).toList()}');

  final books = <Map<String, dynamic>>[
    {
      'title': "Old Man's War",
      'author': {'firstName': 'John', 'lastName': 'Scalzi'},
    },
    {
      'title': 'The Lock Artist',
      'author': {'firstName': 'Steve', 'lastName': 'Hamilton'},
    },
    {
      'title': 'HTML5',
      'author': {'firstName': 'Remy', 'lastName': 'Sharp'},
    },
  ];

  final mapFuse = Fuse(
    books,
    options: FuseOptions<Map<String, dynamic>>(
      keys: ['title', 'author.firstName'],
      includeScore: true,
      includeMatches: true,
      threshold: 0.4,
    ),
  );

  for (final result in mapFuse.search('Stve')) {
    print('Match: ${result.item['title']} (score ${result.score})');
    for (final match in result.matches!) {
      print('  field ${match.key} -> ${match.indices}');
    }
  }

  final weightedFuse = Fuse(
    books,
    options: FuseOptions<Map<String, dynamic>>(
      keys: [
        FuseKey<Map<String, dynamic>>(name: 'title', weight: 0.7),
        FuseKey<Map<String, dynamic>>(name: 'author.lastName', weight: 0.3),
      ],
    ),
  );
  print('Weighted "scalzi": '
      '${weightedFuse.search('scalzi').map((r) => r.item['title']).toList()}');

  final extendedFuse = Fuse(
    books,
    options: FuseOptions<Map<String, dynamic>>(
      keys: ['title'],
      useExtendedSearch: true,
    ),
  );
  print('Extended "\'Lock | ^HTML": '
      '${extendedFuse.search("'Lock | ^HTML").map((r) => r.item['title']).toList()}');

  final models = const [
    Book("Old Man's War", 'John Scalzi'),
    Book('The Lock Artist', 'Steve Hamilton'),
  ];
  final typedFuse = Fuse<Book>(
    models,
    options: FuseOptions<Book>(
      keys: [
        FuseKey<Book>(name: 'title', getFn: (b) => b.title),
        FuseKey<Book>(name: 'author', getFn: (b) => b.author),
      ],
    ),
  );
  print('Typed model "hamilton": '
      '${typedFuse.search('hamilton').map((r) => r.item.title).toList()}');
}
