abstract class JavaBridge {
  Future<void> init({required String pluginJarPath});

  Future<T> call<T>(
    String method, [
    Map<String, dynamic>? args,
    bool throwError = false,
  ]);

  void dispose();
}

/// Safe default for [JavaBridge.call] when a native-side error must not
/// propagate (`throwError: false`).
T emptyJavaBridgeValue<T>() {
  if (null is T) return null as T;
  if (T == bool) return false as T;
  if (T == Map<String, dynamic>) return <String, dynamic>{} as T;
  if (T == List<Map<String, dynamic>>) return <Map<String, dynamic>>[] as T;
  if (T == List<dynamic>) return <dynamic>[] as T;
  throw StateError('emptyJavaBridgeValue: no empty default for $T');
}
