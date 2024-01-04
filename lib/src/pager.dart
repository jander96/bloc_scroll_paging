import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:bloc_scroll_paging/src/async_value/async_value.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stream_transform/stream_transform.dart';

///Represent a base state of a Paginated view. All your state must inherit
///from it
abstract class AsyncPagedState<T, E> {
  abstract final AsyncValue<List<T>> asyncValue;
  abstract final PagingStatus pagingStatus;

  AsyncPagedState<T, E> copyWith({
    AsyncValue<List<T>>? asyncValue,
    PagingStatus? pagingStatus,
  });
}


enum PagingStatus {
  idle,
  paginating,
  paginationCompleted,
  paginationExhausted;

/// return true if current pagination loading is ended
  get isPaginationCompleted => this == paginationCompleted;
/// return true if is no more items from source
  get hasReachedMax => this == paginationExhausted;
}
///Provides an easy and reusable way to request paginated data
/// from the data layer and output the correct status.
///
/// Use generic data. Because Either<L,R> is used for error handling,
/// it is necessary to specify the [Type] of data that is being paged
/// and the type of [Error] that can be thrown.
/// Additionally, since we are using [Bloc],
/// the [Event] and [State] that the Bloc handles must also be provided.
/// The state must necessarily inherit from the AsyncPagedState class
mixin BlocPager<Type, Error, Event,
State extends AsyncPagedState<Type, Error>> on Bloc<Event,State> {

  /// transformer to cancel new request while a old request is in process
  EventTransformer<E> pagerTransformerDrop<E>(Duration duration) {
    return (events, mapper) {
      return droppable<E>().call(events.throttle(duration), mapper);
    };
  }
  /// Is a core function where pagination request is made.
  /// Sample:
  /// ```dart
  /// on<Fetched>((event, emit) {
  ///       return pager(
  ///          event: event,
  ///           emit: emit,
  ///           useCase: repository.getList,
  ///          pageSize: event.pageSize,
  ///           page: event.page);
  ///     }, transformer: throttleDroppable(throttleDuration));
  ///```
  ///
  Future<void> pager(
      {
        required Event event,
        required Emitter<AsyncPagedState<Type, Error>> emit,
        ///Is a function from data layer that return an Either<L,R>
        required Future<Either<Error?, List<Type>>> Function(
            int pageSize, int page)
        useCase,
        required int pageSize,
        required int page}) async {

    emit(state.copyWith(pagingStatus: PagingStatus.paginating));
    if (state.pagingStatus == PagingStatus.paginationExhausted) return;
    // check if is first loading
    if (state.asyncValue == const AsyncValue.initial()) {
      //emit loading status
      emit(state.copyWith(asyncValue: const AsyncValue.loading()));
      final response = await useCase(pageSize, page);
      response.fold((error) {
        return emit(state.copyWith(
            asyncValue: AsyncValue.error(error!),
            pagingStatus: PagingStatus.paginationCompleted));
      }, (data) {
        return emit(state.copyWith(
          asyncValue: AsyncData(data),
          pagingStatus: PagingStatus.paginationCompleted,
        ));
      });
    } else {
      // if is not first loading not emit loading status
      final response = await useCase(pageSize, page);
      response.fold((error) {
        return emit(state.copyWith(
            asyncValue: AsyncError(error!)));
      }, (data) {
        return emit((data.isEmpty || data.length < pageSize)
            ? state.copyWith(pagingStatus: PagingStatus.paginationExhausted)
            : state.copyWith(
          asyncValue: AsyncData([...state.asyncValue.valueOrNull ?? [], ...data]) ,
          pagingStatus: PagingStatus.paginationCompleted,
        ));
      });
    }
  }
}
