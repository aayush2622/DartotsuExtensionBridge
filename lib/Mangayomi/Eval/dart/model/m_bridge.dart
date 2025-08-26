import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:xml/xml.dart';
import 'video.dart';
import '../../../string_extensions.dart';
import 'package:intl/date_symbol_data_local.dart';
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
import '../../../reg_exp_matcher.dart';
import 'm_manga.dart';

class WordSet {
  final List<String> words;
  WordSet(this.words);

  bool anyWordIn(String text) => words.any((w) => text.containsIgnoreCase(w));
  bool startsWith(String text) =>
      words.any((w) => text.startsWithIgnoreCase(w));
  bool endsWith(String text) => words.any((w) => text.endsWithIgnoreCase(w));
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
  // --- String helper functions ---
  static String regHref(String input) => regHrefMatcher(input);
  static String regDataSrc(String input) => regDataSrcMatcher(input);
  static String regSrc(String input) => regSrcMatcher(input);
  static String regImg(String input) => regImgMatcher(input);

  static String regCustom(String input, String pattern, int group) =>
      regCustomMatcher(input, pattern, group);

  static String padIndex(int index) => padIndex(index);

  static final Map<CloudDriveType, QuarkUcExtractor> _extractorCache = {};

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

  // HTML Parsing
  static List<String> parseHtml(String html) {
    try {
      var document = html_parser.parse(html);
      return document
          .querySelectorAll('*')
          .map((node) => node.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('parseHtml error: $e');
      return [];
    }
  }

  // WebView JS Evaluation
  static Future<String> evaluateJavascriptViaWebview(
    String url,
    Map<String, String> headers,
    List<String> scripts,
  ) async {
    final completer = Completer<String>();
    final webview = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url), headers: headers),
      onWebViewCreated: (ctrl) async {
        for (var script in scripts) {
          final res = await ctrl.evaluateJavascript(source: script);
          if (!completer.isCompleted) completer.complete(res?.toString() ?? "");
        }
      },
    );
    await webview.run();
    return completer.future;
  }

  // XPath
  static List<String> xpath(String html, String path) {
    try {
      final document = XmlDocument.parse(html);
      return document.findAllElements(path).map((n) => n.text.trim()).toList();
    } catch (_) {
      return [];
    }
  }

  // Status Parsing
  static Status parseStatus(String status, List statusList) {
    for (var s in statusList) {
      for (var entry in (s as Map).entries) {
        if (entry.key.toString().toLowerCase().contains(
          status.toLowerCase().trim(),
        )) {
          return switch (entry.value as int) {
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

  // JS Unpacker
  static Future<String> unpackJs(String code) async {
    final qjs = QuickJsRuntime2();
    try {
      final result = qjs.evaluate(code);
      return result.toString();
    } catch (_) {
      return "";
    } finally {
      qjs.dispose();
    }
  }

  static Future<String> unpackJsAndCombine(String code) async {
    final qjs = QuickJsRuntime2();
    try {
      final result = qjs.evaluate('''
      (() => {
        const codeToUnpack = ${jsonEncode(code)};
        return JsUnpacker.unpackAndCombine(codeToUnpack) ?? "";
      })()
    ''');
      return result.toString();
    } catch (_) {
      return "";
    } finally {
      qjs.dispose();
    }
  }

  // Header Decoder
  static Map<String, String> decodeHeaders(String? headers) {
    if (headers == null) return {};
    final map = jsonDecode(headers) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k.toString(), v.toString()));
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

  // Extractors

  static Future<List<Video>> gogoCdnExtractor(String url) async =>
      await GogoCdnExtractor().videosFromUrl(url);
  static Future<List<Video>> doodExtractor(String url, String? q) async =>
      await DoodExtractor().videosFromUrl(url, quality: q);
  static Future<List<Video>> streamWishExtractor(
    String url,
    String prefix,
  ) async => await StreamWishExtractor().videosFromUrl(url, prefix);
  static Future<List<Video>> filemoonExtractor(
    String url,
    String prefix,
    String suffix,
  ) async => await FilemoonExtractor().videosFromUrl(url, prefix, suffix);
  static Future<List<Video>> mp4UploadExtractor(
    String url,
    String? headers,
    String prefix,
    String suffix,
  ) async => await Mp4uploadExtractor().videosFromUrl(
    url,
    decodeHeaders(headers),
    prefix: prefix,
    suffix: suffix,
  );

  // Private helper to get or initialize an extractor
  static QuarkUcExtractor _getExtractor(String cookie, CloudDriveType type) {
    if (!_extractorCache.containsKey(type)) {
      final extractor = QuarkUcExtractor();
      extractor.initCloudDrive(cookie, type);
      _extractorCache[type] = extractor;
    }
    return _extractorCache[type]!;
  }

  // Quark/UC Extractors
  static Future<List<Video>> quarkVideosExtractorStatic(
    String url,
    String cookie,
  ) async {
    final extractor = QuarkUcExtractor();
    await extractor.initCloudDrive(cookie, CloudDriveType.quark);
    return extractor.videosFromUrl(url);
  }

  static Future<List<Video>> ucVideosExtractorStatic(
    String url,
    String cookie,
  ) async {
    final extractor = QuarkUcExtractor();
    await extractor.initCloudDrive(cookie, CloudDriveType.uc);
    return extractor.videosFromUrl(url);
  }

  static Future<List<Map<String, String>>> quarkFilesExtractor(
    List<String> url,
    String cookie,
  ) async {
    var quark = _getExtractor(cookie, CloudDriveType.quark);
    return await quark.videoFilesFromUrl(url);
  }

  Future<List<Video>> quarkVideosExtractorInstance(
    String url,
    String cookie,
  ) async {
    final extractor = QuarkUcExtractor();
    await extractor.initCloudDrive(cookie, CloudDriveType.quark);
    return extractor.videosFromUrl(url);
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
  ) async => await StreamTapeExtractor().videosFromUrl(
    url,
    quality: quality ?? "StreamTape",
  );

  // --- Chapter date parser ---
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
      } else if (WordSet(["ago", "atrás", "önce", "قبل"]).endsWith(date) ||
          WordSet(["hace"]).startsWith(date)) {
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

  static Future<List<Video>> sibnetExtractor(String url, String prefix) async =>
      await SibnetExtractor().videosFromUrl(url, prefix: prefix);
  static Future<List<Video>> sendVidExtractor(
    String url,
    String? headers,
    String prefix,
  ) async => await SendvidExtractor(
    decodeHeaders(headers),
  ).videosFromUrl(url, prefix: prefix);
  static Future<List<Video>> myTvExtractor(String url) async =>
      await MytvExtractor().videosFromUrl(url);
  static Future<List<Video>> okruExtractor(String url) async =>
      await OkruExtractor().videosFromUrl(url);
  static Future<List<Video>> quarkUcExtractor(String url) async =>
      await QuarkUcExtractor().videosFromUrl(url);
  static Future<List<Video>> yourUploadExtractor(
    String url,
    String? headers,
    String? name,
    String prefix,
  ) async => await YourUploadExtractor().videosFromUrl(
    url,
    decodeHeaders(headers),
    prefix: prefix,
    name: name ?? "YourUpload",
  );
  static Future<List<Video>> voeExtractor(String url, String? quality) async =>
      await VoeExtractor().videosFromUrl(url, quality);
  static Future<List<Video>> vidBomExtractor(String url) async =>
      await VidBomExtractor().videosFromUrl(url);
  static Future<List<Video>> streamlareExtractor(
    String url,
    String prefix,
    String suffix,
  ) async => await StreamlareExtractor().videosFromUrl(
    url,
    prefix: prefix,
    suffix: suffix,
  );

  /// Handles generic CryptoJS-like logic
  static String cryptoHandler(String data, String key, String iv, String algo) {
    if (algo.toUpperCase() == 'AES') {
      return CryptoAES.encryptAESCryptoJS(data, key);
    } else if (algo.toUpperCase() == 'SHA256') {
      return crypto.sha256.convert(utf8.encode(data)).toString();
    }
    return data;
  }

  // Video Constructor
  static Video toVideo(
    String url,
    String quality,
    String originalUrl,
    String? headers,
    List<Track>? subs,
    List<Track>? audios,
  ) => Video(
    url,
    quality,
    originalUrl,
    headers: decodeHeaders(headers),
    subtitles: subs ?? [],
    audios: audios ?? [],
  );

  /// AES Encryption (CryptoAES wrapper)
  static String encryptAESCryptoJS(String data, String key) {
    return CryptoAES.encryptAESCryptoJS(data, key);
  }

  /// AES Decryption (CryptoAES wrapper)
  static String decryptAESCryptoJS(String data, String key) {
    return CryptoAES.decryptAESCryptoJS(data, key);
  }

  /// Deobfuscates JS password: reverse + base64 decode
  static String deobfuscateJsPassword(String obfuscated) {
    try {
      final reversed = obfuscated.split('').reversed.join();
      return utf8.decode(base64Decode(reversed));
    } catch (_) {
      return obfuscated;
    }
  }

  Future<List<Video>> quarkVideosExtractor(String url, String cookie) async {
    final extractor = QuarkUcExtractor();
    await extractor.initCloudDrive(cookie, CloudDriveType.quark);
    return extractor.videosFromUrl(url);
  }
}
