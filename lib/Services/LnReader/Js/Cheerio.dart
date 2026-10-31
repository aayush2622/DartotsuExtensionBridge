import 'dart:convert';

import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

import 'DomSelector.dart';

class JsCheerio {
  late JavascriptRuntime runtime;
  final Map<int, Node?> _elements = {};
  int _elementKey = 0;

  JsCheerio(this.runtime);

  int _register(Node node) {
    _elementKey++;
    _elements[_elementKey] = node;
    return _elementKey;
  }

  void init() {
    runtime.onMessage('load', (dynamic args) {
      final html = args[0];
      final doc = parse(html);
      _elementKey++;
      _elements[_elementKey] = doc.body;
      return jsonEncode(_elementKey);
    });

    runtime.onMessage('element_call', (dynamic args) {
      final method = args[0] as String;
      final key = args[1] as int?;
      final element = key == null ? null : _elements[key];

      if (element == null) {
        switch (method) {
          case 'find':
          case 'children':
          case 'contents':
          case 'parents':
          case 'siblings':
          case 'nextAll':
          case 'prevAll':
          case 'nextUntil':
          case 'prevUntil':
            return jsonEncode(<int>[]);
          case 'hasClass':
          case 'is':
            return false;
          case 'text':
          case 'html':
          case 'innerHtml':
          case 'outerHtml':
          case 'val':
          case 'attr':
            return '';
          case 'index':
            return jsonEncode(-1);
          case 'parent':
          case 'next':
          case 'prev':
          case 'first':
          case 'last':
          case 'clone':
          case 'closest':
          case 'nodeType':
            return jsonEncode(null);
          default:
            return null;
        }
      }

      final methodArgs = args.length > 2 ? args[2] : [];

      dynamic result;

      switch (method) {
        case 'text':
          result = element.text;
          break;
        case 'html':
        case 'innerHtml':
          result = element is Element ? element.innerHtml : '';
          break;
        case 'outerHtml':
          result = element is Element ? element.outerHtml : (element.text ?? '');
          break;
        case 'addClass':
          if (element is Element) element.classes.add(methodArgs[0]);
          break;
        case 'removeClass':
          if (element is Element) element.classes.remove(methodArgs[0]);
          break;
        case 'hasClass':
          result = element is Element && element.classes.contains(methodArgs[0]);
          break;
        case 'attr':
          result = element.attributes[methodArgs[0]] ?? '';
          break;
        case 'setAttr':
          element.attributes[methodArgs[0]] = methodArgs[1];
          break;
        case 'removeAttr':
          element.attributes.remove(methodArgs[0]);
          break;
        case 'val':
          result = element.attributes['value'] ?? '';
          break;
        case 'setVal':
          element.attributes['value'] = methodArgs[0];
          break;
        case 'children':
          final children = element.children;
          List<int> keys = [];
          for (var child in children) {
            _elementKey++;
            _elements[_elementKey] = child;
            keys.add(_elementKey);
          }
          result = jsonEncode(keys);
          break;
        case 'parent':
          final parent = element.parent;
          if (parent != null) {
            _elementKey++;
            _elements[_elementKey] = parent;
            return jsonEncode(_elementKey);
          }
          return jsonEncode(null);
        case 'find':
          if (element is! Element) {
            result = jsonEncode(<int>[]);
            break;
          }
          final selector = methodArgs[0];
          final elements = element.select(selector);
          List<int> keys = [];
          for (var el in elements ?? []) {
            keys.add(_register(el));
          }
          result = jsonEncode(keys);
          break;
        case 'first':
          final first = element.children.firstOrNull;
          if (first != null) {
            _elementKey++;
            _elements[_elementKey] = first;
            return jsonEncode(_elementKey);
          }
          return jsonEncode(null);
        case 'last':
          final last = element.children.lastOrNull;
          if (last != null) {
            _elementKey++;
            _elements[_elementKey] = last;
            return jsonEncode(_elementKey);
          }
          return jsonEncode(null);
        case 'next':
          final next = element is Element ? element.nextElementSibling : null;
          if (next != null) {
            return jsonEncode(_register(next));
          }
          return jsonEncode(null);
        case 'prev':
          final prev = element is Element ? element.previousElementSibling : null;
          if (prev != null) {
            return jsonEncode(_register(prev));
          }
          return jsonEncode(null);
        case 'clone':
          final cloned = element.clone(true);
          return jsonEncode(_register(cloned));
        case 'is':
          result = element is Element && elementMatches(element, methodArgs[0] as String);
          break;
        case 'append':
          final htmlToAppend = methodArgs[0];
          final newNodes = parse(htmlToAppend).children;
          for (var node in newNodes) {
            element.append(node);
          }
          break;
        case 'prepend':
          final htmlToPrepend = methodArgs[0];
          final newNodes = parse(htmlToPrepend).children;
          for (var node in newNodes.reversed) {
            element.insertBefore(node, element.firstChild);
          }
          break;
        case 'empty':
          element.children.clear();
          break;
        case 'remove':
          element.remove();
          break;
        case 'nodeType':
          return jsonEncode(element.nodeType);
        case 'contents':
          if (element is! Element) {
            return jsonEncode(<int>[]);
          }
          result = jsonEncode([for (final n in element.nodes) _register(n)]);
          break;
        case 'replaceWith':
        case 'before':
        case 'after':
          final parent = element.parentNode;
          if (parent != null) {
            final idx = parent.nodes.indexOf(element);
            if (idx != -1) {
              final fragment = parseFragment(methodArgs[0]?.toString() ?? '');
              final newNodes = fragment.nodes.toList();
              if (method == 'replaceWith') {
                parent.nodes.removeAt(idx);
                parent.nodes.insertAll(idx, newNodes);
              } else if (method == 'before') {
                parent.nodes.insertAll(idx, newNodes);
              } else {
                parent.nodes.insertAll(idx + 1, newNodes);
              }
            }
          }
          break;
        case 'index':
          if (element is Element) {
            final parent = element.parent;
            if (parent != null) {
              return jsonEncode(parent.children.indexOf(element));
            }
          }
          return jsonEncode(-1);
        case 'siblings':
          if (element is! Element || element.parent == null) {
            return jsonEncode(<int>[]);
          }
          result = jsonEncode([
            for (final sib in element.parent!.children)
              if (sib != element) _register(sib),
          ]);
          break;
        case 'nextAll':
          if (element is! Element) {
            return jsonEncode(<int>[]);
          }
          {
            final keys = <int>[];
            var cur = element.nextElementSibling;
            while (cur != null) {
              keys.add(_register(cur));
              cur = cur.nextElementSibling;
            }
            result = jsonEncode(keys);
          }
          break;
        case 'prevAll':
          if (element is! Element) {
            return jsonEncode(<int>[]);
          }
          {
            final keys = <int>[];
            var cur = element.previousElementSibling;
            while (cur != null) {
              keys.add(_register(cur));
              cur = cur.previousElementSibling;
            }
            result = jsonEncode(keys.reversed.toList());
          }
          break;
        case 'nextUntil':
          if (element is! Element) {
            return jsonEncode(<int>[]);
          }
          {
            final selector = methodArgs.isNotEmpty ? methodArgs[0] as String? : null;
            final keys = <int>[];
            var cur = element.nextElementSibling;
            while (cur != null) {
              if (selector != null && elementMatches(cur, selector)) break;
              keys.add(_register(cur));
              cur = cur.nextElementSibling;
            }
            result = jsonEncode(keys);
          }
          break;
        case 'prevUntil':
          if (element is! Element) {
            return jsonEncode(<int>[]);
          }
          {
            final selector = methodArgs.isNotEmpty ? methodArgs[0] as String? : null;
            final keys = <int>[];
            var cur = element.previousElementSibling;
            while (cur != null) {
              if (selector != null && elementMatches(cur, selector)) break;
              keys.add(_register(cur));
              cur = cur.previousElementSibling;
            }
            result = jsonEncode(keys.reversed.toList());
          }
          break;
        case 'parents':
          {
            final selector = methodArgs.isNotEmpty ? methodArgs[0] as String? : null;
            final keys = <int>[];
            var cur = element.parent;
            while (cur != null) {
              if (selector == null || elementMatches(cur, selector)) {
                keys.add(_register(cur));
              }
              cur = cur.parent;
            }
            result = jsonEncode(keys);
          }
          break;
        case 'closest':
          {
            final selector = methodArgs[0] as String;
            Element? cur = element is Element ? element : element.parent;
            while (cur != null) {
              if (elementMatches(cur, selector)) {
                return jsonEncode(_register(cur));
              }
              cur = cur.parent;
            }
            return jsonEncode(null);
          }
        default:
          result = 'Unsupported method: $method';
      }

      return result;
    });

    runtime.evaluate('''
class Element {
  constructor(key) {
    this._key = key;
  }

  _call(method, args = []) {
    return sendMessage("element_call", JSON.stringify([method, this._key, args]));
  }

  text() { return this._call("text"); }
  html() { return this._call("html"); }
  outerHtml() { return this._call("outerHtml"); }
  val() { return this._call("val"); }
  attr(name) { return this._call("attr", [name]); }
  hasClass(cls) { return this._call("hasClass", [cls]); }

  addClass(cls) { this._call("addClass", [cls]); return this; }
  removeClass(cls) { this._call("removeClass", [cls]); return this; }
  setAttr(name, value) { this._call("setAttr", [name, value]); return this; }
  removeAttr(name) { this._call("removeAttr", [name]); return this; }
  setVal(value) { this._call("setVal", [value]); return this; }

  append(html) { this._call("append", [html]); return this; }
  prepend(html) { this._call("prepend", [html]); return this; }
  empty() { this._call("empty"); return this; }
  remove() { this._call("remove"); return this; }

  children() {
    const keys = JSON.parse(this._call("children"));
    return new ElementCollection(keys.map(k => new Element(k)));
  }

  find(selector) {
    const keys = JSON.parse(this._call("find", [selector]));
    return new ElementCollection(keys.map(k => new Element(k)));
  }

  parent() {
    return new Element(JSON.parse(this._call("parent")));
  }

  next() {
    return new Element(JSON.parse(this._call("next")));
  }

  prev() {
    return new Element(JSON.parse(this._call("prev")));
  }

  first() {
    return new Element(JSON.parse(this._call("first")));
  }

  last() {
    return new Element(JSON.parse(this._call("last")));
  }

  clone() {
    return new Element(JSON.parse(this._call("clone")));
  }

  is(selector) {
    return this._call("is", [selector]);
  }

  get nodeType() {
    return JSON.parse(this._call("nodeType"));
  }

  contents() {
    const keys = JSON.parse(this._call("contents"));
    return new ElementCollection(keys.map(k => new Element(k)), new ElementCollection([this]));
  }

  replaceWith(html) { this._call("replaceWith", [html]); return this; }
  before(html) { this._call("before", [html]); return this; }
  after(html) { this._call("after", [html]); return this; }

  index() { return JSON.parse(this._call("index")); }

  siblings(selector) {
    const keys = JSON.parse(this._call("siblings"));
    let els = keys.map(k => new Element(k));
    if (selector) els = els.filter(el => el.is(selector));
    return new ElementCollection(els, new ElementCollection([this]));
  }

  nextAll(selector) {
    const keys = JSON.parse(this._call("nextAll"));
    let els = keys.map(k => new Element(k));
    if (selector) els = els.filter(el => el.is(selector));
    return new ElementCollection(els, new ElementCollection([this]));
  }

  prevAll(selector) {
    const keys = JSON.parse(this._call("prevAll"));
    let els = keys.map(k => new Element(k));
    if (selector) els = els.filter(el => el.is(selector));
    return new ElementCollection(els, new ElementCollection([this]));
  }

  nextUntil(selector) {
    const keys = JSON.parse(this._call("nextUntil", [selector]));
    return new ElementCollection(keys.map(k => new Element(k)), new ElementCollection([this]));
  }

  prevUntil(selector) {
    const keys = JSON.parse(this._call("prevUntil", [selector]));
    return new ElementCollection(keys.map(k => new Element(k)), new ElementCollection([this]));
  }

  parents(selector) {
    const keys = JSON.parse(this._call("parents", [selector || null]));
    return new ElementCollection(keys.map(k => new Element(k)), new ElementCollection([this]));
  }

  closest(selector) {
    return new Element(JSON.parse(this._call("closest", [selector])));
  }

  prop(name) { return this._call("attr", [name]); }

  css(name, value) { return value === undefined ? "" : this; }
}

class ElementCollection {
  constructor(elements, prevObject = null) {
    this.elements = elements;
    this.prevObject = prevObject;
  }

  text() {
    return this.map(function(i, el) {
      return el.text();
    }).toArray().join("\\n") ?? "";
  }

  html() {
    return this.first()?.html();
  }

  outerHtml() {
    return this.first()?.outerHtml();
  }

  attr(name) {
    return this.first()?.attr(name);
  }

  hasClass(cls) {
    return this.first()?.hasClass(cls);
  }

  each(fn) {
    this.elements.forEach((el, i) => fn(i, el));
    return this;
  }

  map(fn) {
    return new ElementCollection(this.elements.map((el, i) => fn(i, el)));
  }

  filter(fn) {
    return new ElementCollection(this.elements.filter(function (el, i) {
      try {
        return fn(i, el);
      } catch (_) {
        return false;
      }
    }));
  }

  addClass(cls) {
    this.elements.forEach(el => el.addClass(cls));
    return this;
  }

  removeClass(cls) {
    this.elements.forEach(el => el.removeClass(cls));
    return this;
  }

  setAttr(name, value) {
    this.elements.forEach(el => el.setAttr(name, value));
    return this;
  }

  removeAttr(name) {
    this.elements.forEach(el => el.removeAttr(name));
    return this;
  }

  setVal(value) {
    this.elements.forEach(el => el.setVal(value));
    return this;
  }

  append(html) {
    this.elements.forEach(el => el.append(html));
    return this;
  }

  prepend(html) {
    this.elements.forEach(el => el.prepend(html));
    return this;
  }

  empty() {
    this.elements.forEach(el => el.empty());
    return this;
  }

  remove() {
    this.elements.forEach(el => el.remove());
    return this;
  }

  find(selector) {
    const found = this.elements.flatMap(el => {
      const keys = JSON.parse(el._call("find", [selector]));
      return keys.map(k => new Element(k));
    });
    return new ElementCollection(found, this);
  }

  children() {
    const children = this.elements.flatMap(el => {
      const keys = JSON.parse(el._call("children"));
      return keys.map(k => new Element(k));
    });
    return new ElementCollection(children, this);
  }

  contents() {
    const all = this.elements.flatMap(el => el.contents().toArray());
    return new ElementCollection(all, this);
  }

  addBack(selector) {
    const prev = this.prevObject;
    if (!prev) return this;
    let merged = [...prev.elements, ...this.elements];
    if (selector) merged = merged.filter(el => el.is(selector));
    return new ElementCollection(merged, this);
  }

  replaceWith(html) { this.elements.forEach(el => el.replaceWith(html)); return this; }
  before(html) { this.elements.forEach(el => el.before(html)); return this; }
  after(html) { this.elements.forEach(el => el.after(html)); return this; }

  not(selector) {
    return new ElementCollection(this.elements.filter(el => !el.is(selector)), this);
  }

  add(other) {
    let extra = [];
    if (other instanceof ElementCollection) extra = other.elements;
    else if (other instanceof Element) extra = [other];
    else if (Array.isArray(other)) extra = other;
    return new ElementCollection([...this.elements, ...extra]);
  }

  eq(index) {
    const el = this.elements[index < 0 ? this.elements.length + index : index];
    return new ElementCollection(el !== undefined ? [el] : [], this);
  }

  index() {
    const first = this.first();
    return first ? first.index() : -1;
  }

  closest(selector) {
    const found = this.elements.map(el => el.closest(selector)).filter(el => el._key != null);
    return new ElementCollection(found, this);
  }

  parents(selector) {
    const all = this.elements.flatMap(el => el.parents(selector).toArray());
    return new ElementCollection(all, this);
  }

  siblings(selector) {
    const all = this.elements.flatMap(el => el.siblings(selector).toArray());
    return new ElementCollection(all, this);
  }

  nextAll(selector) {
    const all = this.elements.flatMap(el => el.nextAll(selector).toArray());
    return new ElementCollection(all, this);
  }

  prevAll(selector) {
    const all = this.elements.flatMap(el => el.prevAll(selector).toArray());
    return new ElementCollection(all, this);
  }

  prop(name) {
    return this.first()?.prop(name);
  }

  css(name, value) {
    if (value === undefined) return "";
    this.elements.forEach(el => el.css(name, value));
    return this;
  }

  parent() {
    const parents = this.elements.map(el => el.parent()).filter(el => el._key != null);
    return new ElementCollection(parents, this);
  }

  next() {
    const nextEls = this.elements.map(el => el.next()).filter(el => el._key != null);
    return new ElementCollection(nextEls, this);
  }

  prev() {
    const prevEls = this.elements.map(el => el.prev()).filter(el => el._key != null);
    return new ElementCollection(prevEls, this);
  }

  clone() {
    return new ElementCollection(this.elements.map(el => el.clone()));
  }

  is(selector) {
    return this.elements.some(el => el.is(selector));
  }

  first() {
    return this.get(0);
  }

  last() {
    return this.get(this.elements.length - 1);
  }

  get(index) {
    const el = this.elements[index];
    return el !== undefined ? el : new Element(null);
  }

  get length() {
    return this.elements.length;
  }

  toArray() {
    return this.elements;
  }

  [Symbol.iterator]() {
    return this.elements[Symbol.iterator]();
  }
}

function load(html) {
  const rootKey = JSON.parse(sendMessage("load", JSON.stringify([html])));
  const root = new Element(rootKey);

  const \$ = function(input) {
    if (input instanceof ElementCollection) {
      return input;
    } else if (input instanceof Element) {
      return input;
    } else if (typeof input === "string") {
      return root.find(input); // returns ElementCollection
    } else if (input && input._key) {
      return new ElementCollection([new Element(input._key)]);
    } else {
      return new ElementCollection([new Element(input)]);
    }
  };

  \$.html = function() {
    return root.html();
  };
  \$.root = root;
  \$.Element = Element;
  \$.Collection = ElementCollection;

  return \$;
}
  ''');
  }
}
