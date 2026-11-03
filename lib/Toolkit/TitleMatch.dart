import 'dart:math';

final _strip = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
final _spaces = RegExp(r'\s+');

String normalizeTitle(String value) =>
    value.toLowerCase().replaceAll(_strip, ' ').replaceAll(_spaces, ' ').trim();

int _distance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = min(
        min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + cost,
      );
    }
    previous = current;
  }
  return previous[b.length];
}

int _ratio(String a, String b) {
  final longest = max(a.length, b.length);
  if (longest == 0) return 0;
  return ((1 - _distance(a, b) / longest) * 100).round();
}

String _sorted(String value) => (value.split(' ')..sort()).join(' ');

int titleRatio(String? left, String? right) {
  final a = normalizeTitle(left ?? '');
  final b = normalizeTitle(right ?? '');
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 100;
  return max(_ratio(a, b), _ratio(_sorted(a), _sorted(b)));
}

int bestTitleRatio(Iterable<String?> candidates, Iterable<String?> targets) {
  var best = 0;
  for (final c in candidates) {
    for (final t in targets) {
      best = max(best, titleRatio(c, t));
    }
  }
  return best;
}
