import '../search/register.dart';
import '../search/searcher.dart';
import '../tools/key_store.dart';
import 'config.dart';
import 'error_messages.dart';
import '../helpers/types.dart';

const String logicalAnd = r'$and';
const String logicalOr = r'$or';
const String keyTypePath = r'$path';
const String keyTypePattern = r'$val';

bool _isExpression(Map query) =>
    query[logicalAnd] != null || query[logicalOr] != null;

bool _isPath(Map query) => query[keyTypePath] != null;

bool _isLeaf(Object query) => query is Map && !_isExpression(query);

Map<String, dynamic> _convertToExplicit(Object query) {
  if (query is String) {
    // Mirror JS `Object.keys(str)` — numeric indices into the characters.
    return {
      logicalAnd: [
        for (var i = 0; i < query.length; i++) {i.toString(): query[i]},
      ],
    };
  }
  final map = query as Map;
  return {
    logicalAnd: [for (final key in map.keys) {key: map[key]}],
  };
}

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

  /// The id of the key to search, or `null` for a keyless string entry that
  /// fans out across all keys.
  final String? keyId;

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
  Object query,
  FuseOptions<T> options, {
  bool auto = true,
}) {
  LogicalNode next(Object query) {
    // Keyless string entry: search across all keys
    if (query is String) {
      final leaf = LogicalLeaf(keyId: null, pattern: query);

      if (auto) {
        leaf.searcher = createSearcher(query, options);
      }

      return leaf;
    }

    final mapQuery = query as Map;
    final keys = mapQuery.keys.toList();

    final isQueryPath = _isPath(mapQuery);

    if (!isQueryPath && keys.length > 1 && !_isExpression(mapQuery)) {
      return next(_convertToExplicit(mapQuery));
    }

    if (_isLeaf(query)) {
      final Object key = isQueryPath
          ? mapQuery[keyTypePath] as Object
          : keys.first as Object;

      final pattern = isQueryPath
          ? mapQuery[keyTypePattern]
          : mapQuery[key];

      if (pattern is! String) {
        throw FuseException(logicalSearchInvalidQueryForKey(key.toString()));
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
      final value = mapQuery[key];
      if (value is List) {
        for (final item in value) {
          node.children.add(next(item as Object));
        }
      }
    }

    return node;
  }

  var root = query;
  var isExpr = false;
  if (root is Map) {
    isExpr = _isExpression(root);
  }
  if (!isExpr) {
    root = _convertToExplicit(root);
  }

  return next(root);
}
