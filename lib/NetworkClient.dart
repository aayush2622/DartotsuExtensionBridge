import 'dart:io';

import 'package:http/io_client.dart';
import 'package:http_interceptor/http_interceptor.dart';

import 'ExtensionBridge.dart';

class MClient {
  static IOClient? _fallbackClient;

  static IOClient _sharedFallbackClient() => _fallbackClient ??= IOClient(
    HttpClient()..connectionTimeout = const Duration(seconds: 15),
  );

  static InterceptedClient init({Map<String, dynamic>? reqcopyWith}) {
    var appHttpClient = DartotsuExtensionBridge.context.http;
    var client =
        reqcopyWith?["useDartHttpClient"] == true || appHttpClient == null
        ? _sharedFallbackClient()
        : appHttpClient;
    return InterceptedClient.build(client: client, interceptors: []);
  }
}
