import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../NetworkClient.dart';
import 'IsolateRpc.dart';

const httpRpcMethod = 'http';

/// Worker-side [http.Client] that has the host isolate perform the request, so
/// the host's own client, cookie jar, proxy and DNS settings all still apply.
class RpcHttpClient extends http.BaseClient {
  RpcHttpClient(this._rpc, this._reqcopyWith);

  final IsolateRpc _rpc;
  final Map<String, dynamic>? _reqcopyWith;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();

    final List reply;
    try {
      reply = await _rpc.call<List>(httpRpcMethod, [
        request.method,
        request.url.toString(),
        Map<String, String>.from(request.headers),
        body.isEmpty ? null : TransferableTypedData.fromList([body]),
        request.followRedirects,
        request.maxRedirects,
        request.persistentConnection,
        _reqcopyWith == null ? null : Map<String, dynamic>.from(_reqcopyWith),
      ]);
    } on RpcRemoteError catch (e) {
      if (e.type == 'TimeoutException') throw TimeoutException(e.message);
      throw http.ClientException(e.message, request.url);
    }

    final bytes = (reply[5] as TransferableTypedData)
        .materialize()
        .asUint8List();

    return http.StreamedResponse(
      http.ByteStream.fromBytes(bytes),
      reply[0] as int,
      contentLength: bytes.length,
      request: request,
      headers: Map<String, String>.from(reply[1] as Map),
      isRedirect: reply[2] as bool,
      persistentConnection: reply[3] as bool,
      reasonPhrase: reply[4] as String?,
    );
  }
}

/// Host-side counterpart of [RpcHttpClient]. Runs the request through
/// [MClient] and returns `[status, headers, isRedirect, persistent, reason,
/// body]`.
Future<List> serveHttpRpc(List args) async {
  final request = http.Request(args[0] as String, Uri.parse(args[1] as String))
    ..headers.addAll(Map<String, String>.from(args[2] as Map))
    ..followRedirects = args[4] as bool
    ..maxRedirects = args[5] as int
    ..persistentConnection = args[6] as bool;

  final transferable = args[3] as TransferableTypedData?;
  if (transferable != null) {
    request.bodyBytes = transferable.materialize().asUint8List();
  }

  final reqcopyWith = (args[7] as Map?)?.cast<String, dynamic>();
  final client = MClient.init(reqcopyWith: reqcopyWith);
  final response = await client.send(request);
  final bytes = await response.stream.toBytes();

  return [
    response.statusCode,
    Map<String, String>.from(response.headers),
    response.isRedirect,
    response.persistentConnection,
    response.reasonPhrase,
    TransferableTypedData.fromList([Uint8List.fromList(bytes)]),
  ];
}
