import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'Exceptions.dart';
import 'Models/TorrentInfo.dart';
import 'Models/TorrServerSettings.dart';

/// Typed HTTP client for interacting with TorrServer's REST / Swagger API.
class TorrServerRestClient {
  final Uri baseUrl;
  final http.Client _client;

  TorrServerRestClient(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  /// Closes the underlying HTTP client.
  void close() {
    _client.close();
  }

  /// Sends a health-check request to `/echo` to verify server responsiveness.
  /// Returns the server version string on success.
  Future<String> echo({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final uri = baseUrl.replace(path: '/echo');
      final res = await _client.get(uri).timeout(timeout);
      if (res.statusCode == 200) {
        return res.body.trim();
      }
      throw TorrServerHttpException(
        'Echo failed with status ${res.statusCode}',
        res.statusCode,
        res.body,
      );
    } catch (e) {
      if (e is TorrServerHttpException) {
        rethrow;
      }
      throw TorrServerHttpException(
        'Failed to connect to TorrServer at $baseUrl',
        0,
        e.toString(),
      );
    }
  }

  /// Sends a shutdown request to `/shutdown` to trigger graceful server termination.
  Future<void> shutdown({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final uri = baseUrl.replace(path: '/shutdown');
      await _client.get(uri).timeout(timeout);
    } catch (_) {}
  }

  /// Adds a torrent via magnet link or hash.
  Future<TorrentInfo> addTorrent({
    required String link,
    String? title,
    String? category,
    String? poster,
    String? data,
    bool saveToDb = false,
  }) async {
    final body = {
      'action': 'add',
      'link': link,
      if (title != null && title.isNotEmpty) 'title': title,
      if (category != null && category.isNotEmpty) 'category': category,
      if (poster != null && poster.isNotEmpty) 'poster': poster,
      if (data != null && data.isNotEmpty) 'data': data,
      'save_to_db': saveToDb,
    };

    final jsonResponse = await _postJson('/torrents', body);
    if (jsonResponse is Map<String, dynamic>) {
      return TorrentInfo.fromJson(jsonResponse);
    }
    throw const TorrServerHttpException(
      'Unexpected response format when adding torrent',
      200,
    );
  }

  /// Uploads raw `.torrent` file bytes via `/torrent/upload` (multipart/form-data).
  Future<TorrentInfo> uploadTorrentFile({
    required Uint8List torrentBytes,
    String filename = 'torrent.torrent',
    String? title,
    String? category,
    String? poster,
    String? data,
    bool saveToDb = false,
  }) async {
    try {
      final uri = baseUrl.replace(path: '/torrent/upload');
      final request = http.MultipartRequest('POST', uri);

      request.files.add(
        http.MultipartFile.fromBytes('file', torrentBytes, filename: filename),
      );

      if (title != null && title.isNotEmpty) {
        request.fields['title'] = title;
      }
      if (category != null && category.isNotEmpty) {
        request.fields['category'] = category;
      }
      if (poster != null && poster.isNotEmpty) {
        request.fields['poster'] = poster;
      }
      if (data != null && data.isNotEmpty) {
        request.fields['data'] = data;
      }
      if (saveToDb) {
        request.fields['save'] = 'true';
      }

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return TorrentInfo.fromJson(decoded);
        } else if (decoded is List &&
            decoded.isNotEmpty &&
            decoded.first is Map<String, dynamic>) {
          return TorrentInfo.fromJson(decoded.first as Map<String, dynamic>);
        }
        throw TorrServerHttpException(
          'Unexpected upload response body format',
          response.statusCode,
          response.body,
        );
      }

      throw TorrServerHttpException(
        'Upload failed with status ${response.statusCode}',
        response.statusCode,
        response.body,
      );
    } catch (e) {
      if (e is TorrServerHttpException) {
        rethrow;
      }
      throw TorrServerHttpException(
        'Failed to upload torrent file',
        0,
        e.toString(),
      );
    }
  }

  /// Lists all active/stored torrents on the server.
  Future<List<TorrentInfo>> listTorrents() async {
    final body = {'action': 'list'};
    final jsonResponse = await _postJson('/torrents', body);

    if (jsonResponse is List) {
      return jsonResponse
          .whereType<Map<String, dynamic>>()
          .map(TorrentInfo.fromJson)
          .toList();
    }
    return <TorrentInfo>[];
  }

  /// Gets status and details for a single torrent by its infohash.
  Future<TorrentInfo> getTorrent(String hash) async {
    final body = {'action': 'get', 'hash': hash};
    final jsonResponse = await _postJson('/torrents', body);

    if (jsonResponse is Map<String, dynamic>) {
      return TorrentInfo.fromJson(jsonResponse);
    }
    throw TorrServerHttpException('Torrent with hash "$hash" not found', 404);
  }

  /// Removes a torrent and its cached data from memory/database.
  Future<void> removeTorrent(String hash) async {
    final body = {'action': 'rem', 'hash': hash};
    await _postJson('/torrents', body);
  }

  /// Drops a torrent from active memory (frees RAM).
  Future<void> dropTorrent(String hash) async {
    final body = {'action': 'drop', 'hash': hash};
    await _postJson('/torrents', body);
  }

  /// Updates metadata (title, poster, category, data) for an existing torrent.
  Future<void> setTorrent(
    String hash, {
    String? title,
    String? poster,
    String? category,
    String? data,
  }) async {
    final body = {
      'action': 'set',
      'hash': hash,
      if (title != null) 'title': title,
      if (poster != null) 'poster': poster,
      if (category != null) 'category': category,
      if (data != null) 'data': data,
    };
    await _postJson('/torrents', body);
  }

  /// Retrieves server configuration settings (`BTSets`).
  Future<TorrServerSettings> getSettings() async {
    final body = {'action': 'get'};
    final jsonResponse = await _postJson('/settings', body);

    if (jsonResponse is Map<String, dynamic>) {
      return TorrServerSettings.fromJson(jsonResponse);
    }
    throw const TorrServerHttpException(
      'Failed to parse TorrServer settings',
      200,
    );
  }

  /// Updates server configuration settings (`BTSets`).
  Future<void> setSettings(TorrServerSettings settings) async {
    final body = {'action': 'set', 'sets': settings.toJson()};
    await _postJson('/settings', body);
  }

  /// Resets server configuration settings to defaults.
  Future<void> setDefaultSettings() async {
    final body = {'action': 'def'};
    await _postJson('/settings', body);
  }

  /// Constructs the playable HTTP streaming URL for a given torrent and file index.
  Uri streamUrl(String hash, {int fileIndex = 0}) {
    final index = fileIndex > 0 ? fileIndex : 1;
    return baseUrl.replace(
      path: '/stream',
      queryParameters: {
        'link': hash,
        'index': index.toString(),
        'play': '',
      },
    );
  }

  /// Sends a POST request with JSON payload to the specified endpoint.
  Future<dynamic> _postJson(String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = baseUrl.replace(path: endpoint);
      final res = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(body),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.isEmpty) {
          return null;
        }
        return jsonDecode(res.body);
      }

      throw TorrServerHttpException(
        'Request to $endpoint failed with status ${res.statusCode}',
        res.statusCode,
        res.body,
      );
    } catch (e) {
      if (e is TorrServerHttpException) {
        rethrow;
      }
      throw TorrServerHttpException(
        'Failed communicating with TorrServer at $endpoint',
        0,
        e.toString(),
      );
    }
  }
}
