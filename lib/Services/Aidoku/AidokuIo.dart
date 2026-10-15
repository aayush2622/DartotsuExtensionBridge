import 'dart:convert';
import 'dart:ffi';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class AidokuNetRequest {
  AidokuNetRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
    required this.timeout,
  });

  final String method;
  final String url;
  final Map<String, String> headers;
  final Uint8List? body;
  final Duration timeout;

  Map<String, Object?> toMap() => {
    'method': method,
    'url': url,
    'headers': headers,
    'body': body,
    'timeout': timeout.inMilliseconds,
  };

  static AidokuNetRequest fromMap(Map m) => AidokuNetRequest(
    method: m['method'] as String,
    url: m['url'] as String,
    headers: (m['headers'] as Map).cast<String, String>(),
    body: m['body'] as Uint8List?,
    timeout: Duration(milliseconds: m['timeout'] as int),
  );
}

class AidokuNetReply {
  AidokuNetReply({
    this.status = -10,
    this.headers = const {},
    Uint8List? body,
    this.url = '',
    this.error,
  }) : body = body ?? Uint8List(0);

  final int status;
  final Map<String, String> headers;
  final Uint8List body;
  final String url;
  final String? error;

  Uint8List encode() {
    final meta = utf8.encode(
      jsonEncode({
        'status': status,
        'headers': headers,
        'url': url,
        'error': error,
      }),
    );
    final out = BytesBuilder(copy: false)
      ..add(
        (ByteData(
          4,
        )..setUint32(0, meta.length, Endian.little)).buffer.asUint8List(),
      )
      ..add(meta)
      ..add(body);
    return out.takeBytes();
  }

  static AidokuNetReply decode(Uint8List data) {
    final metaLen = ByteData.sublistView(data).getUint32(0, Endian.little);
    final meta = jsonDecode(utf8.decode(data.sublist(4, 4 + metaLen))) as Map;
    return AidokuNetReply(
      status: meta['status'] as int,
      headers: (meta['headers'] as Map).cast<String, String>(),
      url: meta['url'] as String,
      error: meta['error'] as String?,
      body: Uint8List.fromList(data.sublist(4 + metaLen)),
    );
  }
}

abstract class AidokuIo {
  List<AidokuNetReply> sendAll(List<AidokuNetRequest> requests);

  String? defaultsGet(String key);

  void defaultsSet(String key, String? value);

  void log(String message);

  void sleep(Duration duration);
}

class AidokuWorkerIo implements AidokuIo {
  AidokuWorkerIo(this._main);

  final SendPort _main;

  static const _maxWait = Duration(seconds: 180);

  Pointer<Int64> _slot(String op, Object? payload) {
    final slot = calloc<Int64>(2);
    _main.send(['rpc', op, payload, slot.address]);
    return slot;
  }

  Uint8List _await(Pointer<Int64> slot) {
    final deadline = DateTime.now().add(_maxWait);
    while (slot[0] == 0) {
      if (DateTime.now().isAfter(deadline)) {
        calloc.free(slot);
        throw StateError('The app did not answer in time');
      }
      io.sleep(const Duration(milliseconds: 1));
    }
    io.sleep(const Duration(milliseconds: 1));
    final blob = Pointer<Uint8>.fromAddress(slot[1]);
    final length = blob.cast<Int64>().value;
    final data = Uint8List.fromList((blob + 8).asTypedList(length));
    malloc.free(blob);
    calloc.free(slot);
    return data;
  }

  @override
  List<AidokuNetReply> sendAll(List<AidokuNetRequest> requests) {
    final slots = [for (final r in requests) _slot('http', r.toMap())];
    final replies = <AidokuNetReply>[];
    for (final slot in slots) {
      try {
        replies.add(AidokuNetReply.decode(_await(slot)));
      } catch (e) {
        replies.add(AidokuNetReply(error: '$e'));
      }
    }
    return replies;
  }

  @override
  String? defaultsGet(String key) {
    final data = _await(_slot('get', key));
    if (data.isEmpty || data[0] == 0) return null;
    return utf8.decode(data.sublist(1));
  }

  @override
  void defaultsSet(String key, String? value) =>
      _main.send(['set', key, value]);

  @override
  void log(String message) => _main.send(['log', message]);

  @override
  void sleep(Duration duration) => io.sleep(duration);
}

void deliverAidokuReply(int slotAddress, Uint8List data) {
  final slot = Pointer<Int64>.fromAddress(slotAddress);
  final blob = malloc<Uint8>(data.length + 8);
  blob.cast<Int64>().value = data.length;
  (blob + 8).asTypedList(data.length).setAll(0, data);
  slot[1] = blob.address;
  slot[0] = 1;
}
