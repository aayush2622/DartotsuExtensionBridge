import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:flutter/foundation.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:wasd/wasm.dart';

import '../../Engines/WasmEngine/WasmEngine.dart';
import 'AidokuDates.dart';
import 'AidokuImages.dart';
import 'AidokuIo.dart';
import 'AidokuPaths.dart';
import 'AidokuSelector.dart';

class _JsContext {
  _JsContext() : runtime = QuickJsRuntime2(stackSize: 1024 * 1024 * 4) {
    runtime.enableHandlePromises();
  }

  final JavascriptRuntime runtime;

  void dispose() {
    try {
      runtime.dispose();
    } catch (_) {}
  }
}

class _NetResource {
  final String method;
  String url = '';
  final Map<String, String> headers = {};
  Uint8List? body;
  Duration timeout = const Duration(seconds: 30);

  int statusCode = -1;
  Uint8List? data;
  Map<String, String> responseHeaders = {};
  String finalUrl = '';
  bool sent = false;

  _NetResource(this.method);
}

class _NodeResource {
  final dom.Node node;
  final String baseUrl;
  _NodeResource(this.node, this.baseUrl);
}

class _NodeListResource {
  final List<dom.Node> nodes;
  final String baseUrl;
  _NodeListResource(this.nodes, this.baseUrl);
}

class AidokuHost {
  AidokuHost(
    this.sourceId, {
    required AidokuIo io,
    Map<String, String> defaultValues = const {},
  }) : _io = io,
       _defaultValues = defaultValues;

  final String sourceId;
  WasmEngine? engine;
  String? lastNetError;

  final AidokuIo _io;

  void _log(String message) => _io.log(message);

  final Map<String, String> _defaultValues;
  Map<String, String> get defaultValues => _defaultValues;

  final Map<int, Object> _resources = {};
  int _nextRid = 1;

  int _alloc(Object resource) {
    final rid = _nextRid++;
    _resources[rid] = resource;
    return rid;
  }

  WasmEngine get _engine {
    final e = engine;
    if (e == null) throw StateError('WasmEngine not attached');
    return e;
  }

  String _readStr(int ptr, int len) =>
      len == 0 ? '' : utf8.decode(_engine.readBytes(ptr, len));

  Uint8List _bufferOf(int rid) {
    final res = _resources[rid];
    if (res is Uint8List) return res;
    if (res is _NetResource) return res.data ?? Uint8List(0);
    throw ArgumentError('Resource $rid has no buffer');
  }

  void release(int rid) {
    final removed = _resources.remove(rid);
    if (removed is _JsContext) removed.dispose();
  }

  int bufferResource(List<int> bytes) => _alloc(Uint8List.fromList(bytes));

  int stringResource(String s) => bufferResource(utf8.encode(s));

  ImportValue _fn(Object? Function(List<Object?>) f) =>
      ImportExportKind.function(f);

  Imports build() => {
    'env': {
      'print': _fn(_envPrint),
      'sleep': _fn(_envSleep),
      'send_partial_result': _fn((_) => null),
      'abort': _fn((_) => throw StateError('wasm module aborted')),
    },
    'std': {
      'destroy': _fn(_stdDestroy),
      'buffer_len': _fn(_stdBufferLen),
      'read_buffer': _fn(_stdReadBuffer),
      'current_date': _fn(
        (_) => DateTime.now().millisecondsSinceEpoch / 1000.0,
      ),
      'utc_offset': _fn((_) => DateTime.now().timeZoneOffset.inSeconds),
      'parse_date': _fn(_stdParseDate),
    },
    'net': {
      'init': _fn(_netInit),
      'send': _fn(_netSend),
      'send_all': _fn(_netSendAll),
      'set_url': _fn(_netSetUrl),
      'set_header': _fn(_netSetHeader),
      'set_body': _fn(_netSetBody),
      'set_timeout': _fn(_netSetTimeout),
      'data_len': _fn(_netDataLen),
      'read_data': _fn(_netReadData),
      'get_image': _fn(_netGetImage),
      'get_header': _fn(_netGetHeader),
      'get_status_code': _fn(_netGetStatusCode),
      'get_url': _fn(_netGetUrl),
      'html': _fn(_netHtml),
      'set_rate_limit': _fn(_netSetRateLimit),
    },
    'defaults': {'get': _fn(_defaultsGet), 'set': _fn(_defaultsSet)},
    'canvas': {
      'new_context': _fn(_canvasNew),
      'set_transform': _fn(_canvasTransform),
      'copy_image': _fn(_canvasCopyImage),
      'draw_image': _fn(_canvasDrawImage),
      'fill': _fn(_canvasFill),
      'stroke': _fn(_canvasStroke),
      'draw_text': _fn(_canvasDrawText),
      'get_image': _fn(_canvasGetImage),
      'new_font': _fn((_) => _alloc(const _FontResource())),
      'system_font': _fn((_) => _alloc(const _FontResource())),
      'load_font': _fn((_) => _alloc(const _FontResource())),
      'new_image': _fn(_canvasNewImage),
      'get_image_data': _fn(_canvasImageData),
      'get_image_width': _fn(
        (a) => _imageOf(a[0])?.image.width.toDouble() ?? 0.0,
      ),
      'get_image_height': _fn(
        (a) => _imageOf(a[0])?.image.height.toDouble() ?? 0.0,
      ),
    },
    'js': {
      'context_create': _fn(_jsCreate),
      'context_eval': _fn(_jsEval),
      'context_eval_async': _fn(_jsEvalAsync),
      'context_get': _fn(_jsGet),
      'webview_create': _fn((_) => -1),
      'webview_set_rule_list': _fn((_) => -2),
      'webview_load': _fn((_) => -2),
      'webview_load_html': _fn((_) => -2),
      'webview_wait_for_load': _fn((_) => -2),
      'webview_eval': _fn((_) => -2),
      'webview_eval_async': _fn((_) => -2),
      'webview_add_user_script': _fn((_) => -2),
      'webview_get_cookies': _fn((_) => -2),
      'webview_delete_cookie': _fn((_) => -2),
    },
    'html': {
      'parse': _fn(_htmlParse),
      'parse_fragment': _fn(_htmlParseFragment),
      'escape': _fn(_htmlEscape),
      'unescape': _fn(_htmlUnescape),
      'kind': _fn(_htmlKind),
      'child_nodes': _fn(_htmlChildNodes),
      'has_attr': _fn(_htmlHasAttr),
      'set_attr': _fn(_htmlSetAttr),
      'remove_attr': _fn(_htmlRemoveAttr),
      'set_text': _fn(_htmlSetText),
      'set_html': _fn(_htmlSetHtml),
      'prepend': _fn(_htmlPrepend),
      'append': _fn(_htmlAppend),
      'children': _fn(_htmlChildren),
      'base_uri': _fn(_htmlBaseUri),
      'own_text': _fn(_htmlOwnText),
      'data': _fn(_htmlData),
      'id': _fn(_htmlId),
      'tag_name': _fn(_htmlTagName),
      'class_name': _fn(_htmlClassName),
      'has_class': _fn(_htmlHasClass),
      'add_class': _fn(_htmlAddClass),
      'remove_class': _fn(_htmlRemoveClass),
      'first': _fn(_htmlFirst),
      'last': _fn(_htmlLast),
      'get': _fn(_htmlGet),
      'size': _fn(_htmlSize),
      'parent': _fn(_htmlParent),
      'siblings': _fn(_htmlSiblings),
      'next': _fn(_htmlNext),
      'previous': _fn(_htmlPrevious),
      'attr': _fn(_htmlAttr),
      'outer_html': _fn(_htmlOuterHtml),
      'remove': _fn(_htmlRemove),
      'select': _fn(_htmlSelect),
      'select_first': _fn(_htmlSelectFirst),
      'text': _fn(_htmlText),
      'untrimmed_text': _fn(_htmlUntrimmedText),
      'html': _fn(_htmlHtml),
    },
  };

  void _envSleep(List<Object?> a) {
    final seconds = (a[0] as num).toInt().clamp(0, 30);
    _io.sleep(Duration(seconds: seconds));
  }

  int _rateLimitPermits = 0;
  Duration _rateLimitPeriod = Duration.zero;
  final List<DateTime> _rateLimitSent = [];

  void _netSetRateLimit(List<Object?> a) {
    final permits = (a[0] as num).toInt();
    final period = (a[1] as num).toInt();
    final unit = switch ((a[2] as num).toInt()) {
      1 => const Duration(minutes: 1),
      2 => const Duration(hours: 1),
      _ => const Duration(seconds: 1),
    };
    _rateLimitPermits = permits;
    _rateLimitPeriod = unit * period;
    _rateLimitSent.clear();
  }

  void _awaitRateLimit() {
    if (_rateLimitPermits <= 0 || _rateLimitPeriod == Duration.zero) return;
    while (true) {
      final now = DateTime.now();
      _rateLimitSent.removeWhere((t) => now.difference(t) >= _rateLimitPeriod);
      if (_rateLimitSent.length < _rateLimitPermits) {
        _rateLimitSent.add(now);
        return;
      }
      final wait = _rateLimitPeriod - now.difference(_rateLimitSent.first);
      _io.sleep(wait + const Duration(milliseconds: 5));
    }
  }

  void _envPrint(List<Object?> a) {
    _log(_readStr(a[0] as int, a[1] as int));
  }

  // --- std ---

  Object? _stdDestroy(List<Object?> a) {
    final removed = _resources.remove(a[0] as int);
    if (removed is _JsContext) removed.dispose();
    return null;
  }

  AidokuImage? _imageOf(Object? rid) {
    final res = _resources[(rid as num).toInt()];
    return res is AidokuImage ? res : null;
  }

  AidokuCanvas? _canvasOf(Object? rid) {
    final res = _resources[(rid as num).toInt()];
    return res is AidokuCanvas ? res : null;
  }

  int _canvasNew(List<Object?> a) {
    final canvas = AidokuCanvas.create(
      (a[0] as num).toDouble(),
      (a[1] as num).toDouble(),
    );
    return canvas == null ? -6 : _alloc(canvas);
  }

  int _canvasTransform(List<Object?> a) {
    final canvas = _canvasOf(a[0]);
    if (canvas == null) return -1;
    canvas
      ..translateX = (a[1] as num).toDouble()
      ..translateY = (a[2] as num).toDouble()
      ..scaleX = (a[3] as num).toDouble()
      ..scaleY = (a[4] as num).toDouble()
      ..rotation = (a[5] as num).toDouble();
    return 0;
  }

  int _canvasCopyImage(List<Object?> a) {
    final canvas = _canvasOf(a[0]);
    if (canvas == null) return -1;
    final image = _imageOf(a[1]);
    if (image == null) return -2;
    double n(int i) => (a[i] as num).toDouble();
    return canvas.draw(
      image.image,
      srcX: n(2),
      srcY: n(3),
      srcWidth: n(4),
      srcHeight: n(5),
      dstX: n(6),
      dstY: n(7),
      dstWidth: n(8),
      dstHeight: n(9),
    );
  }

  int _canvasDrawImage(List<Object?> a) {
    final canvas = _canvasOf(a[0]);
    if (canvas == null) return -1;
    final image = _imageOf(a[1]);
    if (image == null) return -2;
    double n(int i) => (a[i] as num).toDouble();
    return canvas.draw(
      image.image,
      srcX: 0,
      srcY: 0,
      srcWidth: image.image.width.toDouble(),
      srcHeight: image.image.height.toDouble(),
      dstX: n(2),
      dstY: n(3),
      dstWidth: n(4),
      dstHeight: n(5),
    );
  }

  Uint8List? _pointerBytes(int ptr) {
    try {
      final head = ByteData.sublistView(_engine.readBytes(ptr, 8));
      final total = head.getInt32(0, Endian.little);
      if (total < 8) return null;
      return Uint8List.fromList(_engine.readBytes(ptr + 8, total - 8));
    } catch (_) {
      return null;
    }
  }

  int _canvasFill(List<Object?> a) {
    final canvas = _canvasOf(a[0]);
    if (canvas == null) return -1;
    final bytes = _pointerBytes((a[1] as num).toInt());
    if (bytes == null) return -7;
    try {
      canvas.fillPaths(decodeAidokuPath(bytes), [
        for (var i = 2; i < 6; i++) (a[i] as num).toDouble(),
      ]);
      return 0;
    } catch (_) {
      return -7;
    }
  }

  int _canvasStroke(List<Object?> a) {
    final canvas = _canvasOf(a[0]);
    if (canvas == null) return -1;
    final path = _pointerBytes((a[1] as num).toInt());
    if (path == null) return -7;
    final style = _pointerBytes((a[2] as num).toInt());
    if (style == null) return -8;
    try {
      canvas.strokePaths(decodeAidokuPath(path), decodeAidokuStroke(style));
      return 0;
    } on FormatException {
      return -7;
    } catch (_) {
      return -8;
    }
  }

  int _canvasDrawText(List<Object?> a) {
    final canvas = _canvasOf(a[0]);
    if (canvas == null) return -1;
    if (_resources[(a[6] as num).toInt()] is! _FontResource) return -10;
    final String text;
    try {
      text = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    } catch (_) {
      return -9;
    }
    canvas.text(
      text,
      (a[3] as num).toDouble(),
      (a[4] as num).toDouble(),
      (a[5] as num).toDouble(),
      [for (var i = 7; i < 11; i++) (a[i] as num).toDouble()],
    );
    return 0;
  }

  int _canvasGetImage(List<Object?> a) {
    final canvas = _canvasOf(a[0]);
    if (canvas == null) return -1;
    return _alloc(AidokuImage(canvas.image.clone()));
  }

  int _canvasNewImage(List<Object?> a) {
    final bytes = Uint8List.fromList(
      _engine.readBytes((a[0] as num).toInt(), (a[1] as num).toInt()),
    );
    return decodeImageResource(bytes);
  }

  int _canvasImageData(List<Object?> a) {
    final image = _imageOf(a[0]);
    if (image == null) return -3;
    return bufferResource(encodeAidokuImage(image.image));
  }

  int decodeImageResource(Uint8List bytes) {
    try {
      final image = decodeAidokuImage(bytes);
      return image == null ? -3 : _alloc(AidokuImage(image));
    } catch (_) {
      return -3;
    }
  }

  Uint8List? encodeImageResource(int rid) {
    final image = _imageOf(rid);
    if (image == null) return null;
    return encodeAidokuImage(image.image);
  }

  int _netGetImage(List<Object?> a) {
    final res = _net(a[0] as int);
    final data = res.data;
    if (!res.sent || data == null) return -12;
    final rid = decodeImageResource(data);
    return rid < 0 ? -12 : rid;
  }

  int _jsCreate(List<Object?> a) {
    try {
      return _alloc(_JsContext());
    } catch (_) {
      return -1;
    }
  }

  _JsContext? _jsContext(Object? rid) {
    final res = _resources[(rid as num).toInt()];
    return res is _JsContext ? res : null;
  }

  int _jsEval(List<Object?> a) {
    final ctx = _jsContext(a[0]);
    if (ctx == null) return -2;
    final code = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    try {
      final res = ctx.runtime.evaluate(code);
      if (res.isError) return -1;
      return stringResource(res.stringResult);
    } catch (_) {
      return -1;
    }
  }

  Future<int> _jsEvalAsync(List<Object?> a) async {
    final ctx = _jsContext(a[0]);
    if (ctx == null) return -2;
    final code = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    try {
      final res = await ctx.runtime.handlePromise(
        await ctx.runtime.evaluateAsync(code),
      );
      if (res.isError) return -1;
      return stringResource(res.stringResult);
    } catch (_) {
      return -1;
    }
  }

  int _jsGet(List<Object?> a) {
    final ctx = _jsContext(a[0]);
    if (ctx == null) return -2;
    final name = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    try {
      final res = ctx.runtime.evaluate(name);
      if (res.isError) return -1;
      return stringResource(res.stringResult);
    } catch (_) {
      return -1;
    }
  }

  int _stdBufferLen(List<Object?> a) {
    final rid = a[0] as int;
    if (!_resources.containsKey(rid)) return -1;
    try {
      return _bufferOf(rid).length;
    } catch (_) {
      return -1;
    }
  }

  int _stdReadBuffer(List<Object?> a) {
    final rid = a[0] as int;
    final bufPtr = (a[1] as num).toInt();
    final len = (a[2] as num).toInt();
    Uint8List bytes;
    try {
      bytes = _bufferOf(rid);
    } catch (_) {
      return -1;
    }
    if (len > bytes.length) return -2;
    _engine.writeBytes(bufPtr, bytes.sublist(0, len));
    return 0;
  }

  double _stdParseDate(List<Object?> a) {
    final text = _readStr((a[0] as num).toInt(), (a[1] as num).toInt());
    final format = _readStr((a[2] as num).toInt(), (a[3] as num).toInt());
    final zoneLen = (a[7] as num).toInt();
    final zone = zoneLen == 0
        ? 'UTC'
        : _readStr((a[6] as num).toInt(), zoneLen);
    final parsed = parseAidokuDate(text, format, timezone: zone);
    if (parsed != null) return parsed;
    final iso = DateTime.tryParse(text);
    return iso == null ? -5.0 : iso.toUtc().millisecondsSinceEpoch / 1000.0;
  }

  // --- net ---

  int _netInit(List<Object?> a) {
    const methods = [
      'GET',
      'POST',
      'PUT',
      'HEAD',
      'DELETE',
      'PATCH',
      'OPTIONS',
      'CONNECT',
      'TRACE',
    ];
    final idx = (a[0] as num).toInt();
    final method = idx >= 0 && idx < methods.length ? methods[idx] : 'GET';
    return _alloc(_NetResource(method));
  }

  _NetResource _net(int rid) {
    final res = _resources[rid];
    if (res is! _NetResource) throw ArgumentError('Invalid net resource');
    return res;
  }

  int _netSetUrl(List<Object?> a) {
    final res = _net(a[0] as int);
    res.url = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    return Uri.tryParse(res.url) == null ? -4 : 0;
  }

  int _netSetHeader(List<Object?> a) {
    final res = _net(a[0] as int);
    final key = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    final value = _readStr((a[3] as num).toInt(), (a[4] as num).toInt());
    res.headers[key] = value;
    return 0;
  }

  int _netSetBody(List<Object?> a) {
    final res = _net(a[0] as int);
    res.body = _engine.readBytes((a[1] as num).toInt(), (a[2] as num).toInt());
    return 0;
  }

  Object? _netSetTimeout(List<Object?> a) {
    final res = _net(a[0] as int);
    res.timeout = Duration(milliseconds: ((a[1] as num) * 1000).round());
    return null;
  }

  int _netSend(List<Object?> a) {
    _sendBatch([_net(a[0] as int)]);
    return 0;
  }

  void _sendBatch(List<_NetResource> batch) {
    final requests = <AidokuNetRequest>[];
    final sending = <_NetResource>[];
    for (final res in batch) {
      final uri = Uri.tryParse(res.url);
      if (uri == null) {
        res.statusCode = -4;
        res.sent = true;
        continue;
      }
      _awaitRateLimit();
      requests.add(
        AidokuNetRequest(
          method: res.method,
          url: res.url,
          headers: res.headers,
          body: res.body,
          timeout: res.timeout,
        ),
      );
      sending.add(res);
    }
    if (requests.isEmpty) return;
    final replies = _io.sendAll(requests);
    for (var i = 0; i < sending.length; i++) {
      final res = sending[i];
      final reply = replies[i];
      if (reply.error != null) {
        lastNetError = reply.error;
        res.statusCode = -10;
      } else {
        res.statusCode = reply.status;
        res.data = reply.body;
        res.responseHeaders = reply.headers;
        res.finalUrl = reply.url.isEmpty ? res.url : reply.url;
      }
      res.sent = true;
    }
  }

  int _netSendAll(List<Object?> a) {
    final ptr = (a[0] as num).toInt();
    final len = (a[1] as num).toInt();
    final resources = <_NetResource>[];
    for (var i = 0; i < len; i++) {
      final ridBytes = _engine.readBytes(ptr + i * 4, 4);
      final rid = ByteData.sublistView(ridBytes).getInt32(0, Endian.little);
      final res = _resources[rid];
      resources.add(res is _NetResource ? res : _NetResource('GET'));
    }
    _sendBatch(resources);
    for (var i = 0; i < len; i++) {
      final res = resources[i];
      if (res.statusCode < 0) {
        _engine.writeBytes(
          ptr + i * 4,
          Int32List.fromList([res.statusCode]).buffer.asUint8List(),
        );
      }
    }
    return 0;
  }

  int _netDataLen(List<Object?> a) {
    final res = _net(a[0] as int);
    if (!res.sent) return -8;
    return res.data?.length ?? -8;
  }

  int _netReadData(List<Object?> a) {
    final res = _net(a[0] as int);
    final bufPtr = (a[1] as num).toInt();
    final len = (a[2] as num).toInt();
    final data = res.data;
    if (data == null || len > data.length) return -8;
    _engine.writeBytes(bufPtr, data.sublist(0, len));
    return 0;
  }

  int _netGetHeader(List<Object?> a) {
    final res = _net(a[0] as int);
    final key = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    final value = res.responseHeaders[key.toLowerCase()];
    if (value == null) return -1;
    return _alloc(Uint8List.fromList(utf8.encode(value)));
  }

  int _netGetStatusCode(List<Object?> a) => _net(a[0] as int).statusCode;

  int _netGetUrl(List<Object?> a) =>
      _alloc(Uint8List.fromList(utf8.encode(_net(a[0] as int).finalUrl)));

  int _netHtml(List<Object?> a) {
    final res = _net(a[0] as int);
    final data = res.data;
    if (data == null) return -9;
    try {
      final doc = html_parser.parse(utf8.decode(data, allowMalformed: true));
      return _alloc(_NodeResource(doc, res.finalUrl));
    } catch (_) {
      return -5;
    }
  }

  // --- defaults ---

  String _defaultsKey(String key) => 'aidoku-$sourceId-pref-$key';

  int _defaultsGet(List<Object?> a) {
    final key = _readStr((a[0] as num).toInt(), (a[1] as num).toInt());
    final raw = _io.defaultsGet(_defaultsKey(key)) ?? _defaultValues[key];
    if (raw == null) return -1;
    return _alloc(base64Decode(raw));
  }

  int _defaultsSet(List<Object?> a) {
    final key = _readStr((a[0] as num).toInt(), (a[1] as num).toInt());
    final ptr = (a[3] as num).toInt();
    if (ptr == 0) {
      _io.defaultsSet(_defaultsKey(key), null);
      return 0;
    }
    final header = _engine.readBytes(ptr, 8);
    final bd = ByteData.sublistView(header);
    final totalLen = bd.getInt32(0, Endian.little);
    if (totalLen < 8) return -1;
    final payload = _engine.readBytes(ptr + 8, totalLen - 8);
    _io.defaultsSet(_defaultsKey(key), base64Encode(payload));
    return 0;
  }

  // --- html ---

  _NodeResource _nodeRes(int rid) {
    final res = _resources[rid];
    if (res is! _NodeResource) throw ArgumentError('Invalid node resource');
    return res;
  }

  int _htmlParse(List<Object?> a) {
    try {
      final htmlStr = _readStr((a[0] as num).toInt(), (a[1] as num).toInt());
      final baseUrl = _readStr((a[2] as num).toInt(), (a[3] as num).toInt());
      final doc = html_parser.parse(htmlStr);
      return _alloc(_NodeResource(doc, baseUrl));
    } catch (_) {
      return -3;
    }
  }

  int _htmlParseFragment(List<Object?> a) {
    try {
      final htmlStr = _readStr((a[0] as num).toInt(), (a[1] as num).toInt());
      final baseUrl = _readStr((a[2] as num).toInt(), (a[3] as num).toInt());
      // Like SwiftSoup's parseBodyFragment: a document whose body holds it.
      final doc = html_parser.parse('<body>$htmlStr');
      return _alloc(_NodeResource(doc, baseUrl));
    } catch (_) {
      return -3;
    }
  }

  int _htmlEscape(List<Object?> a) {
    final text = _readStr((a[0] as num).toInt(), (a[1] as num).toInt());
    final escaped = const HtmlEscape().convert(text);
    return _alloc(Uint8List.fromList(utf8.encode(escaped)));
  }

  int _htmlUnescape(List<Object?> a) {
    final text = _readStr((a[0] as num).toInt(), (a[1] as num).toInt());
    final unescaped = _unescapeHtml(text);
    return _alloc(Uint8List.fromList(utf8.encode(unescaped)));
  }

  static String _unescapeHtml(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  int _htmlKind(List<Object?> a) {
    final res = _resources[a[0] as int];
    if (res is _NodeListResource) return 6;
    if (res is! _NodeResource) return 0;
    final n = res.node;
    if (n is dom.Document || n is dom.DocumentFragment) return 7;
    if (n is dom.Element) return 5;
    if (n is dom.Comment) return 4;
    if (n is dom.Text) return 2;
    return 1;
  }

  List<dom.Element> _queryAll(dom.Node node, String query) {
    if (needsAidokuSelector(query)) return aidokuSelectAll(node, query);
    if (node is dom.Element) return node.querySelectorAll(query);
    if (node is dom.Document) return node.querySelectorAll(query);
    if (node is dom.DocumentFragment) return node.querySelectorAll(query);
    return const [];
  }

  dom.Element? _queryFirst(dom.Node node, String query) {
    if (needsAidokuSelector(query)) {
      return aidokuSelectAll(node, query).firstOrNull;
    }
    if (node is dom.Element) return node.querySelector(query);
    if (node is dom.Document) return node.querySelector(query);
    if (node is dom.DocumentFragment) return node.querySelector(query);
    return null;
  }

  int _htmlSelect(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final query = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    try {
      final found = _queryAll(res.node, query);
      return _alloc(_NodeListResource(found, res.baseUrl));
    } catch (e) {
      _log('select "$query" failed: $e');
      return -4;
    }
  }

  int _htmlSelectFirst(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final query = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    try {
      final found = _queryFirst(res.node, query);
      if (found == null) return -5;
      return _alloc(_NodeResource(found, res.baseUrl));
    } catch (e) {
      _log('select_first "$query" failed: $e');
      return -4;
    }
  }

  String _normalizeWhitespace(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  int _htmlText(List<Object?> a) {
    final res = _resources[a[0] as int];
    final nodes = res is _NodeListResource
        ? res.nodes
        : [_nodeRes(a[0] as int).node];
    final combined = nodes.map((n) => n.text ?? '').join(' ');
    return _alloc(
      Uint8List.fromList(utf8.encode(_normalizeWhitespace(combined))),
    );
  }

  int _htmlUntrimmedText(List<Object?> a) {
    final res = _resources[a[0] as int];
    final nodes = res is _NodeListResource
        ? res.nodes
        : [_nodeRes(a[0] as int).node];
    final combined = nodes.map((n) => n.text ?? '').join(' ');
    return _alloc(Uint8List.fromList(utf8.encode(combined)));
  }

  int _htmlHtml(List<Object?> a) {
    final res = _resources[a[0] as int];
    String out;
    if (res is _NodeListResource) {
      out = res.nodes.map((n) => n is dom.Element ? n.innerHtml : '').join();
    } else {
      final node = _nodeRes(a[0] as int).node;
      out = node is dom.Element ? node.innerHtml : '';
    }
    return _alloc(Uint8List.fromList(utf8.encode(out)));
  }

  int _htmlOuterHtml(List<Object?> a) {
    final res = _resources[a[0] as int];
    String out;
    if (res is _NodeListResource) {
      out = res.nodes.map(_outerHtmlOf).join();
    } else {
      out = _outerHtmlOf(_nodeRes(a[0] as int).node);
    }
    return _alloc(Uint8List.fromList(utf8.encode(out)));
  }

  String _outerHtmlOf(dom.Node node) {
    if (node is dom.Element) return node.outerHtml;
    if (node is dom.Text) return node.text;
    if (node is dom.Comment) return '<!--${node.data ?? ''}-->';
    return '';
  }

  int _htmlChildNodes(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    return _alloc(_NodeListResource(List.of(res.node.nodes), res.baseUrl));
  }

  int _htmlChildren(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final el = res.node;
    final children = el is dom.Element
        ? el.children
        : (el is dom.Document ? el.children : <dom.Element>[]);
    return _alloc(
      _NodeListResource(List<dom.Node>.from(children), res.baseUrl),
    );
  }

  int _htmlSiblings(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final parent = res.node.parentNode;
    if (parent == null) return _alloc(_NodeListResource(const [], res.baseUrl));
    return _alloc(_NodeListResource(List.of(parent.nodes), res.baseUrl));
  }

  int _htmlFirst(List<Object?> a) {
    final res = _resources[a[0] as int];
    if (res is! _NodeListResource || res.nodes.isEmpty) return -5;
    return _alloc(_NodeResource(res.nodes.first, res.baseUrl));
  }

  int _htmlLast(List<Object?> a) {
    final res = _resources[a[0] as int];
    if (res is! _NodeListResource || res.nodes.isEmpty) return -5;
    return _alloc(_NodeResource(res.nodes.last, res.baseUrl));
  }

  int _htmlGet(List<Object?> a) {
    final res = _resources[a[0] as int];
    final index = (a[1] as num).toInt();
    if (res is! _NodeListResource || index < 0 || index >= res.nodes.length) {
      return -5;
    }
    return _alloc(_NodeResource(res.nodes[index], res.baseUrl));
  }

  int _htmlSize(List<Object?> a) {
    final res = _resources[a[0] as int];
    return res is _NodeListResource ? res.nodes.length : 0;
  }

  int _htmlParent(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final parent = res.node.parentNode;
    if (parent == null) return -5;
    return _alloc(_NodeResource(parent, res.baseUrl));
  }

  int _htmlNext(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final el = res.node;
    final next = el is dom.Element ? el.nextElementSibling : null;
    if (next == null) return -5;
    return _alloc(_NodeResource(next, res.baseUrl));
  }

  int _htmlPrevious(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final el = res.node;
    final prev = el is dom.Element ? el.previousElementSibling : null;
    if (prev == null) return -5;
    return _alloc(_NodeResource(prev, res.baseUrl));
  }

  String? _resolve(String baseUrl, String value) {
    if (baseUrl.isEmpty) return value;
    final base = Uri.tryParse(baseUrl);
    if (base == null) return value;
    final resolved = base.resolve(value);
    return resolved.toString();
  }

  int _htmlAttr(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final el = res.node;
    if (el is! dom.Element) return -5;
    var key = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    var absolute = false;
    if (key.startsWith('abs:')) {
      absolute = true;
      key = key.substring(4);
    }
    final value = el.attributes[key];
    if (value == null) return -5;
    final out = absolute ? (_resolve(res.baseUrl, value) ?? value) : value;
    return _alloc(Uint8List.fromList(utf8.encode(out)));
  }

  int _htmlHasAttr(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final el = res.node;
    if (el is! dom.Element) return 0;
    final key = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    return el.attributes.containsKey(key) ? 1 : 0;
  }

  int _htmlSetAttr(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final el = res.node;
    if (el is! dom.Element) return -1;
    final key = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    final value = _readStr((a[3] as num).toInt(), (a[4] as num).toInt());
    el.attributes[key] = value;
    return 0;
  }

  int _htmlRemoveAttr(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final el = res.node;
    if (el is! dom.Element) return -1;
    el.attributes.remove(
      _readStr((a[1] as num).toInt(), (a[2] as num).toInt()),
    );
    return 0;
  }

  int _htmlSetText(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final el = res.node;
    if (el is! dom.Element) return -1;
    el.text = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    return 0;
  }

  int _htmlSetHtml(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final el = res.node;
    if (el is! dom.Element) return -1;
    el.innerHtml = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    return 0;
  }

  int _htmlPrepend(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final el = res.node;
    if (el is! dom.Element) return -1;
    final frag = html_parser.parseFragment(
      _readStr((a[1] as num).toInt(), (a[2] as num).toInt()),
    );
    el.nodes.insertAll(0, List.of(frag.nodes));
    return 0;
  }

  int _htmlAppend(List<Object?> a) {
    final res = _nodeRes(a[0] as int);
    final el = res.node;
    if (el is! dom.Element) return -1;
    final frag = html_parser.parseFragment(
      _readStr((a[1] as num).toInt(), (a[2] as num).toInt()),
    );
    el.nodes.addAll(List.of(frag.nodes));
    return 0;
  }

  int _htmlBaseUri(List<Object?> a) =>
      _alloc(Uint8List.fromList(utf8.encode(_nodeRes(a[0] as int).baseUrl)));

  int _htmlOwnText(List<Object?> a) {
    final el = _nodeRes(a[0] as int).node;
    if (el is! dom.Element) return -5;
    final own = el.nodes.whereType<dom.Text>().map((t) => t.text).join(' ');
    return _alloc(Uint8List.fromList(utf8.encode(_normalizeWhitespace(own))));
  }

  int _htmlData(List<Object?> a) {
    final el = _nodeRes(a[0] as int).node;
    String out;
    if (el is dom.Comment) {
      out = el.data ?? '';
    } else if (el is dom.Element) {
      out = el.nodes.whereType<dom.Text>().map((t) => t.data).join();
    } else {
      return -5;
    }
    return _alloc(Uint8List.fromList(utf8.encode(out)));
  }

  int _htmlId(List<Object?> a) {
    final el = _nodeRes(a[0] as int).node;
    if (el is! dom.Element) return -5;
    return _alloc(Uint8List.fromList(utf8.encode(el.id)));
  }

  int _htmlTagName(List<Object?> a) {
    final el = _nodeRes(a[0] as int).node;
    if (el is! dom.Element) return -5;
    return _alloc(Uint8List.fromList(utf8.encode(el.localName ?? '')));
  }

  int _htmlClassName(List<Object?> a) {
    final el = _nodeRes(a[0] as int).node;
    if (el is! dom.Element) return -5;
    return _alloc(Uint8List.fromList(utf8.encode(el.className)));
  }

  int _htmlHasClass(List<Object?> a) {
    final el = _nodeRes(a[0] as int).node;
    if (el is! dom.Element) return 0;
    final cls = _readStr((a[1] as num).toInt(), (a[2] as num).toInt());
    return el.classes.contains(cls) ? 1 : 0;
  }

  int _htmlAddClass(List<Object?> a) {
    final el = _nodeRes(a[0] as int).node;
    if (el is! dom.Element) return -1;
    el.classes.add(_readStr((a[1] as num).toInt(), (a[2] as num).toInt()));
    return 0;
  }

  int _htmlRemoveClass(List<Object?> a) {
    final el = _nodeRes(a[0] as int).node;
    if (el is! dom.Element) return -1;
    el.classes.remove(_readStr((a[1] as num).toInt(), (a[2] as num).toInt()));
    return 0;
  }

  int _htmlRemove(List<Object?> a) {
    final res = _resources[a[0] as int];
    if (res is _NodeListResource) {
      for (final n in res.nodes) {
        n.remove();
      }
    } else if (res is _NodeResource) {
      res.node.remove();
    }
    return 0;
  }
}

class _FontResource {
  const _FontResource();
}
