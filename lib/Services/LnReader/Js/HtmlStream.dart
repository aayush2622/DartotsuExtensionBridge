import 'package:html/parser.dart' as html;

const _voidElements = {
  'area',
  'base',
  'basefont',
  'br',
  'col',
  'command',
  'embed',
  'frame',
  'hr',
  'img',
  'input',
  'isindex',
  'keygen',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

const _formTags = {
  'input',
  'option',
  'optgroup',
  'select',
  'button',
  'datalist',
  'textarea',
};

const _pClosers = {'p'};

const _openImpliesClose = <String, Set<String>>{
  'tr': {'tr', 'th', 'td'},
  'th': {'th'},
  'td': {'thead', 'th', 'td'},
  'body': {'head', 'link', 'script'},
  'li': {'li'},
  'p': _pClosers,
  'h1': _pClosers,
  'h2': _pClosers,
  'h3': _pClosers,
  'h4': _pClosers,
  'h5': _pClosers,
  'h6': _pClosers,
  'select': _formTags,
  'input': _formTags,
  'output': _formTags,
  'button': _formTags,
  'datalist': _formTags,
  'textarea': _formTags,
  'option': {'option'},
  'optgroup': {'optgroup', 'option'},
  'dd': {'dt', 'dd'},
  'dt': {'dt', 'dd'},
  'address': _pClosers,
  'article': _pClosers,
  'aside': _pClosers,
  'blockquote': _pClosers,
  'details': _pClosers,
  'div': _pClosers,
  'dl': _pClosers,
  'fieldset': _pClosers,
  'figcaption': _pClosers,
  'figure': _pClosers,
  'footer': _pClosers,
  'form': _pClosers,
  'header': _pClosers,
  'hr': _pClosers,
  'main': _pClosers,
  'nav': _pClosers,
  'ol': _pClosers,
  'pre': _pClosers,
  'section': _pClosers,
  'table': _pClosers,
  'ul': _pClosers,
  'rt': {'rt', 'rp'},
  'rp': {'rt', 'rp'},
  'tbody': {'thead', 'tbody'},
  'tfoot': {'thead', 'tbody'},
};

const _rawTextTags = {'script', 'style'};

final _tagStart = RegExp(r'[a-zA-Z]');
final _space = RegExp(r'\s');
final _nameEnd = RegExp(r'[\s/>]');
final _attrNameEnd = RegExp(r'[\s=/>]');
final _unquotedEnd = RegExp(r'[\s>]');

/// A forgiving HTML tokenizer that reports what `htmlparser2`'s `Parser` would:
/// decoded text, lowercased names, implied closing tags, void elements closed
/// right away and everything left open closed at the end.
class HtmlStream {
  String _pending = '';
  final List<String> _stack = [];
  String? _raw;
  final List<List<Object?>> _events = [];

  List<List<Object?>> write(String chunk) {
    _pending += chunk;
    _scan(last: false);
    return _take();
  }

  List<List<Object?>> end() {
    _scan(last: true);
    while (_stack.isNotEmpty) {
      _events.add(['c', _stack.removeAt(0), true]);
    }
    return _take();
  }

  List<List<Object?>> _take() {
    final out = List<List<Object?>>.of(_events);
    _events.clear();
    return out;
  }

  void _text(String text) {
    if (text.isEmpty) return;
    final value = _raw == null && text.contains('&')
        ? html.parseFragment(text).text ?? text
        : text;
    _events.add(['t', value]);
  }

  void _scan({required bool last}) {
    final s = _pending;
    var i = 0;
    while (i < s.length) {
      final raw = _raw;
      if (raw != null) {
        final close = s.toLowerCase().indexOf('</$raw', i);
        if (close < 0) {
          if (last) {
            _text(s.substring(i));
            i = s.length;
          }
          break;
        }
        _text(s.substring(i, close));
        _raw = null;
        i = close;
        continue;
      }

      final lt = s.indexOf('<', i);
      if (lt < 0) {
        _text(s.substring(i));
        i = s.length;
        break;
      }
      if (lt > i) _text(s.substring(i, lt));
      i = lt;

      if (i + 1 >= s.length) {
        if (last) {
          _text(s.substring(i));
          i = s.length;
        }
        break;
      }
      final next = s[i + 1];

      if (s.startsWith('<!--', i)) {
        final stop = s.indexOf('-->', i + 4);
        if (stop < 0) {
          if (last) i = s.length;
          break;
        }
        _events.add(['m', s.substring(i + 4, stop)]);
        i = stop + 3;
      } else if (next == '!' || next == '?') {
        final stop = s.indexOf('>', i);
        if (stop < 0) {
          if (last) i = s.length;
          break;
        }
        i = stop + 1;
      } else if (next == '/') {
        if (i + 2 < s.length && !_tagStart.hasMatch(s[i + 2])) {
          final stop = s.indexOf('>', i);
          if (stop < 0) {
            if (last) i = s.length;
            break;
          }
          i = stop + 1;
          continue;
        }
        final stop = s.indexOf('>', i);
        if (stop < 0) {
          if (last) i = s.length;
          break;
        }
        _closeTag(s.substring(i + 2, stop).trim().toLowerCase());
        i = stop + 1;
      } else if (_tagStart.hasMatch(next)) {
        final end = _openTag(s, i, last: last);
        if (end < 0) break;
        i = end;
      } else {
        _text('<');
        i++;
      }
    }
    _pending = i >= s.length ? '' : s.substring(i);
  }

  int _openTag(String s, int start, {required bool last}) {
    var i = start + 1;
    final nameStart = i;
    while (i < s.length && !_nameEnd.hasMatch(s[i])) {
      i++;
    }
    final name = s.substring(nameStart, i).toLowerCase();
    final attribs = <String, String>{};

    while (true) {
      while (i < s.length && (_space.hasMatch(s[i]) || s[i] == '/')) {
        i++;
      }
      if (i >= s.length) {
        if (!last) return -1;
        break;
      }
      if (s[i] == '>') {
        i++;
        break;
      }
      final attrStart = i;
      while (i < s.length && !_attrNameEnd.hasMatch(s[i])) {
        i++;
      }
      final attr = s.substring(attrStart, i).toLowerCase();
      if (attr.isEmpty) {
        i++;
        continue;
      }
      var j = i;
      while (j < s.length && _space.hasMatch(s[j])) {
        j++;
      }
      var value = '';
      if (j < s.length && s[j] == '=') {
        j++;
        while (j < s.length && _space.hasMatch(s[j])) {
          j++;
        }
        if (j >= s.length) {
          if (!last) return -1;
          i = j;
        } else if (s[j] == '"' || s[j] == "'") {
          final quote = s[j];
          final close = s.indexOf(quote, j + 1);
          if (close < 0) {
            if (!last) return -1;
            value = s.substring(j + 1);
            i = s.length;
          } else {
            value = s.substring(j + 1, close);
            i = close + 1;
          }
        } else {
          final valueStart = j;
          while (j < s.length && !_unquotedEnd.hasMatch(s[j])) {
            j++;
          }
          value = s.substring(valueStart, j);
          i = j;
        }
        if (value.contains('&')) {
          value = html.parseFragment(value).text ?? value;
        }
      } else {
        i = j;
      }
      attribs.putIfAbsent(attr, () => value);
    }

    final closers = _openImpliesClose[name];
    if (closers != null) {
      while (_stack.isNotEmpty && closers.contains(_stack.first)) {
        _events.add(['c', _stack.removeAt(0), true]);
      }
    }
    final isVoid = _voidElements.contains(name);
    if (!isVoid) _stack.insert(0, name);
    _events.add(['o', name, attribs]);
    if (isVoid) {
      _events.add(['c', name, true]);
    } else if (_rawTextTags.contains(name)) {
      _raw = name;
    }
    return i;
  }

  void _closeTag(String name) {
    final at = _stack.indexOf(name);
    if (at >= 0) {
      for (var n = 0; n < at; n++) {
        _events.add(['c', _stack.removeAt(0), true]);
      }
      _stack.removeAt(0);
      _events.add(['c', name, false]);
    } else if (name == 'br') {
      _events.add(['o', 'br', <String, String>{}]);
      _events.add(['c', 'br', true]);
    } else if (name == 'p') {
      _events.add(['o', 'p', <String, String>{}]);
      _events.add(['c', 'p', false]);
    }
  }
}
