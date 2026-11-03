import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../ExtensionBridge.dart';
import '../Logger.dart';

final _illegal = RegExp(r'[<>:"/\\|?*\x00-\x1f]');

String safeName(String input) {
  var name = input
      .replaceAll(_illegal, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^\.+|\.+$'), '')
      .trim();
  if (name.isEmpty) name = 'Untitled';
  return name.length > 80 ? name.substring(0, 80).trim() : name;
}

String numberLabel(double number) => number % 1 == 0
    ? number.toInt().toString().padLeft(3, '0')
    : number.toString().padLeft(5, '0');

String unitFileName({
  required bool video,
  required double number,
  required String unitKey,
  required String title,
}) {
  final base = '${video ? 'Episode' : 'Chapter'} ${numberLabel(number)}';
  if (!unitKey.contains('~')) return base;
  final name = safeName(title);
  final suffix = name == 'Untitled'
      ? unitKey.split('~').last
      : name.length > 40
      ? name.substring(0, 40).trim()
      : name;
  return '$base - $suffix';
}

String archiveCache(String file) =>
    p.join(p.dirname(file), '.archives', p.basenameWithoutExtension(file));

String extensionOf(String url, {String fallback = 'mp4'}) {
  final path = Uri.tryParse(url)?.path ?? url;
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  return RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext) ? ext : fallback;
}

const videoExtensions = {
  'mp4',
  'mkv',
  'avi',
  'mov',
  'webm',
  'm4v',
  'ts',
  'm2ts',
  'mts',
  'flv',
  'wmv',
  'ogv',
  '3gp',
  'mpg',
  'mpeg',
  'divx',
  'vob',
  'asf',
  'rmvb',
  'f4v',
};

const subtitleExtensions = {'srt', 'vtt', 'ass', 'ssa', 'sub', 'sbv', 'ttml'};

class DownloadPaths {
  DownloadPaths._();

  static Directory? _root;
  static final _mediaDirs = <String, Directory>{};

  static void reset() {
    _root = null;
    _mediaDirs.clear();
  }

  static Future<void> _noMedia(Directory dir) async {
    if (!Platform.isAndroid) return;
    final file = File(p.join(dir.path, '.nomedia'));
    try {
      if (!await file.exists()) await file.create();
    } catch (e) {
      Logger.log('.nomedia failed: $e');
    }
  }

  static Future<Directory> root() async {
    final cached = _root;
    if (cached != null && await cached.exists()) return cached;
    final dir =
        await DartotsuExtensionBridge.context.getDirectory(
          subPath: 'downloads',
          useCustomPath: true,
          useSystemPath: false,
        ) ??
        Directory(p.join(Directory.systemTemp.path, 'downloads'));
    await dir.create(recursive: true);
    await _noMedia(dir);
    return _root = dir;
  }

  static Future<bool> _owns(
    Directory dir,
    String serviceId,
    String mediaId,
  ) async {
    final file = File(p.join(dir.path, 'media.json'));
    if (!await file.exists()) return true;
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map &&
          json['service'] == serviceId &&
          '${json['id']}' == mediaId;
    } catch (_) {
      return true;
    }
  }

  static Future<Directory> mediaDir(
    String serviceId,
    String mediaId,
    String title,
  ) async {
    final slot = '$serviceId/$mediaId';
    final cached = _mediaDirs[slot];
    if (cached != null) {
      if (!await cached.exists()) await cached.create(recursive: true);
      return cached;
    }
    final top = await root();
    final name = safeName(title);
    final legacy = Directory(p.join(top.path, name));
    if (await File(p.join(legacy.path, 'media.json')).exists() &&
        await _owns(legacy, serviceId, mediaId)) {
      await _noMedia(legacy);
      return _mediaDirs[slot] = legacy;
    }
    final base = Directory(p.join(top.path, safeName(serviceId)));
    await base.create(recursive: true);
    await _noMedia(base);
    var dir = Directory(p.join(base.path, name));
    if (!await _owns(dir, serviceId, mediaId)) {
      dir = Directory(p.join(base.path, safeName('$name [$mediaId]')));
    }
    await dir.create(recursive: true);
    await _noMedia(dir);
    return _mediaDirs[slot] = dir;
  }
}

int pathSize(String path) {
  try {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.file) return File(path).lengthSync();
    if (type == FileSystemEntityType.directory) {
      var total = 0;
      for (final e in Directory(path).listSync(recursive: true)) {
        if (e is File) total += e.lengthSync();
      }
      return total;
    }
  } catch (_) {}
  return 0;
}

bool pathExists(String path) =>
    FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
