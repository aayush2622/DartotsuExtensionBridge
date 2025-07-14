import 'package:dartotsu_extension_bridge/Extensions/Extensions.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:flutter/services.dart';

class AniyomiExtensions extends Extension {
  static const platform = MethodChannel('aniyomiExtensionBridge');

  @override
  Future<List<Source>> fetchAvailableExtensions() async {
    final dynamic result = await platform.invokeMethod('getInstalledExtension');
    if (result is List) {
      return result.map((e) => Source.fromJson(e)).toList();
    } else {
      throw Exception('Invalid response format');
    }
  }

  @override
  Future<List<Source>> getInstalledExtensions() {
    // TODO: implement getInstalledExtensions
    throw UnimplementedError();
  }
}
