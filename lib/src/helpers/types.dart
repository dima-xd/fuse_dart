const double epsilon = 2.220446049250313e-16;

bool isDefined(Object? value) => value != null;

bool isBlank(String value) => value.trim().isEmpty;

String toStringValue(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num) {
    if (value == 0 && value.isNegative) return '-0';
    return value.toString();
  }
  return value.toString();
}
