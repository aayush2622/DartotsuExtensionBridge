import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';

import '../ExtensionBridge.dart';
import '../Logger.dart';
import '../NetworkClient.dart';
import 'WebViewCookieSync.dart';

/// Clears Cloudflare challenges for every backend.
///
/// A background WebView loads the page with the app's User-Agent and cookies
/// and waits for a fresh `cf_clearance`, which lands in the app's cookie jar
/// for every client. Only when that fails (an interactive Turnstile, say) is
/// the user shown [CloudflareChallengePage] through
/// [BridgeNetwork.presentChallenge]. Calls for the same host share one
/// attempt, and a host the user just dismissed isn't asked about again for a
/// while.
class CloudflareSolver {
  CloudflareSolver._();

  static const _backgroundTimeout = Duration(seconds: 30);
  static const _settleTime = Duration(seconds: 3);
  static const _askAgainAfter = Duration(minutes: 10);

  static final _inflight = <String, Future<bool>>{};
  static final _dismissed = <String, DateTime>{};
  static Future<void> _promptQueue = Future.value();

  /// Clears the challenge for [url]. Returns true once the app's cookie jar
  /// holds clearance the request can be retried with.
  static Future<bool> solve(Uri url, {bool interactive = true}) {
    final host = url.host;
    return _inflight[host] ??= _solve(url, interactive).whenComplete(
      () => _inflight.remove(host),
    );
  }

  static Future<bool> _solve(Uri url, bool interactive) async {
    final outcome = await _solveInBackground(url);
    Logger.log('[Cloudflare] ${url.host}: background attempt ${outcome.name}');
    switch (outcome) {
      case _Outcome.cleared:
        return true;
      case _Outcome.noChallenge:
        return false;
      case _Outcome.unsolved:
        return interactive && await _askUser(url);
    }
  }

  static Future<_Outcome> _solveInBackground(Uri url) async {
    OffscreenWebViewSession? session;
    try {
      session = await OffscreenWebViewSession.create();
      final controller = session.controller;
      var loaded = false;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setUserAgent(bridgeUserAgent());
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => loaded = true),
      );

      await WebViewCookieSync.toWebView(url);
      final before = await WebViewCookieSync.clearance(url);
      await controller.loadRequest(url);

      final deadline = DateTime.now().add(_backgroundTimeout);
      DateTime? calmSince;
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(seconds: 1));

        final current = await WebViewCookieSync.clearance(url);
        if (current != null && current != before) {
          await WebViewCookieSync.fromWebView(url);
          return _Outcome.cleared;
        }

        if (!loaded || await isChallengePage(controller)) {
          calmSince = null;
          continue;
        }
        calmSince ??= DateTime.now();
        if (DateTime.now().difference(calmSince) >= _settleTime) {
          // The page loads in a browser with the app's cookies. With an
          // existing clearance a retry can pass; without one there was no
          // challenge to clear (a plain block).
          await WebViewCookieSync.fromWebView(url);
          return current != null ? _Outcome.cleared : _Outcome.noChallenge;
        }
      }
      return _Outcome.unsolved;
    } catch (e) {
      Logger.log('[Cloudflare] Background WebView failed for ${url.host}: $e');
      return _Outcome.unsolved;
    } finally {
      try {
        await session?.close();
      } catch (_) {}
    }
  }

  /// One page at a time: challenges for several hosts queue up.
  static Future<bool> _askUser(Uri url) {
    final result = _promptQueue.then((_) => _showPage(url));
    _promptQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<bool> _showPage(Uri url) async {
    final dismissedAt = _dismissed[url.host];
    if (dismissedAt != null &&
        DateTime.now().difference(dismissedAt) < _askAgainAfter) {
      return false;
    }

    final network = DartotsuExtensionBridge.context.network;
    if (network == null) return false;

    final cleared = Completer<bool>();
    final shown = await network.presentChallenge(
      CloudflareChallengePage(
        url: url,
        onFinished: (ok) {
          if (!cleared.isCompleted) cleared.complete(ok);
        },
      ),
    );
    final ok = shown && cleared.isCompleted && await cleared.future;
    if (!ok) _dismissed[url.host] = DateTime.now();
    return ok;
  }

  /// Whether the page in [controller] is a Cloudflare challenge.
  static Future<bool> isChallengePage(WebViewController controller) async {
    try {
      final result = await controller.runJavaScriptReturningResult(
        _challengeProbe,
      );
      return result.toString().replaceAll('"', '') == '1';
    } catch (_) {
      return true;
    }
  }

  static const _challengeProbe = '''
(function () {
  var t = (document.title || '').toLowerCase();
  if (t.indexOf('just a moment') >= 0 || t.indexOf('attention required') >= 0) return '1';
  return document.querySelector('#challenge-form, #challenge-stage, #cf-challenge-running, .cf-turnstile, #turnstile-wrapper, script[src*="challenge-platform"]') ? '1' : '0';
})()
''';
}

enum _Outcome { cleared, noChallenge, unsolved }

/// A visible WebView for a challenge the background WebView couldn't clear.
/// It closes itself once the page hands out clearance.
class CloudflareChallengePage extends StatefulWidget {
  const CloudflareChallengePage({
    super.key,
    required this.url,
    required this.onFinished,
  });

  final Uri url;

  /// Called once with whether the challenge was cleared.
  final void Function(bool cleared) onFinished;

  @override
  State<CloudflareChallengePage> createState() =>
      _CloudflareChallengePageState();
}

class _CloudflareChallengePageState extends State<CloudflareChallengePage> {
  final _controller = WebViewController();
  Timer? _poll;
  String? _before;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setUserAgent(bridgeUserAgent());
    await WebViewCookieSync.toWebView(widget.url);
    _before = await WebViewCookieSync.clearance(widget.url);
    await _controller.loadRequest(widget.url);
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  Future<void> _check() async {
    if (_finished) return;
    final current = await WebViewCookieSync.clearance(widget.url);
    final fresh = current != null && current != _before;
    if (!fresh) return;
    if (await CloudflareSolver.isChallengePage(_controller)) return;
    await WebViewCookieSync.fromWebView(widget.url);
    _finish(true);
  }

  void _finish(bool cleared) {
    if (_finished) return;
    _finished = true;
    _poll?.cancel();
    widget.onFinished(cleared);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (!_finished) {
      _finished = true;
      widget.onFinished(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _finish(false),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Verify you are human'),
            Text(widget.url.host, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
