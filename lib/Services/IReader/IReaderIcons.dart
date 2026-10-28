import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../Logger.dart';
import '../../Models/Source.dart';
import '../Shared/PackagedSource.dart';

final _version = RegExp(r'-v[\d.]+$');
final _rawRepo = RegExp(
  r'^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/(?:refs/heads/)?([^/]+)/',
);

String _stem(String file) {
  final dot = file.lastIndexOf('.');
  return (dot < 0 ? file : file.substring(0, dot)).replaceFirst(_version, '');
}

Map<String, String> ireaderIconsByStem(Iterable<String> files) => {
  for (final f in files)
    if (f.endsWith('.png')) _stem(f): f,
};

List<Source> applyIreaderIcons(
  List<Source> sources,
  Map<String, String> icons,
  String baseUrl,
) {
  for (final s in sources) {
    final apk = s is PackagedSource ? s.apkName : null;
    if (apk == null) continue;
    final file = icons[_stem(apk)];
    if (file != null) s.iconUrl = '$baseUrl/icon/$file';
  }
  return sources;
}

Future<List<Source>> withIreaderIcons(
  List<Source> sources,
  String repoUrl,
  http.Client client,
) async {
  final match = _rawRepo.firstMatch(repoUrl);
  if (match == null || sources.isEmpty) return sources;
  final owner = match[1], repo = match[2], ref = match[3];
  try {
    final res = await client.get(
      Uri.parse(
        'https://data.jsdelivr.com/v1/packages/gh/$owner/$repo@$ref?structure=flat',
      ),
    );
    if (res.statusCode != 200) return sources;
    final files = (jsonDecode(res.body)['files'] as List)
        .map((e) => (e as Map)['name'] as String)
        .where((n) => n.startsWith('/icon/'))
        .map((n) => n.substring('/icon/'.length));
    return applyIreaderIcons(
      sources,
      ireaderIconsByStem(files),
      'https://raw.githubusercontent.com/$owner/$repo/$ref',
    );
  } catch (e) {
    Logger.log('Could not load IReader icons: $e');
    return sources;
  }
}
