import 'dart:async';

typedef RpcHandler = FutureOr<Object?> Function(String method, List args);

class RpcRemoteError implements Exception {
  final String type;
  final String message;
  final String? remoteStack;

  const RpcRemoteError(this.type, this.message, [this.remoteStack]);

  @override
  String toString() => message;
}

/// Symmetric request/response channel over a pair of isolate ports. Both ends
/// build one; every message sent through [_send] must be fed to the peer's
/// [handleMessage].
class IsolateRpc {
  IsolateRpc(this._send, {required this.handler});

  static const _request = 0;
  static const _notify = 1;
  static const _ok = 2;
  static const _error = 3;

  final void Function(Object?) _send;
  final RpcHandler handler;
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;

  int get pendingCount => _pending.length;

  Future<T> call<T>(String method, [List args = const []]) {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    try {
      _send([_request, id, method, args]);
    } catch (e, st) {
      _pending.remove(id);
      completer.completeError(e, st);
    }
    return completer.future.then((v) => v as T);
  }

  void notify(String method, [List args = const []]) {
    _send([_notify, method, args]);
  }

  void failAll(Object error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(error);
    }
  }

  void handleMessage(Object? message) {
    if (message is! List || message.isEmpty) return;

    switch (message[0]) {
      case _request:
        _serve(message[1] as int, message[2] as String, message[3] as List);
      case _notify:
        Future.sync(
          () => handler(message[1] as String, message[2] as List),
        ).ignore();
      case _ok:
        _pending.remove(message[1] as int)?.complete(message[2]);
      case _error:
        _pending
            .remove(message[1] as int)
            ?.completeError(
              RpcRemoteError(
                message[2] as String,
                message[3] as String,
                message[4] as String?,
              ),
            );
    }
  }

  Future<void> _serve(int id, String method, List args) async {
    try {
      final result = await handler(method, args);
      _send([_ok, id, result]);
    } catch (e, st) {
      final type = e is RpcRemoteError ? e.type : e.runtimeType.toString();
      final message = e is RpcRemoteError ? e.message : e.toString();
      _send([_error, id, type, message, st.toString()]);
    }
  }
}
