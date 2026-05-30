import '../search/create_searcher.dart';
import '../search/searcher.dart';
import '../tools/key_store.dart';
import 'config.dart';
import 'error_messages.dart';

const String logicalAnd = r'$and';
const String logicalOr = r'$or';
const String keyTypePath = r'$path';
const String keyTypePattern = r'$val';

bool _isExpression(Map query) =>
    query[logicalAnd] != null || query[logicalOr] != null;

bool _isPath(Map query) => query[keyTypePath] != null;

bool _isLeaf(Object query) => query is Map && !_isExpression(query);

Map<String, dynamic> _convertToExplicit(Map query) => {
      logicalAnd: query.keys.map((key) => {key: query[key]}).toList(),
    };

/// A node in a parsed logical query tree.
///
/// Either a [LogicalLeaf] (a single key/pattern) or a [LogicalExpression]
/// (an `$and`/`$or` over child nodes).
abstract class LogicalNode {
  /// Base constructor for subclasses.
  LogicalNode();
}

/// A leaf of a logical query: match [pattern] against the key [keyId].
class LogicalLeaf extends LogicalNode {
  /// Creates a leaf for [keyId] and [pattern], optionally with a [searcher].
  LogicalLeaf({required this.keyId, required this.pattern, this.searcher});

  /// The id of the key to search.
  final String keyId;

  /// The query pattern for this key.
  final String pattern;

  /// The searcher used to evaluate [pattern]; attached when parsed with
  /// `auto: true`.
  Searcher? searcher;
}

/// An `$and`/`$or` combination of child [LogicalNode]s.
class LogicalExpression extends LogicalNode {
  /// Creates an expression with the given [operator] and [children].
  LogicalExpression({required this.operator, required this.children});

  /// The logical operator: `$and` or `$or`.
  final String operator;

  /// The child nodes combined by [operator].
  final List<LogicalNode> children;
}

LogicalNode parse<T>(
  Map query,
  FuseOptions<T> options, {
  bool auto = true,
}) {
  LogicalNode next(Map query) {
    final keys = query.keys.toList();

    final isQueryPath = _isPath(query);

    if (!isQueryPath && keys.length > 1 && !_isExpression(query)) {
      return next(_convertToExplicit(query));
    }

    if (_isLeaf(query)) {
      final Object key =
          isQueryPath ? query[keyTypePath] as Object : keys.first as Object;

      final pattern = isQueryPath ? query[keyTypePattern] : query[key];

      if (pattern is! String) {
        throw ArgumentError(logicalSearchInvalidQueryForKey(key.toString()));
      }

      final leaf = LogicalLeaf(keyId: createKeyId(key), pattern: pattern);

      if (auto) {
        leaf.searcher = createSearcher(pattern, options);
      }

      return leaf;
    }

    final node = LogicalExpression(
      operator: keys.first as String,
      children: [],
    );

    for (final key in keys) {
      final value = query[key];
      if (value is List) {
        for (final item in value) {
          node.children.add(next(item as Map));
        }
      }
    }

    return node;
  }

  var root = query;
  if (!_isExpression(root)) {
    root = _convertToExplicit(root);
  }

  return next(root);
}
