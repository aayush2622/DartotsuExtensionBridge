import '../../Extensions/BridgeSourceMethods.dart';
import '../../dartotsu_extension_bridge.dart';

class KotatsuSourceMethods<T extends Source> extends BridgeSourceMethods<T> {
  KotatsuSourceMethods(super.source, super.bridge);

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async => const [];

  @override
  Future<String?> getNovelContent(DEpisode episode) async => null;
}
