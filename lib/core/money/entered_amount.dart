/// An amount as someone typed it, as a plain decimal string.
///
/// A comma or a dot groups thousands only in front of exactly three digits, and
/// a cent has two, so "1,250" and "1.250" are 1250 in every language and "12,50"
/// and "12.50" are twelve fifty. It is the rule the sentence parser follows
/// (ADR 0034). Reading the comma as a decimal point turned an English "1,250"
/// into 1.25, on a form that looked fine.
///
/// Nothing is validated here: what this cannot make sense of comes out still
/// not a number, and the caller's check refuses it.
String enteredAmountText(String value) {
  final text = value.trim().replaceAll(RegExp(r'[\s  ]'), '');
  final lastComma = text.lastIndexOf(',');
  final lastDot = text.lastIndexOf('.');

  if (lastComma >= 0 && lastDot >= 0) {
    final point = lastComma > lastDot ? lastComma : lastDot;
    final grouping = lastComma > lastDot ? '.' : ',';
    final whole = text.substring(0, point).replaceAll(grouping, '');
    return '$whole.${text.substring(point + 1)}';
  }

  final separator = lastComma >= 0 ? ',' : '.';
  final groups = text.split(separator);
  if (groups.length > 1 &&
      _firstGroup.hasMatch(groups.first) &&
      groups.skip(1).every(_nextGroup.hasMatch)) {
    return groups.join();
  }
  return text.replaceAll(',', '.');
}

// Not a bare zero: "0,125" is not 125.
final _firstGroup = RegExp(r'^-?[1-9][0-9]{0,2}$');
final _nextGroup = RegExp(r'^[0-9]{3}$');
