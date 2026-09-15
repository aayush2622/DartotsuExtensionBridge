import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Minimal pure-Dart evaluator for Legado (阅读) book-source rules.
///
/// Legado sources are JSON "书源" objects whose `ruleSearch` / `ruleExplore` /
/// `ruleBookInfo` / `ruleToc` / `ruleContent` maps hold JSOUP-style CSS
/// selectors with Legado's extensions:
///
///  * `selector@attr` — pull an attribute (`text` / `html` / `href` / `src` /
///    any name); `@@` is the literal-`@` escape.
///  * `a || b` — try `a`, fall back to `b` on empty.
///  * `sel##pattern##replacement###…` — regex post-processing.
///  * `sel!0` — drop the element at that index.
///  * `:contains(x)` / `:containsOwn(x)` — text-match pseudo-selectors.
///  * URL templates: `{{key}}` / `{{searchKey}}` / `{{page}}`, `<…{{page}}…>`
///    conditional page sections, and `url,{"method":"POST","body":…}` options.
///
/// Ported from RyanYuuki/AnymeXExtensionRuntimeBridge.
class LegadoRuleEngine {
  static final RegExp _orSplitRegex = RegExp(r'\s*\|\|\s*');
  static final RegExp _containsOwnRegex = RegExp(r':containsOwn\(([^)]+)\)');
  static final RegExp _containsRegex = RegExp(r':contains\(([^)]+)\)');
  static final RegExp _quoteStripRegex = RegExp("^['\"]|['\"]\$");
  static final RegExp _conditionalPageRegex = RegExp(
    r'<([^>]*?\{\{page\}\}[^>]*?)>',
  );

  static final Map<String, RegExp> _replacementRegexCache = {};

  static RegExp cachedRegex(String pattern) => _cachedReplacementRegex(pattern);

  static RegExp _cachedReplacementRegex(String pattern) =>
      _replacementRegexCache.putIfAbsent(
        pattern,
        () => RegExp(pattern, multiLine: true),
      );

  static String buildUrl({
    required String urlTemplate,
    required String baseUrl,
    String query = '',
    int page = 1,
  }) {
    String url = urlTemplate.trim();

    String? optionsJson;
    final commaIndex = url.indexOf(',{');
    if (commaIndex != -1) {
      optionsJson = url.substring(commaIndex + 1);
      url = url.substring(0, commaIndex);
    }

    if (page <= 1) {
      url = url.replaceAll(_conditionalPageRegex, '');
    } else {
      url = url.replaceAllMapped(
        _conditionalPageRegex,
        (m) => m.group(1) ?? '',
      );
    }

    url = url
        .replaceAll('{{key}}', Uri.encodeComponent(query))
        .replaceAll('{{searchKey}}', Uri.encodeComponent(query))
        .replaceAll('{{page}}', page.toString());

    String resolvedUrl = url;
    if (!resolvedUrl.startsWith('http://') &&
        !resolvedUrl.startsWith('https://')) {
      resolvedUrl = resolveUrl(baseUrl, resolvedUrl);
    }

    return optionsJson != null ? '$resolvedUrl,$optionsJson' : resolvedUrl;
  }

  static String resolveUrl(String baseUrl, String relativeUrl) {
    if (relativeUrl.isEmpty) return baseUrl;
    if (relativeUrl.startsWith('http://') ||
        relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }
    try {
      return Uri.parse(baseUrl).resolve(relativeUrl).toString();
    } catch (_) {
      if (baseUrl.endsWith('/') && relativeUrl.startsWith('/')) {
        return '$baseUrl${relativeUrl.substring(1)}';
      } else if (!baseUrl.endsWith('/') && !relativeUrl.startsWith('/')) {
        return '$baseUrl/$relativeUrl';
      } else {
        return '$baseUrl$relativeUrl';
      }
    }
  }

  static List<Element> selectElements(dynamic root, String? rule) {
    if (root == null || rule == null || rule.trim().isEmpty) return [];
    for (final singleRule in rule.split(_orSplitRegex)) {
      final elements = _selectElementsSingle(root, singleRule.trim());
      if (elements.isNotEmpty) return elements;
    }
    return [];
  }

  static List<Element> _selectElementsSingle(dynamic root, String rule) {
    if (rule.isEmpty) return [];

    String css = rule;
    final atIdx = css.indexOf('@');
    if (atIdx != -1) css = css.substring(0, atIdx).trim();

    String? indexFilter;
    if (css.contains('!')) {
      final parts = css.split('!');
      css = parts[0].trim();
      if (parts.length > 1) indexFilter = '!${parts[1].trim()}';
    }

    List<Element> matched = [];

    if (_containsOwnRegex.hasMatch(css) || _containsRegex.hasMatch(css)) {
      matched = _selectWithCustomPseudo(root, css);
    } else {
      try {
        if (root is Document) {
          matched = root.querySelectorAll(css);
        } else if (root is Element) {
          matched = root.querySelectorAll(css);
        }
      } catch (_) {
        matched = [];
      }
    }

    if (indexFilter != null &&
        matched.isNotEmpty &&
        indexFilter.startsWith('!')) {
      final idx = int.tryParse(indexFilter.substring(1));
      if (idx != null && idx >= 0 && idx < matched.length) {
        matched.removeAt(idx);
      }
    }

    return matched;
  }

  static String extractString(
    dynamic root,
    String? rule, {
    String baseUrl = '',
  }) {
    if (root == null || rule == null || rule.trim().isEmpty) return '';
    for (final alt in rule.split(_orSplitRegex)) {
      final result = _extractStringSingle(root, alt.trim(), baseUrl: baseUrl);
      if (result.isNotEmpty) return result;
    }
    return '';
  }

  static String _extractStringSingle(
    dynamic root,
    String rule, {
    String baseUrl = '',
  }) {
    if (rule.isEmpty) return '';

    String selectorPart = rule;
    List<List<String>> replacements = [];
    final regexIndex = rule.indexOf('##');
    if (regexIndex != -1) {
      selectorPart = rule.substring(0, regexIndex).trim();
      replacements = parseReplacements(rule.substring(regexIndex + 2));
    }

    String css = selectorPart;
    String attr = 'text';
    final atIndex = selectorPart.lastIndexOf('@');
    if (atIndex != -1 && !selectorPart.contains('@@')) {
      css = selectorPart.substring(0, atIndex).trim();
      attr = selectorPart.substring(atIndex + 1).trim();
    } else if (selectorPart.contains('@@')) {
      final parts = selectorPart.split('@@');
      css = parts[0].trim();
      if (parts.length > 1) attr = parts[1].trim();
    }

    List<Element> targets = [];
    if (css.isEmpty) {
      if (root is Element) targets = [root];
    } else {
      targets = _selectElementsSingle(root, css);
    }

    String result = '';
    if (targets.isNotEmpty) {
      if (attr == 'text') {
        result = targets
            .map((e) => e.text.trim())
            .where((s) => s.isNotEmpty)
            .join('\n');
      } else if (attr == 'html') {
        result = targets.map((e) => e.innerHtml.trim()).join('\n');
      } else {
        final values = <String>[];
        for (final el in targets) {
          String? val;
          if (attr == 'href' || attr == 'src') {
            val =
                el.attributes[attr] ??
                el.attributes['data-$attr'] ??
                el.attributes['data-original'] ??
                el.attributes['data-lazy-src'];
          } else {
            val = el.attributes[attr];
          }
          if (val != null && val.isNotEmpty) {
            if ((attr == 'href' || attr == 'src') && baseUrl.isNotEmpty) {
              val = resolveUrl(baseUrl, val);
            }
            values.add(val);
          }
        }
        result = values.join('\n');
      }
    } else if (root is Element &&
        (css == 'text' || css == 'href' || css == 'src')) {
      if (css == 'text') {
        result = root.text.trim();
      } else {
        final val = root.attributes[css] ?? root.attributes['data-$css'];
        if (val != null && val.isNotEmpty) {
          result = baseUrl.isNotEmpty ? resolveUrl(baseUrl, val) : val;
        }
      }
    }

    for (final rep in replacements) {
      if (rep.isEmpty) continue;
      final pattern = rep[0];
      final replacement = rep.length > 1 ? rep[1] : '';
      try {
        result = result.replaceAll(
          _cachedReplacementRegex(pattern),
          replacement,
        );
      } catch (_) {}
    }

    return result.trim();
  }

  /// `p1##r1###p2##r2` or a bare `to_remove`.
  static List<List<String>> parseReplacements(String raw) {
    final list = <List<String>>[];
    for (final block in raw.split('###')) {
      if (block.isEmpty) continue;
      final parts = block.split('##');
      list.add(parts.length == 1 ? [parts[0], ''] : [parts[0], parts[1]]);
    }
    return list;
  }

  static List<Element> _selectWithCustomPseudo(dynamic root, String css) {
    String baseSelector = css;
    String searchText = '';
    bool own = false;

    final ownMatch = _containsOwnRegex.firstMatch(css);
    if (ownMatch != null) {
      own = true;
      searchText = ownMatch.group(1)!.trim().replaceAll(_quoteStripRegex, '');
      baseSelector = css.replaceFirst(ownMatch.group(0)!, '').trim();
    } else {
      final containsMatch = _containsRegex.firstMatch(css);
      if (containsMatch != null) {
        searchText = containsMatch
            .group(1)!
            .trim()
            .replaceAll(_quoteStripRegex, '');
        baseSelector = css.replaceFirst(containsMatch.group(0)!, '').trim();
      }
    }

    String? siblingSelector;
    if (baseSelector.contains('~')) {
      final parts = baseSelector.split('~');
      baseSelector = parts[0].trim();
      siblingSelector = '~ ${parts[1].trim()}';
    } else if (baseSelector.contains('+')) {
      final parts = baseSelector.split('+');
      baseSelector = parts[0].trim();
      siblingSelector = '+ ${parts[1].trim()}';
    }

    if (baseSelector.isEmpty) baseSelector = '*';

    List<Element> candidates = [];
    try {
      if (root is Document) {
        candidates = root.querySelectorAll(baseSelector);
      } else if (root is Element) {
        candidates = root.querySelectorAll(baseSelector);
      }
    } catch (_) {
      return [];
    }

    final filtered = <Element>[];
    for (final el in candidates) {
      final targetText = own ? _getOwnText(el) : el.text;
      if (targetText.contains(searchText)) {
        if (siblingSelector != null) {
          final parent = el.parent;
          if (parent != null) {
            filtered.addAll(
              parent.querySelectorAll(siblingSelector.substring(2)),
            );
          }
        } else {
          filtered.add(el);
        }
      }
    }
    return filtered;
  }

  static String _getOwnText(Element el) {
    final buffer = StringBuffer();
    for (final node in el.nodes) {
      if (node.nodeType == Node.TEXT_NODE) buffer.write(node.text ?? '');
    }
    return buffer.toString().trim();
  }

  static Document parseHtml(String html) => html_parser.parse(html);
}
