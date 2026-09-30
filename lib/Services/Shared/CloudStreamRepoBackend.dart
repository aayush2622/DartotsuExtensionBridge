import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../Extensions/Extensions.dart';
import '../../Logger.dart';
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
  Stream<double> addRepo(String repoUrl, ItemType type) {
    return progressStream((_) => _addRepoImpl(repoUrl, type));
  }

  Future<void> _addRepoImpl(String repoUrl, ItemType type) async {
    final uri = Uri.tryParse(repoUrl);
    if (uri == null || !uri.hasScheme) {
      throw Exception("Invalid repo URL");
    }

    final repos = loadRepos(type);

    if (repos.any((r) => r.url == repoUrl)) {
      return;
    }

    final res = await repoClient
        .get(Uri.parse(repoUrl))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw Exception("Repo returned ${res.statusCode}");
    }

    final decoded = jsonDecode(res.body);

    if (decoded is Map<String, dynamic>) {
      final pluginLists = decoded["pluginLists"];

      if (pluginLists is List) {
        for (final subRepo in pluginLists.cast<String>()) {
          try {
            await _addRepoImpl(subRepo, type);
          } catch (e) {
            Logger.log("Failed to add $subRepo: $e");
          }
        }
        return;
      }

      throw Exception("Invalid CloudStream repository");
    }

    if (decoded is! List) {
      throw Exception("Invalid CloudStream repository");
    }

    final parsed = await compute(parseExtensionsIsolate, (
      res.body,
      repoUrl,
      type,
    ));
    final repo = Repo(
      name: repoNameFromUrl(repoUrl),
      url: repoUrl,
      extensions: parsed.length.toString(),
    );

    final updatedRepos = [...repos, repo];
    saveRepos(updatedRepos, type);
    state(type).repos.value = updatedRepos;
    await selectRepo(repo, type);
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
        repoClient,
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
    final indexUrl = repo.url;
    final res = await repoClient
        .get(Uri.parse(indexUrl))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      var extensions = await compute(parseExtensionsIsolate, (
        res.body,
        indexUrl,
        type,
      ));
      await updateRepoExtensionCount(repo, type, extensions.length);

      return extensions;
    }
    return [];
  }

  @override
  void detectUpdates(List<Source> available, ItemType type) {
    final installed = state(type).installed.value.cast<CloudStreamSource>();

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
