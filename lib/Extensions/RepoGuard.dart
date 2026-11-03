import 'dart:convert';

/// A repository that can't be added, with a message meant for the user.
class RepoException implements Exception {
  const RepoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The repository formats the bridge knows, used to tell the user which
/// extension manager a link belongs to when it's added to the wrong one.
enum RepoFormat {
  tachiyomi('Aniyomi / Tsundoku'),
  iReader('IReader'),
  cloudStream('CloudStream'),
  mangayomi('Mangayomi'),
  sora('Sora'),
  lnReader('LNReader'),
  legado('Legado'),
  aidoku('Aidoku'),
  kotatsu('Kotatsu'),
  shosetsu('Shosetsu');

  const RepoFormat(this.label);

  final String label;
}

/// Cleans up a repository link typed or pasted by the user: trims it, adds
/// `https://` to a bare host, drops trailing slashes and turns a GitHub file
/// page (`github.com/<owner>/<repo>/blob/<branch>/<path>`) into its raw file.
///
/// Throws [RepoException] when it isn't an http(s) link.
String normalizeRepoUrl(String input) {
  var text = input.trim().replaceAll(RegExp(r'''^["'<]+|["'>]+$'''), '');
  if (!text.contains('://') &&
      RegExp(r'^[\w-]+(\.[\w-]+)+(/|$)').hasMatch(text)) {
    text = 'https://$text';
  }

  final uri = Uri.tryParse(text);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    throw RepoException(
      input.trim().isEmpty
          ? 'Enter a repository link.'
          : '"${input.trim()}" is not a valid link. A repository link starts with https://',
    );
  }

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (uri.host == 'github.com' &&
      segments.length > 4 &&
      segments[2] == 'blob') {
    return Uri.https(
      'raw.githubusercontent.com',
      [segments[0], segments[1], ...segments.skip(3)].join('/'),
    ).toString();
  }

  return text.replaceAll(RegExp(r'/+$'), '');
}

/// Whether [bytes] are an HTML page rather than a repository index.
bool looksLikeWebPage(List<int> bytes) {
  final head = _head(bytes).trimLeft().toLowerCase();
  return head.startsWith('<!doctype html') ||
      head.startsWith('<html') ||
      (head.startsWith('<') && head.contains('<body'));
}

/// The repository format [bytes] (a downloaded index) are in, or null when
/// it isn't one the bridge knows.
RepoFormat? detectRepoFormat(List<int> bytes, {String? url}) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04) {
    return RepoFormat.kotatsu;
  }
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    return RepoFormat.tachiyomi;
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } catch (_) {
    return url != null && url.endsWith('.pb') ? RepoFormat.tachiyomi : null;
  }

  if (decoded is Map) {
    if (decoded['pluginLists'] is List) return RepoFormat.cloudStream;
    if (decoded.containsKey('sourceName')) return RepoFormat.sora;
    if (decoded.containsKey('scripts') && decoded.containsKey('libraries')) {
      return RepoFormat.shosetsu;
    }
    for (final key in const ['sources', 'data', 'bookSourceList']) {
      final list = decoded[key];
      if (list is List) return _formatOfEntries(list);
    }
    final values = decoded.values.whereType<Map>();
    if (values.isNotEmpty && values.first.containsKey('sourceName')) {
      return RepoFormat.sora;
    }
    return null;
  }

  return decoded is List ? _formatOfEntries(decoded) : null;
}

RepoFormat? _formatOfEntries(List<dynamic> entries) {
  final entry = entries.whereType<Map>().firstOrNull;
  if (entry == null) return null;

  if (entry.containsKey('pkg') && entry.containsKey('apk')) {
    return '${entry['pkg']}'.startsWith('ireader.')
        ? RepoFormat.iReader
        : RepoFormat.tachiyomi;
  }
  if (entry.containsKey('internalName')) return RepoFormat.cloudStream;
  if (entry.containsKey('bookSourceUrl')) return RepoFormat.legado;
  if (entry.containsKey('downloadURL') || entry.containsKey('iconURL')) {
    return RepoFormat.aidoku;
  }
  if (entry.containsKey('sourceName')) return RepoFormat.sora;
  if (entry.containsKey('sourceCodeUrl') ||
      entry.containsKey('sourceCodeLanguage') ||
      entry.containsKey('isManga')) {
    return RepoFormat.mangayomi;
  }
  if (entry.containsKey('site') && '${entry['url']}'.endsWith('.js')) {
    return RepoFormat.lnReader;
  }
  return null;
}

String _head(List<int> bytes) => utf8.decode(
  bytes.length > 2048 ? bytes.sublist(0, 2048) : bytes,
  allowMalformed: true,
);
