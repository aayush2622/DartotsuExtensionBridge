import 'dart:convert';
import 'dart:typed_data';

import '../../Models/SourcePreference.dart';
import 'Postcard.dart';

const aidokuSettingsKey = '__settings';

class AidokuSetting {
  AidokuSetting({
    required this.type,
    required this.key,
    required this.title,
    this.subtitle,
    this.titles = const [],
    this.values = const [],
    this.placeholder,
    this.notification,
    this.method,
    this.group,
  });

  final String type;
  final String key;
  final String title;
  final String? subtitle;
  final List<String> titles;
  final List<String> values;
  final String? placeholder;
  final String? notification;
  final String? method;
  final String? group;
}

List<AidokuSetting> parseAidokuSettings(String? json) {
  if (json == null) return const [];
  final out = <AidokuSetting>[];
  void walk(Object? node, String? group) {
    if (node is List) {
      for (final n in node) {
        walk(n, group);
      }
      return;
    }
    if (node is! Map) return;
    final type = node['type'];
    if (type == 'group' || type == 'page') {
      walk(node['items'], node['title']?.toString() ?? group);
      return;
    }
    final key = node['key'];
    if (type is! String || key is! String) return;
    List<String> strings(Object? v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];
    out.add(
      AidokuSetting(
        type: type,
        key: key,
        title: node['title']?.toString() ?? key,
        subtitle: node['subtitle']?.toString(),
        titles: strings(node['titles']),
        values: strings(node['values']),
        placeholder: node['placeholder']?.toString(),
        notification: node['notification']?.toString(),
        method: node['method']?.toString(),
        group: group,
      ),
    );
  }

  try {
    walk(jsonDecode(json), null);
  } catch (_) {}
  return out;
}

Uint8List encodeAidokuValue(String type, Object? value) {
  final w = PostcardWriter();
  switch (type) {
    case 'switch':
      w.writeBool(value == true);
    case 'multi-select':
      w.writeVec<String>(
        (value as List? ?? const []).map((e) => '$e').toList(),
        w.writeString,
      );
    default:
      w.writeString('${value ?? ''}');
  }
  return Uint8List.fromList(w.takeBytes());
}

Object? decodeAidokuValue(String type, String? base64Payload) {
  if (base64Payload == null) return null;
  try {
    final r = PostcardReader(base64Decode(base64Payload));
    return switch (type) {
      'switch' => r.readBool(),
      'multi-select' => r.readVec(r.readString),
      _ => r.readString(),
    };
  } catch (_) {
    return null;
  }
}

List<SourcePreference> buildAidokuPreferences(
  List<AidokuSetting> settings,
  Object? Function(AidokuSetting setting) current,
) {
  final out = <SourcePreference>[];
  var id = 0;
  for (final s in settings) {
    final value = current(s);
    final summary = s.subtitle ?? s.group;
    switch (s.type) {
      case 'switch':
        out.add(
          SourcePreference(
            id: id++,
            key: s.key,
            type: s.type,
            switchPreferenceCompat: SwitchPreferenceCompat(
              title: s.title,
              summary: summary,
              value: value == true,
            ),
          ),
        );
      case 'select':
      case 'segment':
        final index = s.values.indexOf('${value ?? ''}');
        out.add(
          SourcePreference(
            id: id++,
            key: s.key,
            type: s.type,
            listPreference: ListPreference(
              title: s.title,
              summary: summary,
              value: index < 0 ? null : s.values[index],
              valueIndex: index < 0 ? 0 : index,
              entries: s.titles.isEmpty ? s.values : s.titles,
              entryValues: s.values,
            ),
          ),
        );
      case 'multi-select':
        out.add(
          SourcePreference(
            id: id++,
            key: s.key,
            type: s.type,
            multiSelectListPreference: MultiSelectListPreference(
              title: s.title,
              summary: summary,
              entries: s.titles.isEmpty ? s.values : s.titles,
              entryValues: s.values,
              values: (value as List?)?.map((e) => '$e').toList() ?? [],
            ),
          ),
        );
      case 'text':
        out.add(
          SourcePreference(
            id: id++,
            key: s.key,
            type: s.type,
            editTextPreference: EditTextPreference(
              title: s.title,
              summary: s.placeholder ?? summary,
              value: value == null ? '' : '$value',
              dialogTitle: s.title,
              text: value == null ? '' : '$value',
            ),
          ),
        );
      case 'login':
        if (s.method == 'basic') {
          for (final field in const ['username', 'password']) {
            out.add(
              SourcePreference(
                id: id++,
                key: '${s.key}:$field',
                type: 'login-$field',
                editTextPreference: EditTextPreference(
                  title: '${s.title} ($field)',
                  summary: summary,
                  value: field == 'password' ? '' : '${current(s) ?? ''}',
                  dialogTitle: s.title,
                ),
              ),
            );
          }
        }
    }
  }
  return out;
}
