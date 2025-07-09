
import 'package:flutter/services.dart';

class DartotsuExtensionBridge {
  static const platform = MethodChannel('test');

  Future<void> fetchAnimeTitles() async {
    try {
      final List<dynamic> result = await platform.invokeMethod('getAnimeTitles');
      print('Anime titles: $result');
    } catch (e) {
      print('Error: $e');
    }
  }
}