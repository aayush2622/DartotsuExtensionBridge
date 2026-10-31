@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:dartotsu_extension_bridge/Engines/JavaEngine/Bridge/SidecarBridge.dart';
import 'package:dartotsu_extension_bridge/ExtensionBridge.dart';
import 'package:dartotsu_extension_bridge/Settings/KvStore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

void main() {
  final home = Platform.environment['HOME'] ?? '';
  final builds = '${Directory.current.path}/runtimeManager/builds';
  final core = File('$builds/desktopCore/desktopCore-plugin.jar');
  final plugin = File('$builds/aniyomiDesktop/aniyomiDesktop-split.jar');
  final jre = Directory('$home/Documents/Dartotsu/bridge/jre-21');

  final missing = [
    if (!core.existsSync()) core.path,
    if (!plugin.existsSync()) plugin.path,
    if (!jre.existsSync()) jre.path,
  ];

  late Directory work;
  late Isar isar;

  setUpAll(() async {
    if (missing.isNotEmpty) return;
    await Isar.initializeIsarCore(download: true);
    work = await Directory.systemTemp.createTemp('sidecar_split');
    isar = await Isar.open([
      KvEntrySchema,
    ], directory: (await Directory('${work.path}/isar').create()).path);
    DartotsuExtensionBridge.context = BridgeContext(
      isar: isar,
      getDirectory:
          ({subPath, useCustomPath = false, useSystemPath = false}) async =>
              Directory('$home/Documents/Dartotsu/${subPath ?? ''}'),
    );
  });

  tearDownAll(() async {
    if (missing.isNotEmpty) return;
    await isar.close();
    await work.delete(recursive: true);
  });

  test('boots on the core jar plus the thin plugin and answers', () async {
    final bridge = SidecarBridge();
    addTearDown(bridge.dispose);

    await bridge.init(pluginJarPath: plugin.path, libraryJarPaths: [core.path]);
    await bridge.call<void>('initializeDesktop', {'path': work.path}, true);

    final extensions = await Directory(
      '${work.path}/extensions/Manga',
    ).create(recursive: true);
    final sources = await bridge.call<List<Map<String, dynamic>>>(
      'getInstalledMangaExtensions',
      {'path': extensions.path},
      true,
    );

    expect(sources, isEmpty);
  }, skip: missing.isEmpty ? false : 'needs ${missing.join(', ')}');

  test('the thin plugin does not start without the core', () async {
    final bridge = SidecarBridge();
    addTearDown(bridge.dispose);

    await bridge.init(pluginJarPath: plugin.path);

    await expectLater(
      bridge.call<void>('initializeDesktop', {'path': work.path}, true),
      throwsA(anything),
    );
  }, skip: missing.isEmpty ? false : 'needs ${missing.join(', ')}');
}
