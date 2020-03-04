import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'drag.dart';
import 'sliver_drag_target_grid.dart';
import 'sliver_grid_with_animated_hole.dart';

/// A sliver grid, that can be reordered by dragging a child to a new location.
///
/// Note that, because the children returned by [delegate] will be wrapped and not placed in a [SliverGrid] directly,
/// they must not be [ParentDataWidget]s, like [KeepAlive]. In particular, Flutter's [SliverChildListDelegate] or
/// [SliverChildBuilderDelegate] should have their addAutomaticKeepAlives property set to false.
///
/// See also:
/// * [SliverLongPressReorderableGrid]
/// * [SliverGrid]
///
class SliverReorderableGrid extends StatefulWidget {
  const SliverReorderableGrid({
    @required this.delegate,
    @required this.gridDelegate,
    @required this.onReorder,
    Key key,
  })  : assert(delegate != null),
        assert(gridDelegate != null),
        assert(onReorder != null),
        super(key: key);

  /// Note: Because the children will be wrapped they can't be [KeepAlive] widgets (as that is a [ParentDataWidget]).
  /// Therefore, [SliverChildBuilderDelegate]'s and [SliverChildListDelegate]'s addAutomaticKeepAlives must not be true
  /// (which it is by default).
  final SliverChildDelegate delegate;

  final SliverGridDelegate gridDelegate;

  /// Called when a user drags and drops a child to a new location in the grid. When this callback is invoked, the next
  /// build of this widget should have a [delegate] with the children reordered.
  ///
  /// NOTE: The targetIndex might be larger then or equal to the number of children in the grid.
  final void Function(int sourceIndex, int targetIndex) onReorder;

  @protected
  MultiDragGestureRecognizer<MultiDragPointerState> createRecognizer(GestureMultiDragStartCallback onStart) =>
      ImmediateMultiDragGestureRecognizer()..onStart = onStart;

  @override
  _SliverReorderableGridState createState() => _SliverReorderableGridState();
}

/// A sliver grid, that can be reordered by long-pressing on a child and dragging it to a new location.
///
/// Note that, because the children returns by [delegate] will be wrapped, they must not be [ParentDataWidget]s. In
/// particular, Flutter's [SliverChildListDelegate]
///
/// See also:
/// * [SliverReorderableGrid]
/// * [SliverGrid]
///
class SliverLongPressReorderableGrid extends SliverReorderableGrid {
  const SliverLongPressReorderableGrid({
    @required SliverChildDelegate delegate,
    @required SliverGridDelegate gridDelegate,
    @required void Function(int sourceIndex, int targetIndex) onReorder,
    Key key,
  })  : assert(delegate != null),
        assert(gridDelegate != null),
        assert(onReorder != null),
        super(key: key, delegate: delegate, gridDelegate: gridDelegate, onReorder: onReorder);

  @override
  MultiDragGestureRecognizer<MultiDragPointerState> createRecognizer(GestureMultiDragStartCallback onStart) =>
      DelayedMultiDragGestureRecognizer()
        ..onStart = (Offset position) {
          final result = onStart(position);
          if (result != null) HapticFeedback.selectionClick();
          return result;
        };

  @override
  _SliverReorderableGridState createState() => _SliverReorderableGridState();
}

class _SliverReorderableGridState extends State<SliverReorderableGrid> {
  final _identifier = UniqueKey();
  SliverChildDelegate _wrapper;
  SliverChildDelegate _draggableWrapper;
  final _animationController = SliverGridWithAnimatedHoleAnimationController();

  int __activeDrag;

  int get _activeDrag => __activeDrag;

  set _activeDrag(int newValue) {
    if (newValue != __activeDrag) {
      __activeDrag = newValue;
      _wrapper = _SliverChildDelegateSkipper(
        omitIndex: _activeDrag,
        delegate: _draggableWrapper,
      );
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _updateWrapper();
  }

  void _updateWrapper() {
    _draggableWrapper = _SliverChildDelegateChildWrapper(
      delegate: widget.delegate,
      wrapper: (context, index, child) => _ReorderDraggable<ReorderableInfo>(
        data: ReorderableInfo(index, _identifier),
        feedback: (context, size) => SizedBox.fromSize(size: size, child: child),
        recognizerCreator: widget.createRecognizer,
        onDragStarted: () {
          _animationController.animateHoleAppearance = false;
          _animationController.animateHoleDisappearance = true;
          _activeDrag = index;
        },
        onDraggableCanceled: (_, __) async {
          _activeDrag = null;
        },
        child: child,
      ),
    );
    _wrapper = _SliverChildDelegateSkipper(
      omitIndex: _activeDrag,
      delegate: _draggableWrapper,
    );
  }

  @override
  void didUpdateWidget(SliverReorderableGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delegate != widget.delegate) {
      _updateWrapper();
    }
  }

  @override
  Widget build(BuildContext context) => SliverDragTargetGrid<ReorderableInfo>(
        delegate: _wrapper,
        gridDelegate: widget.gridDelegate,
        onWillAccept: (info) => info.sourceGrid == _identifier,
        onAccept: (info, index) {
          widget.onReorder(info.index, index);
          _animationController.animateHoleDisappearance = false;
          _activeDrag = null;
        },
        onLeave: (_) {
          _animationController.animateHoleAppearance = true;
        },
        animationController: _animationController,
      );
}

class _ReorderDraggable<T> extends BetterDraggable<T> {
  const _ReorderDraggable({
    @required Widget child,
    @required Widget Function(BuildContext, Size) feedback,
    @required this.recognizerCreator,
    Key key,
    T data,
    Widget childWhenDragging,
    Offset feedbackOffset = Offset.zero,
    DragAnchor dragAnchor = DragAnchor.child,
    VoidCallback onDragStarted,
    DraggableCanceledCallback onDraggableCanceled,
    bool ignoringFeedbackSemantics = true,
  }) : super(
          key: key,
          child: child,
          feedback: feedback,
          data: data,
          childWhenDragging: childWhenDragging,
          feedbackOffset: feedbackOffset,
          dragAnchor: dragAnchor,
          maxSimultaneousDrags: 1,
          onDragStarted: onDragStarted,
          onDraggableCanceled: onDraggableCanceled,
          ignoringFeedbackSemantics: ignoringFeedbackSemantics,
        );

  final MultiDragGestureRecognizer Function(GestureMultiDragStartCallback onStart) recognizerCreator;

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) => recognizerCreator(onStart);
}

@immutable
class ReorderableInfo {
  const ReorderableInfo(this.index, this.sourceGrid);

  final int index;
  final Key sourceGrid;
}

/// A [SliverChildDelegate] that optionally omits one of its [delegate]'s children and adds a invisible placeholder
/// at the and of its child list if it does so.
class _SliverChildDelegateSkipper extends SliverChildDelegate {
  _SliverChildDelegateSkipper({@required this.delegate, this.omitIndex}) : assert(delegate != null);

  final SliverChildDelegate delegate;
  final int omitIndex;

  @override
  Widget build(BuildContext context, int index) {
    Widget childWidget;
    if (omitIndex != null && index >= omitIndex) {
      childWidget = delegate.build(context, index + 1);
    } else {
      childWidget = delegate.build(context, index);
    }
    // When our delegate SliverChildDelegate's build returns null, per the interface, its estimatedChildCount must
    // return an accurate value. This is used so we can return an additional child at the end of the list. This child
    // allows the user to drop a child after the last child in the grid.
    if (omitIndex != null && childWidget == null) {
      assert(delegate.estimatedChildCount != null);
      if (delegate.estimatedChildCount - 1 == index) {
        return const SizedBox();
      }
    }
    return childWidget;
  }

  @override
  // Out child count is identical to that of our delegate. When omitIndex is specified, a child is omitted, but also
  // an additional child is added at the end of the list
  int get estimatedChildCount => delegate.estimatedChildCount;

  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) =>
      delegate.estimateMaxScrollOffset(firstIndex, lastIndex, leadingScrollOffset, trailingScrollOffset);

  @override
  void didFinishLayout(int firstIndex, int lastIndex) {
    if (omitIndex != null && omitIndex <= lastIndex) {
      if (omitIndex > firstIndex) {
        delegate.didFinishLayout(
          firstIndex,
          omitIndex - 1,
        );
        delegate.didFinishLayout(
          omitIndex + 1,
          lastIndex + 1,
        );
      } else {
        delegate.didFinishLayout(
          firstIndex + 1,
          lastIndex + 1,
        );
      }
    } else {
      delegate.didFinishLayout(firstIndex, lastIndex);
    }
  }

  @override
  int findIndexByKey(Key key) => delegate.findIndexByKey(key);

  @override
  bool shouldRebuild(_SliverChildDelegateSkipper oldDelegate) =>
      oldDelegate.delegate != delegate || oldDelegate.omitIndex != omitIndex;
}

/// A [SliverChildDelegate] that wraps the children of its [delegate] using [wrapper]
class _SliverChildDelegateChildWrapper extends SliverChildDelegate {
  _SliverChildDelegateChildWrapper({@required this.delegate, @required this.wrapper})
      : assert(delegate != null),
        assert(wrapper != null);

  final SliverChildDelegate delegate;
  final Widget Function(BuildContext, int index, Widget child) wrapper;

  @override
  Widget build(BuildContext context, int index) {
    final childWidget = delegate.build(context, index);
    if (childWidget != null) {
      return KeyedSubtree(
        key: childWidget.key,
        child: wrapper(context, index, Builder(builder: (context) => childWidget)),
      );
    } else {
      return null;
    }
  }

  @override
  int get estimatedChildCount => delegate.estimatedChildCount;

  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) =>
      delegate.estimateMaxScrollOffset(firstIndex, lastIndex, leadingScrollOffset, trailingScrollOffset);

  @override
  void didFinishLayout(int firstIndex, int lastIndex) => delegate.didFinishLayout(firstIndex, lastIndex);

  @override
  int findIndexByKey(Key key) => delegate.findIndexByKey(key);

  @override
  bool shouldRebuild(_SliverChildDelegateChildWrapper oldDelegate) =>
      oldDelegate.delegate != delegate || oldDelegate.wrapper != wrapper;
}
