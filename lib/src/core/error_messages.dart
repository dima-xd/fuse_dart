const String extendedSearchUnavailable = 'Extended search is not available';

const String logicalSearchUnavailable = 'Logical search is not available';

const String tokenSearchUnavailable = 'Token search is not available';

const String incorrectIndexType = "Incorrect 'index' type";

const String invalidDocIndex =
    'Invalid doc index: must be a non-negative integer within the bounds of the docs array';

String logicalSearchInvalidQueryForKey(String key) =>
    'Invalid value for key $key';

String patternLengthTooLarge(int max) => 'Pattern length exceeds max of $max.';

String missingKeyProperty(String name) => 'Missing $name property in key';

String invalidKeyWeightValue(String key) =>
    "Property 'weight' in key '$key' must be a positive integer";

const String fuseMatchTokenSearchUnsupported =
    'Fuse.match does not support useTokenSearch: token search requires '
    'corpus-level statistics (df, fieldCount) that a one-off string '
    'comparison does not have. Use new Fuse(...).search(...) instead.';
