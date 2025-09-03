import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:xml/xml.dart' as xml;

xml.XmlDocument parseHtmlToXml(String html) {
  final dom.Document document = html_parser.parse(html);

  final String serialized = document.outerHtml;

  return xml.XmlDocument.parse(serialized);
}

List<xml.XmlElement> selectNodes(xml.XmlDocument doc, String tag) {
  return doc.findAllElements(tag).toList();
}
