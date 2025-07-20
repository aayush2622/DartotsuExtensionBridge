import 'package:dartotsu_extension_bridge/Aniyomi/AniyomiSourceMethods.dart';

import 'Aniyomi/AniyomiExtensions.dart';

class DartotsuExtensionBridge {
  Future<void> fetchAnimeTitles() async {
    var extensions = await AniyomiExtensions().init();
    var ext = extensions.installedAnimeExtensions.value[0];
    var media = await AniyomiSourceMethods(ext).getLatestUpdates(1);
    print(media.list.first.title);
    var data = await AniyomiSourceMethods(ext).getDetail(media.list.first);
    print(data.url);
    var quality = await AniyomiSourceMethods(
      ext,
    ).getVideoList(data.episodes!.first);
    print(quality.first.toJson());
  }
}
