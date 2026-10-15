const _months = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

const _weekdays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

int? _zoneOffset(String zone) {
  if (zone.isEmpty || zone == 'UTC' || zone == 'GMT' || zone == 'Z') return 0;
  if (zone == 'current' || zone == 'autoupdatingCurrent') {
    return DateTime.now().timeZoneOffset.inSeconds;
  }
  final m = RegExp(r'^(?:GMT|UTC)?([+-])(\d{1,2}):?(\d{2})?$').firstMatch(zone);
  if (m == null) return null;
  final sign = m.group(1) == '-' ? -1 : 1;
  return sign *
      (int.parse(m.group(2)!) * 3600 + int.parse(m.group(3) ?? '0') * 60);
}

class _Cursor {
  _Cursor(this.text);

  final String text;
  int pos = 0;

  bool get done => pos >= text.length;

  int? number(int minDigits, int maxDigits) {
    final start = pos;
    while (pos < text.length &&
        pos - start < maxDigits &&
        text.codeUnitAt(pos) >= 48 &&
        text.codeUnitAt(pos) <= 57) {
      pos++;
    }
    if (pos - start < minDigits) {
      pos = start;
      return null;
    }
    return int.parse(text.substring(start, pos));
  }

  int? name(List<String> names, bool full) {
    final lower = text.substring(pos).toLowerCase();
    for (var i = 0; i < names.length; i++) {
      final n = names[i];
      if (lower.startsWith(n)) {
        pos += n.length;
        return i;
      }
    }
    for (var i = 0; i < names.length; i++) {
      final n = names[i].substring(0, 3);
      if (lower.startsWith(n)) {
        pos += 3;
        if (lower.startsWith('.', 3)) pos++;
        return i;
      }
    }
    return null;
  }
}

double? parseAidokuDate(String text, String format, {String timezone = 'UTC'}) {
  var year = 1970, month = 1, day = 1, hour = 0, minute = 0, second = 0;
  var millis = 0;
  var pm = false, hasMeridiem = false;
  int? zone;
  final c = _Cursor(text);
  var i = 0;
  while (i < format.length) {
    final ch = format[i];
    if (ch == "'") {
      var j = i + 1;
      final lit = StringBuffer();
      while (j < format.length) {
        if (format[j] == "'") {
          if (j + 1 < format.length && format[j + 1] == "'") {
            lit.write("'");
            j += 2;
            continue;
          }
          break;
        }
        lit.write(format[j]);
        j++;
      }
      final s = lit.isEmpty ? "'" : lit.toString();
      if (!text.startsWith(s, c.pos)) return null;
      c.pos += s.length;
      i = j + 1;
      continue;
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(ch)) {
      if (ch == ' ') {
        while (!c.done && c.text[c.pos] == ' ') {
          c.pos++;
        }
      } else if (c.done || c.text[c.pos] != ch) {
        return null;
      } else {
        c.pos++;
      }
      i++;
      continue;
    }
    var n = 1;
    while (i + n < format.length && format[i + n] == ch) {
      n++;
    }
    i += n;
    switch (ch) {
      case 'y':
      case 'Y':
      case 'u':
        final v = c.number(n == 2 ? 2 : 1, n == 2 ? 2 : 9);
        if (v == null) return null;
        year = n == 2 ? 2000 + v : v;
      case 'M':
      case 'L':
        if (n >= 3) {
          final v = c.name(_months, n >= 4);
          if (v == null) return null;
          month = v + 1;
        } else {
          final v = c.number(1, 2);
          if (v == null) return null;
          month = v;
        }
      case 'd':
        final v = c.number(1, 2);
        if (v == null) return null;
        day = v;
      case 'H':
      case 'k':
        final v = c.number(1, 2);
        if (v == null) return null;
        hour = v;
      case 'h':
      case 'K':
        final v = c.number(1, 2);
        if (v == null) return null;
        hour = v % 12;
        hasMeridiem = true;
      case 'm':
        final v = c.number(1, 2);
        if (v == null) return null;
        minute = v;
      case 's':
        final v = c.number(1, 2);
        if (v == null) return null;
        second = v;
      case 'S':
        final start = c.pos;
        final v = c.number(1, n);
        if (v == null) return null;
        final digits = c.pos - start;
        millis = (v * 1000 / _pow10(digits)).round();
      case 'a':
        final rest = c.text.substring(c.pos).toLowerCase();
        if (rest.startsWith('am')) {
          pm = false;
        } else if (rest.startsWith('pm')) {
          pm = true;
        } else {
          return null;
        }
        c.pos += 2;
        hasMeridiem = true;
      case 'E':
      case 'e':
      case 'c':
        if (c.name(_weekdays, n >= 4) == null) return null;
      case 'z':
      case 'Z':
      case 'X':
      case 'x':
      case 'O':
        final m = RegExp(
          r'(?:GMT|UTC)?([+-])(\d{1,2}):?(\d{2})?|Z|UTC|GMT',
        ).matchAsPrefix(c.text, c.pos);
        if (m == null) return null;
        c.pos = m.end;
        zone = m.group(1) == null
            ? 0
            : (m.group(1) == '-' ? -1 : 1) *
                  (int.parse(m.group(2)!) * 3600 +
                      int.parse(m.group(3) ?? '0') * 60);
      default:
        return null;
    }
  }
  if (hasMeridiem && pm) hour += 12;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final offset = zone ?? _zoneOffset(timezone);
  if (offset == null) return null;
  final utc = DateTime.utc(year, month, day, hour, minute, second, millis);
  return utc.millisecondsSinceEpoch / 1000.0 - offset;
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
