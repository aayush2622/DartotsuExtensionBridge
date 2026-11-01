import 'package:path/path.dart' as p;

final _brackets = RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}');
final _tags = RegExp(
  r'\b(?:\d{3,4}p|\d{3,4}x\d{3,4}|x26[45]|h\.?26[45]|hevc|av1|aac|flac|opus|ac3|dts|10bit|8bit|bluray|bdrip|bd|web-?dl|webrip|hdtv|dual|multi|uhd|hdr|remux)\b',
  caseSensitive: false,
);
final _season = RegExp(
  r'\bs\d{1,2}\s*e(\d{1,4}(?:\.\d)?)',
  caseSensitive: false,
);
final _labelled = RegExp(
  r'(?:^|[\s._-])(?:episode|ep|e|chapter|chap|ch|c|volume|vol|v)[\s._-]*(\d{1,4}(?:\.\d)?)(?:v\d)?(?=$|[\s._-])',
  caseSensitive: false,
);
final _whole = RegExp(r'^\s*(\d{1,4}(?:\.\d)?)(?:v\d)?\s*$');
final _leading = RegExp(r'^\s*(\d{1,4}(?:\.\d)?)(?:v\d)?\s*[-._ ]');
final _trailing = RegExp(r'[-–_ .]\s*(\d{1,4}(?:\.\d)?)(?:v\d)?\s*$');
final _anyNumber = RegExp(r'(?<![\d.])(\d{1,4}(?:\.\d)?)(?![\d])');

double? episodeNumberOf(String fileName) {
  var name = p.basenameWithoutExtension(fileName);
  name = name.replaceAll(_brackets, ' ').replaceAll(_tags, ' ');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.isEmpty) return null;
  for (final re in [_season, _labelled, _whole, _leading, _trailing]) {
    final m = re.firstMatch(name);
    if (m != null) return double.tryParse(m.group(1)!);
  }
  final numbers = _anyNumber
      .allMatches(name)
      .map((m) => double.tryParse(m.group(1)!))
      .whereType<double>()
      .where((n) => !(n >= 1900 && n <= 2100 && n % 1 == 0))
      .toList();
  return numbers.isEmpty ? null : numbers.last;
}

String unitKeyOf(double number) =>
    number % 1 == 0 ? number.toInt().toString() : number.toString();
