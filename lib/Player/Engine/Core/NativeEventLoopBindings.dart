@DefaultAsset(
  'package:dartotsu_extension_bridge/Player/Engine/Core/NativeEventLoopBindings.dart',
)
library;

import 'dart:ffi';

@Native<
  Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Int64,
  )
>(symbol: 'media_kit_event_loop_create')
external Pointer<Void> create(
  Pointer<Void> handle,
  Pointer<Void> setWakeup,
  Pointer<Void> destroy,
  Pointer<Void> post,
  int port,
);

@Native<Void Function()>(symbol: 'media_kit_prepare')
external void prepare();

@Native<Void Function(Pointer<Void>)>(symbol: 'media_kit_event_loop_stop')
external void stop(Pointer<Void> owner);

@Native<Void Function(Pointer<Void>)>(symbol: 'media_kit_event_loop_destroy')
external void destroy(Pointer<Void> owner);

@Native<Void Function(Pointer<Void>)>(symbol: 'media_kit_event_loop_finalize')
external void finalize(Pointer<Void> owner);

@Native<Void Function(Pointer<Void>)>(symbol: 'media_kit_event_loop_release')
external void release(Pointer<Void> owner);
