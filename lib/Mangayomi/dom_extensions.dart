import 'reg_exp_matcher.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;

dom.Document parseHtml(String html) => html_parser.parse(html);

xml.XmlDocument domToXml(dom.Document doc) =>
    xml.XmlDocument.parse(doc.outerHtml);

extension PseudoSelectors on dom.Element {
  bool isNthChild(int n) {
    final parentNode = parent;
    if (parentNode == null) return false;
    return parentNode.children.indexOf(this) == n;
  }

  bool containsText(String text) => this.text.contains(text);

  bool hasChildMatching(bool Function(dom.Element) matcher) {
    return children.any(matcher);
  }

  bool isFirstChild() => previousElementSibling == null;

  bool isLastChild() => nextElementSibling == null;

  bool isOnlyChild() =>
      previousElementSibling == null && nextElementSibling == null;
}

extension DocumentExtensions on dom.Document? {
  List<dom.Element> selectByTag(String tag) {
    if (this == null) return [];
    return this!.getElementsByTagName(tag);
  }

  dom.Element? selectFirstByTag(String tag) {
    final elems = selectByTag(tag);
    return elems.isNotEmpty ? elems.first : null;
  }

  String? attr(String attribute) =>
      this?.documentElement?.attributes[attribute];

  bool hasAttr(String attribute) => attr(attribute) != null;

  List<xml.XmlElement> xpath(String xpathQuery) {
    if (this == null) return [];
    final docXml = domToXml(this!);
    return docXml.findAllElements(xpathQuery).toList();
  }

  xml.XmlElement? xpathFirst(String xpathQuery) {
    final results = xpath(xpathQuery);
    return results.isNotEmpty ? results.first : null;
  }
}

extension ElementExtensions on dom.Element {
  List<dom.Element> selectByTag(String tag) => getElementsByTagName(tag);

  dom.Element? selectFirstByTag(String tag) {
    final elems = selectByTag(tag);
    return elems.isNotEmpty ? elems.first : null;
  }

  String? attr(String attribute) => attributes[attribute];

  bool hasAttr(String attribute) => attr(attribute) != null;

  List<xml.XmlElement> xpath(String xpathQuery) {
    final docXml = xml.XmlDocument.parse(outerHtml);
    return docXml.findAllElements(xpathQuery).toList();
  }

  xml.XmlElement? xpathFirst(String xpathQuery) {
    final results = xpath(xpathQuery);
    return results.isNotEmpty ? results.first : null;
  }

  String? get getSrc {
    try {
      return regSrcMatcher(outerHtml);
    } catch (_) {
      return null;
    }
  }

  String? get getImg {
    try {
      return regImgMatcher(outerHtml);
    } catch (_) {
      return null;
    }
  }

  String? get getHref {
    try {
      return regHrefMatcher(outerHtml);
    } catch (_) {
      return null;
    }
  }

  String? get getDataSrc {
    try {
      return regDataSrcMatcher(outerHtml);
    } catch (_) {
      return null;
    }
  }
}
