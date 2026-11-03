import 'dart:convert';

import 'package:flutter_qjs/flutter_qjs.dart';

import 'HtmlStream.dart';

class JsHtmlParser {
  late JavascriptRuntime runtime;
  JsHtmlParser(this.runtime);

  final Map<int, HtmlStream> _streams = {};
  int _next = 0;

  void init() {
    runtime.onMessage('hp_create', (dynamic args) {
      final id = ++_next;
      _streams[id] = HtmlStream();
      return jsonEncode(id);
    });

    runtime.onMessage('hp_write', (dynamic args) {
      final stream = _streams[args[0] as int];
      if (stream == null) return jsonEncode(const []);
      return jsonEncode(stream.write(args[1] as String));
    });

    runtime.onMessage('hp_end', (dynamic args) {
      final stream = _streams.remove(args[0] as int);
      if (stream == null) return jsonEncode(const []);
      return jsonEncode(stream.end());
    });

    runtime.evaluate('''
class Parser {
  constructor(options = {}) {
    this.options = options || {};
    this._id = JSON.parse(sendMessage("hp_create", JSON.stringify([])));
  }

  isVoidElement(name) {
    return [
      "area", "base", "basefont", "br", "col", "command", "embed", "frame",
      "hr", "img", "input", "isindex", "keygen", "link", "meta", "param",
      "source", "track", "wbr",
    ].includes(String(name).toLowerCase());
  }

  _dispatch(events) {
    const o = this.options;
    for (const e of events) {
      switch (e[0]) {
        case "t":
          if (o.ontext) o.ontext(e[1]);
          break;
        case "o":
          if (o.onopentagname) o.onopentagname(e[1]);
          if (o.onattribute) {
            for (const k in e[2]) o.onattribute(k, e[2][k]);
          }
          if (o.onopentag) o.onopentag(e[1], e[2]);
          if (o.onopentagend) o.onopentagend();
          break;
        case "c":
          if (o.onclosetag) o.onclosetag(e[1], e[2]);
          break;
        case "m":
          if (o.oncomment) o.oncomment(e[1]);
          break;
      }
    }
  }

  write(chunk) {
    if (this._id === null) return;
    this._dispatch(
      JSON.parse(sendMessage("hp_write", JSON.stringify([this._id, String(chunk)])))
    );
  }

  end(chunk) {
    if (chunk !== undefined && chunk !== null) this.write(chunk);
    if (this._id === null) return;
    const id = this._id;
    this._id = null;
    this._dispatch(JSON.parse(sendMessage("hp_end", JSON.stringify([id]))));
    if (this.options.onend) this.options.onend();
  }

  parseComplete(data) {
    this.write(data);
    this.end();
  }
}
''');
  }
}
