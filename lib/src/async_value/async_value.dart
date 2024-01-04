import 'package:meta/meta.dart' show immutable, sealed;

/// An utility for safely manipulating asynchronous data.
///
/// By using [AsyncValue], you are guaranteed that you cannot forget to
/// handle the loading/error state of an asynchronous operation.
///
/// It also expose some utilities to nicely convert an [AsyncValue] to
/// a different object.
/// For example, a Flutter Widget may use [when] to convert an [AsyncValue]
/// into either a progress indicator, an error screen, or to show the data:
///
/// ```dart
/// /// A provider that asynchronously expose the current user
/// final userProvider = StreamProvider<User>((_) async* {
///   // fetch the user
/// });
///
/// class Example extends ConsumerWidget {
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     final AsyncValue<User> user = ref.watch(userProvider);
///
///     return user.when(
///       loading: (_) => CircularProgressIndicator(),
///       error: (error, stack) => Text('Oops, something unexpected happened'),
///       data: (value) => Text('Hello ${user.name}'),
///     );
///   }
/// }
/// ```
///
/// If a consumer of an [AsyncValue] does not care about the loading/error
/// state, consider using [value] to read the state:
///
/// ```dart
/// Widget build(BuildContext context, WidgetRef ref) {
///   // reads the data state directly – will be throw during loading/error states
///   final User user = ref.watch(userProvider).value;
///
///   return Text('Hello ${user.name}');
/// }
/// ```
///
/// See also:
///
/// - [FutureProvider] and [StreamProvider], which transforms a [Future] into
///   an [AsyncValue].
/// - [AsyncValue.guard], to simplify transforming a [Future] into an [AsyncValue].
@sealed
@immutable
abstract class AsyncValue<T> {
  /// Creates an [AsyncValue] with a data.
  ///
  /// The data can be `null`.
  const factory AsyncValue.data(T value) = AsyncData<T>;

  /// Creates an [AsyncValue] in loading state.
  ///
  /// Prefer always using this constructor with the `const` keyword.
  const factory AsyncValue.loading({AsyncValue<T>? previous}) = AsyncLoading<T>;

  /// Creates an [AsyncValue] that has not been started yet.
  ///
  ///
  const factory AsyncValue.initial() = AsyncInitial<T>;

  /// Creates an [AsyncValue] in error state.
  ///
  /// The parameter [error] cannot be `null`.
  const factory AsyncValue.error(
    Object error, [
    StackTrace? stackTrace,
  ]) = AsyncError<T>;

  /// Transforms a [Future] that may fail into something that is safe to read.
  ///
  /// This is useful to avoid having to do a tedious `try/catch`. Instead of:
  ///
  /// ```dart
  /// class MyNotifier extends StateNotifier<AsyncValue<MyData> {
  ///   MyNotifier(): super(const AsyncValue.loading()) {
  ///     _fetchData();
  ///   }
  ///
  ///   Future<void> _fetchData() async {
  ///     state = const AsyncValue.loading();
  ///     try {
  ///       final response = await dio.get('my_api/data');
  ///       final data = MyData.fromJson(response);
  ///       state = AsyncValue.data(data);
  ///     } catch (err, stack) {
  ///       state = AsyncValue.error(err, stack);
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// which is redundant as the application grows and we need more and more of this
  /// pattern – we can use [guard] to simplify it:
  ///
  ///
  /// ```dart
  /// class MyNotifier extends StateNotifier<AsyncValue<MyData>> {
  ///   MyNotifier(): super(const AsyncValue.loading()) {
  ///     _fetchData();
  ///   }
  ///
  ///   Future<void> _fetchData() async {
  ///     state = const AsyncValue.loading();
  ///     // does the try/catch for us like previously
  ///     state = await AsyncValue.guard(() async {
  ///       final response = await dio.get('my_api/data');
  ///       return Data.fromJson(response);
  ///     });
  ///   }
  /// }
  /// ```
  static Future<AsyncValue<T>> guard<T>(Future<T> Function() future) async {
    try {
      return AsyncValue.data(await future());
    } catch (err, stack) {
      return AsyncValue.error(err, stack);
    }
  }

  // private mapper, so that classes inheriting AsyncValue can specify their own
  // `map` method with different parameters.
  R _map<R>({
    required R Function(AsyncInitial<T> initial) initial,
    required R Function(AsyncData<T> data) data,
    required R Function(AsyncError<T> error) error,
    required R Function(AsyncLoading<T> loading) loading,
  });
}

/// Creates an [AsyncValue] with a data.
///
/// The data can be `null`.
class AsyncData<T> implements AsyncValue<T> {
  /// Creates an [AsyncValue] with a data.
  ///
  /// The data can be `null`.
  const AsyncData(this.value);

  /// The value currently exposed.
  final T value;

  @override
  R _map<R>({
    required R Function(AsyncInitial<T> initial) initial,
    required R Function(AsyncData<T> data) data,
    required R Function(AsyncError<T> error) error,
    required R Function(AsyncLoading<T> loading) loading,
  }) {
    return data(this);
  }

  @override
  String toString() {
    return 'AsyncData<$T>(value: $value)';
  }

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType && other is AsyncData<T> && other.value == value;
  }

  @override
  int get hashCode => '$runtimeType${value.hashCode}'.hashCode;
}

/// An extension that adds methods like [when] to an [AsyncValue].
extension AsyncValueX<T> on AsyncValue<T> {
  /// Upcast [AsyncValue] into an [AsyncData], or return null if the [AsyncValue]
  /// is in loading/error state.
  AsyncData<T>? get getOrNull {
    return _map(data: (d) => d, error: (e) => null, loading: (l) => null, initial: (i) => null);
  }

  /// Unwrap an [AsyncValue] content if its an [AsyncData] else null.
  T? get valueOrNull {
    return _map(
      initial: (i) => null,
      data: (d) => d.value,
      error: (e) => null,
      loading: (l) => null,
    );
  }

  /// Shorthand for [when] to handle only the `data` case.
  ///
  /// For loading/error cases, creates a new [AsyncValue] with the corresponding
  /// generic type while preserving the error/stacktrace.
  AsyncValue<R> whenData<R>(R Function(T value) cb) {
    return _map(
        data: (d) {
          try {
            return AsyncValue.data(cb(d.value));
          } catch (err, stack) {
            return AsyncValue.error(err, stack);
          }
        },
        error: (e) => AsyncError(e.error, e.stackTrace),
        loading: (l) => AsyncLoading<R>(),
        initial: (i) => AsyncInitial<R>());
  }

  /// Switch-case over the state of the [AsyncValue] while purposefully not handling
  /// some cases.
  ///
  /// If [AsyncValue] was in a case that is not handled, will return [orElse].
  R maybeWhen<R>({
    R Function(AsyncInitial<T> initial)? initial,
    R Function(T data)? data,
    R Function(Object error, StackTrace? stackTrace)? error,
    R Function(AsyncValue<T>? previous)? loading,
    required R Function() orElse,
  }) {
    return _map(data: (d) {
      if (data != null) return data(d.value);
      return orElse();
    }, error: (e) {
      if (error != null) return error(e.error, e.stackTrace);
      return orElse();
    }, loading: (l) {
      if (loading != null) return loading(l.previous);
      return orElse();
    }, initial: (i) {
      if (initial != null) return initial(i);
      return orElse();
    });
  }

  /// Performs an action based on the state of the [AsyncValue].
  ///
  /// All cases are required, which allows returning a non-nullable value.
  R when<R>({
    required R Function(AsyncInitial<T> initial) initial,
    required R Function(T data) data,
    required R Function(Object error, StackTrace? stackTrace) error,
    required R Function(AsyncValue<T>? previous) loading,
  }) {
    return _map(
        data: (d) => data(d.value),
        error: (e) => error(e.error, e.stackTrace),
        loading: (l) => loading(l.previous),
        initial: (i) => initial(i));
  }

  /// Perform actions conditionally based on the state of the [AsyncValue].
  ///
  /// Returns null if [AsyncValue] was in a state that was not handled.
  ///
  /// This is similar to [maybeWhen] where `orElse` returns null.
  R? whenOrNull<R>({
    R Function(AsyncInitial<T> initial)? initial,
    R Function(T data)? data,
    R Function(Object error, StackTrace? stackTrace)? error,
    R Function(AsyncValue<T>? previous)? loading,
  }) {
    return _map(
      data: (d) => data?.call(d.value),
      error: (e) => error?.call(e.error, e.stackTrace),
      loading: (l) => loading?.call(l.previous),
      initial: (i) => initial?.call(i),
    );
  }

  /// Perform some action based on the current state of the [AsyncValue].
  ///
  /// This allows reading the content of an [AsyncValue] in a type-safe way,
  /// without potentially ignoring to handle a case.
  R map<R>({
    required R Function(AsyncInitial<T> initial) initial,
    required R Function(AsyncData<T> data) data,
    required R Function(AsyncError<T> error) error,
    required R Function(AsyncLoading<T> loading) loading,
  }) {
    return _map(data: data, error: error, loading: loading, initial: initial);
  }

  /// Perform some actions based on the state of the [AsyncValue], or call orElse
  /// if the current state was not tested.
  R maybeMap<R>({
    R Function(AsyncInitial<T> initial)? initial,
    R Function(AsyncData<T> data)? data,
    R Function(AsyncError<T> error)? error,
    R Function(AsyncLoading<T> loading)? loading,
    required R Function() orElse,
  }) {
    return _map(data: (d) {
      if (data != null) return data(d);
      return orElse();
    }, error: (d) {
      if (error != null) return error(d);
      return orElse();
    }, loading: (d) {
      if (loading != null) return loading(d);
      return orElse();
    }, initial: (i) {
      if (initial != null) return initial(i);
      return orElse();
    });
  }

  /// Perform some actions based on the state of the [AsyncValue], or return null
  /// if the current state wasn't tested.
  R? mapOrNull<R>({
    R Function(AsyncInitial<T> initial)? initial,
    R Function(AsyncData<T> data)? data,
    R Function(AsyncError<T> error)? error,
    R Function(AsyncLoading<T> loading)? loading,
  }) {
    return _map(
      data: (d) => data?.call(d),
      error: (d) => error?.call(d),
      loading: (d) => loading?.call(d),
      initial: (i) => initial?.call(i),
    );
  }
}

/// Creates an [AsyncValue] in loading state.
///
/// Prefer always using this constructor with the `const` keyword.
class AsyncLoading<T> implements AsyncValue<T> {
  /// Creates an [AsyncValue] in loading state.
  ///
  /// Prefer always using this constructor with the `const` keyword.
  const AsyncLoading({this.previous, this.progress});

  /// The previous error or loading valid state, if any.
  ///
  /// This is useful when a value is refreshing, to keep showing the value
  /// before refresh while the request is pending.
  final AsyncValue<T>? previous;

  /// An optional progress percentage for slow (down/up)loads
  ///
  /// This is useful to display in the UI the download progress if available
  final double? progress;

  @override
  R _map<R>({
    required R Function(AsyncInitial<T> initial) initial,
    required R Function(AsyncData<T> data) data,
    required R Function(AsyncError<T> error) error,
    required R Function(AsyncLoading<T> loading) loading,
  }) {
    return loading(this);
  }

  @override
  String toString() {
    return 'AsyncLoading<$T>(previous: $previous)';
  }

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType && other is AsyncLoading<T> && other.previous == previous;
  }

  @override
  int get hashCode => '$runtimeType${previous.hashCode}'.hashCode;
}

/// Creates an [AsyncValue] in error state.
///
/// The parameter [error] cannot be `null`.
class AsyncError<T> implements AsyncValue<T> {
  /// Creates an [AsyncValue] in error state.
  ///
  /// The parameter [error] cannot be `null`.
  const AsyncError(this.error, [this.stackTrace]);

  /// The error.
  final Object error;

  /// The stacktrace of [error].
  final StackTrace? stackTrace;

  @override
  R _map<R>({
    required R Function(AsyncInitial<T> initial) initial,
    required R Function(AsyncData<T> data) data,
    required R Function(AsyncError<T> error) error,
    required R Function(AsyncLoading<T> loading) loading,
  }) {
    return error(this);
  }

  @override
  String toString() {
    return 'AsyncError<$T>(error: $error, stackTrace: $stackTrace)';
  }

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType &&
        other is AsyncError<T> &&
        other.error == error &&
        other.stackTrace == stackTrace;
  }

  @override
  int get hashCode => '$runtimeType${error.hashCode + stackTrace.hashCode}'.hashCode;
}

/// Creates an [AsyncValue] in initial state.
///
/// Prefer always using this constructor with the `const` keyword.
class AsyncInitial<T> implements AsyncValue<T> {
  /// Creates an [AsyncValue] in initial state.
  ///
  /// Prefer always using this constructor with the `const` keyword.
  const AsyncInitial();

  @override
  R _map<R>({
    required R Function(AsyncInitial<T> initial) initial,
    required R Function(AsyncData<T> data) data,
    required R Function(AsyncError<T> error) error,
    required R Function(AsyncLoading<T> loading) loading,
  }) {
    return initial(this);
  }

  @override
  String toString() {
    return 'AsyncInitial<$T>()';
  }

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType && other is AsyncInitial<T>;
  }

  int get hashCode => '$runtimeType'.hashCode;
}

/// An exception thrown when trying to read [AsyncValueX.value] before the value
/// was loaded.
class AsyncValueLoadingError extends Error {}
