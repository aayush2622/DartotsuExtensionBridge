import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:webview_all/webview_all.dart';

import '../Logger.dart';
import 'BridgeWebView.dart';
import 'MClient.dart';
import 'WebViewCookieSync.dart';

/// Long-lived WebViews for the JVM backends' `android.webkit.WebView`.
///
/// The JVM has no Chromium of its own: a source that creates a `WebView`
/// gets a provider that drives one of these sessions instead, so pages run in
/// the app's own WebView with its User-Agent and cookies.
///
/// The JVM sends `wv*` calls (create, load, eval, interface, action, state,
/// close) and long-polls [poll] for what happened: page start / finish,
/// progress, errors, every request the page makes (`fetch` / XHR / resource
/// timing hooks, not the network layer), and calls from JavaScript
/// interfaces. A session nobody touches for [idle] is closed.
class BridgeWebViewSessions {
  BridgeWebViewSessions._();

  static const _callChannel = 'DartotsuCall';
  static const idle = Duration(minutes: 5);

  static final _sessions = <String, _Session>{};
  static Timer? _reaper;

  static Future<dynamic> handle(String method, Map args) async {
    final id = args['id'] as String;
    if (method == 'wvCreate') return _create(id, args);
    final session = _sessions[id];
    if (session == null) {
      if (method == 'wvPoll') {
        return jsonEncode([
          {'t': 'closed'},
        ]);
      }
      return null;
    }
    if (method != 'wvPoll') session.touch();
    switch (method) {
      case 'wvLoad':
        return _load(session, args);
      case 'wvLoadHtml':
        await session.controller.loadHtmlString(
          args['html'] as String,
          baseUrl: args['baseUrl'] as String?,
        );
        return true;
      case 'wvEval':
        return _eval(session, args['script'] as String);
      case 'wvPoll':
        final timeout = Duration(
          milliseconds: (args['timeoutMs'] as num?)?.toInt() ?? 20000,
        );
        return jsonEncode(await session.drain(timeout));
      case 'wvInterface':
        return _interface(
          session,
          args['name'] as String,
          (args['functions'] as List).cast<String>(),
        );
      case 'wvUnInterface':
        return _removeInterface(session, args['name'] as String);
      case 'wvAction':
        return _action(session, args['action'] as String);
      case 'wvState':
        return jsonEncode({
          'url': await session.controller.currentUrl(),
          'title': await _guard(session.controller.getTitle),
          'canGoBack': await _guard(session.controller.canGoBack) ?? false,
          'canGoForward':
              await _guard(session.controller.canGoForward) ?? false,
        });
      case 'wvClose':
        await _close(id);
        return true;
    }
    throw Exception('Unknown method: $method');
  }

  static Future<T?> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _create(String id, Map args) async {
    await _close(id);
    final offscreen = await OffscreenWebViewSession.create();
    final session = _Session(offscreen);
    final controller = session.controller;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    session.userAgent = bridgeUserAgent();
    await controller.setUserAgent(session.userAgent);
    await controller.addJavaScriptChannel(
      BridgeWebView.channel,
      onMessageReceived: (m) =>
          session.push({'t': 'resource', 'url': m.message}),
    );
    await controller.addJavaScriptChannel(
      _callChannel,
      onMessageReceived: (m) {
        try {
          session.push({
            't': 'js',
            ...Map<String, dynamic>.from(jsonDecode(m.message) as Map),
          });
        } catch (_) {}
      },
    );
    await controller.addUserScript(
      const WebViewUserScript(
        source: BridgeWebView.requestHook,
        forMainFrameOnly: false,
      ),
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          session.push({
            't': 'nav',
            'url': request.url,
            'main': request.isMainFrame,
          });
          return NavigationDecision.navigate;
        },
        onPageStarted: (url) {
          session.url = url;
          session.push({'t': 'start', 'url': url});
        },
        onPageFinished: (url) async {
          session.url = url;
          final title = await _guard(controller.getTitle);
          final uri = Uri.tryParse(url);
          if (uri != null && uri.hasAuthority) {
            await _guard(() => WebViewCookieSync.fromWebView(uri));
          }
          session.push({'t': 'finish', 'url': url, 'title': title});
        },
        onProgress: (progress) =>
            session.push({'t': 'progress', 'p': progress}),
        onWebResourceError: (error) => session.push({
          't': 'error',
          'code': error.errorCode,
          'desc': error.description,
        }),
      ),
    );
    _sessions[id] = session;
    _reaper ??= Timer.periodic(const Duration(minutes: 1), (_) => _reap());
    return true;
  }

  static Future<bool> _load(_Session session, Map args) async {
    final controller = session.controller;
    final agent = args['userAgent'] as String?;
    if (agent != null && agent.isNotEmpty && agent != session.userAgent) {
      session.userAgent = agent;
      await controller.setUserAgent(agent);
    }
    final uri = Uri.parse(args['url'] as String);
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      await controller.loadHtmlString('', baseUrl: uri.toString());
      return true;
    }
    await _guard(() => WebViewCookieSync.toWebView(uri));
    final headers =
        (args['headers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        const <String, String>{};
    final body = args['body'] as String?;
    await controller.loadRequest(
      uri,
      method: body == null ? LoadRequestMethod.get : LoadRequestMethod.post,
      headers: headers,
      body: body == null ? null : Uint8List.fromList(base64Decode(body)),
    );
    return true;
  }

  static Future<String> _eval(_Session session, String script) async {
    final controller = session.controller;
    Object? result;
    try {
      result = await controller.runJavaScriptReturningResult(
        'JSON.stringify([(0, eval)(${jsonEncode(script)})])',
      );
      final decoded = _json(result);
      if (decoded is List && decoded.isNotEmpty) {
        return jsonEncode(decoded.first);
      }
    } catch (_) {}
    try {
      return jsonEncode(
        _json(await controller.runJavaScriptReturningResult(script)),
      );
    } catch (e) {
      Logger.log('[WebView] Script failed: $e');
      return 'null';
    }
  }

  static Object? _json(Object? raw) {
    var value = raw;
    for (var i = 0; i < 3 && value is String; i++) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        break;
      }
    }
    return value;
  }

  static Future<bool> _interface(
    _Session session,
    String name,
    List<String> functions,
  ) async {
    final source =
        '''
(function () {
  var n = ${jsonEncode(name)};
  window[n] = window[n] || {};
  var pending = window.__dartotsuPending = window.__dartotsuPending || {};
  if (!window.__dartotsuReply) {
    window.__dartotsuReply = function (id, ok, value) {
      var p = pending[id];
      if (!p) return;
      delete pending[id];
      ok ? p.resolve(value) : p.reject(value);
    };
  }
  ${jsonEncode(functions)}.forEach(function (f) {
    window[n][f] = function () {
      var args = Array.prototype.slice.call(arguments);
      return Promise.all(args).then(function (a) {
        return new Promise(function (resolve, reject) {
          var id = window.__dartotsuSeq = (window.__dartotsuSeq || 0) + 1;
          pending[id] = { resolve: resolve, reject: reject };
          window.$_callChannel.postMessage(
            JSON.stringify({ c: id, i: n, f: f, a: a.map(function (x) {
              return typeof x === 'string' ? x : JSON.stringify(x);
            }) })
          );
        });
      });
    };
  });
})();
''';
    await _removeInterface(session, name);
    final scriptId = await session.controller.addUserScript(
      WebViewUserScript(source: source, forMainFrameOnly: false),
    );
    session.interfaces[name] = scriptId;
    await _guard(() => session.controller.runJavaScript(source));
    return true;
  }

  static Future<bool> _removeInterface(_Session session, String name) async {
    final scriptId = session.interfaces.remove(name);
    if (scriptId == null) return false;
    await _guard(() => session.controller.removeUserScript(scriptId));
    await _guard(
      () => session.controller.runJavaScript(
        'try { delete window[${jsonEncode(name)}]; } catch (e) {}',
      ),
    );
    return true;
  }

  static Future<bool> _action(_Session session, String action) async {
    final controller = session.controller;
    switch (action) {
      case 'stop':
        await _guard(() => controller.runJavaScript('window.stop();'));
      case 'reload':
        await controller.reload();
      case 'back':
        await controller.goBack();
      case 'forward':
        await controller.goForward();
    }
    return true;
  }

  static Future<void> _close(String id) async {
    final session = _sessions.remove(id);
    if (session == null) return;
    session.push({'t': 'closed'});
    session.closed = true;
    await _guard(session.offscreen.close);
    if (_sessions.isEmpty) {
      _reaper?.cancel();
      _reaper = null;
    }
  }

  static void _reap() {
    final now = DateTime.now();
    for (final entry in _sessions.entries.toList()) {
      if (now.difference(entry.value.lastUse) > idle) {
        Logger.log('[WebView] Closing idle session ${entry.key}');
        unawaited(_close(entry.key));
      }
    }
  }
}

class _Session {
  _Session(this.offscreen);

  final OffscreenWebViewSession offscreen;
  final events = <Map<String, dynamic>>[];
  final interfaces = <String, String>{};
  Completer<void>? _waiter;
  DateTime lastUse = DateTime.now();
  String? userAgent;
  String? url;
  bool closed = false;

  WebViewController get controller => offscreen.controller;

  void touch() => lastUse = DateTime.now();

  void push(Map<String, dynamic> event) {
    events.add(event);
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<List<Map<String, dynamic>>> drain(Duration timeout) async {
    if (events.isEmpty && !closed) {
      final waiter = _waiter = Completer<void>();
      await waiter.future.timeout(timeout, onTimeout: () {});
      _waiter = null;
    }
    final out = List<Map<String, dynamic>>.of(events);
    events.clear();
    return out;
  }
}
