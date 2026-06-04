import '../../Engines/JavaEngine/JavaBridgeServer.dart';
import '../../Logger.dart';
import '../../dartotsu_extension_bridge.dart';

class AniyomiDesktopNetwork {
  static Future<void> init() async {
    var context = DartotsuExtensionBridge.context;
    await JavaBridgeServer((method, args) async {
      switch (method) {
        case "logger":
          Logger.log(args["message"]);
          return true;

        case "getCookies":
          return await context.network?.getCookies(args["url"] as String);

        case "setCookies":
          await context.network?.setCookies(
            args["url"] as String,
            (args["cookies"] as List).cast<String>(),
          );
          return true;
      }

      throw Exception("Unknown method: $method");
    }).start();
  }

  void test() {}
}
