import 'package:html/dom.dart';
import 'package:xml/xml.dart' as xml;

import 'element.dart';

class MDocument {
  final Document? _document;

  const MDocument(this._document);

  MElement? get body => MElement(_document?.body);

  MElement? get documentElement => MElement(_document?.documentElement);

  MElement? get head => MElement(_document?.head);

  String? get outerHtml => _document?.outerHtml;

  String? get text => _document?.text?.trim();

  List<MElement>? get children =>
      _document?.children.map((e) => MElement(e)).toList();

  List<MElement>? select(String selector) {
    return _document
        ?.querySelectorAll(selector)
        .map((e) => MElement(e))
        .toList();
  }

  MElement? selectFirst(String selector) {
    final first = _document?.querySelector(selector);
    return first != null ? MElement(first) : null;
  }

  // XPath using xml package
  String? xpathFirst(String xpathExpr) {
    if (_document?.outerHtml == null) return null;
    try {
      final doc = xml.XmlDocument.parse(_document!.outerHtml);
      final node = doc.findAllElements(xpathExpr).firstOrNull;
      return node?.text.trim();
    } catch (_) {
      return null;
    }
  }

  List<String> xpath(String xpathExpr) {
    if (_document?.outerHtml == null) return [];
    try {
      final doc = xml.XmlDocument.parse(_document!.outerHtml);
      return doc.findAllElements(xpathExpr).map((e) => e.text.trim()).toList();
    } catch (_) {
      return [];
    }
  }

  List<MElement>? getElementsByClassName(String classNames) {
    return _document
        ?.getElementsByClassName(classNames)
        .map((e) => MElement(e))
        .toList();
  }

  List<MElement>? getElementsByTagName(String localNames) {
    return _document
        ?.getElementsByTagName(localNames)
        .map((e) => MElement(e))
        .toList();
  }

  MElement? getElementById(String id) {
    return MElement(_document?.getElementById(id));
  }

  String? attr(String attribute) => null; // Document itself has no attributes

  bool hasAttr(String attribute) => false; // Document itself has no attributes
}

// Extension for safe firstOrNull
extension FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
