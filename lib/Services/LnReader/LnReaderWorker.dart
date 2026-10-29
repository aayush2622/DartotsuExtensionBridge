import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:http/http.dart' as http;

import '../../Logger.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Network/MClient.dart';
import '../../Settings/KvStore.dart';
import 'Js/Cheerio.dart';
import 'Js/HtmlParser.dart';
import 'Js/HttpClient.dart';
import 'Js/Libs.dart';
import 'Js/Polyfills.dart';
import 'Js/Storage.dart';
import 'Models/NovelModels.dart';

class LnReaderWorker {
  LnReaderWorker._(this._isolate, this._send, this._inbox);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _inbox;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 1;
  http.Client? _client;
  bool _disposed = false;
  static http.Client Function() clientFactory = MClient.init;
  static void Function(String message) logSink = Logger.log;
  static String? Function(String key) readStore = getVal<String>;
  static void Function(String key, String? value) writeStore = setVal;

  static Future<LnReaderWorker> spawn({
    required String sourceId,
    required String code,
  }) async {
    final inbox = ReceivePort();
    final isolate = await Isolate.spawn(_entry, inbox.sendPort);
    final events = inbox.asBroadcastStream();
    final send = await events.first as SendPort;
    final worker = LnReaderWorker._(isolate, send, inbox);
    events.listen(worker._onMessage);
    try {
      await worker._call('init', {
        'id': sourceId,
        'code': code,
        'seed': readStore(JsStorage.namespaceFor(sourceId)),
      });
    } catch (_) {
      unawaited(worker.dispose());
      rethrow;
    }
    return worker;
  }

  void _onMessage(Object? message) {
    if (message is! List) return;
    switch (message[0]) {
      case 'done':
        final c = _pending.remove(message[1] as int);
        if (c == null) return;
        if (message[2] == true) {
          c.completeError(Exception(message[3]));
        } else {
          c.complete(message[3]);
        }
      case 'log':
        logSink(message[1] as String);
      case 'persist':
        writeStore(message[1] as String, message[2] as String);
      case 'http':
        unawaited(
          _serve(message[1] as int, message[2] as String, message[3] as List),
        );
    }
  }

  Future<void> _serve(int id, String method, List args) async {
    try {
      final client = _client ??= clientFactory();
      final body = await lnHttpFetch(client, method, args);
      if (!_disposed) _send.send(['httpReply', id, false, body]);
    } catch (e) {
      if (!_disposed) _send.send(['httpReply', id, true, '$e']);
    }
  }

  Future<Object?> _call(String op, Map<String, Object?> args) {
    if (_disposed) return Future.error(Exception('LNReader worker stopped'));
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send.send(['call', id, op, args]);
    return completer.future;
  }

  Future<Map<String, Object?>> pages(
    String op,
    Map<String, Object?> args,
  ) async => Map<String, Object?>.from(await _call(op, args) as Map);

  Future<Map<String, Object?>> detail(DMedia media) async =>
      Map<String, Object?>.from(
        await _call('detail', {
              'url': media.url,
              'title': media.title,
              'cover': media.cover,
            })
            as Map,
      );

  Future<String?> content(String url) async =>
      await _call('content', {'url': url}) as String?;

  Future<Object?> settings() => _call('settings', const {});

  Future<void> setPreference(String key, Object? value) =>
      _call('setPref', {'key': key, 'value': value});

  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await _call('dispose', const {}).timeout(const Duration(seconds: 1));
    } catch (_) {}
    _disposed = true;
    for (final c in _pending.values) {
      c.completeError(Exception('LNReader worker stopped'));
    }
    _pending.clear();
    _inbox.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

const _bootstrap = r'''
module={},exports=Function("return this")(),Object.defineProperties(module,{namespace:{set:function(a){exports=a}},exports:{set:function(a){for(var b in a)a.hasOwnProperty(b)&&(exports[b]=a[b])},get:function(){return exports}}});
''';

const _require = r'''
const require = (package) => {
  switch (package) {
    case "htmlparser2":
        return {Parser: Parser};
    case "cheerio":
        return {load: load};
    case "dayjs":
        return module.exports.dayjs;
    case "urlencode":
        return {encode: urlencode, decode: urldecode};
    case "@libs/fetch":
        return {fetchApi: fetchApi, fetchText: fetchText, fetchProto: fetchProto};
    case "@libs/novelStatus":
        return {NovelStatus: NovelStatus};
    case "@libs/isAbsoluteUrl":
        return {isUrlAbsolute: isUrlAbsolute};
    case "@libs/filterInputs":
        return {
          FilterTypes: FilterTypes,
          isPickerValue: isPickerValue,
          isCheckboxValue: isCheckboxValue,
          isSwitchValue: isSwitchValue,
          isTextValue: isTextValue,
          isXCheckboxValue: isXCheckboxValue
        };
    case "@libs/defaultCover":
        return {defaultCover: 'https://raw.githubusercontent.com/LNReader/lnreader-plugins/refs/heads/master/public/static/coverNotAvailable.webp'};
    case "@libs/storage":
        return {storage: storage, localStorage: localStorage, sessionStorage: sessionStorage};
    case "@libs/aes":
        return {gcm: () => { throw new Error("@libs/aes is not supported"); }};
    case "@libs/utils":
        return {
          utf8ToBytes: (s) => Array.from(new TextEncoder().encode(s)),
          bytesToUtf8: (b) => new TextDecoder().decode(new Uint8Array(b))
        };
    default:
        return {};
  }
};
''';

class _Host {
  _Host(this.main);

  final SendPort main;
  final Map<int, Completer<String>> waiting = {};
  int next = 1;
  JavascriptRuntime? runtime;

  Future<String> fetch(String method, List args) {
    final id = next++;
    final completer = Completer<String>();
    waiting[id] = completer;
    main.send(['http', id, method, args]);
    return completer.future;
  }

  void reply(int id, bool failed, Object? body) {
    final completer = waiting.remove(id);
    if (completer == null) return;
    failed
        ? completer.completeError(Exception(body))
        : completer.complete(body as String);
  }

  void init(String id, String code, String? seed) {
    final rt = QuickJsRuntime2(stackSize: 1024 * 1024 * 4);
    rt.enableHandlePromises();
    rt.evaluate(_bootstrap);
    JsPolyfills(rt).init();
    JsHttpClient(rt, fetcher: fetch).init();
    JsLibs(rt).init();
    JsHtmlParser(rt).init();
    JsCheerio(rt).init();
    JsStorage(
      rt,
      sourceId: id,
      seed: seed,
      persist: (ns, json) => main.send(['persist', ns, json]),
    ).init();
    rt.evaluate(_require);
    rt.evaluate('$code\nconst extension = exports.default;');
    runtime = rt;
  }

  Future<dynamic> callAsync(String expr) async {
    final rt = runtime!;
    final promised = await rt.handlePromise(
      await rt.evaluateAsync('jsonStringify(() => extension.$expr)'),
    );
    return jsonDecode(promised.stringResult);
  }

  dynamic callSync(String expr) {
    final rt = runtime;
    if (rt == null) return null;
    try {
      return jsonDecode(
        rt.evaluate('JSON.stringify(extension.$expr)').stringResult,
      );
    } catch (_) {
      return null;
    }
  }

  List<Map<String, Object?>> mediaList(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw.whereType<Map>())
        () {
          final n = NovelItem.fromJson(Map<String, dynamic>.from(e));
          return DMedia(title: n.name, url: n.path, cover: n.cover).toJson();
        }(),
    ];
  }

  Future<Object?> run(String op, Map args) async {
    switch (op) {
      case 'init':
        init(
          args['id'] as String,
          args['code'] as String,
          args['seed'] as String?,
        );
        return null;
      case 'popular':
        final latest = args['latest'] == true;
        final raw = await callAsync(
          'popularNovels(${args['page']}, {showLatestNovels: $latest, '
          'filters: extension.filters})',
        );
        final list = mediaList(raw);
        return {'list': list, 'hasNextPage': list.isNotEmpty};
      case 'search':
        final raw = await callAsync(
          'searchNovels(${jsonEncode(args['query'])}, ${args['page']})',
        );
        final list = mediaList(raw);
        return {'list': list, 'hasNextPage': list.isNotEmpty};
      case 'detail':
        return detail(args);
      case 'content':
        final res = await runtime!.handlePromise(
          await runtime!.evaluateAsync(
            'jsonStringify(() => extension.parseChapter('
            '${jsonEncode(args['url'] ?? '')}))',
          ),
        );
        final decoded = jsonDecode(res.stringResult);
        return decoded is String ? decoded : decoded?.toString();
      case 'settings':
        return callSync('pluginSettings');
      case 'setPref':
        runtime!.evaluate(
          'storage.set(${jsonEncode(args['key'])}, ${jsonEncode(args['value'])})',
        );
        return null;
      case 'dispose':
        try {
          runtime?.dispose();
        } catch (_) {}
        runtime = null;
        return null;
    }
    throw StateError('Unknown op $op');
  }

  Future<Map<String, Object?>> detail(Map args) async {
    final url = args['url'] as String?;
    final novel = SourceNovel.fromJson(
      Map<String, dynamic>.from(
        await callAsync('parseNovel(${jsonEncode(url)})'),
      ),
    );
    var chapters = novel.chapters ?? const <ChapterItem>[];
    if (chapters.isEmpty) {
      try {
        final page = await callAsync(
          'parsePage(${jsonEncode(novel.path)}, "1")',
        );
        chapters = SourcePage.fromJson(
          Map<String, dynamic>.from(page),
        ).chapters;
      } catch (_) {}
    }
    final episodes = <DEpisode>[
      for (final c in chapters)
        DEpisode(
          name: c.name,
          url: c.path,
          episodeNumber: c.chapterNumber?.toString() ?? '',
          dateUpload: _releaseToMillis(c.releaseTime),
        ),
    ];
    return DMedia(
      title: novel.name.isNotEmpty ? novel.name : args['title'] as String?,
      url: novel.path,
      cover: novel.cover ?? args['cover'] as String?,
      description: novel.summary,
      author: novel.author,
      artist: novel.artist,
      genre: novel.genres
          ?.split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      episodes: episodes.reversed.toList(),
    ).toJson();
  }
}

String _releaseToMillis(String? release) {
  if (release == null || release.isEmpty) {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
  return DateTime.tryParse(release)?.millisecondsSinceEpoch.toString() ??
      int.tryParse(release)?.toString() ??
      DateTime.now().millisecondsSinceEpoch.toString();
}

void _entry(SendPort main) {
  final inbox = ReceivePort();
  main.send(inbox.sendPort);
  final host = _Host(main);
  inbox.listen((message) async {
    if (message is! List) return;
    if (message[0] == 'httpReply') {
      host.reply(message[1] as int, message[2] == true, message[3]);
      return;
    }
    if (message[0] != 'call') return;
    final id = message[1] as int;
    try {
      final result = await host.run(message[2] as String, message[3] as Map);
      main.send(['done', id, false, result]);
    } catch (e) {
      main.send(['done', id, true, '$e'.replaceFirst('Exception: ', '')]);
    }
  });
}
