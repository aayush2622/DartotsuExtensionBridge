import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../Extensions/Extensions.dart';
import '../../Extensions/RepoGuard.dart';
import '../../Logger.dart';
import '../../Network/MClient.dart';
import '../../Models/Source.dart';
import 'CloudStreamSource.dart';
import 'TachiyomiRepo.dart' show downloadPackageFile;

class CloudStreamRepoEntry {
  final String id;
  final String? name;
  final String? baseUrl;
  final String? lang;
  final String? iconUrl;
  final bool isNsfw;
  final String? version;
  final String repo;
  final String? internalName;
  final String? pluginUrl;

  const CloudStreamRepoEntry({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.lang,
    required this.iconUrl,
    required this.isNsfw,
    required this.version,
    required this.repo,
    required this.internalName,
    required this.pluginUrl,
  });
}

List<T> parseCloudStreamRepoBody<T extends CloudStreamSource>(
  String body,
  String repoUrl,
  T Function(CloudStreamRepoEntry entry) factory,
) {
  final decoded = jsonDecode(body) as List;

  return decoded
      .map<T>((e) {
        final json = e as Map<String, dynamic>;
        final name = json['name'] as String?;

        return factory(
          CloudStreamRepoEntry(
            id: (json['name'] ?? json['internalName']).toString().toLowerCase(),
            name: name,
            baseUrl: json['url'] as String?,
            lang: json['language'] as String?,
            iconUrl: json['iconUrl'] as String?,
            isNsfw: json['isNsfw'] ?? false,
            version: json['version']?.toString(),
            repo: repoUrl,
            internalName: json['internalName'] as String? ?? name,
            pluginUrl: json['url'] as String?,
          ),
        );
      })
      .toList(growable: false);
}

mixin CloudStreamRepoBackend<T extends CloudStreamSource> on Extension {
  http.Client get repoClient;

  List<Source> Function((String body, String repoUrl, ItemType type))
  get parseExtensionsIsolate;

  Future<Directory?> get extensionsDir;

  Future<void> onSourceFileWritten(File file) async {}

  Future<void> onSourceFileDeleted(File file) async {}

  @override
  Set<RepoFormat> get repoFormats => const {RepoFormat.cloudStream};

  @override
  Stream<double> addRepo(String repoUrl, ItemType type) =>
      addRepoTask(repoUrl, type, (url, _) => _addRepoImpl(url, type));

  /// Adds the plugin list at [url], or every list a repository manifest
  /// (`{"pluginLists": [...]}`) points to.
  Future<void> _addRepoImpl(String url, ItemType type) async {
    final bytes = await downloadRepoIndex(
      repoClient,
      url,
      timeout: const Duration(seconds: 10),
    );
    final body = utf8.decode(bytes, allowMalformed: true);
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw invalidRepo(type, body: bytes, url: url);
    }

    if (decoded is Map && decoded['pluginLists'] is List) {
      Object? firstError;
      var usable = 0;
      for (final list in (decoded['pluginLists'] as List).whereType<String>()) {
        try {
          final listUrl = normalizeRepoUrl(list);
          if (!hasRepo(listUrl, type)) await _addRepoImpl(listUrl, type);
          usable++;
        } catch (e) {
          Logger.log('Failed to add CloudStream plugin list $list: $e');
          firstError ??= e;
        }
      }
      if (usable == 0) {
        throw firstError ?? invalidRepo(type, body: bytes, url: url);
      }
      return;
    }

    List<Source> parsed = const [];
    if (decoded is List) {
      try {
        parsed = await compute(parseExtensionsIsolate, (body, url, type));
      } catch (e) {
        Logger.log('Could not parse CloudStream repo $url: $e');
      }
    }
    if (parsed.isEmpty) throw invalidRepo(type, body: bytes, url: url);

    await commitRepo(
      Repo(
        name: repoNameFromUrl(url),
        url: url,
        extensions: parsed.length.toString(),
      ),
      type,
      sources: parsed,
    );
  }

  String _safeFileBaseName(String name) {
    final sanitized = name.replaceAll(RegExp(r'[\\/]'), '_').trim();
    if (sanitized.isEmpty || RegExp(r'^\.+$').hasMatch(sanitized)) {
      return 'extension';
    }
    return sanitized;
  }

  final Map<String, Stream<double>> _installsInFlight = {};

  @override
  Stream<double> installSource(Source source) {
    final id = (source as CloudStreamSource).id;

    if (id != null) {
      final inFlight = _installsInFlight[id];
      if (inFlight != null) return inFlight;
    }

    final stream = progressStream((report) async {
      try {
        await _installSourceImpl(source, report);
      } finally {
        if (id != null) _installsInFlight.remove(id);
      }
    });

    if (id != null) {
      _installsInFlight[id] = stream;
    }

    return stream;
  }

  Future<void> _installSourceImpl(
    Source source,
    void Function(double) report,
  ) async {
    final s = source as CloudStreamSource;
    final type = source.itemType!;
    final dir = await extensionsDir;

    final pluginUrl = s.pluginUrl;
    if (pluginUrl == null || pluginUrl.isEmpty) {
      throw Exception("Plugin URL missing");
    }

    final file = File(
      p.join(
        dir!.path,
        "${_safeFileBaseName(s.name ?? s.id ?? 'extension')}${p.extension(Uri.parse(pluginUrl).path)}",
      ),
    );

    final progressId = s.id;
    if (progressId != null) {
      state(type).installProgress[progressId] = 0.0;
    }

    try {
      await downloadPackageFile(
        MClient.download(),
        pluginUrl,
        file.path,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            final fraction = received / total;
            if (progressId != null) {
              state(type).installProgress[progressId] = fraction;
            }
            report(fraction);
          }
        },
      );
    } finally {
      if (progressId != null) {
        state(type).installProgress.remove(progressId);
      }
    }

    await onSourceFileWritten(file);

    final avail = state(type).available;

    avail.value = avail.value.where((e) => e.id != s.id).toList();

    switch (s.itemType) {
      case ItemType.anime:
        await fetchInstalledAnimeExtensions();
        break;

      default:
        throw Exception('Unsupported item type: ${source.itemType}');
    }
    final raw = state(type).rawAvailable.value;
    detectUpdates(raw, type);
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as CloudStreamSource;
    final type = source.itemType!;

    final dir = await extensionsDir;

    File? pluginFile;

    final expectedBaseName = _safeFileBaseName(
      s.name ?? s.id ?? 'extension',
    ).toLowerCase();

    await for (final entity in dir!.list()) {
      if (entity is! File) continue;
      var baseName = p.basenameWithoutExtension(entity.path);
      if (baseName.toLowerCase() == expectedBaseName) {
        pluginFile = entity;
        break;
      }
    }

    if (pluginFile != null) {
      await onSourceFileDeleted(pluginFile);
      await pluginFile.delete();
      Logger.log("Deleted private extension: ${s.name}");
    } else {
      Logger.log("Private extension file not found: ${s.name}");
    }

    switch (type) {
      case ItemType.anime:
        await fetchInstalledAnimeExtensions();
        break;
      default:
        throw Exception("Unsupported item type: $type");
    }

    final raw = state(type).rawAvailable.value;
    final installedIds = state(type).installed.value.map((e) => e.id).toSet();

    state(type).available.value = List.unmodifiable(
      raw.where((e) => !installedIds.contains(e.id)),
    );

    detectUpdates(raw, type);
  }

  @override
  Stream<double> updateSource(Source source) => installSource(source);

  @override
  Set<String> schemes = {"cloudstreamrepo"};

  @override
  Future<void> handleSchemes(Uri uri) async {
    final urlWithoutScheme = uri.toString().replaceFirst(
      'cloudstreamrepo://',
      '',
    );

    await addRepo(
      urlWithoutScheme.startsWith('http')
          ? urlWithoutScheme
          : 'https://$urlWithoutScheme',
      ItemType.anime,
    ).drain<void>();
  }

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async {
    try {
      final bytes = await downloadRepoIndex(
        repoClient,
        repo.url,
        timeout: const Duration(seconds: 10),
      );
      final extensions = await compute(parseExtensionsIsolate, (
        utf8.decode(bytes, allowMalformed: true),
        repo.url,
        type,
      ));
      await updateRepoExtensionCount(repo, type, extensions.length);
      return extensions;
    } catch (e) {
      Logger.log('Failed to fetch CloudStream repo ${repo.url}: $e');
      return const [];
    }
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    final installed = state(
      type,
    ).installed.value.cast<CloudStreamSource>().toList();

    final repoMap = {
      for (var s in available.cast<CloudStreamSource>()) s.id?.toLowerCase(): s,
    };

    var changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id?.toLowerCase()];

      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..pluginUrl = repo.pluginUrl
          ..versionLast = repo.version;
        changed = true;
      } else if (inst.hasUpdate == true) {
        installed[i] = inst..hasUpdate = false;
        changed = true;
      }
      if (repo.iconUrl != inst.iconUrl) {
        installed[i] = inst..iconUrl = repo.iconUrl;
        changed = true;
      }
    }

    if (changed) {
      state(type).installed.value = List.unmodifiable(installed);
    }
  }
}
