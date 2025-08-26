import 'dart:convert';
import 'dart:async';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter/foundation.dart';

import 'video.dart';
import '../../javascript/http.dart';
import '../../../string_extensions.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:js_packer/js_packer.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import '../../../anime_extractors/dood_extractor.dart';
import '../../../anime_extractors/filemoon.dart';
import '../../../anime_extractors/gogocdn_extractor.dart';
import '../../../anime_extractors/mp4upload_extractor.dart';
import '../../../anime_extractors/mytv_extractor.dart';
import '../../../anime_extractors/okru_extractor.dart';
import '../../../anime_extractors/quarkuc_extractor.dart';
import '../../../anime_extractors/sendvid_extractor.dart';
import '../../../anime_extractors/sibnet_extractor.dart';
import '../../../anime_extractors/streamlare_extractor.dart';
import '../../../anime_extractors/streamtape_extractor.dart';
import '../../../anime_extractors/streamwish_extractor.dart';
import '../../../anime_extractors/vidbom_extractor.dart';
import '../../../anime_extractors/voe_extractor.dart';
import '../../../anime_extractors/your_upload_extractor.dart';
import '../../../cryptoaes/crypto_aes.dart';
import '../../../cryptoaes/deobfuscator.dart';
import '../../../cryptoaes/js_unpacker.dart';
import '../../../reg_exp_matcher.dart';
import 'm_manga.dart';

class WordSet {
  final List<String> words;

  WordSet(this.words);

  bool anyWordIn(String dateString) {
    return words.any(
      (word) => dateString.toLowerCase().contains(word.toLowerCase()),
    );
  }

  bool startsWith(String dateString) {
    return words.any(
      (word) => dateString.toLowerCase().startsWith(word.toLowerCase()),
    );
  }

  bool endsWith(String dateString) {
    return words.any(
      (word) => dateString.toLowerCase().endsWith(word.toLowerCase()),
    );
  }
}

class MBridge {
  static const List<String> _dateFormats = [
    "yyyy-MM-dd",
    "dd-MM-yyyy",
    "MM/dd/yyyy",
    "dd/MM/yyyy",
    "MMM dd, yyyy",
    "MMMM dd, yyyy",
    "dd MMM yyyy",
    "dd MMMM yyyy",
    "yyyy/MM/dd",
    "EEE, dd MMM yyyy",
    "EEE, dd MMM yyyy HH:mm:ss",
  ];

  static List<String> parseHtml(String html) {
    try {
      final doc = HtmlXPath.html(html);
      final nodes = doc.query('//*');

      List<String> result = [];
      for (var node in nodes.attrs) {
        if (node != null && node.trim().isNotEmpty) {
          result.add(node.trim());
        }
      }

      return result;
    } catch (e) {
      debugPrint('parseHtml error: $e');
      return [];
    }
  }

  static Future<String> evaluateJavascriptViaWebview(
    String url,
    Map<String, String> headers,
    List<String> scripts,
  ) async {
    debugPrint("evaluateJavascriptViaWebview called: $url");

    final Completer<String> resultCompleter = Completer<String>();

    final headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url), headers: headers),

      onWebViewCreated: (ctrl) async {
        for (String script in scripts) {
          final jsResult = await ctrl.evaluateJavascript(source: script);
          if (!resultCompleter.isCompleted) {
            resultCompleter.complete(jsResult?.toString() ?? "");
          }
        }
      },
    );

    await headlessWebView.run();

    return resultCompleter.future;
  }

  static List<String>? xpath(String html, String xpath) {
    List<String> attrs = [];
    try {
      var htmlXPath = HtmlXPath.html(html);
      var query = htmlXPath.query(xpath);
      if (query.nodes.length > 1) {
        for (var element in query.attrs) {
          attrs.add(element!.trim().trimLeft().trimRight());
        }
      } else if (query.nodes.length == 1) {
        String attr = query.attr != null
            ? query.attr!.trim().trimLeft().trimRight()
            : "";
        if (attr.isNotEmpty) {
          attrs = [attr];
        }
      }
      return attrs;
    } catch (_) {
      return [];
    }
  }

  static Status parseStatus(String status, List statusList) {
    for (var element in statusList) {
      Map statusMap = {};
      statusMap = element;
      for (var element in statusMap.entries) {
        if (element.key.toString().toLowerCase().contains(
          status.toLowerCase().trim().trimLeft().trimRight(),
        )) {
          return switch (element.value as int) {
            0 => Status.ongoing,
            1 => Status.completed,
            2 => Status.onHiatus,
            3 => Status.canceled,
            4 => Status.publishingFinished,
            _ => Status.unknown,
          };
        }
      }
    }
    return Status.unknown;
  }

  static String? unpackJs(String code) {
    try {
      final jsPacker = JSPacker(code);
      return jsPacker.unpack() ?? "";
    } catch (_) {
      return "";
    }
  }

  static String? unpackJsAndCombine(String code) {
    try {
      return JsUnpacker.unpackAndCombine(code) ?? "";
    } catch (_) {
      return "";
    }
  }

  static String getMapValue(String source, String attr, bool encode) {
    try {
      var map = json.decode(source) as Map<String, dynamic>;
      if (!encode) {
        return map[attr] != null ? map[attr].toString() : "";
      }
      return map[attr] != null ? jsonEncode(map[attr]) : "";
    } catch (_) {
      return "";
    }
  }

  static List parseDates(
    List value,
    String dateFormat,
    String dateFormatLocale,
  ) {
    List<dynamic> val = [];
    for (var element in value) {
      element = element.toString().trim();
      if (element.isNotEmpty) {
        val.add(element);
      }
    }
    bool error = false;
    List<dynamic> valD = [];
    for (var date in val) {
      String dateStr = "";
      if (error) {
        dateStr = DateTime.now().millisecondsSinceEpoch.toString();
      } else {
        dateStr = parseChapterDate(date, dateFormat, dateFormatLocale, (val) {
          dateFormat = val.$1;
          dateFormatLocale = val.$2;
          error = val.$3;
        });
      }
      valD.add(dateStr);
    }
    return valD;
  }

  static List sortMapList(List list, String value, int type) {
    if (type == 0) {
      list.sort((a, b) => a[value].compareTo(b[value]));
    } else if (type == 1) {
      list.sort((a, b) => b[value].compareTo(a[value]));
    }

    return list;
  }

  static String regExp(
    String expression,
    String source,
    String replace,
    int type,
    int group,
  ) {
    if (type == 0) {
      return expression.replaceAll(RegExp(source), replace);
    }
    return regCustomMatcher(expression, source, group);
  }

  static Future<List<Video>> gogoCdnExtractor(String url) async {
    return await GogoCdnExtractor().videosFromUrl(url);
  }

  static Future<List<Video>> doodExtractor(String url, String? quality) async {
    return await DoodExtractor().videosFromUrl(url, quality: quality);
  }

  static Future<List<Video>> streamWishExtractor(
    String url,
    String prefix,
  ) async {
    return await StreamWishExtractor().videosFromUrl(url, prefix);
  }

  static Future<List<Video>> filemoonExtractor(
    String url,
    String prefix,
    String suffix,
  ) async {
    return await FilemoonExtractor().videosFromUrl(url, prefix, suffix);
  }

  static Map<String, String> decodeHeaders(String? headers) =>
      headers == null ? {} : (jsonDecode(headers) as Map).toMapStringString!;

  static Future<List<Video>> mp4UploadExtractor(
    String url,
    String? headers,
    String prefix,
    String suffix,
  ) async {
    return await Mp4uploadExtractor().videosFromUrl(
      url,
      decodeHeaders(headers),
      prefix: prefix,
      suffix: suffix,
    );
  }

  static final Map<CloudDriveType, QuarkUcExtractor> _extractorCache = {};

  static QuarkUcExtractor _getExtractor(String cookie, CloudDriveType type) {
    if (!_extractorCache.containsKey(type)) {
      QuarkUcExtractor extractor = QuarkUcExtractor();
      extractor.initCloudDrive(cookie, type);
      _extractorCache[type] = extractor;
    }
    return _extractorCache[type]!;
  }

  static Future<List<Map<String, String>>> quarkFilesExtractor(
    List<String> url,
    String cookie,
  ) async {
    var quark = _getExtractor(cookie, CloudDriveType.quark);
    return await quark.videoFilesFromUrl(url);
  }

  static Future<List<Video>> quarkVideosExtractor(
    String url,
    String cookie,
  ) async {
    var quark = _getExtractor(cookie, CloudDriveType.quark);
    return await quark.videosFromUrl(url);
  }

  static Future<List<Map<String, String>>> ucFilesExtractor(
    List<String> url,
    String cookie,
  ) async {
    var uc = _getExtractor(cookie, CloudDriveType.uc);
    return await uc.videoFilesFromUrl(url);
  }

  static Future<List<Video>> ucVideosExtractor(
    String url,
    String cookie,
  ) async {
    var uc = _getExtractor(cookie, CloudDriveType.uc);
    return await uc.videosFromUrl(url);
  }

  static Future<List<Video>> streamTapeExtractor(
    String url,
    String? quality,
  ) async {
    return await StreamTapeExtractor().videosFromUrl(
      url,
      quality: quality ?? "StreamTape",
    );
  }

  static String substringAfter(String text, String pattern) {
    return text.substringAfter(pattern);
  }

  static String substringBefore(String text, String pattern) {
    return text.substringBefore(pattern);
  }

  static String substringBeforeLast(String text, String pattern) {
    return text.substringBeforeLast(pattern);
  }

  static String substringAfterLast(String text, String pattern) {
    return text.split(pattern).last;
  }

  static String parseChapterDate(
    String date,
    String dateFormat,
    String dateFormatLocale,
    Function((String, String, bool)) newLocale,
  ) {
    int parseRelativeDate(String date) {
      final number = int.tryParse(RegExp(r"(\d+)").firstMatch(date)!.group(0)!);
      if (number == null) return 0;
      final cal = DateTime.now();

      if (WordSet([
        "hari",
        "gün",
        "jour",
        "día",
        "dia",
        "day",
        "วัน",
        "ngày",
        "giorni",
        "أيام",
        "天",
      ]).anyWordIn(date)) {
        return cal.subtract(Duration(days: number)).millisecondsSinceEpoch;
      } else if (WordSet([
        "jam",
        "saat",
        "heure",
        "hora",
        "hour",
        "ชั่วโมง",
        "giờ",
        "ore",
        "ساعة",
        "小时",
      ]).anyWordIn(date)) {
        return cal.subtract(Duration(hours: number)).millisecondsSinceEpoch;
      } else if (WordSet([
        "menit",
        "dakika",
        "min",
        "minute",
        "minuto",
        "นาที",
        "دقائق",
      ]).anyWordIn(date)) {
        return cal.subtract(Duration(minutes: number)).millisecondsSinceEpoch;
      } else if (WordSet([
        "detik",
        "segundo",
        "second",
        "วินาที",
        "sec",
      ]).anyWordIn(date)) {
        return cal.subtract(Duration(seconds: number)).millisecondsSinceEpoch;
      } else if (WordSet(["week", "semana"]).anyWordIn(date)) {
        return cal.subtract(Duration(days: number * 7)).millisecondsSinceEpoch;
      } else if (WordSet(["month", "mes"]).anyWordIn(date)) {
        return cal.subtract(Duration(days: number * 30)).millisecondsSinceEpoch;
      } else if (WordSet(["year", "año"]).anyWordIn(date)) {
        return cal
            .subtract(Duration(days: number * 365))
            .millisecondsSinceEpoch;
      } else {
        return 0;
      }
    }

    try {
      if (WordSet(["yesterday", "يوم واحد"]).startsWith(date)) {
        DateTime cal = DateTime.now().subtract(const Duration(days: 1));
        cal = DateTime(cal.year, cal.month, cal.day);
        return cal.millisecondsSinceEpoch.toString();
      } else if (WordSet(["today"]).startsWith(date)) {
        DateTime cal = DateTime.now();
        cal = DateTime(cal.year, cal.month, cal.day);
        return cal.millisecondsSinceEpoch.toString();
      } else if (WordSet(["يومين"]).startsWith(date)) {
        DateTime cal = DateTime.now().subtract(const Duration(days: 2));
        cal = DateTime(cal.year, cal.month, cal.day);
        return cal.millisecondsSinceEpoch.toString();
      } else if (WordSet(["ago", "atrás", "önce", "قبل"]).endsWith(date)) {
        return parseRelativeDate(date).toString();
      } else if (WordSet(["hace"]).startsWith(date)) {
        return parseRelativeDate(date).toString();
      } else if (date.contains(RegExp(r"\d(st|nd|rd|th)"))) {
        final cleanedDate = date
            .split(" ")
            .map(
              (it) => it.contains(RegExp(r"\d\D\D"))
                  ? it.replaceAll(RegExp(r"\D"), "")
                  : it,
            )
            .join(" ");
        return DateFormat(
          dateFormat,
          dateFormatLocale,
        ).parse(cleanedDate).millisecondsSinceEpoch.toString();
      } else {
        return DateFormat(
          dateFormat,
          dateFormatLocale,
        ).parse(date).millisecondsSinceEpoch.toString();
      }
    } catch (e) {
      final supportedLocales = DateFormat.allLocalesWithSymbols();

      for (var locale in supportedLocales) {
        for (var dateFormat in _dateFormats) {
          newLocale((dateFormat, locale, false));
          try {
            initializeDateFormatting(locale);
            if (WordSet(["yesterday", "يوم واحد"]).startsWith(date)) {
              DateTime cal = DateTime.now().subtract(const Duration(days: 1));
              cal = DateTime(cal.year, cal.month, cal.day);
              return cal.millisecondsSinceEpoch.toString();
            } else if (WordSet(["today"]).startsWith(date)) {
              DateTime cal = DateTime.now();
              cal = DateTime(cal.year, cal.month, cal.day);
              return cal.millisecondsSinceEpoch.toString();
            } else if (WordSet(["يومين"]).startsWith(date)) {
              DateTime cal = DateTime.now().subtract(const Duration(days: 2));
              cal = DateTime(cal.year, cal.month, cal.day);
              return cal.millisecondsSinceEpoch.toString();
            } else if (WordSet([
              "ago",
              "atrás",
              "önce",
              "قبل",
            ]).endsWith(date)) {
              return parseRelativeDate(date).toString();
            } else if (WordSet(["hace"]).startsWith(date)) {
              return parseRelativeDate(date).toString();
            } else if (date.contains(RegExp(r"\d(st|nd|rd|th)"))) {
              final cleanedDate = date
                  .split(" ")
                  .map(
                    (it) => it.contains(RegExp(r"\d\D\D"))
                        ? it.replaceAll(RegExp(r"\D"), "")
                        : it,
                  )
                  .join(" ");
              return DateFormat(
                dateFormat,
                locale,
              ).parse(cleanedDate).millisecondsSinceEpoch.toString();
            } else {
              return DateFormat(
                dateFormat,
                locale,
              ).parse(date).millisecondsSinceEpoch.toString();
            }
          } catch (_) {}
        }
      }
      newLocale((dateFormat, dateFormatLocale, true));
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  static String deobfuscateJsPassword(String inputString) {
    return Deobfuscator.deobfuscateJsPassword(inputString);
  }

  static Future<List<Video>> sibnetExtractor(String url, String prefix) async {
    return await SibnetExtractor().videosFromUrl(url, prefix: prefix);
  }

  static Future<List<Video>> sendVidExtractor(
    String url,
    String? headers,
    String prefix,
  ) async {
    return await SendvidExtractor(
      decodeHeaders(headers),
    ).videosFromUrl(url, prefix: prefix);
  }

  static Future<List<Video>> myTvExtractor(String url) async {
    return await MytvExtractor().videosFromUrl(url);
  }

  static Future<List<Video>> okruExtractor(String url) async {
    return await OkruExtractor().videosFromUrl(url);
  }

  static Future<List<Video>> yourUploadExtractor(
    String url,
    String? headers,
    String? name,
    String prefix,
  ) async {
    return await YourUploadExtractor().videosFromUrl(
      url,
      decodeHeaders(headers),
      prefix: prefix,
      name: name ?? "YourUpload",
    );
  }

  static Future<List<Video>> voeExtractor(String url, String? quality) async {
    return await VoeExtractor().videosFromUrl(url, quality);
  }

  static Future<List<Video>> vidBomExtractor(String url) async {
    return await VidBomExtractor().videosFromUrl(url);
  }

  static Future<List<Video>> streamlareExtractor(
    String url,
    String prefix,
    String suffix,
  ) async {
    return await StreamlareExtractor().videosFromUrl(
      url,
      prefix: prefix,
      suffix: suffix,
    );
  }

  static Future<String> encryptAESCryptoJS(
    String plainText,
    String passphrase,
  ) async {
    return CryptoAES.encryptAESCryptoJS(plainText, passphrase);
  }

  static Future<String> decryptAESCryptoJS(
    String encrypted,
    String passphrase,
  ) async {
    return CryptoAES.decryptAESCryptoJS(encrypted, passphrase);
  }

  static Video toVideo(
    String url,
    String quality,
    String originalUrl,
    String? headers,
    List<Track>? subtitles,
    List<Track>? audios,
  ) {
    return Video(
      url,
      quality,
      originalUrl,
      headers: decodeHeaders(headers),
      subtitles: subtitles ?? [],
      audios: audios ?? [],
    );
  }

  static String cryptoHandler(
    String text,
    String ivStr,
    String secretKeyStr,
    bool doEncrypt,
  ) {
    try {
      final key = Uint8List.fromList(utf8.encode(secretKeyStr).sublist(0, 32));
      final iv = Uint8List.fromList(utf8.encode(ivStr).sublist(0, 16));

      final aes = AES(key);

      if (doEncrypt) {
        final data = Uint8List.fromList(utf8.encode(text));
        final padded = _pkcs7Pad(data);

        final encrypted = _aesCbcEncrypt(aes, padded, iv);
        return base64.encode(encrypted);
      } else {
        final cipherText = base64.decode(text);
        final decrypted = _aesCbcDecrypt(aes, cipherText, iv);
        final unpadded = _pkcs7Unpad(decrypted);
        return utf8.decode(unpadded);
      }
    } catch (_) {
      return text;
    }
  }

  static Uint8List _aesCbcEncrypt(AES aes, Uint8List data, Uint8List iv) {
    final out = Uint8List(data.length);
    var prev = iv;

    for (var i = 0; i < data.length; i += 16) {
      final block = data.sublist(i, i + 16);
      final xored = _xor(block, prev);

      final cipherBlock = Uint8List.fromList(aes.encryptBlock(xored));
      out.setRange(i, i + 16, cipherBlock);

      prev = cipherBlock;
    }
    return out;
  }

  static Uint8List _aesCbcDecrypt(AES aes, Uint8List data, Uint8List iv) {
    final out = Uint8List(data.length);
    var prev = iv;

    for (var i = 0; i < data.length; i += 16) {
      final block = data.sublist(i, i + 16);

      final plainBlock = Uint8List.fromList(aes.decryptBlock(block));
      final xored = _xor(plainBlock, prev);

      out.setRange(i, i + 16, xored);
      prev = block;
    }
    return out;
  }

  static Uint8List _xor(Uint8List a, Uint8List b) {
    final res = Uint8List(a.length);
    for (var i = 0; i < a.length; i++) {
      res[i] = a[i] ^ b[i];
    }
    return res;
  }

  static Uint8List _pkcs7Pad(Uint8List data) {
    final padLen = 16 - (data.length % 16);
    return Uint8List.fromList([...data, ...List.filled(padLen, padLen)]);
  }

  static Uint8List _pkcs7Unpad(Uint8List data) {
    final padLen = data.last;
    return data.sublist(0, data.length - padLen);
  }
}
