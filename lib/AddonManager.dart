import 'package:get/get.dart';

import '../Engines/TorrentEngine/LibTorrentAddon.dart';
import 'Extensions/Addon.dart';

class AddonManager extends GetxService {
  final List<Addon> addons = [LibtorrentAddon()];

  @override
  void onInit() {
    super.onInit();

    for (final addon in addons) {
      addon.isInstalled().then((value) {
        addon.installed.value = value;
      });
    }
  }

  T get<T extends Addon>() {
    return addons.firstWhere(
          (addon) => addon is T,
          orElse: () => throw StateError("Addon $T not registered."),
        )
        as T;
  }

  Addon? byId(String id) {
    for (final addon in addons) {
      if (addon.id == id) return addon;
    }
    return null;
  }

  Future<void> checkForUpdates() async {
    for (final addon in addons) {
      try {
        await addon.checkForUpdate();
      } catch (_) {}
    }
  }

  Future<void> autoUpdate() async {
    for (final addon in addons) {
      try {
        if (await addon.checkForUpdate()) {
          await addon.update();
        }
      } catch (_) {}
    }
  }
}
