import 'dart:convert';
import 'dart:io';

class JavaBridgeServer {
  final Future<dynamic> Function(String, Map<String, dynamic>) handler;

  HttpServer? _server;

  JavaBridgeServer(this.handler);

  Future<void> start({int port = 4567}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);

    _server!.listen((request) async {
      try {
        final body = await utf8.decoder.bind(request).join();

        final json = jsonDecode(body) as Map<String, dynamic>;

        final method = json["method"] as String;

        final args = (json["args"] as Map?)?.cast<String, dynamic>() ?? {};

        final result = await handler(method, args);

        request.response.headers.contentType = ContentType.json;

        request.response.write(jsonEncode({"success": true, "result": result}));
      } catch (e, st) {
        request.response.statusCode = 500;

        request.response.write(
          jsonEncode({
            "success": false,
            "error": e.toString(),
            "stack": st.toString(),
          }),
        );
      }

      await request.response.close();
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }
}
