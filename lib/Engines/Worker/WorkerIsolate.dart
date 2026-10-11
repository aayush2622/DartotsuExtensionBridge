import 'dart:async';
import 'dart:isolate';

import 'IsolateRpc.dart';

/// Entry point run inside the worker isolate. It must be a top-level (or
/// static) function and receives the port to reach the host. Build the
/// worker's [IsolateRpc] with [startWorkerEndpoint].
typedef WorkerEntry = void Function(SendPort host);

/// Starts the worker's side of the channel: replies to the host with the
/// worker's own port and routes everything it receives into the returned rpc.
IsolateRpc startWorkerEndpoint(SendPort host, RpcHandler handler) {
  final inbox = ReceivePort();
  final rpc = IsolateRpc(host.send, handler: handler);
  inbox.listen(rpc.handleMessage);
  host.send(inbox.sendPort);
  return rpc;
}

/// A lazily spawned long-lived isolate with an RPC channel in both
/// directions. If the isolate dies, in-flight calls fail and the next call
/// spawns a fresh one.
class WorkerIsolate {
  WorkerIsolate({
    required this.name,
    required this.entry,
    required this.hostHandler,
    this.onRestart,
  });

  final String name;
  final WorkerEntry entry;
  final RpcHandler hostHandler;

  /// Called whenever a new worker isolate comes up, so the owner can drop any
  /// state it tracked about the previous one.
  final void Function()? onRestart;

  Future<IsolateRpc>? _starting;
  IsolateRpc? _rpc;
  Isolate? _isolate;
  ReceivePort? _inbox;
  ReceivePort? _lifecycle;

  bool get isRunning => _rpc != null;

  Future<T> call<T>(String method, [List args = const []]) async {
    final rpc = await _ensure();
    return rpc.call<T>(method, args);
  }

  void notify(String method, [List args = const []]) {
    _rpc?.notify(method, args);
  }

  Future<IsolateRpc> _ensure() {
    final rpc = _rpc;
    if (rpc != null) return Future.value(rpc);
    return _starting ??= _spawn().whenComplete(() => _starting = null);
  }

  Future<IsolateRpc> _spawn() async {
    final inbox = ReceivePort();
    final lifecycle = ReceivePort();
    final ready = Completer<SendPort>();
    IsolateRpc? rpc;

    inbox.listen((message) {
      if (!ready.isCompleted && message is SendPort) {
        ready.complete(message);
      } else {
        rpc?.handleMessage(message);
      }
    });

    final isolate = await Isolate.spawn<SendPort>(
      entry,
      inbox.sendPort,
      debugName: name,
      onError: lifecycle.sendPort,
      onExit: lifecycle.sendPort,
    );

    lifecycle.listen((message) {
      if (message == null) {
        _teardown(isolate, StateError('$name isolate exited'));
      }
    });

    final workerPort = await ready.future;
    rpc = IsolateRpc(workerPort.send, handler: hostHandler);

    _rpc = rpc;
    _isolate = isolate;
    _inbox = inbox;
    _lifecycle = lifecycle;
    onRestart?.call();
    return rpc;
  }

  void _teardown(Isolate isolate, Object error) {
    if (!identical(_isolate, isolate)) return;
    final rpc = _rpc;
    _rpc = null;
    _isolate = null;
    _inbox?.close();
    _lifecycle?.close();
    _inbox = null;
    _lifecycle = null;
    rpc?.failAll(error);
  }

  Future<void> shutdown() async {
    final isolate = _isolate;
    if (isolate == null) return;
    isolate.kill(priority: Isolate.immediate);
    _teardown(isolate, StateError('$name isolate shut down'));
  }
}
