import 'package:get/get_rx/src/rx_types/rx_types.dart';

enum StepStatus {
  waiting,
  checking,
  downloading,
  installing,
  done,
  upToDate,
  skipped,
  failed,
}

class InstallStep {
  InstallStep(
    this.id,
    this.name, {
    RxDouble? progress,
    RxInt? receivedBytes,
    RxInt? totalBytes,
    RxDouble? speed,
  }) : progress = progress ?? 0.0.obs,
       receivedBytes = receivedBytes ?? 0.obs,
       totalBytes = totalBytes ?? 0.obs,
       speed = speed ?? 0.0.obs;

  final String id;

  final String name;

  final state = StepStatus.waiting.obs;
  final RxDouble progress;
  final RxInt receivedBytes;
  final RxInt totalBytes;
  final RxDouble speed;

  final version = RxnString();

  final replaces = false.obs;

  final detail = RxnString();

  final error = RxnString();

  bool get active =>
      state.value == StepStatus.checking ||
      state.value == StepStatus.downloading ||
      state.value == StepStatus.installing;

  bool get finished =>
      state.value == StepStatus.done ||
      state.value == StepStatus.upToDate ||
      state.value == StepStatus.skipped;

  void reset({
    required StepStatus to,
    int bytes = 0,
    String? version,
    bool replaces = false,
  }) {
    state.value = to;
    progress.value = to == StepStatus.upToDate || to == StepStatus.done ? 1 : 0;
    receivedBytes.value = 0;
    totalBytes.value = bytes;
    speed.value = 0;
    this.version.value = version;
    detail.value = null;
    this.replaces.value = replaces;
    error.value = null;
  }
}

abstract interface class PluginDependency {
  String get key;

  List<InstallStep> get steps;

  Future<List<InstallStep>> plan({int minimum = 0, bool refresh = false});

  Future<void> ensure({int minimum = 0, bool latest = false});

  Future<List<String>> classpath();

  Future<void> autoUpdate();

  void cancel();
}
