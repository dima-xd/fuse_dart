const String extendedSearchUnavailable = 'Extended search is not available';

const String logicalSearchUnavailable = 'Logical search is not available';

const String incorrectIndexType = "Incorrect 'index' type";

String logicalSearchInvalidQueryForKey(String key) =>
    'Invalid value for key $key';

String patternLengthTooLarge(int max) => 'Pattern length exceeds max of $max.';

String missingKeyProperty(String name) => 'Missing $name property in key';

String invalidKeyWeightValue(String key) =>
    "Property 'weight' in key '$key' must be a positive integer";
