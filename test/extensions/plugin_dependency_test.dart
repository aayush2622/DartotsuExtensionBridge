import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dartotsu_extension_bridge/ExtensionBridge.dart';
import 'package:dartotsu_extension_bridge/Extensions/DownloadablePlugin.dart';
import 'package:dartotsu_extension_bridge/Extensions/InstallStep.dart';
import 'package:dartotsu_extension_bridge/Settings/KvStore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

class _Core extends DownloadablePlugin {
  _Core([this.name = 'testCore']);

  @override
  final String name;

  @override
  String get stepId => 'core';

  @override
  String get fileName => '$name-plugin.jar';
}

class _Backend extends DownloadablePlugin {
  _Backend(this.core, this.name);

  final DownloadablePlugin core;

  @override
  final String name;

  @override
  String get fileName => '$name-plugin.jar';

  @override
  List<DownloadablePlugin> get dependencies => [core];
}

List<int> _zip(String content) {
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('payload.txt', utf8.encode(content)));
  return ZipEncoder().encode(archive);
}

void main() {
  late Directory work;
  late Isar isar;
  late HttpServer server;
  final served = <String, List<int>>{};
  final hits = <String>[];
  var index = <Map<String, dynamic>>[];
  var indexPath = '/plugins-0.json';
  var round = 0;

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Map<String, dynamic> entry(
    String name,
    int version,
    String file, {
    Map<String, int>? requires,
    int? size,
    String platform = 'desktopSplit',
  }) => {
    'name': name,
    'versionCode': version,
    'platform': platform,
    'fileName': '$name-plugin.jar',
    'downloadUrl': url(file),
    ?(requires == null ? null : 'requires'): requires,
    ?(size == null ? null : 'fileSize'): size,
  };

  void publish(List<Map<String, dynamic>> entries) {
    index = entries;
    indexPath = '/plugins-${++round}.json';
    DownloadablePlugin.setIndexUrl(url(indexPath));
  }

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
    work = await Directory.systemTemp.createTemp('plugin_dependency');
    isar = await Isar.open([
      KvEntrySchema,
    ], directory: (await Directory('${work.path}/isar').create()).path);
    DartotsuExtensionBridge.context = BridgeContext(
      isar: isar,
      getDirectory:
          ({subPath, useCustomPath = false, useSystemPath = false}) async =>
              Directory('${work.path}/${subPath ?? ''}'),
    );

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      hits.add(path);
      if (path == indexPath) {
        request.response.write(jsonEncode(index));
      } else if (served.containsKey(path)) {
        request.response.add(served[path]!);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await server.close(force: true);
    await isar.close();
    await work.delete(recursive: true);
  });

  setUp(hits.clear);

  File installed(String name) {
    return File('${work.path}/bridge/plugins/$name-plugin.jar');
  }

  test('a plugin installs what it needs first', () async {
    served['/core-3.jar'] = _zip('core 3');
    served['/a-5.jar'] = _zip('a 5');
    publish([
      entry('testCore', 3, '/core-3.jar'),
      entry('backendA', 5, '/a-5.jar', requires: {'testCore': 3}),
    ]);

    final core = _Core();
    final a = _Backend(core, 'backendA');

    expect(await a.download(), isTrue);

    expect(installed('testCore').existsSync(), isTrue);
    expect(installed('backendA').existsSync(), isTrue);
    expect(hits.where((h) => h.endsWith('.jar')).toList(), [
      '/core-3.jar',
      '/a-5.jar',
    ], reason: 'the core comes before the plugin that needs it');
    expect(getVal<int>('testCore_version'), 3);
    expect(getVal<int>('backendA_version'), 5);
    expect(a.error.value, isNull);
    expect(core.installed.value, isTrue);
  });

  test('a second plugin reuses the core it finds', () async {
    served['/b-2.jar'] = _zip('b 2');
    publish([
      entry('testCore', 3, '/core-3.jar'),
      entry('backendB', 2, '/b-2.jar', requires: {'testCore': 3}),
    ]);

    final b = _Backend(_Core(), 'backendB');

    expect(await b.download(), isTrue);
    expect(hits.where((h) => h == '/core-3.jar'), isEmpty);
    expect(hits.where((h) => h == '/b-2.jar'), hasLength(1));
  });

  test('the install is a list of steps, dependency first', () async {
    served['/steps-core-3.jar'] = _zip('core 3');
    served['/steps-1.jar'] = _zip('plugin 1');
    publish([
      entry('coreSteps', 3, '/steps-core-3.jar'),
      entry('backendSteps', 1, '/steps-1.jar', requires: {'coreSteps': 3}),
    ]);
    final core = _Core('coreSteps');
    final c = _Backend(core, 'backendSteps');

    final planned = await c.plan();

    expect(planned.map((s) => s.id), ['core', 'plugin']);
    expect(planned.map((s) => s.state.value), [
      StepStatus.waiting,
      StepStatus.waiting,
    ]);

    final events = <String>[];
    core.step.state.listen((v) => events.add('core ${v.name}'));
    c.step.state.listen((v) => events.add('plugin ${v.name}'));

    expect(await c.download(), isTrue);

    expect(events, [
      'core downloading',
      'core installing',
      'core done',
      'plugin downloading',
      'plugin installing',
      'plugin done',
    ]);
    expect(core.step.progress.value, 1.0);
    expect(core.step.receivedBytes.value, greaterThan(0));
  });

  test('a plan shows what is installed and what is not', () async {
    served['/plan-core-4.jar'] = _zip('core 4');
    publish([
      entry('corePlan', 4, '/plan-core-4.jar'),
      entry('backendPlan', 1, '/plan-1.jar', requires: {'corePlan': 4}),
    ]);
    await _Core('corePlan').ensure();

    final fresh = _Backend(_Core('corePlan'), 'backendPlan');
    final planned = await fresh.plan();

    expect(planned.first.state.value, StepStatus.upToDate);
    expect(planned.last.state.value, StepStatus.waiting);
    expect(
      planned.last.totalBytes.value,
      0,
      reason: 'no fileSize in this index',
    );
  });

  test('an install takes a newer core too, before the plugin', () async {
    served['/newer-core-4.jar'] = _zip('core 4');
    served['/newer-core-5.jar'] = _zip('core 5');
    served['/newer-1.jar'] = _zip('plugin 1');
    publish([entry('coreNewer', 4, '/newer-core-4.jar')]);
    await _Core('coreNewer').ensure();

    publish([
      entry('coreNewer', 5, '/newer-core-5.jar'),
      entry('backendNewer', 1, '/newer-1.jar', requires: {'coreNewer': 4}),
    ]);
    hits.clear();

    final core = _Core('coreNewer');
    var released = 0;
    core.beforeSwap = () async => released++;
    final e = _Backend(core, 'backendNewer');

    final planned = await e.plan();
    expect(
      planned.first.state.value,
      StepStatus.waiting,
      reason: 'installed core is 4, the index has 5',
    );
    expect(planned.first.replaces.value, isTrue);

    expect(await e.download(), isTrue);

    expect(getVal<int>('coreNewer_version'), 5);
    expect(hits.where((h) => h.endsWith('.jar')).toList(), [
      '/newer-core-5.jar',
      '/newer-1.jar',
    ]);
    expect(released, 1, reason: 'running sidecars are stopped before the swap');
    expect(core.step.state.value, StepStatus.done);
  });

  test(
    'a failing dependency stops the install and is the failed step',
    () async {
      served['/fail-1.jar'] = _zip('plugin 1');
      publish([
        entry('coreFail', 6, '/fail-core-missing.jar'),
        entry('backendFail', 1, '/fail-1.jar', requires: {'coreFail': 6}),
      ]);

      final core = _Core('coreFail');
      final f = _Backend(core, 'backendFail');

      expect(await f.download(), isFalse);

      expect(core.step.state.value, StepStatus.failed);
      expect(core.step.error.value, contains('404'));
      expect(f.step.state.value, StepStatus.waiting);
      expect(installed('backendFail').existsSync(), isFalse);
      expect(
        hits.where((h) => h == '/fail-core-missing.jar'),
        hasLength(1),
        reason: 'a missing file is not retried',
      );
    },
  );

  test(
    'an installed plugin updates when only its dependency is outdated',
    () async {
      served['/only-core-4.jar'] = _zip('core 4');
      served['/only-core-7.jar'] = _zip('core 7');
      served['/only-1.jar'] = _zip('plugin 1');
      publish([
        entry('coreOnly', 4, '/only-core-4.jar'),
        entry('backendOnly', 1, '/only-1.jar', requires: {'coreOnly': 4}),
      ]);
      expect(
        await _Backend(_Core('coreOnly'), 'backendOnly').download(),
        isTrue,
      );

      publish([
        entry('coreOnly', 7, '/only-core-7.jar'),
        entry('backendOnly', 1, '/only-1.jar', requires: {'coreOnly': 4}),
      ]);
      hits.clear();

      var reloaded = 0;
      final a = _Backend(_Core('coreOnly'), 'backendOnly')
        ..onUpdated = () async => reloaded++;

      expect(
        await a.checkForUpdate(),
        isFalse,
        reason: 'the plugin itself is current',
      );
      final planned = await a.plan();
      expect(
        a.updateAvailable.value,
        isTrue,
        reason: 'the core has a newer version',
      );
      expect(planned.last.state.value, StepStatus.upToDate);

      await a.update();

      expect(getVal<int>('coreOnly_version'), 7);
      expect(hits.where((h) => h == '/only-1.jar'), isEmpty);
      expect(reloaded, 0, reason: 'the plugin file did not change');
      expect(a.updateAvailable.value, isFalse);
    },
  );

  test('an update first brings the core to the version it asks for', () async {
    served['/core-4.jar'] = _zip('core 4');
    served['/a-6.jar'] = _zip('a 6');
    publish([
      entry('testCore', 4, '/core-4.jar'),
      entry('backendA', 6, '/a-6.jar', requires: {'testCore': 4}),
    ]);

    final core = _Core();
    var released = 0;
    var reloaded = 0;
    core.beforeSwap = () async => released++;
    core.onUpdated = () async => reloaded++;
    final a = _Backend(core, 'backendA');

    await a.update();

    expect(hits.where((h) => h.endsWith('.jar')).toList(), [
      '/core-4.jar',
      '/a-6.jar',
    ]);
    expect(getVal<int>('testCore_version'), 4);
    expect(getVal<int>('backendA_version'), 6);
    expect(released, 1, reason: 'running sidecars are stopped before the swap');
    expect(reloaded, 1, reason: 'and started again on the new core');
    expect(await installed('testCore').readAsBytes(), served['/core-4.jar']);
  });

  group('an app that has the old self-contained jar installed', () {
    Future<void> installFat(String name, int version) async {
      final file = installed(name);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(_zip('a big self-contained jar ' * 400));
      setVal('${name}_version', version);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    test(
      'moves to the split jar and the core when the index has a newer one',
      () async {
        served['/leg-core-1.jar'] = _zip('core');
        served['/leg-thin-1.jar'] = _zip('thin');
        await installFat('backendLegacy', 31);
        publish([
          entry('coreLegacy', 1, '/leg-core-1.jar'),
          entry(
            'backendLegacy',
            32,
            '/leg-thin-1.jar',
            requires: {'coreLegacy': 1},
          ),
        ]);

        final core = _Core('coreLegacy');
        final plugin = _Backend(core, 'backendLegacy');
        expect(await plugin.checkForUpdate(), isTrue);
        await plugin.update();

        expect(
          await installed('backendLegacy').readAsBytes(),
          served['/leg-thin-1.jar'],
        );
        expect(installed('coreLegacy').existsSync(), isTrue);
        expect(getVal<int>('backendLegacy_version'), 32);
      },
    );

    test(
      'moves over even when its stored version is higher than the new one',
      () async {
        served['/leg2-core-1.jar'] = _zip('core');
        final thin = _zip('thin');
        served['/leg2-thin-1.jar'] = thin;
        await installFat('backendHigh', 90);
        publish([
          entry('coreHigh', 1, '/leg2-core-1.jar'),
          entry(
            'backendHigh',
            5,
            '/leg2-thin-1.jar',
            requires: {'coreHigh': 1},
            size: thin.length,
          ),
        ]);

        final plugin = _Backend(_Core('coreHigh'), 'backendHigh');
        expect(
          await plugin.checkForUpdate(),
          isTrue,
          reason: 'the file is not the size the index says',
        );
        await plugin.update();

        expect(await installed('backendHigh').readAsBytes(), thin);
      },
    );

    test(
      'with no split entry in the index it is simply not available',
      () async {
        await installFat('backendOnlyFat', 31);
        publish([entry('backendOnlyFat', 32, '/x.jar', platform: 'desktop')]);

        final plugin = _Backend(_Core('coreNone'), 'backendOnlyFat');
        expect(await plugin.fetchRemote(forceRefresh: true), isNull);
        expect(await plugin.checkForUpdate(), isFalse);
        expect(
          installed('backendOnlyFat').existsSync(),
          isTrue,
          reason: 'what is installed is left alone',
        );
      },
    );
  });

  test('ensure does nothing when the installed version is enough', () async {
    publish([entry('testCore', 4, '/core-4.jar')]);
    final core = _Core();

    await core.ensure(minimum: 4);
    await core.ensure();

    expect(hits.where((h) => h.endsWith('.jar')), isEmpty);
  });

  test('concurrent callers share one install', () async {
    served['/d-core-1.jar'] = _zip('shared core');
    publish([entry('sharedCore', 1, '/d-core-1.jar')]);

    final core = _SharedCore();
    await Future.wait([core.ensure(), core.ensure(), core.ensure(minimum: 1)]);

    expect(hits.where((h) => h == '/d-core-1.jar'), hasLength(1));
    expect(installed('sharedCore').existsSync(), isTrue);
  });

  test('installDependencies returns the core paths', () async {
    publish([entry('testCore', 4, '/core-4.jar')]);
    final a = _Backend(_Core(), 'backendA');

    final paths = await a.installDependencies();

    expect(paths, [installed('testCore').path]);
  });

  test(
    'installDependencies that cannot be installed leaves the plugin to start alone',
    () async {
      publish([]);
      final missing = _Backend(_MissingCore(), 'backendM');

      expect(await missing.installDependencies(), isEmpty);
    },
  );
}

class _SharedCore extends DownloadablePlugin {
  @override
  String get name => 'sharedCore';

  @override
  String get fileName => 'sharedCore-plugin.jar';
}

class _MissingCore extends DownloadablePlugin {
  @override
  String get name => 'missingCore';

  @override
  String get fileName => 'missingCore-plugin.jar';
}
