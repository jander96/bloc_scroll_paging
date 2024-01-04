library async_data;

import 'package:flutter/cupertino.dart';

import 'async_value.dart';
export 'async_value.dart';

/// A [ValueNotifier] or simply an observable for asynchronous operations.
/// The commodity is that the Future passed in is guarded by an [AsyncValue].
/// So the different states of the computation can only be interacted as a sum type.
/// And also is refresh-able
class AsyncValueNotifier<T> extends ValueNotifier<AsyncValue<T>> {
  final Future<T> Function() _future;
  late bool _running = false;

  AsyncValueNotifier(this._future, [AsyncValue<T>? value]) : super(value ?? AsyncValue<T>.initial()) {
    if (super.value is AsyncInitial<T>) _run();
  }

  ///Returns true if the computation ended in an [AsyncData] or [AsyncError].
  bool get canRetry => !_running;

  bool retry() {
    if (canRetry) {
      _run();
      return true;
    }
    return false;
  }

  void _run() async {
    _running = true;

    try {
      value = AsyncValue<T>.loading(previous: value);
      _future().then(
        (event) {
          if (_running) value = AsyncValue<T>.data(event);
          _running = false;
        },
        // ignore: avoid_types_on_closure_parameters
        onError: (Object err, StackTrace stack) {
          if (_running) value = AsyncValue<T>.error(err, stack);
          _running = false;
        },
      );
    } catch (e, stack) {
      value = AsyncValue.error(e, stack);
      _running = false;
    }
  }
}
