import 'dart:io';

import 'package:http/io_client.dart';
import 'package:http_interceptor/http_interceptor.dart';

import '../../../ExtensionBridge.dart';

class MClient {
  MClient();

  static InterceptedClient init({
    Map<String, dynamic>? reqcopyWith,
  }) {
    var appHttpClient = DartotsuExtensionBridge.context.http;
    var client =
        reqcopyWith?["useDartHttpClient"] == true || appHttpClient == null
            ? IOClient(HttpClient())
            : appHttpClient;
    return InterceptedClient.build(client: client, interceptors: []);
  }
}
