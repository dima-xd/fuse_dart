/// Interactive demo mirroring <https://fusejs.io/demo.html>.
///
/// Same data (19 books), same keys (`title`, `author.firstName`,
/// `author.lastName`), and the same toggles as the web demo's options bar:
///
///   threshold           0.0–1.0 in 0.1 steps, default 0.6
///   includeScore        on by default
///   includeMatches      on by default (drives the highlights)
///   ignoreLocation      off by default
///   useExtendedSearch   off by default
///   useTokenSearch      off by default
///
/// Run interactively:
///
///   dart run example/demo.dart
///
/// Or one-shot with flags:
///
///   dart run example/demo.dart "old man" --threshold=0.4 --useTokenSearch
///
/// REPL commands (anything else is a query):
///   `threshold <0..1>`    set the threshold slider
///   `toggle <option>`     flip a boolean toggle
///   options               show the current option bar state
///   `data <file.json>`    replace the corpus with a JSON file of books
///   help                  show this list
///   quit                  exit
library;

import 'dart:convert';
import 'dart:io';

import 'package:fuse_dart/fuse_dart.dart';

import 'books.dart';

/// The demo's keys — identical to the web demo's Code panel.
const List<Object> demoKeys = [
  'title',
  'author.firstName',
  'author.lastName',
];

void main(List<String> args) {
  final state = _DemoState();

  // One-shot mode: `dart run example/demo.dart "query" [--flag=value]`.
  if (args.isNotEmpty) {
    final flags = args.where((a) => a.startsWith('--')).toList();
    final query = args.where((a) => !a.startsWith('--')).join(' ');
    for (final flag in flags) {
      state.applyCliFlag(flag);
    }
    if (query.isNotEmpty) {
      state.searchAndPrint(query);
    } else {
      state.printOptions();
    }
    return;
  }

  print('fuse_dart demo — mirrors https://fusejs.io/demo.html');
  print('Type a query (e.g. "old man", "ste ham", "^the"), or: help');
  state.printOptions();

  while (true) {
    stdout.write('\nquery> ');
    final line = stdin.readLineSync();
    if (line == null) break;
    final input = line.trim();
    if (input.isEmpty) continue;

    if (input == 'quit' || input == 'exit' || input == 'q') break;

    if (!state.handleCommand(input)) {
      state.searchAndPrint(input);
    }
  }
}

class _DemoState {
  // Toggles — same defaults as the web demo's options bar.
  double threshold = 0.6;
  bool includeScore = true;
  bool includeMatches = true;
  bool ignoreLocation = false;
  bool useExtendedSearch = false;
  bool useTokenSearch = false;

  List<Map<String, Object?>> books = List.of(demoBooks);

  static const _toggles = {
    'includeScore',
    'includeMatches',
    'ignoreLocation',
    'useExtendedSearch',
    'useTokenSearch',
  };

  /// Applies `--flag[=value]` CLI flags. Returns false for unknown flags.
  void applyCliFlag(String flag) {
    final body = flag.substring(2);
    final eq = body.indexOf('=');
    final name = eq == -1 ? body : body.substring(0, eq);
    final value = eq == -1 ? null : body.substring(eq + 1);

    switch (name) {
      case 'threshold':
        threshold = double.parse(value ?? '0.6');
      case 'ignoreLocation' ||
          'useExtendedSearch' ||
          'useTokenSearch' ||
          'includeScore' ||
          'includeMatches':
        final toggle = name;
        final on = value == null ? true : value == 'true';
        if (toggle == 'ignoreLocation') ignoreLocation = on;
        if (toggle == 'useExtendedSearch') useExtendedSearch = on;
        if (toggle == 'useTokenSearch') useTokenSearch = on;
        if (toggle == 'includeScore') includeScore = on;
        if (toggle == 'includeMatches') includeMatches = on;
      default:
        stderr.writeln('unknown flag: $flag');
    }
  }

  /// Handles a REPL command; returns true when the input was consumed.
  bool handleCommand(String input) {
    final parts = input.split(RegExp(r'\s+'));
    final command = parts[0].toLowerCase();

    switch (command) {
      case 'help' || 'h' || '?':
        _printHelp();
        return true;
      case 'options' || 'opts':
        printOptions();
        return true;
      case 'threshold' || 't':
        if (parts.length > 1) {
          final value = double.tryParse(parts[1]);
          if (value == null || value < 0 || value > 1) {
            print('threshold must be between 0.0 and 1.0');
          } else {
            threshold = value;
            printOptions();
          }
        } else {
          print('usage: threshold <0..1>   (current: $threshold)');
        }
        return true;
      case 'toggle' || 'flip':
        if (parts.length > 1 && _toggles.contains(parts[1])) {
          _flip(parts[1]);
          printOptions();
        } else {
          print('usage: toggle <${_toggles.join('|')}>');
        }
        return true;
      case 'data':
        if (parts.length > 1) {
          _loadData(parts.sublist(1).join(' '));
        } else {
          print('usage: data <file.json>');
        }
        return true;
      default:
        // Bare toggle names flip directly, like clicking the checkbox.
        if (_toggles.contains(parts[0])) {
          _flip(parts[0]);
          printOptions();
          return true;
        }
        return false;
    }
  }

  void _flip(String name) {
    switch (name) {
      case 'includeScore':
        includeScore = !includeScore;
      case 'includeMatches':
        includeMatches = !includeMatches;
      case 'ignoreLocation':
        ignoreLocation = !ignoreLocation;
      case 'useExtendedSearch':
        useExtendedSearch = !useExtendedSearch;
      case 'useTokenSearch':
        useTokenSearch = !useTokenSearch;
    }
  }

  void _loadData(String path) {
    try {
      final raw = jsonDecode(File(path).readAsStringSync()) as List;
      books = [
        for (final item in raw.cast<Map<String, Object?>>()) item,
      ];
      print('loaded ${books.length} items from $path');
      printOptions();
    } catch (e) {
      print('could not load $path: $e');
    }
  }

  void printOptions() {
    final bar = [
      'threshold: ${threshold.toStringAsFixed(1)}',
      'includeScore: ${includeScore ? '✔' : '✘'}',
      'includeMatches: ${includeMatches ? '✔' : '✘'}',
      'ignoreLocation: ${ignoreLocation ? '✔' : '✘'}',
      'useExtendedSearch: ${useExtendedSearch ? '✔' : '✘'}',
      'useTokenSearch: ${useTokenSearch ? '✔' : '✘'}',
    ].join('   ');
    print('[$bar]   (${books.length} items)');
  }

  /// Runs the search exactly like the demo's Code panel:
  ///
  ///   const fuse = new Fuse(books, {
  ///     includeScore: true,
  ///     includeMatches: true,
  ///     keys: ['title', 'author.firstName', 'author.lastName'],
  ///     ...currentToggles
  ///   })
  void searchAndPrint(String query) {
    final fuse = Fuse<Map<String, Object?>>(
      books,
      options: FuseOptions<Map<String, Object?>>(
        keys: demoKeys,
        threshold: threshold,
        includeScore: includeScore,
        includeMatches: includeMatches,
        ignoreLocation: ignoreLocation,
        useExtendedSearch: useExtendedSearch,
        useTokenSearch: useTokenSearch,
      ),
    );

    final results = fuse.search(query);

    if (results.isEmpty) {
      print('No results');
      return;
    }

    for (var rank = 0; rank < results.length; rank++) {
      final result = results[rank];
      final doc = result.item;
      final meta = <String>[
        if (includeScore)
          'score: ${result.score!.toStringAsFixed(result.score == 0 ? 3 : 4)}',
        'refIndex: ${result.refIndex}',
      ].join(', ');

      print('');
      print('${rank + 1}. $meta');

      // Per-field rendering with highlights, like the demo's result rows.
      final lines = <String>[
        _renderField(doc, result, 'title', fallback: doc['title']?.toString()),
        _renderAuthor(doc, result),
      ];
      for (final line in lines) {
        print('   $line');
      }
    }
  }

  /// Highlights the matched ranges within one field's text.
  ///
  /// `match.value` is the indexed text for the field, and `match.indices`
  /// are inclusive [start, end] UTF-16 code-unit ranges — the same numbers
  /// the JS demo feeds to its highlight spans.
  String _highlight(
    String? text,
    List<RangeTuple>? indices,
  ) {
    if (text == null) return '';
    if (indices == null || indices.isEmpty) return text;

    final buffer = StringBuffer();
    var cursor = 0;
    for (final range in indices) {
      final start = range[0];
      final end = range[1];
      if (start > text.length || end >= text.length && start > text.length) {
        continue;
      }
      buffer.write(text.substring(cursor, start.clamp(0, text.length)));
      final hiStart = start.clamp(0, text.length);
      final hiEnd = (end + 1).clamp(0, text.length);
      final matched = text.substring(hiStart, hiEnd);
      buffer.write(_emphasize(matched));
      cursor = hiEnd;
    }
    if (cursor < text.length) {
      buffer.write(text.substring(cursor));
    }
    return buffer.toString();
  }

  String _renderField(
    Map<String, Object?> doc,
    FuseResult<Map<String, Object?>> result,
    String keyId, {
    String? fallback,
  }) {
    final match = result.matches?.where((m) => m.key == keyId).toList();
    final text = fallback ?? '';
    if (match == null || match.isEmpty) {
      return text;
    }
    return _highlight(text, match[0].indices);
  }

  String _renderAuthor(Map<String, Object?> doc, FuseResult<Map<String, Object?>> result) {
    final author = doc['author'];
    if (author is! Map) return '';
    final first = author['firstName']?.toString() ?? '';
    final last = author['lastName']?.toString() ?? '';
    final firstRendered =
        _renderField(doc, result, 'author.firstName', fallback: first);
    final lastRendered =
        _renderField(doc, result, 'author.lastName', fallback: last);
    return [firstRendered, lastRendered].where((s) => s.isNotEmpty).join(' ');
  }
}

String _emphasize(String text) {
  if (stdout.supportsAnsiEscapes) {
    // Bold + underline, like the demo's <mark> styling.
    return '\x1B[1m\x1B[4m$text\x1B[0m';
  }
  return '<<$text>>';
}

void _printHelp() {
  print('''
Commands:
  threshold <0..1>          set the threshold slider (demo: range 0–1, step 0.1)
  toggle <option>           flip includeScore / includeMatches / ignoreLocation /
                            useExtendedSearch / useTokenSearch
  options                   show the option bar state
  data <file.json>          replace the corpus with a JSON array of books
  help                      show this help
  quit                      exit

Anything else is treated as a search query.''');
}
