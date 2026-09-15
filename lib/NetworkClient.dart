import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:http_interceptor/http_interceptor.dart';

import 'ExtensionBridge.dart';

class MClient {
  static IOClient? _fallbackClient;

  static IOClient _sharedFallbackClient() {
    final existing = _fallbackClient;
    if (existing != null) return existing;

    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..findProxy = _findProxy
      ..connectionFactory = _dnsAwareConnect;
    return _fallbackClient = IOClient(httpClient);
  }

  static String _findProxy(Uri uri) {
    final proxy = DartotsuExtensionBridge.context.network?.proxy;
    return (proxy == null || proxy.isEmpty) ? 'DIRECT' : 'PROXY $proxy; DIRECT';
  }

  static Future<ConnectionTask<Socket>> _dnsAwareConnect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final host = proxyHost ?? uri.host;
    final port = proxyPort ?? uri.port;

    // A proxy resolves the target host itself - only override DNS for the
    // direct-connection case.
    if (proxyHost == null) {
      final dohUrl = DartotsuExtensionBridge.context.network?.dns;
      if (dohUrl != null && dohUrl.isNotEmpty) {
        final resolved = await _resolveViaDoh(dohUrl, host);
        if (resolved != null) {
          return Socket.startConnect(resolved, port);
        }
      }
    }

    return Socket.startConnect(host, port);
  }

  static InterceptedClient init({Map<String, dynamic>? reqcopyWith}) {
    var appHttpClient = DartotsuExtensionBridge.context.http;
    var client =
        reqcopyWith?["useDartHttpClient"] == true || appHttpClient == null
        ? _sharedFallbackClient()
        : appHttpClient;
    return InterceptedClient.build(
      client: client,
      interceptors: const [_NetworkContextInterceptor()],
    );
  }
}

/// The default `User-Agent` MClient sends when neither the caller nor
/// [BridgeNetwork.userAgent] supplies one. Exposed so backends that need the
/// same UA outside of an MClient request (e.g. headers handed to a native
/// video player) can stay in sync with it instead of hardcoding their own copy.
const defaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Bridges every [MClient] request through [BridgeContext.network]: fills in
/// a default `User-Agent` and `Cookie` header when the caller hasn't already
/// set their own (some extractors manage a source-specific session cookie or
/// need a specific UA to pass anti-bot checks, and must not be overridden),
/// and feeds observed `Set-Cookie` responses back into the host app's shared
/// cookie jar so every backend reads/writes the same cookie store.
class _NetworkContextInterceptor implements HttpInterceptor {
  const _NetworkContextInterceptor();

  @override
  bool shouldInterceptRequest({required BaseRequest request}) => true;

  @override
  bool shouldInterceptResponse({required BaseResponse response}) => true;

  @override
  Future<BaseRequest> interceptRequest({required BaseRequest request}) async {
    final network = DartotsuExtensionBridge.context.network;
    final headerNames = request.headers.keys.map((k) => k.toLowerCase());

    if (!headerNames.contains('user-agent')) {
      final ua = network?.userAgent;
      request.headers['User-Agent'] = (ua != null && ua.isNotEmpty)
          ? ua
          : defaultUserAgent;
    }

    if (network != null && !headerNames.contains('cookie')) {
      final raw = await network.getCookies(request.url.toString());
      final header = cookieHeaderFromStoredCookies(raw);
      if (header != null && header.isNotEmpty) {
        request.headers['Cookie'] = header;
      }
    }

    return request;
  }

  @override
  Future<BaseResponse> interceptResponse({
    required BaseResponse response,
  }) async {
    final network = DartotsuExtensionBridge.context.network;
    final setCookie = response.headers['set-cookie'];
    final url = response.request?.url;

    if (network != null && url != null && setCookie != null) {
      final cookies = splitSetCookieHeader(setCookie);
      if (cookies.isNotEmpty) {
        unawaited(network.setCookies(url.toString(), cookies));
      }
    }

    return response;
  }
}

/// Parses [BridgeNetwork.getCookies]'s JSON-encoded `[{name, value, ...}]`
/// array (the same shape the native `CookieInterceptor` in `runtimeManager`
/// decodes) into a `name=value; name2=value2` `Cookie` header value.
String? cookieHeaderFromStoredCookies(String? json) {
  if (json == null || json.isEmpty) return null;

  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return null;

    final pairs = <String>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final name = entry['name'];
      final value = entry['value'];
      if (name is String && value is String) {
        pairs.add('$name=$value');
      }
    }
    return pairs.isEmpty ? null : pairs.join('; ');
  } catch (_) {
    return null;
  }
}

/// Splits a raw `set-cookie` response header back into individual cookie
/// strings.
///
/// `package:http`'s `IOClient` joins multiple `Set-Cookie` response headers
/// with a plain `,` (see its `io_client.dart`), which is ambiguous with the
/// comma inside a cookie's own `Expires=Wed, 09 Jun 2021 10:18:14 GMT`
/// attribute. This only splits on a `,` followed by what looks like the start
/// of a new cookie (`token=`), which keeps date commas intact in the common
/// case - not a fully RFC-6265-correct parse, but good enough for a header
/// that was already lossily flattened before it reached here.
List<String> splitSetCookieHeader(String header) {
  final boundary = RegExp(r',(?=\s*[!#$%&\x27*+\-.^_`|~0-9A-Za-z]+=)');
  final matches = boundary.allMatches(header).toList();
  if (matches.isEmpty) return [header.trim()];

  final parts = <String>[];
  var start = 0;
  for (final m in matches) {
    parts.add(header.substring(start, m.start).trim());
    start = m.end;
  }
  parts.add(header.substring(start).trim());
  return parts;
}

/// Resolves [host] via DNS-over-HTTPS JSON API (the format Cloudflare/Google
/// public resolvers both support), caching successful lookups briefly so a
/// burst of requests to the same host doesn't re-resolve on every connection.
final _dohCache = <String, (InternetAddress address, DateTime expires)>{};
HttpClient? _dohClient;

Future<InternetAddress?> _resolveViaDoh(String dohUrl, String host) async {
  final cached = _dohCache[host];
  if (cached != null && cached.$2.isAfter(DateTime.now())) {
    return cached.$1;
  }

  try {
    final client = _dohClient ??= HttpClient();
    final uri = Uri.parse(
      dohUrl,
    ).replace(queryParameters: {'name': host, 'type': 'A'});

    final request = await client.getUrl(uri);
    request.headers.set('accept', 'application/dns-json');

    final response = await request.close().timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return null;

    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;

    final answers = decoded['Answer'];
    if (answers is! List) return null;

    for (final answer in answers) {
      final data = answer is Map ? answer['data'] as String? : null;
      final address = data == null ? null : InternetAddress.tryParse(data);
      if (address != null) {
        _dohCache[host] = (
          address,
          DateTime.now().add(const Duration(seconds: 60)),
        );
        return address;
      }
    }
    return null;
  } catch (_) {
    // Any failure (network, malformed response, bad DoH URL) falls back to
    // the platform's normal DNS resolution - a broken custom resolver must
    // not take down every request.
    return null;
  }
}
