import 'dart:io';

import 'package:http/io_client.dart';
import 'package:http_interceptor/http_interceptor.dart';

import 'ExtensionBridge.dart';

class MClient {
  static InterceptedClient init({Map<String, dynamic>? reqcopyWith}) {
    var appHttpClient = DartotsuExtensionBridge.context.http;
    var client =
        reqcopyWith?["useDartHttpClient"] == true || appHttpClient == null
        ? IOClient(
            // Bounds a server that never accepts the TCP connection (a dead
            // or firewalled host) - it does not bound a server that
            // connects then hangs mid-response, so callers making a
            // request they need an upper bound on should still add their
            // own .timeout(...).
            HttpClient()..connectionTimeout = const Duration(seconds: 15),
          )
        : appHttpClient;
    return InterceptedClient.build(client: client, interceptors: []);
  }
}
