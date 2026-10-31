import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';

import '../ExtensionBridge.dart';
import '../Logger.dart';
import 'MClient.dart';
import 'WebViewCookieSync.dart';

enum CloudflareFailure {
  timeout,
  blocked,
  turnstile,
  loadFailed,
  rejected,
  dismissed,
  cooldown,
  quiet,
  webView,
  unavailable,
}

class CloudflareResult {
  final Uri url;
  final bool cleared;
  final bool noChallenge;
  final CloudflareFailure? failure;
  final bool byUser;
  final DateTime at;
  final Duration took;

  const CloudflareResult({
    required this.url,
    required this.at,
    required this.took,
    this.cleared = false,
    this.noChallenge = false,
    this.failure,
    this.byUser = false,
  });
}

/// Clears Cloudflare challenges for every backend.
///
/// A background WebView loads the page with the app's User-Agent and cookies
/// and waits for a fresh `cf_clearance`, which lands in the app's cookie jar
/// for every client. Only when that fails (an interactive Turnstile, say) is
/// the user shown [CloudflareChallengePage] through
/// [BridgeNetwork.presentChallenge], and it closes itself as soon as the
/// challenge is passed so the waiting request carries on.
///
/// Calls for the same host share one attempt. A request that was already in
/// flight when a clearance landed (a search over several pages, a list of
/// covers) also gets its challenge response late: it is retried with the new
/// cookies instead of starting another attempt. The user is asked only when a
/// retry with the clearance was rejected (`retried`), never for work the app
/// does by itself ([quietly]) and never again for a while after a dismissal.
class CloudflareSolver {
  CloudflareSolver._();

  static const _backgroundTimeout = Duration(seconds: 30);
  static const _interactiveAfter = Duration(seconds: 14);
  static const _poll = Duration(milliseconds: 500);
  static const _settleTime = Duration(seconds: 2);
  static const _lateWindow = Duration(seconds: 20);
  static const _askAgainAfter = Duration(minutes: 10);

  static final _inflight = <String, Future<CloudflareResult>>{};
  static final _dismissed = <String, DateTime>{};
  static final _clearedAt = <String, DateTime>{};
  static final _results = <String, CloudflareResult>{};
  static Future<void> _promptQueue = Future.value();
  static int _quiet = 0;

  /// Runs [job] without ever showing the challenge page: a challenge met
  /// while it runs is still cleared in the background when possible, but a
  /// source that needs the user fails quietly and is asked about the next
  /// time the user opens it. Use it for everything the app starts by itself.
  static Future<T> quietly<T>(Future<T> Function() job) async {
    _quiet++;
    try {
      return await job();
    } finally {
      _quiet--;
    }
  }

  /// How the last attempt on [host] ended, or null when none was made since
  /// the app started.
  static CloudflareResult? lastResult(String host) => _results[host];

  /// Whether an attempt on [host] is running.
  static bool isSolving(String host) => _inflight.containsKey(host);

  /// Clears the challenge for [url]. Returns true once the app's cookie jar
  /// holds clearance the request can be retried with. [retried] means the
  /// request already went out again with the app's clearance and was
  /// challenged once more.
  static Future<bool> solve(
    Uri url, {
    bool interactive = true,
    bool retried = false,
  }) async => (await attempt(
    url,
    interactive: interactive,
    retried: retried,
  )).cleared;

  /// [solve] with the reason it failed. [force] asks the user even right
  /// after they dismissed the page, for an attempt the user started.
  static Future<CloudflareResult> attempt(
    Uri url, {
    bool interactive = true,
    bool retried = false,
    bool force = false,
  }) {
    final host = url.host;
    return _inflight[host] ??= _solve(url, interactive, retried, force)
        .then((result) => _results[host] = result)
        .whenComplete(() => _inflight.remove(host));
  }

  static Future<CloudflareResult> _solve(
    Uri url,
    bool interactive,
    bool retried,
    bool force,
  ) async {
    final host = url.host;
    final started = DateTime.now();
    CloudflareResult done({
      bool cleared = false,
      bool noChallenge = false,
      bool byUser = false,
      CloudflareFailure? failure,
    }) => CloudflareResult(
      url: url,
      at: DateTime.now(),
      took: DateTime.now().difference(started),
      cleared: cleared,
      noChallenge: noChallenge,
      byUser: byUser,
      failure: failure,
    );

    final last = _clearedAt[host];
    if (!retried && last != null) {
      if (DateTime.now().difference(last) < _lateWindow) {
        Logger.log('[Cloudflare] $host: cleared a moment ago, retrying');
        return done(cleared: true);
      }
    }
    if (retried) {
      _clearedAt.remove(host);
      Logger.log('[Cloudflare] $host: clearance was rejected');
      if (!interactive) return done(failure: CloudflareFailure.rejected);
      final asked = await _askUser(url, force: force);
      return done(
        cleared: asked.cleared,
        byUser: asked.cleared,
        failure: asked.cleared ? null : asked.failure,
      );
    }
    final background = await _solveInBackground(url);
    Logger.log('[Cloudflare] $host: background attempt ${background.name}');
    switch (background.outcome) {
      case _Outcome.cleared:
        _clearedAt[host] = DateTime.now();
        return done(cleared: true);
      case _Outcome.noChallenge:
        return done(noChallenge: true);
      case _Outcome.unsolved:
        final failure = background.failure ?? CloudflareFailure.timeout;
        if (!interactive || failure == CloudflareFailure.blocked) {
          return done(failure: failure);
        }
        final asked = await _askUser(url, force: force);
        return done(
          cleared: asked.cleared,
          byUser: asked.cleared,
          failure: asked.cleared ? null : asked.failure,
        );
    }
  }

  static Future<_Background> _solveInBackground(Uri url) async {
    OffscreenWebViewSession? session;
    try {
      session = await OffscreenWebViewSession.create();
      final controller = session.controller;
      var loaded = false;
      var loadError = false;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setUserAgent(bridgeUserAgent());
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => loaded = true,
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) loadError = true;
          },
        ),
      );

      await WebViewCookieSync.toWebView(url);
      final before = await WebViewCookieSync.clearance(url);
      await controller.loadRequest(url);

      final started = DateTime.now();
      final deadline = started.add(_backgroundTimeout);
      DateTime? calmSince;
      var sawWidget = false;
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(_poll);

        final current = await WebViewCookieSync.clearance(url);
        if (current != null && current != before) {
          await WebViewCookieSync.fromWebView(url);
          return const _Background(_Outcome.cleared);
        }

        if (!loaded) {
          calmSince = null;
          if (loadError) {
            return const _Background(
              _Outcome.unsolved,
              CloudflareFailure.loadFailed,
            );
          }
          continue;
        }
        final state = await _probe(controller);
        if (state == _Page.blocked) {
          return const _Background(
            _Outcome.unsolved,
            CloudflareFailure.blocked,
          );
        }
        if (state != _Page.open) {
          calmSince = null;
          if (state == _Page.widget) {
            sawWidget = true;
            if (DateTime.now().difference(started) >= _interactiveAfter) {
              return const _Background(
                _Outcome.unsolved,
                CloudflareFailure.turnstile,
              );
            }
          }
          continue;
        }
        calmSince ??= DateTime.now();
        if (DateTime.now().difference(calmSince) >= _settleTime) {
          await WebViewCookieSync.fromWebView(url);
          return _Background(
            current != null ? _Outcome.cleared : _Outcome.noChallenge,
          );
        }
      }
      return _Background(
        _Outcome.unsolved,
        !loaded
            ? CloudflareFailure.loadFailed
            : sawWidget
            ? CloudflareFailure.turnstile
            : CloudflareFailure.timeout,
      );
    } catch (e) {
      Logger.log('[Cloudflare] Background WebView failed for ${url.host}: $e');
      return const _Background(
        _Outcome.unsolved,
        CloudflareFailure.webView,
      );
    } finally {
      try {
        await session?.close();
      } catch (_) {}
    }
  }

  static Future<_Asked> _askUser(Uri url, {bool force = false}) {
    if (_quiet > 0 && !force) {
      Logger.log(
        '[Cloudflare] ${url.host}: needs the user, not asking while the app works on its own',
      );
      return Future.value(const _Asked(false, CloudflareFailure.quiet));
    }
    final result = _promptQueue.then((_) => _showPage(url, force));
    _promptQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<_Asked> _showPage(Uri url, bool force) async {
    final dismissedAt = _dismissed[url.host];
    if (!force &&
        dismissedAt != null &&
        DateTime.now().difference(dismissedAt) < _askAgainAfter) {
      return const _Asked(false, CloudflareFailure.cooldown);
    }
    final recent = _clearedAt[url.host];
    if (recent != null && DateTime.now().difference(recent) < _lateWindow) {
      return const _Asked(true);
    }

    final network = DartotsuExtensionBridge.context.network;
    if (network == null) {
      return const _Asked(false, CloudflareFailure.unavailable);
    }

    final cleared = Completer<bool>();
    final shown = await network.presentChallenge(
      CloudflareChallengePage(
        url: url,
        onFinished: (ok) {
          if (!cleared.isCompleted) cleared.complete(ok);
        },
      ),
    );
    if (!shown) return const _Asked(false, CloudflareFailure.unavailable);
    final ok = cleared.isCompleted && await cleared.future;
    if (ok) {
      _clearedAt[url.host] = DateTime.now();
      _dismissed.remove(url.host);
      return const _Asked(true);
    }
    _dismissed[url.host] = DateTime.now();
    return const _Asked(false, CloudflareFailure.dismissed);
  }

  /// Whether the page in [controller] is a Cloudflare challenge.
  static Future<bool> isChallengePage(WebViewController controller) async {
    final state = await _probe(controller);
    return state == _Page.challenge || state == _Page.widget;
  }

  static Future<_Page> _probe(WebViewController controller) async {
    try {
      final result = await controller.runJavaScriptReturningResult(
        _challengeProbe,
      );
      return switch (result.toString().replaceAll('"', '')) {
        '0' => _Page.open,
        '2' => _Page.blocked,
        '3' => _Page.widget,
        _ => _Page.challenge,
      };
    } catch (_) {
      return _Page.challenge;
    }
  }

  static const _challengeProbe = '''
(function () {
  var t = (document.title || '').toLowerCase();
  var body = ((document.body && document.body.innerText) || '').toLowerCase();
  if (t.indexOf('access denied') >= 0 || body.indexOf('you have been blocked') >= 0 ||
      body.indexOf('error code: 1020') >= 0 || body.indexOf('error 1015') >= 0 ||
      body.indexOf('error 1010') >= 0 || body.indexOf('error 1006') >= 0) return '2';
  if (document.querySelector('iframe[src*="challenges.cloudflare.com"]') &&
      (t.indexOf('just a moment') >= 0 || document.querySelector('#challenge-stage, #challenge-form, .cf-turnstile'))) return '3';
  if (t.indexOf('just a moment') >= 0 || t.indexOf('attention required') >= 0) return '1';
  return document.querySelector('#challenge-form, #challenge-stage, #cf-challenge-running, .cf-turnstile, #turnstile-wrapper, script[src*="challenge-platform"]') ? '1' : '0';
})()
''';
}

enum _Outcome { cleared, noChallenge, unsolved }

class _Background {
  final _Outcome outcome;
  final CloudflareFailure? failure;

  const _Background(this.outcome, [this.failure]);

  String get name =>
      failure == null ? outcome.name : '${outcome.name} (${failure!.name})';
}

class _Asked {
  final bool cleared;
  final CloudflareFailure? failure;

  const _Asked(this.cleared, [this.failure]);
}

enum _Page { open, challenge, widget, blocked }

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
  bool _loaded = false;
  bool _checking = false;
  int _calm = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setUserAgent(bridgeUserAgent());
    await _controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => _loaded = true),
    );
    await WebViewCookieSync.toWebView(widget.url);
    _before = await WebViewCookieSync.clearance(widget.url);
    await _controller.loadRequest(widget.url);
    _poll = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_check()),
    );
  }

  Future<void> _check() async {
    if (_finished || _checking || !_loaded) return;
    _checking = true;
    try {
      if (await CloudflareSolver.isChallengePage(_controller)) {
        _calm = 0;
        return;
      }
      final current = await WebViewCookieSync.clearance(widget.url);
      final fresh = current != null && current != _before;
      if (!fresh && ++_calm < 3) return;
      await WebViewCookieSync.fromWebView(widget.url);
      _finish(true);
    } finally {
      _checking = false;
    }
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
