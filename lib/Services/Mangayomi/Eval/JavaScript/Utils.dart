import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:fjs/fjs.dart';
import 'package:js_packer/js_packer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../Logger.dart';
import '../../cryptoaes/js_unpacker.dart';
import '../../http/m_client.dart';
import '../dart/model/m_bridge.dart';
import 'BridgeRegister.dart';

class JsUtils {
  final JsEngine engine;

  JsUtils(this.engine);

  final _client = MClient.init();

  Future<void> init() async {
    await engine.eval(
      source: const JsCode.code(r'''
console.log = function(message) {
  if (typeof message === "object") {
    message = JSON.stringify(message);
  }
  fjs.bridge_call({
    type: "log",
    message: message.toString()
  });
};

console.warn = console.log;
console.error = console.log;

String.prototype.substringAfter = function(pattern) {
  const i = this.indexOf(pattern);
  if (i === -1) return this.substring(0);
  return this.substring(i + pattern.length);
};

String.prototype.substringAfterLast = function(pattern) {
  return this.split(pattern).pop();
};

String.prototype.substringBefore = function(pattern) {
  const i = this.indexOf(pattern);
  if (i === -1) return this.substring(0);
  return this.substring(0, i);
};

String.prototype.substringBeforeLast = function(pattern) {
  const i = this.lastIndexOf(pattern);
  if (i === -1) return this.substring(0);
  return this.substring(0, i);
};

String.prototype.substringBetween = function(left, right) {
  const start = this.indexOf(left);
  if (start === -1) return "";
  const end = this.indexOf(right, start + left.length);
  if (end === -1) return "";
  return this.substring(start + left.length, end);
};

async function cryptoHandler(text, iv, key, encrypt) {
  return await fjs.bridge_call({
    type: "cryptoHandler",
    text,
    iv,
    key,
    encrypt
  });
}

async function encryptAESCryptoJS(text, passphrase) {
  return await fjs.bridge_call({
    type: "encryptAESCryptoJS",
    text,
    passphrase
  });
}

async function decryptAESCryptoJS(text, passphrase) {
  return await fjs.bridge_call({
    type: "decryptAESCryptoJS",
    text,
    passphrase
  });
}

async function deobfuscateJsPassword(input) {
  return await fjs.bridge_call({
    type: "deobfuscateJsPassword",
    input
  });
}

async function unpackJsAndCombine(script) {
  return await fjs.bridge_call({
    type: "unpackJsAndCombine",
    script
  });
}

async function unpackJs(script) {
  return await fjs.bridge_call({
    type: "unpackJs",
    script
  });
}

async function parseEpub(bookName, url, headers) {
  return await fjs.bridge_call({
    type: "parseEpub",
    bookName,
    url,
    headers
  });
}

async function parseEpubChapter(bookName, url, headers, chapterTitle) {
  return await fjs.bridge_call({
    type: "parseEpubChapter",
    bookName,
    url,
    headers,
    chapterTitle
  });
}
'''),
    );
    register();
  }

  void register() {
    BridgeReg.register(
      "log",
      (Map data) async {
        Logger.log(data['message'].toString());
        return const JsResult.ok(JsValue.none());
      },
    );
    BridgeReg.register(
      "cryptoHandler",
      (Map data) async {
        final result = MBridge.cryptoHandler(
          data['text'],
          data['iv'],
          data['key'],
          data['encrypt'],
        );

        return JsResult.ok(JsValue.string(result));
      },
    );
    BridgeReg.register(
      "encryptAESCryptoJS",
      (Map data) async {
        final result =
            MBridge.encryptAESCryptoJS(data['text'], data['passphrase']);

        return JsResult.ok(JsValue.string(result));
      },
    );
    BridgeReg.register(
      "decryptAESCryptoJS",
      (Map data) async {
        final result =
            MBridge.decryptAESCryptoJS(data['text'], data['passphrase']);

        return JsResult.ok(JsValue.string(result));
      },
    );
    BridgeReg.register(
      "deobfuscateJsPassword",
      (Map data) async {
        final result = MBridge.deobfuscateJsPassword(data['input']);
        return JsResult.ok(JsValue.string(result));
      },
    );
    BridgeReg.register(
      "unpackJsAndCombine",
      (Map data) async {
        final result = JsUnpacker.unpackAndCombine(data['script']) ?? "";
        return JsResult.ok(JsValue.string(result));
      },
    );
    BridgeReg.register(
      "unpackJs",
      (Map data) async {
        final result = JSPacker(data['script']).unpack() ?? "";
        return JsResult.ok(JsValue.string(result));
      },
    );
    BridgeReg.register(
      "parseEpub",
      (Map data) async {
        final bytes = await _toBytesResponse(
          data['bookName'],
          data['url'],
          data['headers'],
        );

        final book = await EpubReader.readBook(bytes);

        final chapters = <String>[];

        for (var chapter in (book.Chapters ?? <EpubChapter>[])) {
          final title = chapter.Title;
          if (title != null) chapters.add(title);
        }

        return JsResult.ok(
          JsValue.object({
            'title': JsValue.string(book.Title ?? ''),
            'author': JsValue.string(book.Author ?? ''),
            'chapters': JsValue.array(
              chapters.map(JsValue.string).toList(),
            ),
          }),
        );
      },
    );
    BridgeReg.register(
      "parseEpubChapter",
      (Map data) async {
        final bytes = await _toBytesResponse(
          data['bookName'],
          data['url'],
          data['headers'],
        );

        final book = await EpubReader.readBook(bytes);

        final chapter =
            book.Chapters?.where((c) => c.Title == data['chapterTitle'])
                .firstOrNull;

        return JsResult.ok(
          JsValue.string(chapter?.HtmlContent ?? ""),
        );
      },
    );
  }

  Future<List<int>> _toBytesResponse(
    String bookName,
    String url,
    Map? headers,
  ) async {
    final tmpDirectory = await getTemporaryDirectory();

    if (Platform.isAndroid) {
      final nm = File(p.join(tmpDirectory.path, ".nomedia"));
      if (!(await nm.exists())) {
        await nm.create();
      }
    }

    final file = File(p.join(tmpDirectory.path, "$bookName.epub"));

    if (await file.exists()) {
      return await file.readAsBytes();
    }

    final response = await _client.get(
      Uri.parse(url),
      headers: headers?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
    );

    final bytes = response.bodyBytes;

    await file.writeAsBytes(bytes);

    return bytes;
  }
}
