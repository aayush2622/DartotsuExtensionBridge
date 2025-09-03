import 'Eval/dart/model/source_preference.dart';
import 'Models/Source.dart';
import '../objectbox.g.dart';

late final Box<SourcePreference> sourcePreferenceBox;
late final Box<SourcePreferenceStringValue> sourcePreferenceStringValueBox;

Future<void> initObjectBox() async {
  // Use the globally initialized store from extension_bridge.dart
  sourcePreferenceBox = objectboxStore.box<SourcePreference>();
  sourcePreferenceStringValueBox = objectboxStore.box<SourcePreferenceStringValue>();
}

void setPreferenceSetting(SourcePreference sourcePreference, MSource source) {
  final sourcePref = sourcePreferenceBox
      .query(
        SourcePreference_.sourceId.equals(source.id) &
            SourcePreference_.key.equals(sourcePreference.key ?? ""),
      )
      .build()
      .findFirst();

  objectboxStore.runInTransaction(TxMode.write, () {
    if (sourcePref != null) {
      sourcePreferenceBox.put(sourcePreference..id = sourcePref.id);
    } else {
      sourcePreferenceBox.put(sourcePreference..sourceId = source.id);
    }
  });
}

dynamic getPreferenceValue(int sourceId, String key) {
  final sourcePreference = getSourcePreferenceEntry(key, sourceId);
  if (sourcePreference == null) return null;

  if (sourcePreference.listPreference != null) {
    final pref = sourcePreference.listPreference!;
    return pref.entryValues![pref.valueIndex!];
  } else if (sourcePreference.checkBoxPreference != null) {
    return sourcePreference.checkBoxPreference!.value;
  } else if (sourcePreference.switchPreferenceCompat != null) {
    return sourcePreference.switchPreferenceCompat!.value;
  } else if (sourcePreference.editTextPreference != null) {
    return sourcePreference.editTextPreference!.value;
  }
  return sourcePreference.multiSelectListPreference?.values;
}

SourcePreference? getSourcePreferenceEntry(String key, int sourceId) {
  return sourcePreferenceBox
      .query(
        SourcePreference_.sourceId.equals(sourceId) &
            SourcePreference_.key.equals(key),
      )
      .build()
      .findFirst();
}

String getSourcePreferenceStringValue(
  int sourceId,
  String key,
  String defaultValue,
) {
  SourcePreferenceStringValue? sourcePreferenceStringValue =
      sourcePreferenceStringValueBox
          .query(
            SourcePreferenceStringValue_.sourceId.equals(sourceId) &
                SourcePreferenceStringValue_.key.equals(key),
          )
          .build()
          .findFirst();

  return sourcePreferenceStringValue?.value ?? defaultValue;
}

void setSourcePreferenceStringValue(int sourceId, String key, String value) {
  final sourcePref = sourcePreferenceStringValueBox
      .query(
        SourcePreferenceStringValue_.sourceId.equals(sourceId) &
            SourcePreferenceStringValue_.key.equals(key),
      )
      .build()
      .findFirst();

  objectboxStore.runInTransaction(TxMode.write, () {
    if (sourcePref != null) {
      sourcePreferenceStringValueBox.put(sourcePref..value = value);
    } else {
      sourcePreferenceStringValueBox.put(
        SourcePreferenceStringValue()
          ..key = key
          ..sourceId = sourceId
          ..value = value,
      );
    }
  });
}
