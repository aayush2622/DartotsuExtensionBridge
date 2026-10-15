import 'package:html/dom.dart' as dom;

const _custom = {
  'contains',
  'containsown',
  'has',
  'matches',
  'matchesown',
  'eq',
  'lt',
  'gt',
  'containswholetext',
};

bool needsAidokuSelector(String query) {
  final lower = query.toLowerCase();
  for (final name in _custom) {
    if (lower.contains(':$name(')) return true;
  }
  return false;
}

class _Pseudo {
  _Pseudo(this.name, this.arg);

  final String name;
  final String arg;
}

class _Compound {
  _Compound(this.base, this.pseudos, this.combinator);

  final String base;
  final List<_Pseudo> pseudos;
  final String combinator;
}

List<String> _splitTop(String text, bool Function(String) isSeparator) {
  final parts = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  String? quote;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quote != null) {
      buf.write(c);
      if (c == quote) quote = null;
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
      buf.write(c);
      continue;
    }
    if (c == '(' || c == '[') depth++;
    if (c == ')' || c == ']') depth--;
    if (depth == 0 && isSeparator(c)) {
      parts.add(buf.toString());
      buf.clear();
      continue;
    }
    buf.write(c);
  }
  parts.add(buf.toString());
  return parts;
}

List<_Compound> _parseChain(String group) {
  final out = <_Compound>[];
  var pendingCombinator = ' ';
  final buf = StringBuffer();
  var depth = 0;
  String? quote;

  void flush() {
    final text = buf.toString().trim();
    buf.clear();
    if (text.isEmpty) return;
    out.add(_parseCompound(text, pendingCombinator));
    pendingCombinator = ' ';
  }

  for (var i = 0; i < group.length; i++) {
    final c = group[i];
    if (quote != null) {
      buf.write(c);
      if (c == quote) quote = null;
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
      buf.write(c);
      continue;
    }
    if (c == '(' || c == '[') depth++;
    if (c == ')' || c == ']') depth--;
    if (depth == 0 && (c == '>' || c == '+' || c == '~')) {
      flush();
      pendingCombinator = c;
      continue;
    }
    if (depth == 0 && c.trim().isEmpty) {
      flush();
      continue;
    }
    buf.write(c);
  }
  flush();
  return out;
}

_Compound _parseCompound(String text, String combinator) {
  final base = StringBuffer();
  final pseudos = <_Pseudo>[];
  var i = 0;
  while (i < text.length) {
    if (text[i] == ':') {
      final m = RegExp(r':([A-Za-z]+)\(').matchAsPrefix(text, i);
      if (m != null && _custom.contains(m.group(1)!.toLowerCase())) {
        var depth = 1;
        var j = m.end;
        String? quote;
        while (j < text.length && depth > 0) {
          final c = text[j];
          if (quote != null) {
            if (c == quote) quote = null;
          } else if (c == '"' || c == "'") {
            quote = c;
          } else if (c == '(') {
            depth++;
          } else if (c == ')') {
            depth--;
          }
          j++;
        }
        var arg = text.substring(m.end, j - 1).trim();
        if (arg.length >= 2 &&
            (arg.startsWith('"') && arg.endsWith('"') ||
                arg.startsWith("'") && arg.endsWith("'"))) {
          arg = arg.substring(1, arg.length - 1);
        }
        pseudos.add(_Pseudo(m.group(1)!.toLowerCase(), arg));
        i = j;
        continue;
      }
    }
    base.write(text[i]);
    i++;
  }
  return _Compound(
    base.toString().isEmpty ? '*' : base.toString(),
    pseudos,
    combinator,
  );
}

String _normalize(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String _ownText(dom.Element el) =>
    _normalize(el.nodes.whereType<dom.Text>().map((t) => t.text).join(' '));

int _siblingIndex(dom.Element el) {
  final parent = el.parent;
  if (parent == null) return 0;
  return parent.children.indexOf(el);
}

bool _pseudoMatches(dom.Element el, _Pseudo p) {
  switch (p.name) {
    case 'contains':
      return _normalize(el.text).toLowerCase().contains(p.arg.toLowerCase());
    case 'containswholetext':
      return el.text.contains(p.arg);
    case 'containsown':
      return _ownText(el).toLowerCase().contains(p.arg.toLowerCase());
    case 'matches':
      return RegExp(p.arg, caseSensitive: false).hasMatch(_normalize(el.text));
    case 'matchesown':
      return RegExp(p.arg, caseSensitive: false).hasMatch(_ownText(el));
    case 'eq':
      return _siblingIndex(el) == int.tryParse(p.arg);
    case 'lt':
      return _siblingIndex(el) < (int.tryParse(p.arg) ?? 0);
    case 'gt':
      return _siblingIndex(el) > (int.tryParse(p.arg) ?? 1 << 30);
    case 'has':
      return _has(el, p.arg);
  }
  return false;
}

bool _has(dom.Element el, String selector) {
  final trimmed = selector.trim();
  final relative = RegExp(r'^[>+~]').hasMatch(trimmed);
  for (final group in _splitTop(trimmed, (c) => c == ',')) {
    final text = group.trim();
    if (text.isEmpty) continue;
    if (relative) {
      final chain = _parseChain(text);
      if (chain.isEmpty) continue;
      final first = chain.first;
      final candidates = switch (first.combinator) {
        '>' => el.children,
        '+' => [if (el.nextElementSibling != null) el.nextElementSibling!],
        '~' => [
          for (final s in el.parent?.children ?? <dom.Element>[])
            if (s != el && _siblingIndex(s) > _siblingIndex(el)) s,
        ],
        _ => el.children,
      };
      final rest = chain.sublist(1);
      for (final c in candidates) {
        if (!_compoundMatches(c, first)) continue;
        if (rest.isEmpty) return true;
        final restText = _chainText(rest);
        if (aidokuSelectAll(c, restText).isNotEmpty) return true;
      }
    } else if (aidokuSelectAll(el, text).isNotEmpty) {
      return true;
    }
  }
  return false;
}

String _chainText(List<_Compound> chain) {
  final b = StringBuffer();
  for (var i = 0; i < chain.length; i++) {
    final c = chain[i];
    if (i > 0 || c.combinator != ' ') b.write(' ${c.combinator} ');
    b.write(c.base == '*' && c.pseudos.isNotEmpty ? '' : c.base);
    for (final p in c.pseudos) {
      b.write(':${p.name}(${p.arg})');
    }
  }
  return b.toString().trim();
}

final _baseCache = Expando<Map<String, Set<dom.Element>>>();

dom.Node _top(dom.Node node) {
  var n = node;
  while (n.parent != null) {
    n = n.parent!;
  }
  return n;
}

bool _baseMatches(dom.Element el, String base) {
  final top = _top(el);
  final cache = _baseCache[top] ??= {};
  final set = cache[base] ??= switch (top) {
    dom.Document d => d.querySelectorAll(base).toSet(),
    dom.DocumentFragment f => f.querySelectorAll(base).toSet(),
    dom.Element e => {
      ...e.querySelectorAll(base),
      if (e.parent == null && _selfMatches(e, base)) e,
    },
    _ => <dom.Element>{},
  };
  return set.contains(el);
}

bool _selfMatches(dom.Element e, String base) {
  final holder = dom.DocumentFragment()..append(e.clone(false));
  return holder.querySelectorAll(base).isNotEmpty;
}

bool _compoundMatches(dom.Element el, _Compound c) {
  if (c.base != '*' && !_baseMatches(el, c.base)) return false;
  for (final p in c.pseudos) {
    if (!_pseudoMatches(el, p)) return false;
  }
  return true;
}

bool _chainMatches(
  dom.Element el,
  List<_Compound> chain,
  int index,
  dom.Node root,
) {
  final c = chain[index];
  if (!_compoundMatches(el, c)) return false;
  if (index == 0) return true;
  switch (c.combinator) {
    case '>':
      final parent = el.parent;
      return parent != null &&
          (root is! dom.Element || parent == root || _within(parent, root)) &&
          _chainMatches(parent, chain, index - 1, root);
    case '+':
      final prev = el.previousElementSibling;
      return prev != null && _chainMatches(prev, chain, index - 1, root);
    case '~':
      var prev = el.previousElementSibling;
      while (prev != null) {
        if (_chainMatches(prev, chain, index - 1, root)) return true;
        prev = prev.previousElementSibling;
      }
      return false;
    default:
      var parent = el.parent;
      while (parent != null) {
        if (_chainMatches(parent, chain, index - 1, root)) return true;
        if (parent == root) break;
        parent = parent.parent;
      }
      return false;
  }
}

bool _within(dom.Node node, dom.Node root) {
  dom.Node? n = node;
  while (n != null) {
    if (n == root) return true;
    n = n.parent;
  }
  return false;
}

void _collect(dom.Node node, List<dom.Element> out) {
  for (final child in node.nodes) {
    if (child is dom.Element) {
      out.add(child);
      _collect(child, out);
    }
  }
}

List<dom.Element> aidokuSelectAll(dom.Node root, String query) {
  final candidates = <dom.Element>[];
  _collect(root, candidates);
  final groups = <List<_Compound>>[
    for (final g in _splitTop(query, (c) => c == ','))
      if (g.trim().isNotEmpty) _parseChain(g.trim()),
  ];
  final out = <dom.Element>[];
  for (final el in candidates) {
    for (final chain in groups) {
      if (chain.isNotEmpty &&
          _chainMatches(el, chain, chain.length - 1, root)) {
        out.add(el);
        break;
      }
    }
  }
  return out;
}
