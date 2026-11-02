import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../Models/Page.dart';
import 'DownloadCancel.dart';
import 'DownloadPaths.dart';
import 'FileFetcher.dart';

const imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'avif',
  'heic',
  'bmp',
  'jxl',
  'tif',
  'tiff',
};

String? sniffImageExtension(List<int> b) {
  bool at(int i, String text) {
    if (b.length < i + text.length) return false;
    for (var k = 0; k < text.length; k++) {
      if (b[i + k] != text.codeUnitAt(k)) return false;
    }
    return true;
  }

  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'jpg';
  }
  if (b.length >= 4 && b[0] == 0x89 && at(1, 'PNG')) return 'png';
  if (at(0, 'GIF8')) return 'gif';
  if (at(0, 'RIFF') && at(8, 'WEBP')) return 'webp';
  if (at(4, 'ftyp')) {
    if (at(8, 'avif') || at(8, 'avis')) return 'avif';
    if (at(8, 'heic') || at(8, 'heix') || at(8, 'mif1')) return 'heic';
  }
  if (at(0, 'BM')) return 'bmp';
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0x0A) return 'jxl';
  if (b.length >= 12 && b[0] == 0 && b[3] == 0x0C && at(4, 'JXL ')) {
    return 'jxl';
  }
  if (at(0, 'II*') || at(0, 'MM')) return 'tif';
  return null;
}

Future<String?> _sniff(File file) async {
  final handle = await file.open();
  try {
    return sniffImageExtension(await handle.read(16));
  } finally {
    await handle.close();
  }
}

Future<File?> _existing(Directory dir, String base) async {
  await for (final entity in dir.list()) {
    if (entity is File &&
        p.basenameWithoutExtension(entity.path) == base &&
        !entity.path.endsWith('.part')) {
      return entity;
    }
  }
  return null;
}

Future<void> downloadPages(
  List<PageUrl> pages,
  Directory dir, {
  required DownloadCancel cancel,
  required void Function(int done, int total) onProgress,
  int workers = 2,
}) async {
  await dir.create(recursive: true);
  final width = pages.length.toString().length.clamp(3, 6);
  var next = 0;
  var done = 0;
  Object? failure;

  Future<void> worker() async {
    while (failure == null) {
      final i = next++;
      if (i >= pages.length) return;
      final page = pages[i];
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final base = (i + 1).toString().padLeft(width, '0');
      try {
        if (await _existing(dir, base) == null) {
          final urlExt = extensionOf(page.url, fallback: '');
          final provisional = File(p.join(dir.path, '$base.tmp'));
          final fetch = page.fetch;
          if (fetch != null) {
            await provisional.writeAsBytes(await fetch(), flush: true);
          } else {
            await fetchWithRetry(
              () => fetchFile(
                url: page.url,
                target: provisional,
                cancel: cancel,
                headers: page.headers,
                onProgress: (_, _) {},
              ),
              cancel: cancel,
            );
          }
          final process = page.process;
          if (process != null) {
            final processed = await process(await provisional.readAsBytes());
            await provisional.writeAsBytes(processed, flush: true);
          }
          final sniffed = await _sniff(provisional);
          final ext =
              sniffed ?? (imageExtensions.contains(urlExt) ? urlExt : null);
          if (ext == null) {
            await provisional.delete();
            throw FormatException('Page ${i + 1} is not an image');
          }
          await provisional.rename(p.join(dir.path, '$base.$ext'));
        }
        done++;
        onProgress(done, pages.length);
      } catch (e) {
        failure ??= e;
      }
    }
  }

  await Future.wait([for (var k = 0; k < workers; k++) worker()]);
  final error = failure;
  if (error != null) throw error;
}

List<File> pageFilesIn(Directory dir) {
  if (!dir.existsSync()) return const [];
  final files = [
    for (final entity in dir.listSync())
      if (entity is File &&
          imageExtensions.contains(
            p.extension(entity.path).replaceFirst('.', '').toLowerCase(),
          ))
        entity,
  ]..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  return files;
}

final _imgTag = RegExp(
  r'''(<img\b[^>]*?\b(?:data-src|src)\s*=\s*)(["'])(https?://[^"']+)\2''',
  caseSensitive: false,
);

Future<String> localizeNovelImages(
  String html,
  Directory files, {
  required DownloadCancel cancel,
}) async {
  final matches = _imgTag.allMatches(html).toList();
  if (matches.isEmpty) return html;
  await files.create(recursive: true);
  final replaced = <String, String>{};
  for (final (i, m) in matches.indexed) {
    final url = m.group(3)!;
    if (replaced.containsKey(url)) continue;
    final base = (i + 1).toString().padLeft(3, '0');
    try {
      final provisional = File(p.join(files.path, '$base.tmp'));
      await fetchWithRetry(
        () => fetchFile(
          url: url,
          target: provisional,
          cancel: cancel,
          onProgress: (_, _) {},
        ),
        cancel: cancel,
      );
      final ext = await _sniff(provisional);
      if (ext == null) {
        await provisional.delete();
        continue;
      }
      final target = File(p.join(files.path, '$base.$ext'));
      await provisional.rename(target.path);
      replaced[url] = target.path;
    } catch (_) {
      if (cancel.isCancelled) rethrow;
    }
  }
  return html.replaceAllMapped(_imgTag, (m) {
    final local = replaced[m.group(3)!];
    return local == null
        ? m.group(0)!
        : '${m.group(1)}${m.group(2)}$local${m.group(2)}';
  });
}
