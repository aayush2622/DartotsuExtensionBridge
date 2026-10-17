import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../Extensions/Extensions.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';

/// Repos that are a single JSON index listing every source (Mangayomi, Sora,
/// LNReader, Legado, Aidoku): adding one downloads and parses the index, and
/// refuses it unless it lists sources of the requested type.
mixin JsonRepoBackend on Extension {
  http.Client get repoClient;

  /// Parses an index body; the function handed to `compute()`, so it must be
  /// a static or top-level function.
  List<Source> Function((String body, String repoUrl, ItemType type))
  get parseRepoIsolate;

  Duration get repoTimeout => const Duration(seconds: 15);

  /// The [Repo] saved for a newly added index.
  Repo repoFor(String url, String body, List<Source> sources) => Repo(
    url: url,
    name: repoNameFromUrl(url),
    extensions: sources.length.toString(),
  );

  @override
  Stream<double> addRepo(String repoUrl, ItemType type) =>
      addRepoTask(repoUrl, type, (url, _) async {
        final bytes = await downloadRepoIndex(
          repoClient,
          url,
          timeout: repoTimeout,
        );
        final body = utf8.decode(bytes, allowMalformed: true);
        final sources = await _parse(body, url, type);
        if (sources.isEmpty) throw invalidRepo(type, body: bytes, url: url);
        await commitRepo(repoFor(url, body, sources), type, sources: sources);
      });

  @override
  Future<List<Source>> fetchRepo(Repo repo, ItemType type) async {
    try {
      final bytes = await downloadRepoIndex(
        repoClient,
        repo.url,
        timeout: repoTimeout,
      );
      final sources = await _parse(
        utf8.decode(bytes, allowMalformed: true),
        repo.url,
        type,
      );
      await updateRepoExtensionCount(repo, type, sources.length);
      return sources;
    } catch (e) {
      Logger.log('Failed to fetch $name repo ${repo.url}: $e');
      return const [];
    }
  }

  Future<List<Source>> _parse(String body, String url, ItemType type) async {
    try {
      return await compute(parseRepoIsolate, (body, url, type));
    } catch (e) {
      Logger.log('Could not parse $name repo $url: $e');
      return const [];
    }
  }
}
