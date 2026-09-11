import '../../Extensions/BridgeSourceMethods.dart';
import '../../dartotsu_extension_bridge.dart';

/// Kotatsu is manga-only — `KotatsuExtensionApi` (native) only implements
/// getPopular/getLatestUpdates/search/getDetail/getPageList; everything else
/// is inherited from [BridgeSourceMethods] as-is except the two that don't
/// apply to a manga reader.
class KotatsuSourceMethods<T extends Source> extends BridgeSourceMethods<T> {
  KotatsuSourceMethods(super.source, super.bridge);

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async => const [];

  @override
  Future<String?> getNovelContent(DEpisode episode) async => null;
}
