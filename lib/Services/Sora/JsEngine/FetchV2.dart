import 'dart:convert';

import 'package:fjs/fjs.dart';
import 'package:http/http.dart' as http;

import '../../Mangayomi/http/m_client.dart';

class FetchV2 {
  final JsEngine engine;
  FetchV2(this.engine);

  final http.Client _client = MClient.init();

  static const _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Connection': 'keep-alive',
  };

  Future<void> inject() async {
    await engine.eval(
      source: const JsCode.code(r'''
async function fetchv2(url, headers = {}, method = "GET", body = null) {
  const res = await fjs.bridge_call({
    type: "fetchv2",
    url,
    headers,
    method,
    body
  });

  return {
    status: res.status,
    headers: res.headers,
    ok: res.status >= 200 && res.status < 300,
    json: () => Promise.resolve(JSON.parse(res.body)),
    text: () => Promise.resolve(res.body)
  };
}

// alias
const fetch = fetchv2;
'''),
    );
  }

  Future<JsResult> handle(Map data) async {
    final url = data['url'] as String;
    final method = (data['method'] as String? ?? 'GET').toUpperCase();
    final body = data['body'];

    final headers = Map<String, String>.from(_defaultHeaders);

    final Map? extHeaders = data['headers'];
    if (extHeaders != null) {
      extHeaders.forEach((k, v) {
        headers[k.toString()] = v.toString();
      });
    }

    try {
      final uri = Uri.parse(url);

      http.Response response;

      if (method == 'GET') {
        response = await _client.get(uri, headers: headers);
      } else if (method == 'HEAD') {
        response = await _client.head(uri, headers: headers);
      } else {
        final req = http.Request(method, uri)..headers.addAll(headers);

        if (body != null) {
          req.body = body is String ? body : jsonEncode(body);
        }

        final streamed = await _client.send(req);
        response = await http.Response.fromStream(streamed);
      }

      final headerMap = <String, JsValue>{};
      response.headers.forEach((k, v) {
        headerMap[k] = JsValue.string(v);
      });

      return JsResult.ok(
        JsValue.object({
          'status': JsValue.integer(response.statusCode),
          'headers': JsValue.object(headerMap),
          'body': JsValue.string(response.body),
        }),
      );
    } catch (e) {
      return JsResult.err(
        JsError.cancelled('fetchv2 failed: $e'),
      );
    }
  }
}
