import 'package:fuse_dart/fuse_dart.dart';

List<Map<String, dynamic>> generateDataset(int size) {
  const firstNames = [
    'John',
    'Steve',
    'Remy',
    'Dan',
    'Max',
    'Rob',
    'David',
    'Brad',
    'Christopher',
    'Stephen',
  ];
  const lastNames = [
    'Scalzi',
    'Hamilton',
    'Sharp',
    'Brown',
    'Barry',
    'Grant',
    'Maine',
    'Meltzer',
    'Moore',
    'Hawking',
  ];
  const words = [
    'Old',
    'Man',
    'War',
    'Lock',
    'Artist',
    'Code',
    'Lost',
    'Symbol',
    'Book',
    'Lies',
    'Grand',
    'Design',
    'Monster',
    'Fallen',
    'Colony',
    'Backwards',
  ];

  return List.generate(size, (i) {
    final title = List.generate(
      3,
      (j) => words[(i * 7 + j * 13) % words.length],
    ).join(' ');
    return {
      'id': i,
      'title': '$title $i',
      'author': {
        'firstName': firstNames[i % firstNames.length],
        'lastName': lastNames[(i ~/ 3) % lastNames.length],
      },
    };
  });
}

void measure(String label, int iterations, void Function() body) {
  body();
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i += 1) {
    body();
  }
  stopwatch.stop();
  final perOp = stopwatch.elapsedMicroseconds / iterations;
  print('$label: ${perOp.toStringAsFixed(1)} us/op over $iterations ops');
}

void main() {
  for (final size in [1000, 10000]) {
    final data = generateDataset(size);
    final options = FuseOptions<Map<String, dynamic>>(
      keys: ['title', 'author.firstName', 'author.lastName'],
      includeScore: true,
    );

    measure('Index build (size=$size)', 10, () {
      Fuse(data, options: options);
    });

    final fuse = Fuse(data, options: options);

    measure('Fuzzy search (size=$size)', 50, () {
      fuse.search('Old Man War');
    });

    final extendedFuse = Fuse(
      data,
      options: FuseOptions<Map<String, dynamic>>(
        keys: ['title', 'author.lastName'],
        useExtendedSearch: true,
        includeScore: true,
      ),
    );

    measure('Extended search (size=$size)', 50, () {
      extendedFuse.search("'Old ^War | =Scalzi");
    });

    measure('Logical search (size=$size)', 50, () {
      fuse.search({
        r'$and': [
          {'title': 'Old'},
          {'author.lastName': 'Grant'},
        ],
      });
    });
  }
}
