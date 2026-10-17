import 'dart:convert';

import '../../Extensions/SourceMethods.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/Source.dart';
import '../../Models/SourcePreference.dart';
import '../../Models/Video.dart';
import '../../Network/MClient.dart';
import '../../Settings/KvStore.dart';
import 'AidokuDefaults.dart';
import 'AidokuSettings.dart';
import 'Models/Source.dart';
import 'AidokuWorker.dart';

class AidokuSourceMethods extends SourceMethods {
  final AidokuSource _source;

  AidokuSourceMethods(this._source);

  @override
  Source get source => _source;

  static final _runtimes = <String, Future<AidokuWorker>>{};

  static void dispose(String sourceId) {
    _runtimes.remove(sourceId)?.then((w) => w.dispose(), onError: (_) {});
  }

  static void disposeAll() {
    for (final id in _runtimes.keys.toList()) {
      dispose(id);
    }
  }

  Future<void>? _defaultsLoad;

  Future<void> _ensureDefaults() => _defaultsLoad ??= () async {
    if (_source.defaults?[aidokuDefaultsVersionKey] != null) return;
    final url = _source.downloadUrl;
    if (url == null || url.isEmpty) return;
    try {
      final res = await MClient.init().get(Uri.parse(url));
      if (res.statusCode == 200) {
        _source.defaults = extractAidokuDefaults(res.bodyBytes) ?? const {};
      }
    } catch (_) {}
  }();

  Future<AidokuWorker> _runtime() {
    final id = _source.id!;
    return _runtimes[id] ??=
        () async {
          await _ensureDefaults();
          final defaults = {...?_source.defaults};
          if (!defaults.containsKey('languages')) {
            final languages = aidokuLanguageDefault(
              _source.languages,
              _source.lang,
            );
            if (languages != null) defaults['languages'] = languages;
          }
          return AidokuWorker.spawn(
            id,
            _source.wasmBytesBase64 ?? '',
            defaults,
          );
        }().catchError((Object e) {
          _runtimes.remove(id);
          throw e;
        });
  }

  @override
  Future<Pages> getPopular(int page) async =>
      (await _runtime()).getPopular(page);

  @override
  Future<Pages> getLatestUpdates(int page) async =>
      (await _runtime()).getLatestUpdates(page);

  @override
  Future<Pages> search(String query, int page, List<dynamic> filters) async =>
      (await _runtime()).search(query, page);

  @override
  Future<DMedia> getDetail(DMedia media) async =>
      (await _runtime()).getDetail(media);

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async {
    final pages = await (await _runtime()).getPageList(episode);
    return pagesWithHeaders(pages, baseUrl: _source.baseUrl);
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) =>
      throw UnimplementedError();

  @override
  Future<String?> getNovelContent(DEpisode episode) =>
      throw UnimplementedError();

  String _prefKey(String key) => 'aidoku-${_source.id}-pref-$key';

  String _loginKey(String key, String field) =>
      'aidoku-${_source.id}-login-$key-$field';

  @override
  Future<List<SourcePreference>> getPreference() async {
    await _ensureDefaults();
    final settings = parseAidokuSettings(_source.defaults?[aidokuSettingsKey]);
    return buildAidokuPreferences(settings, (s) {
      if (s.type == 'login')
        return getVal<String>(_loginKey(s.key, 'username'));
      final stored =
          getVal<String>(_prefKey(s.key)) ?? _source.defaults?[s.key];
      return decodeAidokuValue(s.type, stored);
    });
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    final key = pref.key;
    if (key == null) return false;
    if (key.contains(':')) {
      final split = key.split(':');
      final field = split.last;
      final loginKey = split.first;
      setVal(_loginKey(loginKey, field), '${value ?? ''}');
      final user = getVal<String>(_loginKey(loginKey, 'username')) ?? '';
      final password = getVal<String>(_loginKey(loginKey, 'password')) ?? '';
      if (user.isEmpty || password.isEmpty) return true;
      return (await _runtime()).basicLogin(loginKey, user, password);
    }
    final settings = parseAidokuSettings(_source.defaults?[aidokuSettingsKey]);
    final setting = settings.where((s) => s.key == key).firstOrNull;
    if (setting == null) return false;
    setVal(_prefKey(key), base64Encode(encodeAidokuValue(setting.type, value)));
    final notification = setting.notification;
    if (notification != null) await (await _runtime()).notify(notification);
    return true;
  }
}
