import 'dart:async';

import '../../Extensions/BridgeSourceMethods.dart';
import '../../dartotsu_extension_bridge.dart';

class IReaderSourceMethods<T extends Source> extends BridgeSourceMethods<T> {
  IReaderSourceMethods(super.source, super.bridge);

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) {
    throw UnimplementedError();
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) {
    throw UnimplementedError();
  }

  @override
  Future<List<SourcePreference>> getPreference() async => const [];

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async =>
      false;
}
