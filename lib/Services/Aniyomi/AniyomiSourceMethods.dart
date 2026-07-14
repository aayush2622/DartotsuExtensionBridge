import '../../Extensions/BridgeSourceMethods.dart';
import '../../dartotsu_extension_bridge.dart';

class AniyomiSourceMethods<T extends Source> extends BridgeSourceMethods<T> {
  AniyomiSourceMethods(super.source, super.bridge);

  @override
  Future<String?> getNovelContent(DEpisode episode) async {
    throw UnimplementedError();
  }
}
