import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dartotsu_extension_bridge/Engines/JavaEngine/JvmAddon.dart';
import 'package:dartotsu_extension_bridge/ExtensionBridge.dart';
import 'package:dartotsu_extension_bridge/Extensions/DownloadablePlugin.dart';
import 'package:dartotsu_extension_bridge/Extensions/InstallStep.dart';
import 'package:dartotsu_extension_bridge/Services/Shared/DesktopCorePlugin.dart';
import 'package:dartotsu_extension_bridge/Settings/KvStore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

class _Desk extends DesktopPlugin {
  @override
  String get name => 'backendDesk';

  @override
  String get fileName => 'backendDesk-plugin.jar';
}

List<int> _zip(String content) => ZipEncoder().encode(
  Archive()..addFile(ArchiveFile.bytes('payload.txt', utf8.encode(content))),
);

void main() {
  late Directory work;
  late Isar isar;
  late JvmAddon addon;
  late HttpServer server;
  final served = <String, List<int>>{};
  final hits = <String>[];
  var index = <Map<String, dynamic>>[];

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Map<String, dynamic> entry(
    String name,
    int version,
    String file, {
    Map<String, int>? requires,
  }) => {
    'name': name,
    'versionCode': version,
    'platform': 'desktopSplit',
    'fileName': '$name-plugin.jar',
    'downloadUrl': url(file),
    ?(requires == null ? null : 'requires'): requires,
  };

  File installed(String name) =>
      File('${work.path}/bridge/plugins/$name-plugin.jar');

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
    work = await Directory.systemTemp.createTemp('jvm_addon');
    isar = await Isar.open([
      KvEntrySchema,
    ], directory: (await Directory('${work.path}/isar').create()).path);
    DartotsuExtensionBridge.context = BridgeContext(
      isar: isar,
      getDirectory:
          ({subPath, useCustomPath = false, useSystemPath = false}) async =>
              Directory('${work.path}/${subPath ?? ''}'),
    );

    final java = Platform.isWindows ? 'java.exe' : 'java';
    final bin = await Directory(
      '${work.path}/bridge/jre-21/jdk/bin',
    ).create(recursive: true);
    await File('${bin.path}/$java').writeAsString('#!/bin/sh');

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      hits.add(request.uri.path);
      if (request.uri.path.startsWith('/plugins')) {
        request.response.write(jsonEncode(index));
      } else if (served.containsKey(request.uri.path)) {
        request.response.add(served[request.uri.path]!);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    served['/core-1.jar'] = _zip('core 1');
    served['/core-2.jar'] = _zip('core 2');
    served['/desk-1.jar'] = _zip('desk 1');
    index = [
      entry('desktopCore', 1, '/core-1.jar'),
      entry('backendDesk', 1, '/desk-1.jar', requires: {'desktopCore': 1}),
    ];

    DownloadablePlugin.setIndexUrl(url('/plugins.json'));
    addon = JvmAddon.instance;
  });

  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await server.close(force: true);
    await isar.close();
    await work.delete(recursive: true);
  });

  test('it is an addon with the runtime and the core as steps', () {
    expect(addon.id, 'jvm');
    expect(addon.steps.map((s) => s.id), ['jre', 'core']);
    expect(addon.key, 'desktopCore');
  });

  test(
    'a backend\'s install lists the runtime, the core, then itself',
    () async {
      final desk = _Desk();
      final planned = await desk.plan();

      expect(planned.map((s) => s.id), ['jre', 'core', 'plugin']);
      expect(
        planned[0].state.value,
        StepStatus.upToDate,
        reason: 'a Java is already there',
      );
      expect(planned[1].state.value, StepStatus.waiting);
      expect(planned[2].state.value, StepStatus.waiting);
      expect(await addon.isInstalled(), isFalse);
    },
  );

  test(
    'installing the backend installs the core first, then the backend',
    () async {
      final desk = _Desk();
      await desk.plan();
      final events = <String>[];
      for (final step in desk.steps) {
        step.state.listen((v) => events.add('${step.id} ${v.name}'));
      }

      expect(await desk.download(), isTrue);

      expect(events.where((e) => e.startsWith('core')), [
        'core downloading',
        'core installing',
        'core done',
      ]);
      expect(
        events.indexOf('core done') < events.indexOf('plugin downloading'),
        isTrue,
      );
      expect(installed('desktopCore').existsSync(), isTrue);
      expect(installed('backendDesk').existsSync(), isTrue);
      expect(await addon.isInstalled(), isTrue);
      expect(addon.installed.value, isTrue);
      expect(await addon.classpath(), [installed('desktopCore').path]);
    },
  );

  test('the next install takes a newer core before the backend', () async {
    index = [
      entry('desktopCore', 2, '/core-2.jar'),
      entry('backendDesk', 2, '/desk-1.jar', requires: {'desktopCore': 2}),
    ];
    DownloadablePlugin.setIndexUrl(url('/plugins-2.json'));
    final desk = _Desk();
    hits.clear();

    expect(await addon.checkForUpdate(), isTrue);
    final planned = await desk.plan();
    expect(planned[1].replaces.value, isTrue);

    await desk.update();

    expect(hits.where((h) => h.endsWith('.jar')).toList(), [
      '/core-2.jar',
      '/desk-1.jar',
    ]);
    expect(getVal<int>('desktopCore_version'), 2);
    expect(await installed('desktopCore').readAsBytes(), served['/core-2.jar']);
    expect(addon.hasUpdate.value, isFalse);
  });

  test(
    'removing it stops the backends first and deletes the core and Java',
    () async {
      var released = 0;
      DesktopCorePlugin.instance.attach(
        Object(),
        release: () async => released++,
        reload: () async {},
      );

      await addon.uninstall();

      expect(released, 1);
      expect(installed('desktopCore').existsSync(), isFalse);
      expect(await addon.isInstalled(), isFalse);
      expect(
        addon.steps.first.state.value,
        StepStatus.waiting,
        reason: 'the bundled Java went with it',
      );
      expect(addon.installed.value, isFalse);
    },
  );
}
