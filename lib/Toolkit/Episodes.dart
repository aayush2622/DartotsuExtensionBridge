import '../Models/DEpisode.dart';

List<DEpisode> normalizeEpisodes(List<DEpisode> input) {
  var first = true;
  var normalize = false;
  var shift = 0;
  final seen = <String, int>{};
  final ordered = input.reversed.toList();
  final out = <DEpisode>[];
  for (final (index, ep) in ordered.indexed) {
    final number = double.tryParse(ep.episodeNumber) ?? (index + 1).toDouble();
    if (first) {
      first = false;
      if (number > 3.0) normalize = true;
    }
    var label = ep.episodeNumber;
    if (normalize) {
      if (number % 1 != 0) {
        shift--;
        final remainder = double.parse((number % 1).toStringAsFixed(2));
        label = (index + 1 + remainder + shift).toString();
      } else {
        label = (index + 1 + shift).toString();
      }
    }
    final count = seen[label];
    if (count != null) {
      seen[label] = count + 1;
      label = '$label.${count + 1}';
    } else {
      seen[label] = 1;
    }
    ep.episodeNumber = label;
    out.add(ep);
  }
  out.sort(
    (a, b) => (double.tryParse(a.episodeNumber) ?? 0).compareTo(
      double.tryParse(b.episodeNumber) ?? 0,
    ),
  );
  return out;
}

final _chapterNumber = RegExp(r'([0-9]+)(\.[0-9]+)?');
final _volume = RegExp(r'\b(?:v|ver|vol|version|volume|season|s)[^a-z]?[0-9]+');

double? parseChapterNumber(String title, String name) {
  var text = name.toLowerCase().replaceAll(title.toLowerCase(), '').trim();
  text = text.replaceAll(',', '.').replaceAll('-', '.').replaceAll(_volume, '');
  final match = _chapterNumber.firstMatch(text);
  if (match == null) return null;
  return double.tryParse('${match.group(1)}${match.group(2) ?? ''}');
}

List<DEpisode> prepareChapters(List<DEpisode> input, String title) {
  final out = <DEpisode>[];
  for (final (index, ch) in input.reversed.indexed) {
    final known = double.tryParse(ch.episodeNumber);
    final value =
        (known != null && known > 0 ? known : null) ??
        parseChapterNumber(title, ch.name ?? '') ??
        (index + 1).toDouble();
    ch.episodeNumber = value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toString();
    out.add(ch);
  }
  return out;
}

List<DEpisode> normalizeIsolate(List<DEpisode> input) => normalizeAll(input);

final _digits = RegExp(r'\d+');

int _naturalCompare(String a, String b) {
  final x = int.tryParse(_digits.firstMatch(a)?.group(0) ?? '');
  final y = int.tryParse(_digits.firstMatch(b)?.group(0) ?? '');
  if (x != null && y != null && x != y) return x.compareTo(y);
  return a.toLowerCase().compareTo(b.toLowerCase());
}

Map<String, List<DEpisode>>? _seasonGroups(
  List<DEpisode> input,
  double Function(DEpisode e, int index) numberOf,
) {
  final groups = <String, List<DEpisode>>{};
  for (final e in input) {
    final name = e.scanlator?.trim() ?? '';
    if (name.isEmpty) return null;
    (groups[name] ??= []).add(e);
  }
  if (groups.length < 2) return null;
  final seen = <double>{};
  var overlap = false;
  for (final group in groups.values) {
    final numbers = {
      for (final (i, e) in group.reversed.indexed) numberOf(e, i),
    };
    if (numbers.any(seen.contains)) overlap = true;
    seen.addAll(numbers);
  }
  return overlap ? groups : null;
}

String? seasonOf(DEpisode e) => e.scanlator?.trim();

List<DEpisode> normalizeAll(List<DEpisode> input) {
  final groups = _seasonGroups(
    input,
    (e, i) => double.tryParse(e.episodeNumber) ?? (i + 1).toDouble(),
  );
  if (groups == null) return normalizeEpisodes(input);
  final names = groups.keys.toList()..sort(_naturalCompare);
  return [for (final name in names) ...normalizeEpisodes(groups[name]!)];
}

Map<String, double> seasonOffsets(
  List<DEpisode> normalized,
  List<String> order,
) {
  final counts = <String, Set<double>>{};
  for (final e in normalized) {
    final name = seasonOf(e);
    final number = double.tryParse(e.episodeNumber);
    if (name == null || number == null) continue;
    (counts[name] ??= {}).add(number);
  }
  final out = <String, double>{};
  var total = 0.0;
  for (final name in order) {
    out[name] = total;
    total += counts[name]?.length ?? 0;
  }
  return out;
}

List<String> seasonNames(List<DEpisode> normalized) =>
    _seasonGroups(
      normalized,
      (e, i) => double.tryParse(e.episodeNumber) ?? (i + 1).toDouble(),
    )?.keys.toList() ??
    const [];

DateTime? parseUploadDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final millis = int.tryParse(raw);
  if (millis != null && millis > 100000000) {
    return DateTime.fromMillisecondsSinceEpoch(
      millis < 100000000000 ? millis * 1000 : millis,
    );
  }
  return DateTime.tryParse(raw);
}
