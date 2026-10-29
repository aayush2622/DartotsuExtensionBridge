import '../../Extensions/BridgeSourceMethods.dart';
import '../../dartotsu_extension_bridge.dart';

class ShosetsuSourceMethods<T extends Source> extends BridgeSourceMethods<T> {
  ShosetsuSourceMethods(super.source, super.bridge);

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async => const [];

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async => const [];
}
