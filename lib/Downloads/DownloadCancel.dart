import 'dart:async';

/// One switch shared by every request of a download. Completing it aborts
/// the requests in flight and makes later ones fail at once.
class DownloadCancel {
  final _signal = Completer<void>();

  bool get isCancelled => _signal.isCompleted;

  /// Pass to `AbortableRequest.abortTrigger`.
  Future<void> get trigger => _signal.future;

  Future<void> cancel() async {
    if (!_signal.isCompleted) _signal.complete();
  }
}
