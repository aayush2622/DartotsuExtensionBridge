
import 'package:flutter/services.dart';

class DartotsuExtensionBridge {
  static const platform = MethodChannel('test');

  Future<void> fetchAnimeTitles() async {
    try {
      final dynamic result = await platform.invokeMethod('getInstalledExtensions');
      print('Anime titles: $result');
    } catch (e) {
      print('Error: $e');
    }
  }
}