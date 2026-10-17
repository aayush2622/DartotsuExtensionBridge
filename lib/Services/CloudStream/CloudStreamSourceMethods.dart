import 'dart:async';

import '../../Extensions/BridgeSourceMethods.dart';
import '../../Extensions/ExtensionBridge.dart';
import '../../Logger.dart';
import '../../dartotsu_extension_bridge.dart';

class CloudStreamSourceMethods<T extends Source>
    extends BridgeSourceMethods<T> {
  CloudStreamSourceMethods(super.source, super.bridge);

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) {
    throw UnimplementedError();
  }

  @override
  Future<String?> getNovelContent(DEpisode episode) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> openNativeSettings() async {
    if (bridge is! MethodChannelBridge) return false;
    try {
      return await bridge.call<bool>('openSettings', {'sourceId': source.id});
    } catch (e) {
      Logger.log('Could not open settings for ${source.name}: $e');
      return false;
    }
  }
}
