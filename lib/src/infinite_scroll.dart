import 'package:flutter/material.dart';

class BlocInfiniteList<T> extends StatefulWidget {
  ///Helper Widget for infinite scroll
  ///[T] represents the data type of our [itemList],
  const BlocInfiniteList({
    super.key,
    required this.itemList,
    required this.triggerEvent,
    this.loadingBuilder,
    this.bottomBuilder,
    required this.child,
    required this.scrollableWidgetBuilder,
    required this.hasReachedMax,
    required this.pagingCompleted,
    this.initialPage = 1,
  });

  /// list of items to display
  final List<T> itemList;

  /// Value from our BLOC that indicates whether the end of pagination has been reached
  final bool hasReachedMax;

  /// function to call BLOC event that triggers loading of elements
  /// ```dart
  ///triggerEvent:(page){
  /// context.read<Bloc>().add(Fetched(page: page)) ;
  /// },
  /// ```
  ///
  final void Function(int page) triggerEvent;

  /// [optional] widget to show in loading status
  final Widget? Function()? loadingBuilder;

  /// [optional] widget to show when there are no more elements to show
  final Widget? Function()? bottomBuilder;

  /// widget that displays items
  final Widget? Function(T) child;

  /// represent when a page is completed loaded
  final bool pagingCompleted;

  /// set initial page, by default is 1
  final int initialPage;

  /// Layout in which the elements will be displayed.
  /// It can be List, Grid or any other type.
  /// Provides [controller], [itemCount],and the [itemBuilder]
  /// that builds the [child] widget
  final Widget Function(
      ScrollController controller,
      int itemCount,
      Widget? Function(BuildContext, int) itemBuilder,
      ) scrollableWidgetBuilder;

  @override
  State<BlocInfiniteList<T>> createState() => _BlocInfiniteListState<T>();
}

class _BlocInfiniteListState<T> extends State<BlocInfiniteList<T>> {
  final ScrollController _scrollController = ScrollController();
  late int page;
  bool isPaging = false;

  @override
  void initState() {
    super.initState();
    page = widget.initialPage;
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      if(!isPaging){
        widget.triggerEvent(page);
        isPaging = true;
        page++;
      }
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  Widget build(BuildContext context) {
    if(widget.pagingCompleted){
      isPaging= false;
    }

    final itemCount = widget.hasReachedMax
        ? widget.itemList.length
        : widget.itemList.length + 1;

    return widget.scrollableWidgetBuilder(
      _scrollController,
      itemCount,
          (context, index) {
        return index >= (widget.itemList.length)
            ? widget.hasReachedMax
            ? widget.bottomBuilder?.call()
            : widget.loadingBuilder?.call()
            : widget.child(widget.itemList[index]);
      },
    );
  }
}

