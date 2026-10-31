import '../../Engines/JavaEngine/JvmAddon.dart';
import '../../Extensions/DownloadablePlugin.dart';
import '../../Extensions/InstallStep.dart';
import '../../Logger.dart';

abstract class DesktopPlugin extends DownloadablePlugin {
  @override
  List<PluginDependency> get dependencies => [JvmAddon.instance];
}

// the file is open in every sidecar, so they stop before it is replaced and restart on the new one
class DesktopCorePlugin extends DownloadablePlugin {
  DesktopCorePlugin._() {
    beforeSwap = _releaseAll;
    onUpdated = _reloadAll;
  }

  static final DesktopCorePlugin instance = DesktopCorePlugin._();

  @override
  String get name => "desktopCore";

  @override
  String get stepId => "core";

  @override
  String get fileName => "desktopCore-plugin.jar";

  final _users = <Object, _User>{};

  void attach(
    Object owner, {
    required Future<void> Function() release,
    required Future<void> Function() reload,
  }) => _users[owner] = _User(release, reload);

  void detach(Object owner) => _users.remove(owner);

  Future<void> _releaseAll() async {
    await Future.wait([for (final user in _users.values) user.release()]);
  }

  Future<void> _reloadAll() async {
    for (final user in _users.values.toList()) {
      try {
        await user.reload();
      } catch (e) {
        Logger.log("A backend could not restart on the new desktop core: $e");
      }
    }
  }
}

class _User {
  final Future<void> Function() release;
  final Future<void> Function() reload;

  _User(this.release, this.reload);
}
