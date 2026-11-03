import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

class PageProxy {
  PageProxy._();

  static const _keep = 600;

  static final _entries = <String, Future<Uint8List> Function()>{};
  static final _random = Random.secure();
  static Future<HttpServer>? _starting;

  static Future<String> serve(Future<Uint8List> Function() fetch) async {
    final server = await _start();
    final id = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _entries[id] = fetch;
    while (_entries.length > _keep) {
      _entries.remove(_entries.keys.first);
    }
    return 'http://127.0.0.1:${server.port}/page/$id';
  }

  static Future<HttpServer> _start() =>
      _starting ??= HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((s) {
        s.listen(_handle, onError: (Object e) => debugPrint('PageProxy: $e'));
        return s;
      });

  static Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final fetch = segments.length == 2 && segments.first == 'page'
          ? _entries[segments.last]
          : null;
      if (fetch == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final bytes = await fetch();
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.parse(_typeOf(bytes));
      response.headers.contentLength = bytes.length;
      response.add(bytes);
    } catch (e) {
      debugPrint('PageProxy: page fetch failed: $e');
      response.statusCode = HttpStatus.internalServerError;
      response.write('$e');
    } finally {
      await response.close();
    }
  }

  static String _typeOf(Uint8List b) {
    bool starts(List<int> m, [int at = 0]) {
      if (b.length < at + m.length) return false;
      for (var i = 0; i < m.length; i++) {
        if (b[at + i] != m[i]) return false;
      }
      return true;
    }

    if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (starts([0x47, 0x49, 0x46])) return 'image/gif';
    if (starts([0x52, 0x49, 0x46, 0x46]) &&
        starts([0x57, 0x45, 0x42, 0x50], 8)) {
      return 'image/webp';
    }
    if (starts([0x66, 0x74, 0x79, 0x70], 4)) return 'image/avif';
    return 'application/octet-stream';
  }
}
