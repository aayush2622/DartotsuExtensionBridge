import 'dart:convert';

import 'package:webview_all/webview_all.dart';

import '../ExtensionBridge.dart';

/// Moves cookies between the platform WebView's cookie store and the app's
/// cookie jar ([BridgeNetwork]), so a page opened in a WebView and every
/// backend's HTTP client see the same session.
class WebViewCookieSync {
  WebViewCookieSync._();

  static final _manager = WebViewCookieManager();

  /// WebView cookie stores don't expose expiry, so cookies read from them are
  /// kept this long (Cloudflare re-challenges once its own clearance lapses).
  static const _lifetime = Duration(days: 30);

  /// Copies the app's cookies for [url] into the WebView's store.
  static Future<void> toWebView(Uri url) async {
    final raw = await DartotsuExtensionBridge.context.network?.getCookies(
      url.toString(),
    );
    if (raw == null || raw.isEmpty) return;

    final decoded = jsonDecode(raw);
    if (decoded is! List) return;

    for (final entry in decoded) {
      if (entry is! Map) continue;
      final name = entry['name'];
      final value = entry['value'];
      if (name is! String || value is! String) continue;
      final domain = entry['domain'] as String? ?? url.host;
      final hostOnly = entry['hostOnly'] == true;
      try {
        await _manager.setCookie(
          WebViewCookie(
            name: name,
            value: value,
            domain: hostOnly ? domain : '.${domain.replaceFirst('.', '')}',
            path: entry['path'] as String? ?? '/',
          ),
        );
      } catch (_) {
        // One cookie the platform store refuses must not stop the rest.
      }
    }
  }

  /// Copies the WebView's cookies for [url] into the app's jar and returns
  /// them.
  static Future<List<WebViewCookie>> fromWebView(Uri url) async {
    final cookies = await cookiesFor(url);
    final headers = [for (final c in cookies) _toSetCookie(c, url)];
    if (headers.isNotEmpty) {
      await DartotsuExtensionBridge.context.network?.setCookies(
        url.toString(),
        headers,
      );
    }
    return cookies;
  }

  /// The WebView's cookies for [url], or none when the store can't be read.
  static Future<List<WebViewCookie>> cookiesFor(Uri url) async {
    try {
      return await _manager.getCookies(domain: url);
    } catch (_) {
      return const [];
    }
  }

  /// The WebView's `cf_clearance` value for [url], or null.
  static Future<String?> clearance(Uri url) async {
    for (final cookie in await cookiesFor(url)) {
      if (cookie.name == 'cf_clearance') return cookie.value;
    }
    return null;
  }

  static String _toSetCookie(WebViewCookie cookie, Uri url) {
    final out = StringBuffer('${cookie.name}=${cookie.value}')
      ..write('; Path=${cookie.path.isEmpty ? '/' : cookie.path}')
      ..write('; Max-Age=${_lifetime.inSeconds}');
    final domain = cookie.domain.trim();
    if (domain.isNotEmpty && (domain.startsWith('.') || domain != url.host)) {
      out.write('; Domain=$domain');
    }
    return out.toString();
  }
}
