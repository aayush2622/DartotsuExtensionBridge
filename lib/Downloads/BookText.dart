import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'Archives.dart';
import 'DownloadPaths.dart';

Future<String> readBookText(String path, {String? cacheDir}) async {
  final file = File(path);
  if (!isBookFile(path)) return file.readAsString();
  final dir = cacheDir ?? archiveCache(path);
  final cache = File(p.join(dir, 'book2.html'));
  if (cache.existsSync() &&
      cache.lastModifiedSync().isAfter(file.lastModifiedSync())) {
    return cache.readAsString();
  }
  final html = await epubToHtml(path, dir);
  await Directory(dir).create(recursive: true);
  await cache.writeAsString(html);
  return html;
}

Future<String> bookCacheDir(String path) async {
  final root = await getApplicationCacheDirectory();
  final modified = File(path).statSync().modified.millisecondsSinceEpoch;
  final key = '${path.hashCode.toUnsigned(32).toRadixString(16)}-$modified';
  return p.join(root.path, 'books', key);
}
