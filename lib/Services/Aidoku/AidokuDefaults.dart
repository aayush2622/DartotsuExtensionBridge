import 'dart:convert';

import 'package:archive/archive.dart';

import 'AidokuSettings.dart';
import 'Postcard.dart';

const aidokuListingsKey = '__listings';
const aidokuDefaultsVersionKey = '__v';
const _defaultsVersion = '3';

Map<String, String>? extractAidokuDefaults(List<int> aixBytes) {
  try {
    final archive = ZipDecoder().decodeBytes(aixBytes);
    Map<String, String>? out;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name.endsWith('settings.json')) {
        final text = utf8.decode(file.content);
        out = {...parseAidokuDefaults(text), ...?out, aidokuSettingsKey: text};
      } else if (file.name.endsWith('source.json')) {
        final text = utf8.decode(file.content);
        final listings = _listingNames(text);
        final url = _baseUrl(text);
        out = {
          ...?out,
          if (listings.isNotEmpty) aidokuListingsKey: jsonEncode(listings),
          if (url != null && !(out?.containsKey('url') ?? false))
            'url': base64Encode(
              (PostcardWriter()..writeString(url)).takeBytes(),
            ),
        };
      }
    }
    return {...?out, aidokuDefaultsVersionKey: _defaultsVersion};
  } catch (_) {}
  return null;
}

String? _baseUrl(String json) {
  try {
    final decoded = jsonDecode(json);
    final info = decoded is Map ? decoded['info'] : null;
    if (info is! Map) return null;
    final urls = info['urls'];
    if (urls is List && urls.isNotEmpty && urls.first is String) {
      return urls.first as String;
    }
    final url = info['url'];
    return url is String && url.isNotEmpty ? url : null;
  } catch (_) {
    return null;
  }
}

List<List<String>> _listingNames(String json) {
  try {
    final decoded = jsonDecode(json);
    final listings = decoded is Map ? decoded['listings'] : null;
    if (listings is! List) return const [];
    return [
      for (final l in listings)
        if (l is String)
          [l, l]
        else if (l is Map && l['name'] is String)
          [(l['id'] ?? l['name']).toString(), l['name'] as String],
    ];
  } catch (_) {
    return const [];
  }
}

Map<String, String> parseAidokuDefaults(String json) {
  final out = <String, String>{};
  try {
    _collect(jsonDecode(json), out);
  } catch (_) {}
  return out;
}

void _collect(Object? node, Map<String, String> out) {
  if (node is List) {
    for (final item in node) {
      _collect(item, out);
    }
    return;
  }
  if (node is! Map) return;
  final key = node['key'];
  if (key is String && node.containsKey('default')) {
    final payload = _encode(node['default']);
    if (payload != null) out[key] = base64Encode(payload);
  }
  _collect(node['items'], out);
}

List<int>? _encode(Object? value) {
  final writer = PostcardWriter();
  if (value is bool) {
    writer.writeBool(value);
  } else if (value is String) {
    writer.writeString(value);
  } else if (value is List && value.every((e) => e is String)) {
    writer.writeVec<String>(value.cast<String>(), writer.writeString);
  } else {
    return null;
  }
  return writer.takeBytes();
}

String? aidokuLanguageDefault(List<String> languages, String? lang) {
  final options = [...languages, if (lang != null && lang.isNotEmpty) lang];
  if (options.isEmpty) return null;
  final picked = options.contains('en') ? 'en' : options.first;
  final writer = PostcardWriter();
  writer.writeVec<String>([picked], writer.writeString);
  return base64Encode(writer.takeBytes());
}
