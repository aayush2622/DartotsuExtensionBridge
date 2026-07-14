import 'dart:async';

import '../../Extensions/BridgeSourceMethods.dart';
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
  Future<List<SourcePreference>> getPreference() async => const [];

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async =>
      false;
}
