import 'package:fjs/fjs.dart';

typedef JsMethod = Future<JsResult> Function(Map data);

class BridgeReg {
  static final Map<String, JsMethod> methods = {};

  static void register(String name, JsMethod method) {
    methods[name] = method;
  }

  static Future<JsResult> call(String name, Map data) async {
    final method = methods[name];

    if (method != null) {
      return await method(data);
    }

    return const JsResult.err(
      JsError.cancelled("Unknown bridge call"),
    );
  }
}
