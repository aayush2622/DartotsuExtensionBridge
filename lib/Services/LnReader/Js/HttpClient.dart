import 'dart:convert';
import 'dart:io';

import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';

import '../../../Network/MClient.dart';

typedef LnFetcher = Future<String> Function(String method, List args);

Future<String> lnHttpFetch(Client client, String method, List args) =>
    _toHttpResponse(client, method, args);

class JsHttpClient {
  late JavascriptRuntime runtime;
  final LnFetcher? fetcher;
  JsHttpClient(this.runtime, {this.fetcher});

  // Reused for every request this instance makes, rather than calling
  // MClient.init() fresh per call - when the host app hasn't supplied its
  // own http.Client, MClient.init() falls back to a brand new
  // IOClient(HttpClient()) (its own socket pool) each time, and nothing
  // here was ever closing the previous one.
  InterceptedClient? _client;

  void init() {
    InterceptedClient client() => _client ??= MClient.init();
    Future<String> fetch(String method, dynamic args) {
      final send = fetcher;
      return send != null
          ? send(method, args as List)
          : _toHttpResponse(client(), method, args as List);
    }

    runtime.onMessage('http_head', (dynamic args) async {
      return await fetch("HEAD", args);
    });
    runtime.onMessage('http_get', (dynamic args) async {
      return await fetch("GET", args);
    });
    runtime.onMessage('http_post', (dynamic args) async {
      return await fetch("POST", args);
    });
    runtime.onMessage('http_put', (dynamic args) async {
      return await fetch("PUT", args);
    });
    runtime.onMessage('http_delete', (dynamic args) async {
      return await fetch("DELETE", args);
    });
    runtime.onMessage('http_patch', (dynamic args) async {
      return await fetch("PATCH", args);
    });
    runtime.evaluate('''
class Headers {
  constructor(obj) {
    this._map = {};
    if (obj) {
      for (const k in obj) {
        if (Object.prototype.hasOwnProperty.call(obj, k)) {
          this._map[k.toLowerCase()] = obj[k];
        }
      }
    }
  }
  get(name) {
    const v = this._map[String(name).toLowerCase()];
    return v === undefined ? null : v;
  }
  has(name) {
    return Object.prototype.hasOwnProperty.call(this._map, String(name).toLowerCase());
  }
  set(name, value) {
    this._map[String(name).toLowerCase()] = String(value);
  }
  append(name, value) {
    const key = String(name).toLowerCase();
    if (Object.prototype.hasOwnProperty.call(this._map, key)) {
      this._map[key] += ", " + value;
    } else {
      this._map[key] = String(value);
    }
  }
  delete(name) {
    delete this._map[String(name).toLowerCase()];
  }
  forEach(fn) {
    for (const k in this._map) fn(this._map[k], k, this);
  }
  entries() {
    const map = this._map;
    return Object.keys(map).map(function(k) { return [k, map[k]]; });
  }
  toJSON() {
    return this._map;
  }
}

class Response {
  constructor(url, result) {
    this.url = url;
    this.response = JSON.parse(result);
  }
  get status() {
    return this.response.statusCode;
  }
  get statusText() {
    return this.response.reasonPhrase;
  }
  get ok() {
    return this.status >= 200 && this.status <= 299;
  }
  get redirected() {
    return this.response.isRedirect;
  }
  get headers() {
    return new Headers(this.response.headers);
  }
  get body() {
    return this.response.body;
  }
  json() {
    const val = JSON.parse(this.body);
    return new Promise(function(resolve, reject) {
      resolve(val);
    });
  }
  text() {
    const val = this.body;
    return new Promise(function(resolve, reject) {
      resolve(val);
    });
  }
}

async function fetchApi(url, init) {
  const method = init?.method ? init.method.toLowerCase() : "get";
  const result = await sendMessage(
    "http_" + method,
    JSON.stringify([url, init?.headers, init?.body])
  );
  return new Response(url, result);
}

// Some plugins call the bare global `fetch` instead of @libs/fetch's
// `fetchApi` - same Fetch API shape, so alias it.
var fetch = fetchApi;

// @libs/fetch also exports fetchText: a `.text()` shortcut that never throws.
async function fetchText(url, init, _encoding) {
  try {
    const res = await fetchApi(url, init);
    return await res.text();
  } catch (e) {
    return "";
  }
}

// fetchProto (protobuf responses) is not supported by this runtime.
async function fetchProto() {
  throw new Error("fetchProto is not supported");
}
''');
  }
}

Future<String> _toHttpResponse(Client client, String method, List args) async {
  final url = args[0] as String;
  final headers = (args[1] as Map?)?.toMapStringString ?? {};
  final body = args.length >= 3
      ? args[2] is List
            ? args[2] as List
            : args[2] is String
            ? args[2] as String
            : (args[2] as Map?)?.toMapStringDynamic
      : null;
  var request = http.Request(method, Uri.parse(url));
  request.headers.addAll(headers);
  if ((request.headers[HttpHeaders.contentTypeHeader]?.contains(
        "application/json",
      )) ??
      false) {
    request.body = body is String ? body : json.encode(body);
    request.headers.addAll(headers);
    http.StreamedResponse response = await client.send(request);
    final res = Response(
      "",
      response.statusCode,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
    Map<String, dynamic> resMap = res.toJson();
    resMap["body"] = await response.stream.bytesToString();
    return jsonEncode(resMap);
  }
  String? formData;
  if (body is Map) {
    formData = body.entries
        .map(
          (e) =>
              "${Uri.encodeQueryComponent(e.key)}"
              "=${Uri.encodeQueryComponent(e.value?.toString() ?? '')}",
        )
        .join("&");
    headers["content-type"] =
        "application/x-www-form-urlencoded; charset=UTF-8";
  }
  final future = switch (method) {
    "HEAD" => client.head(Uri.parse(url), headers: headers),
    "GET" => client.get(Uri.parse(url), headers: headers),
    "POST" => client.post(
      Uri.parse(url),
      headers: headers,
      body: formData ?? body,
    ),
    "PUT" => client.put(
      Uri.parse(url),
      headers: headers,
      body: formData ?? body,
    ),
    "DELETE" => client.delete(
      Uri.parse(url),
      headers: headers,
      body: formData ?? body,
    ),
    _ => client.patch(Uri.parse(url), headers: headers, body: formData ?? body),
  };
  return jsonEncode((await future).toJson());
}

extension ResponseExtexsion on Response {
  Map<String, dynamic> toJson() => {
    'body': body,
    'headers': headers,
    'isRedirect': isRedirect,
    'persistentConnection': persistentConnection,
    'reasonPhrase': reasonPhrase,
    'statusCode': statusCode,
    'request': {
      'contentLength': request?.contentLength,
      'finalized': request?.finalized,
      'followRedirects': request?.followRedirects,
      'headers': request?.headers,
      'maxRedirects': request?.maxRedirects,
      'method': request?.method,
      'persistentConnection': request?.persistentConnection,
      'url': request?.url.toString(),
    },
  };
}

extension ToMapExtension on Map? {
  Map<String, dynamic>? get toMapStringDynamic {
    return this?.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, String>? get toMapStringString {
    return this?.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }
}
