import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../Logger.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../NetworkClient.dart';
import '../../Settings/KvStore.dart';
import 'AidokuIo.dart';
import 'AidokuRuntime.dart';

class AidokuWorker {
  AidokuWorker._(this._isolate, this._send);

  final Isolate _isolate;
  final SendPort _send;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 1;
  late final ReceivePort _inbox;
  http.Client? _client;
  static http.Client Function() clientFactory = MClient.init;
  static void Function(String message) logSink = Logger.log;
  static String? Function(String key) readStore = getVal<String>;
  static void Function(String key, String? value) writeStore = setVal;

  static Future<AidokuWorker> spawn(
    String sourceId,
    String wasmBase64,
    Map<String, String>? defaults,
  ) async {
    final inbox = ReceivePort();
    final isolate = await Isolate.spawn(_entry, inbox.sendPort);
    final events = inbox.asBroadcastStream();
    final send = await events.first as SendPort;
    final worker = AidokuWorker._(isolate, send).._inbox = inbox;
    events.listen(worker._onMessage);
    await worker._call('load', {
      'id': sourceId,
      'wasm': wasmBase64,
      'defaults': defaults,
    });
    return worker;
  }

  Future<void> _onMessage(Object? message) async {
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
      case 'set':
        writeStore(message[1] as String, message[2] as String?);
      case 'rpc':
        unawaited(_serve(message[1] as String, message[2], message[3] as int));
    }
  }

  Future<void> _serve(String op, Object? payload, int slot) async {
    Uint8List reply;
    try {
      if (op == 'get') {
        final value = readStore(payload as String);
        reply = Uint8List.fromList([
          value == null ? 0 : 1,
          ...utf8.encode(value ?? ''),
        ]);
      } else {
        reply = await _fetch(AidokuNetRequest.fromMap(payload as Map));
      }
    } catch (e) {
      reply = AidokuNetReply(error: '$e').encode();
    }
    deliverAidokuReply(slot, reply);
  }

  Future<Uint8List> _fetch(AidokuNetRequest request) async {
    try {
      final client = _client ??= clientFactory();
      final req = http.Request(request.method, Uri.parse(request.url));
      req.headers.addAll(request.headers);
      final body = request.body;
      if (body != null) req.bodyBytes = body;
      final streamed = await client.send(req).timeout(request.timeout);
      final response = await http.Response.fromStream(streamed);
      return AidokuNetReply(
        status: response.statusCode,
        headers: response.headers,
        body: response.bodyBytes,
        url: response.request?.url.toString() ?? request.url,
      ).encode();
    } catch (e) {
      return AidokuNetReply(error: '$e').encode();
    }
  }

  Future<Object?> _call(String op, Map<String, Object?> args) {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send.send(['call', id, op, args]);
    return completer.future;
  }

  Future<Pages> _pages(String op, Map<String, Object?> args) async {
    final json = await _call(op, args) as Map;
    return Pages(
      list: [
        for (final m in json['list'] as List)
          DMedia.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
      hasNextPage: json['hasNextPage'] as bool,
    );
  }

  Future<Pages> getPopular(int page) => _pages('popular', {'page': page});

  Future<Pages> getLatestUpdates(int page) => _pages('latest', {'page': page});

  Future<Pages> search(String query, int page) =>
      _pages('search', {'query': query, 'page': page});

  Future<DMedia> getDetail(DMedia media) async => DMedia.fromJson(
    Map<String, dynamic>.from(
      await _call('detail', {'media': media.toJson()}) as Map,
    ),
  );

  Future<List<PageUrl>> getPageList(DEpisode episode) async {
    final list = await _call('pages', {'episode': episode.toJson()}) as List;
    return [
      for (final raw in list) _page(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  PageUrl _page(Map<String, dynamic> json) {
    final url = json['url'] as String;
    final headers = (json['headers'] as Map?)?.cast<String, String>() ?? {};
    final context = (json['context'] as Map?)?.cast<String, String>();
    return PageUrl(
      url,
      headers: headers.isEmpty ? null : headers,
      process: json['process'] == true
          ? (data) async =>
                await _call('process', {
                      'data': data,
                      'url': url,
                      'headers': headers,
                      'context': context,
                    })
                    as Uint8List
          : null,
    );
  }

  Future<void> notify(String name) => _call('notify', {'name': name});

  Future<bool> basicLogin(String key, String user, String password) async =>
      await _call('login', {'key': key, 'user': user, 'password': password})
          as bool;

  void dispose() {
    for (final c in _pending.values) {
      c.completeError(Exception('Aidoku worker stopped'));
    }
    _pending.clear();
    _inbox.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

void _entry(SendPort main) {
  final inbox = ReceivePort();
  main.send(inbox.sendPort);
  AidokuRuntime? runtime;
  final io = AidokuWorkerIo(main);

  Future<Object?> run(String op, Map args) async {
    final rt = runtime;
    switch (op) {
      case 'load':
        runtime = await AidokuRuntime.load(
          args['id'] as String,
          args['wasm'] as String,
          (args['defaults'] as Map?)?.cast<String, String>(),
          io,
        );
        return null;
      case 'popular':
        return _pagesJson(await rt!.getPopular(args['page'] as int));
      case 'latest':
        return _pagesJson(await rt!.getLatestUpdates(args['page'] as int));
      case 'search':
        return _pagesJson(
          await rt!.search(args['query'] as String, args['page'] as int),
        );
      case 'detail':
        final media = DMedia.fromJson(
          Map<String, dynamic>.from(args['media'] as Map),
        );
        return (await rt!.getDetail(media)).toJson();
      case 'pages':
        final episode = DEpisode.fromJson(
          Map<String, dynamic>.from(args['episode'] as Map),
        );
        return await rt!.getPageDescriptors(episode);
      case 'process':
        return await rt!.processPageImage(
          args['data'] as Uint8List,
          url: args['url'] as String,
          headers: (args['headers'] as Map).cast<String, String>(),
          context: (args['context'] as Map?)?.cast<String, String>(),
        );
      case 'notify':
        await rt!.notify(args['name'] as String);
        return null;
      case 'login':
        return await rt!.basicLogin(
          args['key'] as String,
          args['user'] as String,
          args['password'] as String,
        );
    }
    throw StateError('Unknown op $op');
  }

  inbox.listen((message) async {
    if (message is! List) return;
    final id = message[1] as int;
    try {
      final result = await run(message[2] as String, message[3] as Map);
      main.send(['done', id, false, result]);
    } catch (e) {
      main.send(['done', id, true, '$e'.replaceFirst('Exception: ', '')]);
    }
  });
}

Map<String, Object?> _pagesJson(Pages pages) => {
  'list': [for (final m in pages.list) m.toJson()],
  'hasNextPage': pages.hasNextPage,
};
