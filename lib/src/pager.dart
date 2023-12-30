import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stream_transform/stream_transform.dart';

abstract class AsyncPagedState<T, E> {
  abstract final AsyncViewState asyncViewState;
  abstract final PagingStatus pagingStatus;
  abstract final List<T> paginatedList;
  abstract final E? asyncError;

  AsyncPagedState<T, E> copyWith({
    AsyncViewState? asyncViewState,
    PagingStatus? pagingStatus,
    List<T>? paginatedList,
    E? asyncError,
  });
}

enum AsyncViewState {
  idle,
  loading,
  success,
  error;

  Widget when({
    required Widget Function() idle,
    required Widget Function() loading,
    required Widget Function() success,
    required Widget Function() error,
  }) =>
      switch (this) {
        AsyncViewState.idle => idle(),
        AsyncViewState.loading => loading(),
        AsyncViewState.success => success(),
        AsyncViewState.error => error(),
      };
}

enum PagingStatus {
  idle,
  paginating,
  paginationCompleted,
  paginationExhausted;

  get isPaginationCompleted => this == paginationCompleted;

  get hasReachedMax => this == paginationExhausted;
}

mixin BlocPager<Type, Error, Event,
State extends AsyncPagedState<Type, Error>> {
  EventTransformer<E> throttleDroppable<E>(Duration duration) {
    return (events, mapper) {
      return droppable<E>().call(events.throttle(duration), mapper);
    };
  }

  Future<void> pager(
      {required Event event,
        required Emitter<AsyncPagedState<Type, Error>> emit,
        required State state,
        required Future<Either<Error?, List<Type>>> Function(
            int pageSize, int page)
        useCase,
        required int pageSize,
        required int page}) async {

    emit(state.copyWith(pagingStatus: PagingStatus.paginating));
    if (state.pagingStatus == PagingStatus.paginationExhausted) return;
    // check if is first loading
    if (state.asyncViewState == AsyncViewState.idle) {
      //emit loading status
      emit(state.copyWith(asyncViewState: AsyncViewState.loading));
      final response = await useCase(pageSize, page);
      response.fold((error) {
        return emit(state.copyWith(
            asyncError: error,
            asyncViewState: AsyncViewState.error,
            pagingStatus: PagingStatus.paginationCompleted));
      }, (data) {
        return emit(state.copyWith(
          paginatedList: data,
          asyncViewState: AsyncViewState.success,
          pagingStatus: PagingStatus.paginationCompleted,
        ));
      });
    } else {
      // if is not first loading not emit loading status
      final response = await useCase(pageSize, page);
      response.fold((error) {
        return emit(state.copyWith(
            asyncError: error, asyncViewState: AsyncViewState.error));
      }, (data) {
        return emit((data.isEmpty || data.length < pageSize)
            ? state.copyWith(pagingStatus: PagingStatus.paginationExhausted)
            : state.copyWith(
          paginatedList: [...state.paginatedList, ...data],
          asyncViewState: AsyncViewState.success,
          pagingStatus: PagingStatus.paginationCompleted,
        ));
      });
    }
  }
}
