// Deprecated: use the unified ObjectBox initialization in extension_bridge.dart
// This file remains to avoid breaking imports; do not open a separate Store here.
import 'package:dartotsu_extension_bridge/objectbox.g.dart';
import 'package:dartotsu_extension_bridge/Mangayomi/Eval/dart/model/m_source.dart';
import '../extension_bridge.dart';

late final Box<MSource> objectboxMSourceBox;

Future<void> initObjectBox() async {
  // Initialize boxes using the global store created by DartotsuExtensionBridge.init()
  objectboxMSourceBox = objectboxStore.box<MSource>();
}
