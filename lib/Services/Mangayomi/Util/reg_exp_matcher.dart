final _hrefRegExp = RegExp(r'href="([^"]+)"');
final _dataSrcRegExp = RegExp(r'data-src="([^"]+)"');
final _srcRegExp = RegExp(r'src="([^"]+)"');
final _imgRegExp = RegExp(r'img="([^"]+)"');

final _customRegExpCache = <String, RegExp>{};

String regHrefMatcher(String input) {
  Iterable<Match> matches = _hrefRegExp.allMatches(input);
  String? firstMatch = matches.first.group(1);
  return firstMatch!;
}

String regDataSrcMatcher(String input) {
  Iterable<Match> matches = _dataSrcRegExp.allMatches(input);
  String? firstMatch = matches.first.group(1);
  return firstMatch!;
}

String regSrcMatcher(String input) {
  Iterable<Match> matches = _srcRegExp.allMatches(input);
  String? firstMatch = matches.first.group(1);
  return firstMatch!;
}

String regImgMatcher(String input) {
  Iterable<Match> matches = _imgRegExp.allMatches(input);
  String? firstMatch = matches.first.group(1);
  return firstMatch!;
}

String regCustomMatcher(String input, String source, int group) {
  try {
    final exp = _customRegExpCache.putIfAbsent(source, () => RegExp(source));
    Iterable<Match> matches = exp.allMatches(input);
    String? firstMatch = matches.first.group(group);
    return firstMatch!;
  } catch (_) {
    return input;
  }
}

String padIndex(int index) {
  return index.toString().padLeft(3, "0");
}
