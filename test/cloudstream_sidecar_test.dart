@Timeout(Duration(minutes: 20))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Drives the real CloudStream desktop sidecar over its stdio protocol and
/// reads what it answers and logs.
///
/// a JRE 21 and some `.cs3` plugins (the ones Dartotsu installed are copied, never
/// touched). Anything missing skips the suite. Overrides: `CS_JAR`, `CS_JAVA`,
/// `CS_PLUGINS`; `CS_OFFLINE=1` skips the tests that need the network.
///
/// The work folder is kept between runs on purpose: the second start must find the
/// converted plugin jars and not rebuild them.

final _home = Platform.environment['HOME'] ?? '';
final _jar = File(
  Platform.environment['CS_JAR'] ??
      '${Directory.current.path}/runtimeManager/builds/cloudStreamDesktop/cloudStreamDesktop-split.jar',
);
final _core = File(
  Platform.environment['CS_CORE'] ??
      '${Directory.current.path}/runtimeManager/builds/desktopCore/desktopCore-plugin.jar',
);
final _pluginSource = Directory(
  Platform.environment['CS_PLUGINS'] ??
      '$_home/Documents/Dartotsu/bridge/cloudStream/extensions/Anime',
);
final _work = Directory('${Directory.systemTemp.path}/dartotsu-cs-harness');
final _offline = Platform.environment['CS_OFFLINE'] == '1';

String? _findJava() {
  final explicit = Platform.environment['CS_JAVA'];
  if (explicit != null && File(explicit).existsSync()) return explicit;
  final root = Directory('$_home/Documents/Dartotsu/bridge/jre-21');
  if (!root.existsSync()) return null;
  for (final entry in root.listSync()) {
    final java = File('${entry.path}/bin/java');
    if (java.existsSync()) return java.path;
  }
  return null;
}

class _Host {
  HttpServer? server;
  final logs = <String>[];

  bool get capturing => server != null;

  Future<void> start() async {
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4567);
    } on SocketException {
      return;
    }
    server!.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      final method = body['method'] as String;
      final args = (body['args'] as Map?) ?? const {};
      if (method == 'logger') logs.add('${args['message']}');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'result': null}));
      await request.response.close();
    });
  }

  Future<void> stop() async => server?.close(force: true);
}

class _Sidecar {
  final Process process;
  final Map<int, Completer<dynamic>> _pending = {};
  final lines = <String>[];
  int _next = 1;

  _Sidecar._(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(lines.add);
  }

  static Future<_Sidecar> start(String java) async {
    final process = await Process.start(java, [
      '-Dfile.encoding=UTF-8',
      '-Xmx3072m',
      '-cp',
      '${_core.path}${Platform.isWindows ? ';' : ':'}${_jar.path}',
      'com.aayush262.dartotsu_extension_bridge.Main',
    ]);
    return _Sidecar._(process);
  }

  void _onLine(String line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final completer = _pending.remove(json['id']);
      if (completer == null) return;
      if (json['success'] == true) {
        completer.complete(json['data']);
      } else {
        completer.completeError(Exception('${json['error']}'));
      }
    } catch (_) {
      lines.add(line);
    }
  }

  Future<dynamic> call(
    String method, [
    Map<String, dynamic> args = const {},
    Duration timeout = const Duration(minutes: 5),
  ]) async {
    final id = _next++;
    final completer = _pending[id] = Completer<dynamic>();
    process.stdin.writeln(
      jsonEncode({'id': id, 'method': method, 'args': args}),
    );
    final raw = await completer.future.timeout(timeout);
    if (raw is! String || raw.trim().isEmpty) return raw;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  Future<void> stop() async {
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () => -1,
    );
  }
}

Future<void> _prepareWork() async {
  final plugins = Directory('${_work.path}/extensions/Anime');
  await plugins.create(recursive: true);
  for (final file in _pluginSource.listSync().whereType<File>()) {
    if (!file.path.endsWith('.cs3')) continue;
    final target = File('${plugins.path}/${file.uri.pathSegments.last}');
    if (!target.existsSync() || target.lengthSync() != file.lengthSync()) {
      await file.copy(target.path);
    }
  }
}

String get _pluginsPath => '${_work.path}/extensions/Anime';

Future<_Sidecar> _boot(String java) async {
  final sidecar = await _Sidecar.start(java);
  await sidecar.call('initializeDesktop', {'path': _work.path});
  await sidecar.call('initClient', {
    'data': jsonEncode({'dns': null, 'proxy': null, 'userAgent': null}),
  });
  return sidecar;
}

Future<List<Map<String, dynamic>>> _installed(_Sidecar sidecar) async {
  final result = await sidecar.call('getInstalledAnimeExtensions', {
    'path': _pluginsPath,
  });
  return (result as List).cast<Map<String, dynamic>>();
}

Future<int> _pending(_Sidecar sidecar) async =>
    ((await sidecar.call('pendingExtensions')) as num).toInt();

Future<void> _settle(_Sidecar sidecar, {void Function(int)? onRound}) async {
  while (true) {
    final list = await _installed(sidecar);
    onRound?.call(list.length);
    if (await _pending(sidecar) == 0) return;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

void main() {
  final java = _findJava();
  final missing = [
    if (java == null) 'a JRE 21 under Documents/Dartotsu/bridge/jre-21',
    if (!_jar.existsSync()) 'the sidecar jar (${_jar.path})',
    if (!_core.existsSync()) 'the desktop core jar (${_core.path})',
    if (!_pluginSource.existsSync())
      'CloudStream plugins (${_pluginSource.path})',
  ];
  if (missing.isNotEmpty) {
    test(
      'CloudStream sidecar harness',
      () {},
      skip: 'needs ${missing.join(', ')}',
    );
    return;
  }

  final host = _Host();
  setUpAll(() async {
    await host.start();
    await _prepareWork();
    if (!host.capturing) {
      stderr.writeln(
        'Port 4567 is taken (Dartotsu is running?): sidecar logs go to the app, '
        'log based checks are skipped.',
      );
    }
  });
  tearDownAll(host.stop);

  test('the first start lists plugins as they become ready', () async {
    host.logs.clear();
    final sidecar = await _boot(java!);
    addTearDown(sidecar.stop);

    final started = DateTime.now();
    final counts = <int>[];
    await _settle(
      sidecar,
      onRound: (n) {
        counts.add(n);
        stdout.writeln(
          '  ${DateTime.now().difference(started).inSeconds}s: $n sources listed',
        );
      },
    );

    final names = (await _installed(sidecar)).map((e) => e['name']).toList();
    stdout.writeln('  sources: $names');
    expect(names, isNotEmpty);
    expect(await _pending(sidecar), 0);
    expect(
      counts,
      isNot(contains(0)),
      reason: 'the list was empty while loading',
    );
    expect(
      counts,
      orderedEquals([...counts]..sort()),
      reason: 'sources vanished',
    );
  });

  test('a refresh never unloads what is already loaded', () async {
    final sidecar = await _boot(java!);
    addTearDown(sidecar.stop);
    await _settle(sidecar);
    final before = (await _installed(sidecar)).map((e) => e['name']).toSet();

    final again = await Future.wait([
      for (var i = 0; i < 5; i++) _installed(sidecar),
    ]);
    for (final list in again) {
      expect(list.map((e) => e['name']).toSet(), before);
    }
  });

  test('plugins converted once are reused by the next start', () async {
    final sidecar = await _boot(java!);
    addTearDown(sidecar.stop);
    host.logs.clear();
    await _settle(sidecar);

    if (!host.capturing) return;
    final builds = host.logs.where((l) => l.contains('Building jar for'));
    expect(builds, isEmpty, reason: 'converted again: $builds');
  });

  test('a call made while plugins load waits instead of failing', () async {
    // Drop the cached jars so StreamPlay (the slow one) has to be rebuilt.
    final jars = Directory('$_pluginsPath/jar');
    if (jars.existsSync()) await jars.delete(recursive: true);

    final sidecar = await _boot(java!);
    addTearDown(sidecar.stop);

    final first = _installed(sidecar);
    Object? error;
    dynamic search;
    try {
      search = await sidecar.call('search', {
        'sourceId': 'StreamPlay',
        'isAnime': true,
        'query': 'Adventure Time',
        'page': 1,
      });
    } catch (e) {
      error = e;
    }
    await first;
    await _settle(sidecar);

    expect(
      error,
      isNull,
      reason: 'search failed while the plugin was loading: $error',
    );
    if (!_offline) {
      expect(search, isA<Map>());
      expect((search as Map)['list'], isNotEmpty);
    }
  }, skip: _offline ? 'needs the network' : null);

  test('a show with several seasons is sent grouped by season', () async {
    final sidecar = await _boot(java!);
    addTearDown(sidecar.stop);
    await _settle(sidecar);

    final found =
        await sidecar.call('search', {
              'sourceId': 'StreamPlay',
              'isAnime': true,
              'query': 'Adventure Time',
              'page': 1,
            })
            as Map;
    final show = (found['list'] as List).cast<Map>().firstWhere(
      (m) => '${m['title']}'.toLowerCase() == 'adventure time',
      orElse: () => (found['list'] as List).first as Map,
    );
    stdout.writeln('  picked: ${show['title']} ${show['url']}');

    final detail =
        await sidecar.call('getDetail', {
              'sourceId': 'StreamPlay',
              'isAnime': true,
              'media': jsonEncode({'url': show['url']}),
            })
            as Map;
    final episodes = (detail['episodes'] as List).cast<Map>();
    final seasons = {for (final e in episodes) e['scanlator']};
    stdout.writeln(
      '  ${episodes.length} episodes in ${seasons.length} groups: $seasons',
    );

    expect(seasons.length, greaterThan(1));
    expect(seasons, everyElement(isNotNull));
    expect(
      seasons.whereType<String>().every(
        (s) => s == 'Specials' || s.startsWith('Season '),
      ),
      isTrue,
    );
    final firstSeason = episodes.where((e) => e['scanlator'] == 'Season 1');
    final numbers = firstSeason.map(
      (e) => (e['episodeNumber'] as num).toDouble(),
    );
    expect(numbers, isNotEmpty);
    expect(
      numbers.every((n) => n == n.truncateToDouble()),
      isTrue,
      reason: 'episode numbers must stay whole inside a season',
    );
    expect(numbers.reduce((a, b) => a > b ? a : b), lessThan(60));
  }, skip: _offline ? 'needs the network' : null);
}
