import '../../Extensions/BridgeSourceMethods.dart';
import '../../dartotsu_extension_bridge.dart';

class AniyomiSourceMethods<T extends Source> extends BridgeSourceMethods<T> {
  AniyomiSourceMethods(super.source, super.bridge);

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) {
    throw UnimplementedError();
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) {
    throw UnimplementedError();
  }
}
