import 'dart:io';

import 'TorrServerController.dart';
import 'TorrServerControllerIos.dart';
import 'TorrServerControllerSubprocess.dart';

export 'Exceptions.dart';
export 'Models/TorrentInfo.dart';
export 'Models/TorrServerSettings.dart';
export 'PortFinder.dart';
export 'RestClient.dart';
export 'TorrServerAddon.dart';
export 'TorrServerController.dart';
export 'TorrServerControllerIos.dart';
export 'TorrServerControllerSubprocess.dart';

/// Creates the [TorrServerController] appropriate for the current platform:
/// [TorrServerControllerIos] (in-process, statically-linked engine) on iOS,
/// [TorrServerControllerSubprocess] (spawned binary) everywhere else.
TorrServerController createTorrServerController() {
  return Platform.isIOS
      ? TorrServerControllerIos()
      : TorrServerControllerSubprocess();
}
