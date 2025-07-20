import 'package:dartotsu_extension_bridge/Extensions/Extensions.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';

class MangayomiExtensions extends Extension {
  @override
  Future<List<Source>> fetchAvailableAnimeExtensions(
    List<String>? repos,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Source>> getInstalledAnimeExtensions() {
    throw UnimplementedError();
  }

  @override
  Future<List<Source>> fetchAvailableMangaExtensions(List<String>? repos) {
    throw UnimplementedError();
  }

  @override
  Future<List<Source>> getInstalledMangaExtensions() {
    throw UnimplementedError();
  }
}
