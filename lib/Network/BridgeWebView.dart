import 'dart:async';
import 'dart:convert';

import 'package:webview_all/webview_all.dart';

import '../Logger.dart';
import '../NetworkClient.dart';
import 'WebViewCookieSync.dart';

/// Background WebView tasks for backends whose sources need a real browser
/// (CloudStream's `WebViewResolver`, Kotatsu's `evaluateJs`, …).
///
/// Request (JSON from the JVM side, `BridgeWebView.kt`):
/// * `url` – page to load; `headers` – extra headers for that load.
/// * `interceptUrl` – regex; the task ends at the first request matching it.
/// * `additionalUrls` – regexes; every matching request is collected.
/// * `script` – JavaScript run after the page loads; its result is returned.
/// * `timeoutMs` – upper bound for the whole task.
///
/// Result: `{url, additional, scriptResult, userAgent}`.
///
/// The page runs with the app's User-Agent and cookies, and cookies it sets
/// are saved to the app's jar. Requests are seen through `fetch`/XHR hooks,
/// resource timing and navigations, not at the network layer, so the
/// requests' own headers aren't available.
class BridgeWebView {
  BridgeWebView._();

  static const _channel = 'DartotsuResolver';

  static Future<Map<String, dynamic>> run(Map<String, dynamic> request) async {
    final url = Uri.parse(request['url'] as String);
    final headers = (request['headers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        const <String, String>{};
    final intercept = _regex(request['interceptUrl']);
    final additional = [
      for (final pattern in (request['additionalUrls'] as List? ?? const []))
        ?_regex(pattern),
    ];
    final script = request['script'] as String?;
    final timeout = Duration(
      milliseconds: (request['timeoutMs'] as num?)?.toInt() ?? 60000,
    );
    final userAgent = bridgeUserAgent();

    String? matched;
    final collected = <String>{};
    String? scriptResult;
    final done = Completer<void>();

    void finishIfReady() {
      final interceptDone = intercept == null || matched != null;
      final scriptDone = script == null || scriptResult != null;
      if (interceptDone && scriptDone && !done.isCompleted) done.complete();
    }

    void seen(String requestUrl) {
      if (intercept != null && matched == null && intercept.hasMatch(requestUrl)) {
        matched = requestUrl;
      }
      for (final regex in additional) {
        if (regex.hasMatch(requestUrl)) collected.add(requestUrl);
      }
      finishIfReady();
    }

    OffscreenWebViewSession? session;
    try {
      session = await OffscreenWebViewSession.create();
      final controller = session.controller;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setUserAgent(userAgent);
      await controller.addJavaScriptChannel(
        _channel,
        onMessageReceived: (message) => seen(message.message),
      );
      await controller.addUserScript(
        const WebViewUserScript(source: _requestHook, forMainFrameOnly: false),
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (navigation) {
            seen(navigation.url);
            return NavigationDecision.navigate;
          },
          onPageFinished: (_) async {
            if (script == null || scriptResult != null) return;
            try {
              final result = await controller.runJavaScriptReturningResult(
                script,
              );
              scriptResult = result is String ? result : jsonEncode(result);
            } catch (e) {
              scriptResult = '';
              Logger.log('[WebView] Script failed on $url: $e');
            }
            finishIfReady();
          },
        ),
      );

      await WebViewCookieSync.toWebView(url);
      seen(url.toString());
      await controller.loadRequest(url, headers: headers);
      await done.future.timeout(timeout, onTimeout: () {});
      await WebViewCookieSync.fromWebView(url);
    } catch (e) {
      Logger.log('[WebView] Task on $url failed: $e');
    } finally {
      try {
        await session?.close();
      } catch (_) {}
    }

    return {
      'url': matched,
      'additional': collected.toList(),
      'scriptResult': scriptResult,
      'userAgent': userAgent,
    };
  }

  static RegExp? _regex(Object? pattern) {
    if (pattern is! String || pattern.isEmpty) return null;
    try {
      return RegExp(pattern);
    } catch (_) {
      return null;
    }
  }

  /// Reports every URL the page (and its frames) requests: `fetch`, XHR,
  /// resource timing entries and media/iframe `src` attributes.
  static const _requestHook = '''
(function () {
  if (window.__dartotsuResolver) return;
  window.__dartotsuResolver = true;
  var channel = window.$_channel;
  var sent = {};
  function report(u) {
    try {
      if (!u) return;
      u = new URL(u, location.href).href;
      if (sent[u]) return;
      sent[u] = true;
      if (channel && channel.postMessage) channel.postMessage(u);
    } catch (e) {}
  }
  var originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function (input, init) {
      report(typeof input === 'string' ? input : (input && input.url));
      return originalFetch.apply(this, arguments);
    };
  }
  var open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, u) {
    report(u);
    return open.apply(this, arguments);
  };
  try {
    new PerformanceObserver(function (list) {
      list.getEntries().forEach(function (e) { report(e.name); });
    }).observe({ type: 'resource', buffered: true });
  } catch (e) {}
  function scan(node) {
    if (!node || !node.querySelectorAll) return;
    node.querySelectorAll('video[src],source[src],iframe[src],audio[src],embed[src]')
      .forEach(function (el) { report(el.src); });
  }
  new MutationObserver(function (mutations) {
    mutations.forEach(function (m) {
      if (m.type === 'attributes') report(m.target.src);
      m.addedNodes && m.addedNodes.forEach(function (n) {
        if (n.src) report(n.src);
        scan(n);
      });
    });
  }).observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ['src'] });
})();
''';
}
