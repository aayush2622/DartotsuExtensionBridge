import 'package:html/dom.dart';
import 'package:xml/xml.dart' as xml;

class MElement {
  final Element? _element;

  MElement(this._element);

  String? get outerHtml => _element?.outerHtml;
  String? get innerHtml => _element?.innerHtml;
  String? get text => _element?.text.trim();
  String? get className => _element?.className;
  String? get localName => _element?.localName;
  String? get namespaceUri => _element?.namespaceUri;
  String? get getSrc => _element?.attributes['src'];
  String? get getImg => _element?.getElementsByTagName('img').isNotEmpty == true
      ? _element!.getElementsByTagName('img').first.attributes['src']
      : null;
  String? get getHref => _element?.attributes['href'];
  String? get getDataSrc => _element?.attributes['data-src'];

  List<MElement>? get children =>
      _element?.children.map((e) => MElement(e)).toList();

  MElement? get parent =>
      _element?.parent != null ? MElement(_element!.parent) : null;
  MElement? get nextElementSibling => _element?.nextElementSibling != null
      ? MElement(_element!.nextElementSibling)
      : null;
  MElement? get previousElementSibling =>
      _element?.previousElementSibling != null
      ? MElement(_element!.previousElementSibling)
      : null;

  List<MElement>? getElementsByClassName(String classNames) {
    return _element
        ?.getElementsByClassName(classNames)
        .map((e) => MElement(e))
        .toList();
  }

  List<MElement>? getElementsByTagName(String localNames) {
    return _element
        ?.getElementsByTagName(localNames)
        .map((e) => MElement(e))
        .toList();
  }

  List<MElement>? select(String selector) {
    return _element
        ?.querySelectorAll(selector)
        .map((e) => MElement(e))
        .toList();
  }

  MElement? selectFirst(String selector) {
    final first = _element?.querySelector(selector);
    return first != null ? MElement(first) : null;
  }

  String? attr(String attribute) => _element?.attributes[attribute];

  bool hasAttr(String attribute) =>
      _element?.attributes.containsKey(attribute) ?? false;

  // --- XPath using xml package ---
  String? xpathFirst(String xpathExpr) {
    if (_element == null) return null;
    try {
      final document = xml.XmlDocument.parse(_element.outerHtml);
      final node = document.findAllElements(xpathExpr).firstOrNull;
      return node?.text.trim();
    } catch (_) {
      return null;
    }
  }

  List<String>? xpath(String xpathExpr) {
    if (_element == null) return null;
    try {
      final document = xml.XmlDocument.parse(_element.outerHtml);
      return document
          .findAllElements(xpathExpr)
          .map((e) => e.text.trim())
          .toList();
    } catch (_) {
      return null;
    }
  }
}
