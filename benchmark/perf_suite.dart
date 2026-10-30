import 'dart:convert';

import 'package:fuse_dart/fuse_dart.dart';

import 'fuse_benchmark.dart' show generateDataset;

/// Deterministic workload suite used to measure optimizations.
///
/// Run with `dart compile exe benchmark/perf_suite.dart` for stable numbers,
/// or `dart run benchmark/perf_suite.dart` during development.
///
/// Each workload is executed [samples] times after [warmup] untimed runs and
/// the median is reported as JSON.
void main(List<String> args) {
  final size = _arg(args, '--size', 10000);
  final samples = _arg(args, '--samples', 7);
  final warmup = _arg(args, '--warmup', 2);
  final only = _strArg(args, '--workload');

  final data = generateDataset(size);
  final strings = [for (final doc in data) doc['title'] as String];

  final options = FuseOptions<Map<String, dynamic>>(
    keys: ['title', 'author.firstName', 'author.lastName'],
    includeScore: true,
  );
  final fuse = Fuse(data, options: options);

  final stringOptions = FuseOptions<String>();
  final stringFuse = Fuse(strings, options: stringOptions);

  final unsortedFuse = Fuse(
    data,
    options: FuseOptions<Map<String, dynamic>>(
      keys: ['title', 'author.firstName', 'author.lastName'],
      includeScore: true,
      shouldSort: false,
    ),
  );

  final extendedFuse = Fuse(
    data,
    options: FuseOptions<Map<String, dynamic>>(
      keys: ['title', 'author.lastName'],
      useExtendedSearch: true,
      includeScore: true,
    ),
  );

  final matchFuse = Fuse(
    data,
    options: FuseOptions<Map<String, dynamic>>(
      keys: ['title', 'author.lastName'],
      includeMatches: true,
    ),
  );

  final results = <String, double>{};

  void measure(String name, void Function() body) {
    if (only != null && only != name) {
      return;
    }
    for (var i = 0; i < warmup; i += 1) {
      body();
    }
    final times = <int>[];
    for (var i = 0; i < samples; i += 1) {
      final sw = Stopwatch()..start();
      body();
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }
    times.sort();
    results[name] = times[times.length ~/ 2].toDouble();
  }

  measure('index_build', () {
    Fuse(data, options: options);
  });

  measure('fuzzy_obj_hit', () {
    fuse.search('Old Man War');
  });

  measure('fuzzy_obj_miss', () {
    fuse.search('qzxvbnm');
  });

  measure('fuzzy_obj_unsorted', () {
    unsortedFuse.search('Old Man War');
  });

  measure('fuzzy_obj_short', () {
    fuse.search('old');
  });

  measure('fuzzy_str_hit', () {
    stringFuse.search('Old Man War');
  });

  measure('extended', () {
    extendedFuse.search("'Old ^War | =Scalzi");
  });

  measure('logical', () {
    fuse.search({
      r'$and': [
        {'title': 'Old'},
        {'author.lastName': 'Grant'},
      ],
    });
  });

  measure('include_matches', () {
    matchFuse.search('Old Man War');
  });

  measure('sorted_limit', () {
    fuse.search('Old Man War', limit: 10);
  });

  print(jsonEncode({'size': size, 'samples': samples, 'results': results}));
}

int _arg(List<String> args, String name, int fallback) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return fallback;
  }
  return int.parse(args[index + 1]);
}

String? _strArg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}
