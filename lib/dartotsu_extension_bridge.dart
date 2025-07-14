import 'package:flutter/services.dart';

class DartotsuExtensionBridge {
  static const platform = MethodChannel("aniyomiExtensionBridge");

  Future<void> fetchAnimeTitles() async {
    //test one
    print('Fetching installed anime extensions...');
    await Future.delayed(Duration(seconds: 2));
    try {
      final dynamic result = await platform.invokeMethod(
        'getInstalledAnimeExtensions',
      );
      print(result);
    } catch (e) {
      print('Error fetching anime extensions: $e');
    }
    //test two
    print('Fetching installed manga extensions...');
    await Future.delayed(Duration(seconds: 2));
    try {
      final dynamic result = await platform.invokeMethod(
        'getInstalledMangaExtensions',
      );
      print(result);
    } catch (e) {
      print('Error fetching manga extensions: $e');
    }
    //test three
    print('Fetching anime extensions...');
    await Future.delayed(Duration(seconds: 2));
    try {
      final dynamic
      result = await platform.invokeMethod('fetchAnimeExtensions', [
        'https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json',
      ]);
      print(result);
    } catch (e) {
      print('Error fetching anime extensions: $e');
    }

    //test four
    print('Fetching manga extensions...');
    await Future.delayed(Duration(seconds: 2));
    try {
      final dynamic
      result = await platform.invokeMethod('fetchMangaExtensions', [
        'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
      ]);
      print(result);
    } catch (e) {
      print('Error fetching manga extensions: $e');
    }
  }
}
