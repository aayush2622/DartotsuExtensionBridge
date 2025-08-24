import 'package:dartotsu_extension_bridge/objectbox.g.dart';
import 'package:dartotsu_extension_bridge/Mangayomi/Eval/dart/model/m_source.dart';

late final Store store;
late final Box<MSource> objectboxMSourceBox;

Future<void> initObjectBox() async {
  store = await openStore();
  objectboxMSourceBox = store.box<MSource>();
}
