import 'dart:convert';
import 'dart:io';

import 'package:fuse_dart/fuse_dart.dart';

import 'fuse_benchmark.dart' show generateDataset;

/// Deterministic workload suite used to measure optimizations.
///
/// Run with `dart compile exe benchmark/perf_suite.dart` for stable numbers,
/// or `dart run benchmark/perf_suite.dart` during development.
///
/// Each workload is executed [samples] times after [warmup] untimed runs and
/// the median is reported as JSON.
///
/// In `--workload NAME` filtered mode the suite additionally reports
/// `mem{name: bytes}` — the peak incremental RSS attributable to that
/// workload, sampled around every run against a baseline taken after
/// fixture setup (the driver runs each filtered measurement in a fresh
/// process, so per-workload attribution is clean). Unlike the Go and JS
/// suites, Dart exposes no way to force a GC: the numbers are
/// peaks-including-uncollected-garbage (an upper bound on retained
/// state), and the VM reusing freed pages can make large retained
/// structures read low. Treat the numbers as cross-port ballparks.
void main(List<String> args) {
  final size = _arg(args, '--size', 10000);
  final samples = _arg(args, '--samples', 7);
  final warmup = _arg(args, '--warmup', 2);
  final only = _strArg(args, '--workload');

  final data = generateDataset(size);

  // Cross-language parity: `compare.mjs` diffs this against the JS twin's
  // dataset to prove both libraries are timed on identical input.
  if (args.contains('--dump-dataset')) {
    stdout.writeln(jsonEncode(data));
    return;
  }

  // Fixtures are built lazily so a `--workload` filtered run only pays
  // for (and only attributes memory to) what that workload needs.
  List<String>? stringsSlice;
  List<String> getStrings() =>
      stringsSlice ??= [for (final doc in data) doc['title'] as String];

  Fuse<Map<String, dynamic>>? fuseInst;
  Fuse<Map<String, dynamic>> getFuse() => fuseInst ??= Fuse(
        data,
        options: FuseOptions<Map<String, dynamic>>(
          keys: ['title', 'author.firstName', 'author.lastName'],
          includeScore: true,
        ),
      );

  Fuse<String>? stringFuseInst;
  Fuse<String> getStringFuse() =>
      stringFuseInst ??= Fuse(getStrings(), options: FuseOptions<String>());

  Fuse<Map<String, dynamic>>? unsortedInst;
  Fuse<Map<String, dynamic>> getUnsortedFuse() => unsortedInst ??= Fuse(
        data,
        options: FuseOptions<Map<String, dynamic>>(
          keys: ['title', 'author.firstName', 'author.lastName'],
          includeScore: true,
          shouldSort: false,
        ),
      );

  Fuse<Map<String, dynamic>>? extendedInst;
  Fuse<Map<String, dynamic>> getExtendedFuse() => extendedInst ??= Fuse(
        data,
        options: FuseOptions<Map<String, dynamic>>(
          keys: ['title', 'author.lastName'],
          useExtendedSearch: true,
          includeScore: true,
        ),
      );

  Fuse<Map<String, dynamic>>? matchInst;
  Fuse<Map<String, dynamic>> getMatchFuse() => matchInst ??= Fuse(
        data,
        options: FuseOptions<Map<String, dynamic>>(
          keys: ['title', 'author.lastName'],
          includeMatches: true,
        ),
      );

  // fixturesFor returns the fixture builders a workload needs, so a
  // filtered run can build exactly those before taking the memory
  // baseline.
  List<void Function()> fixturesFor(String name) {
    switch (name) {
      case 'fuzzy_obj_hit' ||
            'fuzzy_obj_miss' ||
            'fuzzy_obj_short' ||
            'logical' ||
            'sorted_limit':
        return [getFuse];
      case 'fuzzy_obj_unsorted':
        return [getUnsortedFuse];
      case 'fuzzy_str_hit':
        return [getStringFuse];
      case 'extended':
        return [getExtendedFuse];
      case 'include_matches':
        return [getMatchFuse];
      default: // index_build: raw data only
        return const [];
    }
  }

  final results = <String, double>{};
  final mem = <String, int>{};
  final memTrackers = <String, void Function()>{};

  void measure(String name, void Function() body) {
    if (only != null && only != name) {
      return;
    }
    if (only != null) {
      // Filtered mode: build this workload's fixtures, then take the RSS
      // baseline and track the peak current RSS across warmup + samples.
      for (final build in fixturesFor(name)) {
        build();
      }
      final baseRss = ProcessInfo.currentRss;
      void trackMem() {
        final d = ProcessInfo.currentRss - baseRss;
        if (d > (mem[name] ?? 0)) mem[name] = d;
      }

      memTrackers[name] = trackMem;
      for (var i = 0; i < warmup; i += 1) {
        body();
        trackMem();
      }
      final times = <int>[];
      for (var i = 0; i < samples; i += 1) {
        final sw = Stopwatch()..start();
        body();
        trackMem();
        sw.stop();
        times.add(sw.elapsedMicroseconds);
      }
      times.sort();
      results[name] = times[times.length ~/ 2].toDouble();
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
    Fuse(
      data,
      options: FuseOptions<Map<String, dynamic>>(
        keys: ['title', 'author.firstName', 'author.lastName'],
        includeScore: true,
      ),
    );
  });

  measure('fuzzy_obj_hit', () {
    getFuse().search('Old Man War');
  });

  measure('fuzzy_obj_miss', () {
    getFuse().search('qzxvbnm');
  });

  measure('fuzzy_obj_unsorted', () {
    getUnsortedFuse().search('Old Man War');
  });

  measure('fuzzy_obj_short', () {
    getFuse().search('old');
  });

  measure('fuzzy_str_hit', () {
    getStringFuse().search('Old Man War');
  });

  measure('extended', () {
    getExtendedFuse().search("'Old ^War | =Scalzi");
  });

  measure('logical', () {
    getFuse().search({
      r'$and': [
        {'title': 'Old'},
        {'author.lastName': 'Grant'},
      ],
    });
  });

  measure('include_matches', () {
    getMatchFuse().search('Old Man War');
  });

  measure('sorted_limit', () {
    getFuse().search('Old Man War', limit: 10);
  });

  print(jsonEncode({
    'size': size,
    'samples': samples,
    'results': results,
    if (mem.isNotEmpty) 'mem': mem,
  }));
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
