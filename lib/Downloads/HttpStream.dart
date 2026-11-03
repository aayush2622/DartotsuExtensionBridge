import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';

import '../ExtensionBridge.dart';
import 'DownloadCancel.dart';

class FetchResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> body;

  const FetchResponse(this.statusCode, this.headers, this.body);

  Future<void> drop() async {
    try {
      await body.listen((_) {}).cancel();
    } catch (_) {}
  }
}

final _fallback = Client();

Client get _client {
  try {
    return DartotsuExtensionBridge.context.network?.downloadClient ?? _fallback;
  } catch (_) {
    return _fallback;
  }
}

/// Opens a streaming GET through the host's network stack.
Future<FetchResponse> openStream(
  String url, {
  Map<String, String>? headers,
  DownloadCancel? cancel,
}) async {
  final request = AbortableRequest(
    'GET',
    Uri.parse(url),
    abortTrigger: cancel?.trigger,
  )..headers.addAll(headers ?? const {});
  final res = await _client.send(request);
  return FetchResponse(res.statusCode, res.headers, res.stream);
}

/// Reads a whole text response. Throws [DownloadHttpError] from `status >= 400`.
Future<String> readText(
  String url, {
  Map<String, String>? headers,
  DownloadCancel? cancel,
}) async {
  final res = await openStream(url, headers: headers, cancel: cancel);
  if (res.statusCode >= 400) {
    await res.drop();
    throw HttpStatusError(res.statusCode);
  }
  final bytes = <int>[];
  await for (final chunk in res.body) {
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

class HttpStatusError implements Exception {
  final int status;
  final Duration? retryAfter;

  const HttpStatusError(this.status, {this.retryAfter});

  @override
  String toString() => 'HTTP $status';
}
