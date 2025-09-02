import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:path/path.dart' as p;
import 'package:dartotsu_extension_bridge/Mangayomi/cryptoaes/js_unpacker.dart';

import '../dart/model/m_bridge.dart';

class JsUtils {
  late JavascriptRuntime runtime;
  late Dio dio;

  JsUtils(this.runtime) {
    dio = Dio();
  }

  void init() {
    runtime.onMessage('log', (dynamic args) {
      debugPrint(args.toString());
      return null;
    });

    runtime.onMessage('cryptoHandler', (dynamic args) {
      return MBridge.cryptoHandler(args[0], args[1], args[2], args[3]);
    });

    runtime.onMessage('encryptAESCryptoJS', (dynamic args) {
      return MBridge.encryptAESCryptoJS(args[0], args[1]);
    });

    runtime.onMessage('decryptAESCryptoJS', (dynamic args) {
      return MBridge.decryptAESCryptoJS(args[0], args[1]);
    });

    runtime.onMessage('deobfuscateJsPassword', (dynamic args) {
      return MBridge.deobfuscateJsPassword(args[0]);
    });

    runtime.onMessage('unpackJsAndCombine', (dynamic args) {
      return JsUnpacker.unpackAndCombine(args[0]) ?? "";
    });

    runtime.onMessage('unpackJs', (dynamic args) {
      return JsUnpacker.unpack(args[0]);
    });

    runtime.onMessage('evaluateJavascriptViaWebview', (dynamic args) async {
      final headers = (args[1]! as Map).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
      final scripts = (args[2]! as List).map((e) => e.toString()).toList();
      return await MBridge.evaluateJavascriptViaWebview(
        args[0]!,
        headers,
        scripts,
      );
    });

    runtime.onMessage('parseEpub', (dynamic args) async {
      final bytes = await _toBytesResponse("GET", args);
      final book = await EpubReader.readBook(bytes);
      final chapters = book.Chapters?.map((c) => c.Title).toList() ?? [];
      return jsonEncode({
        "title": book.Title,
        "author": book.Author,
        "chapters": chapters,
      });
    });

    runtime.onMessage('parseEpubChapter', (dynamic args) async {
      final bytes = await _toBytesResponse("GET", args);
      final book = await EpubReader.readBook(bytes);
      final chapter = book.Chapters?.cast<EpubChapter?>().firstWhere(
        (c) => c?.Title == args[3],
        orElse: () => null,
      );
      return chapter?.HtmlContent;
    });

    // JavaScript shims
    runtime.evaluate(_jsPolyfills);
  }

  Future<Uint8List> _toBytesResponse(String method, List args) async {
    final bookName = args[0] as String;
    final url = args[1] as String;
    final headers = (args[2] as Map?)?.map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    );
    final body = args.length >= 4 ? args[3] : null;

    final tmpDir = await getTemporaryDirectory();
    final file = File(p.join(tmpDir.path, "$bookName.epub"));
    if (await file.exists()) return await file.readAsBytes();

    final response = await dio.fetch(
      Options(
        method: method,
        headers: headers,
        responseType: ResponseType.bytes,
      ).compose(dio.options, url, data: body),
    );

    final bytes = response.data as Uint8List;
    await file.writeAsBytes(bytes);
    return bytes;
  }

  static const String _jsPolyfills = '''
console.log = function (msg) { sendMessage("log", JSON.stringify([msg.toString()])); };
console.warn = console.log;
console.error = console.log;

String.prototype.substringAfter = function(pattern) {
  const idx = this.indexOf(pattern);
  return idx === -1 ? this.substring(0) : this.substring(idx + pattern.length);
};

String.prototype.substringAfterLast = function(pattern) {
  return this.split(pattern).pop();
};

String.prototype.substringBefore = function(pattern) {
  const idx = this.indexOf(pattern);
  return idx === -1 ? this.substring(0) : this.substring(0, idx);
};

String.prototype.substringBeforeLast = function(pattern) {
  const idx = this.lastIndexOf(pattern);
  return idx === -1 ? this.substring(0) : this.substring(0, idx);
};

String.prototype.substringBetween = function(left, right) {
  const start = this.indexOf(left);
  if(start === -1) return "";
  const leftIndex = start + left.length;
  const rightIndex = this.indexOf(right, leftIndex);
  if(rightIndex === -1) return "";
  return this.substring(leftIndex, rightIndex);
};
''';
function cryptoHandler(text, iv, secretKeyString, encrypt) {
    return sendMessage(
        "cryptoHandler",
        JSON.stringify([text, iv, secretKeyString, encrypt])
    );
}
function encryptAESCryptoJS(plainText, passphrase) {
    return sendMessage(
        "encryptAESCryptoJS",
        JSON.stringify([plainText, passphrase])
    );
}
function decryptAESCryptoJS(encrypted, passphrase) {
    return sendMessage(
        "decryptAESCryptoJS",
        JSON.stringify([encrypted, passphrase])
    );
}
function deobfuscateJsPassword(inputString) {
    return sendMessage(
        "deobfuscateJsPassword",
        JSON.stringify([inputString])
    );
}
function unpackJsAndCombine(scriptBlock) {
    return sendMessage(
        "unpackJsAndCombine",
        JSON.stringify([scriptBlock])
    );
}
function unpackJs(packedJS) {
    return sendMessage(
        "unpackJs",
        JSON.stringify([packedJS])
    );
}
function parseDates(value, dateFormat, dateFormatLocale) {
    return sendMessage(
        "parseDates",
        JSON.stringify([value, dateFormat, dateFormatLocale])
    );
}
async function evaluateJavascriptViaWebview(url, headers, scripts) {
    return await sendMessage(
        "evaluateJavascriptViaWebview",
        JSON.stringify([url, headers, scripts])
    );
}
async function parseEpub(bookName, url, headers) {
    return JSON.parse(await sendMessage(
        "parseEpub",
        JSON.stringify([bookName, url, headers])
    ));
}
async function parseEpubChapter(bookName, url, headers, chapterTitle) {
    return await sendMessage(
        "parseEpubChapter",
        JSON.stringify([bookName, url, headers, chapterTitle])
    );
}
''');
  }

  Future<Uint8List> _toBytesResponse(
    http.Client client,
    String method,
    List args,
  ) async {
    final bookName = args[0] as String;
    final url = args[1] as String;
    final headers = (args[2] as Map?)?.toMapStringString;
    final body = args.length >= 4
        ? args[3] is List
              ? args[3] as List
              : args[3] is String
              ? args[3] as String
              : (args[3] as Map?)?.toMapStringDynamic
        : null;

    final tmpDirectory = (await getTemporaryDirectory());
    if (Platform.isAndroid) {
      if (!(await File(p.join(tmpDirectory.path, ".nomedia")).exists())) {
        await File(p.join(tmpDirectory.path, ".nomedia")).create();
      }
    }
    final file = File(p.join(tmpDirectory.path, "$bookName.epub"));
    if (await file.exists()) {
      return await file.readAsBytes();
    }

    var request = http.Request(method, Uri.parse(url));
    request.headers.addAll(headers ?? {});
    final future = switch (method) {
      "GET" => client.get(Uri.parse(url), headers: headers),
      "POST" => client.post(Uri.parse(url), headers: headers, body: body),
      "PUT" => client.put(Uri.parse(url), headers: headers, body: body),
      "DELETE" => client.delete(Uri.parse(url), headers: headers, body: body),
      _ => client.patch(Uri.parse(url), headers: headers, body: body),
    };
    final bytes = (await future).bodyBytes;
    await file.writeAsBytes(bytes);
    return bytes;
  }
}
