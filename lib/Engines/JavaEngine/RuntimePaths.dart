import 'dart:io';

import 'package:path/path.dart' as p;

import '../../Logger.dart';
import '../../dartotsu_extension_bridge.dart';

bool _isAscii(String value) => value.codeUnits.every((c) => c < 128);

/// The folder for [subPath] under the app's system directory. The Java
/// launcher on Windows cannot open a runtime or jar whose path has characters
/// outside ASCII (a localized Documents folder such as `เอกสาร` ends in "could
/// not find java.dll"), so there the runtime files move to a plain-ASCII
/// folder instead.
Future<Directory> runtimeDirectory(String subPath) async {
  final dir = await DartotsuExtensionBridge.context.getDirectory(
    subPath: subPath,
    useSystemPath: true,
    useCustomPath: false,
  );
  if (dir == null) throw Exception('Unable to get runtime directory');

  if (Platform.isWindows && !_isAscii(dir.path)) {
    final env = Platform.environment;
    for (final root in [
      env['LOCALAPPDATA'],
      env['PROGRAMDATA'],
      r'C:\Users\Public',
    ]) {
      if (root == null || root.isEmpty || !_isAscii(root)) continue;
      final safe = Directory(
        p.joinAll([root, 'Dartotsu', ...subPath.split('/')]),
      );
      try {
        await safe.create(recursive: true);
        Logger.log(
          '${dir.path} has characters Java cannot open, using ${safe.path}',
        );
        return safe;
      } catch (_) {}
    }
  }

  await dir.create(recursive: true);
  return dir;
}
