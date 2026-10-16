import 'dart:convert';

import 'package:flutter/services.dart';

import '../Engines/JavaEngine/Bridge/JavaBridge.dart';

abstract class ExtensionBridge {
  Future<T> call<T>(String method, Map<String, dynamic> args);
}

class MethodChannelBridge implements ExtensionBridge {
  final MethodChannel channel;

  MethodChannelBridge(this.channel);

  @override
  Future<T> call<T>(String method, Map<String, dynamic> args) async {
    final result = await channel.invokeMethod(method, args);

    if (result is String) {
      return jsonDecode(result) as T;
    }

    return result as T;
  }
}

class JavaExtensionBridge implements ExtensionBridge {
  final JavaBridge bridge;

  JavaExtensionBridge(this.bridge);

  @override
  Future<T> call<T>(String method, Map<String, dynamic> args) =>
      bridge.call(method, args);
}
