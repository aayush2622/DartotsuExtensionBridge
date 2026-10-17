import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_interceptor/http_interceptor.dart';

import 'ExtensionBridge.dart';
import 'Network/CloudflareSolver.dart';
import 'Logger.dart';

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
    if (proxy == null || proxy.isEmpty) return 'DIRECT';

    if (proxy.contains('://')) {
      final parsed = Uri.tryParse(proxy);
      if (parsed != null) {
        final hostPort = '${parsed.host}:${parsed.port}';
        if (parsed.scheme == 'socks5' || parsed.scheme == 'socks') {
          return 'SOCKS5 $hostPort; DIRECT';
        }
        return 'PROXY $hostPort; DIRECT';
      }
    }
    return 'PROXY $proxy; DIRECT';
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

  static InterceptedClient download() {
    final context = DartotsuExtensionBridge.context;
    final client = context.downloadHttp ?? context.http;
    if (client == null) return init();
    return InterceptedClient.build(
      client: _SharedClient(client),
      interceptors: const [],
    );
  }

  static InterceptedClient init({Map<String, dynamic>? reqcopyWith}) {
    var appHttpClient = DartotsuExtensionBridge.context.http;
    var useFallback =
        reqcopyWith?["useDartHttpClient"] == true || appHttpClient == null;
    var client = useFallback ? _sharedFallbackClient() : appHttpClient;

    return InterceptedClient.build(
      client: _SharedClient(client),
      interceptors: useFallback
          ? const [_NetworkContextInterceptor()]
          : const [],
    );
  }
}

/// Every [MClient.init] caller gets its own wrapper over one shared client, so
/// a caller's `close()` must not dispose the client everyone else is using.
///
/// It also clears Cloudflare challenges: a challenge response to a plain
/// [Request] goes to [CloudflareSolver], and once the app's cookie jar has
/// clearance the request is sent again with those cookies and the app's
/// User-Agent (the pair Cloudflare checks). Streamed and multipart requests
/// can't be replayed and come back as they are.
class _SharedClient extends http.BaseClient {
  _SharedClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final replay = request is http.Request ? _copy(request) : null;
    final response = await _inner.send(request);
    if (replay == null || !_mayBeChallenge(response)) return response;

    final bytes = await response.stream.toBytes();
    final buffered = _rebuild(response, bytes);
    if (!_isChallenge(response, bytes)) return buffered;

    Logger.log('[Cloudflare] Challenge on ${request.url.host}, clearing it');
    if (!await CloudflareSolver.solve(request.url)) return buffered;

    await _withAppSession(replay, mergeCookies: true);
    return _inner.send(replay);
  }

  @override
  void close() {}

  static http.Request _copy(http.Request request) {
    return http.Request(request.method, request.url)
      ..bodyBytes = request.bodyBytes
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
  }

  static http.StreamedResponse _rebuild(
    http.StreamedResponse response,
    List<int> bytes,
  ) {
    return http.StreamedResponse(
      http.ByteStream.fromBytes(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  static bool _mayBeChallenge(http.BaseResponse response) {
    if (!const {403, 429, 503}.contains(response.statusCode)) return false;
    if (response.headers['cf-mitigated']?.toLowerCase() == 'challenge') {
      return true;
    }
    return (response.headers['server'] ?? '').toLowerCase().startsWith(
      'cloudflare',
    );
  }

  static bool _isChallenge(http.BaseResponse response, List<int> bytes) {
    if (response.headers['cf-mitigated']?.toLowerCase() == 'challenge') {
      return true;
    }
    final length = bytes.length < 65536 ? bytes.length : 65536;
    return _looksLikeAntiBotChallenge(
      utf8.decode(bytes.sublist(0, length), allowMalformed: true),
    );
  }
}

/// The app's User-Agent ([BridgeNetwork.userAgent]), the one its WebViews
/// and every backend send, or [defaultUserAgent] without one.
String bridgeUserAgent() {
  final ua = DartotsuExtensionBridge.context.network?.userAgent;
  return (ua != null && ua.isNotEmpty) ? ua : defaultUserAgent;
}

/// Adds the app's session to [request]: its cookies for the URL (with
/// [mergeCookies], next to the ones the request already carries, which win;
/// otherwise only when it carries none) and its User-Agent when the request
/// has none or carries a `cf_clearance` cookie, which Cloudflare only accepts
/// with the User-Agent that earned it.
Future<void> _withAppSession(
  http.BaseRequest request, {
  required bool mergeCookies,
}) async {
  final network = DartotsuExtensionBridge.context.network;
  final headers = request.headers;
  String? keyOf(String name) {
    for (final key in headers.keys) {
      if (key.toLowerCase() == name) return key;
    }
    return null;
  }

  final cookieKey = keyOf('cookie');
  var cookie = cookieKey == null ? '' : headers.remove(cookieKey)!;
  if (network != null && (mergeCookies || cookie.isEmpty)) {
    final present = {
      for (final part in cookie.split(';'))
        if (part.contains('=')) part.substring(0, part.indexOf('=')).trim(),
    };
    final jar = cookieHeaderFromStoredCookies(
      await network.getCookies(request.url.toString()),
      exclude: present,
    );
    if (jar != null && jar.isNotEmpty) {
      cookie = cookie.isEmpty ? jar : '$cookie; $jar';
    }
  }
  if (cookie.isNotEmpty) headers['Cookie'] = cookie;

  final uaKey = keyOf('user-agent');
  final hasClearance = cookie
      .split(';')
      .any((part) => part.trim().startsWith('cf_clearance='));
  if (uaKey == null || hasClearance) {
    if (uaKey != null) headers.remove(uaKey);
    headers['User-Agent'] = bridgeUserAgent();
  }
}

/// The default `User-Agent` MClient sends when neither the caller nor
/// [BridgeNetwork.userAgent] supplies one. Exposed so backends that need the
/// same UA outside of an MClient request (e.g. headers handed to a native
/// video player) can stay in sync with it instead of hardcoding their own copy.
const defaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Bridges every [MClient] request through [BridgeContext.network]: adds the
/// app's cookies next to the caller's own (which win) and the app's
/// User-Agent (see [_withAppSession]), and feeds observed `Set-Cookie`
/// responses back into the host app's shared cookie jar so every backend
/// reads/writes the same cookie store.
class _NetworkContextInterceptor implements HttpInterceptor {
  const _NetworkContextInterceptor();

  @override
  bool shouldInterceptRequest({required BaseRequest request}) => true;

  @override
  bool shouldInterceptResponse({required BaseResponse response}) => true;

  @override
  Future<BaseRequest> interceptRequest({required BaseRequest request}) async {
    await _withAppSession(request, mergeCookies: true);
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

    return _warnIfChallengePage(response);
  }
}

/// Anti-bot challenge pages (Cloudflare and similar) are often served with a
/// plain `200` status, so a source's HTML parsing silently finds nothing
/// instead of hitting an error path - surfacing as "0 results"/"no episodes"
/// with no visible failure. Flags that case in the log so it's diagnosable
/// without re-running the source under a debugger.
Future<BaseResponse> _warnIfChallengePage(BaseResponse response) async {
  if (response is! StreamedResponse) return response;

  final contentType = response.headers['content-type'] ?? '';
  if (!contentType.contains('text/html')) return response;

  final length = response.contentLength;
  if (length == null || length > 65536) return response;

  final bytes = await response.stream.toBytes();
  final text = utf8.decode(bytes, allowMalformed: true);
  if (_looksLikeAntiBotChallenge(text)) {
    Logger.log(
      '[possible anti-bot challenge] ${response.request?.url} -> '
      '${response.statusCode}, ${bytes.length}B: '
      '${text.substring(0, text.length < 300 ? text.length : 300)}',
    );
  }

  return StreamedResponse(
    ByteStream.fromBytes(bytes),
    response.statusCode,
    contentLength: bytes.length,
    request: response.request,
    headers: response.headers,
    isRedirect: response.isRedirect,
    persistentConnection: response.persistentConnection,
    reasonPhrase: response.reasonPhrase,
  );
}

bool _looksLikeAntiBotChallenge(String body) {
  final lower = body.toLowerCase();
  return lower.contains('cf-chl') ||
      lower.contains('__cf_chl') ||
      lower.contains('just a moment') ||
      lower.contains('challenge-platform') ||
      lower.contains('enable javascript and cookies to continue') ||
      lower.contains('checking your browser before accessing');
}

/// Parses [BridgeNetwork.getCookies]'s JSON-encoded `[{name, value, ...}]`
/// array (the same shape the native `CookieInterceptor` in `runtimeManager`
/// decodes) into a `name=value; name2=value2` `Cookie` header value.
String? cookieHeaderFromStoredCookies(
  String? json, {
  Set<String> exclude = const {},
}) {
  if (json == null || json.isEmpty) return null;

  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return null;

    final pairs = <String>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final name = entry['name'];
      final value = entry['value'];
      if (name is String && value is String && !exclude.contains(name)) {
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
