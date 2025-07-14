

import '../Models/Source.dart';

abstract class Extension {

  Future<List<Source>> getInstalledExtensions();
  Future<List<Source>> fetchAvailableExtensions();

}