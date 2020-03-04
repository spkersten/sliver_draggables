import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'drag.dart';
import 'sliver_grid_with_animated_hole.dart';
import 'sliver_meta_data.dart';

/// A sliver grid that can serve as a drag target.
///
/// When [onWillAccept] returns true (or isn't specified), the widget will animate
/// a hole under the draggable where the draggable would end up when dropped.
/// In all other respects in behaves like [SliverGrid].
///
class SliverDragTargetGrid<T> extends StatefulWidget {
  const SliverDragTargetGrid({
    @required this.delegate,
    @required this.gridDelegate,
    this.onWillAccept,
    this.onAccept,
    this.onLeave,
    this.animationController,
    Key key,
  })  : assert(delegate != null),
        assert(gridDelegate != null),
        super(key: key);

  final SliverChildDelegate delegate;
  final SliverGridDelegate gridDelegate;

  /// Called to determine whether this widget is interested in receiving a given
  /// piece of data being dragged over this drag target. When not specified, all
  /// data will be accepted.
  ///
  /// Called when a piece of data enters the target. This will be followed by
  /// either [onAccept], if the data is dropped, or [onLeave], if the drag
  /// leaves the target.
  final DragTargetWillAccept<T> onWillAccept;

  /// Called when an acceptable piece of data was dropped over this drag target
  /// and the index at which it was dropped.
  ///
  /// NOTE: The index might be larger then or equal to the number of children in the grid.
  final SliverGridDragTargetAccept<T> onAccept;

  /// Called when a given piece of data being dragged over this target leaves
  /// the target.
  final DragTargetLeave onLeave;

  final SliverGridWithAnimatedHoleAnimationController animationController;

  @override
  SliverDragTargetGridState<T> createState() => SliverDragTargetGridState<T>();
}

/// Signature for when the draggable is dropped on a grid at position [index]
typedef SliverGridDragTargetAccept<T> = void Function(T data, int index);

class SliverDragTargetGridState<T> extends State<SliverDragTargetGrid<T>> implements BetterDragTargetState {
  int _hoverIndex;
  DragAvatar<T> _candidateAvatar;

  @override
  void updateDragAvatarPosition(Offset globalPosition) {
    final renderObject = context.findRenderObject() as RenderSliver;
    final localPos = _globalToLocal(globalPosition, renderObject.getTransformTo(null));

    final layout = widget.gridDelegate.getLayout(renderObject.constraints);

    final firstIndex = layout.getMinChildIndexForScrollOffset(renderObject.constraints.scrollOffset);
    final lastIndex = layout.getMaxChildIndexForScrollOffset(
        renderObject.constraints.scrollOffset + renderObject.constraints.remainingPaintExtent);

    int newHoverIndex;
    for (var index = firstIndex; index <= lastIndex; index++) {
      final geometryForChildIndex = layout.getGeometryForChildIndex(index);
      final childRect = _rectForSliverGridGeometry(geometryForChildIndex, renderObject.constraints);
      if (childRect.contains(localPos)) {
        newHoverIndex = index;
        break;
      }
    }
    // newHoverIndex == null is ignored because it corresponds to the draggable on the spacing between the grid items.
    // The draggable leaving our bounds is handled by the didLeave callback.
    if (newHoverIndex != null && newHoverIndex != _hoverIndex) {
      setState(() {
        _hoverIndex = newHoverIndex;
      });
    }
  }

  Rect _rectForSliverGridGeometry(SliverGridGeometry geometry, SliverConstraints constraints) {
    Offset offset;
    switch (constraints.axis) {
      case Axis.vertical:
        offset = Offset(
          geometry.crossAxisOffset,
          geometry.scrollOffset - constraints.scrollOffset,
        );
        break;
      case Axis.horizontal:
        offset = Offset(
          geometry.scrollOffset - constraints.scrollOffset,
          geometry.crossAxisOffset,
        );
        break;
    }
    return offset & geometry.getBoxConstraints(constraints).biggest;
  }

  @override
  bool didEnter(Offset globalPosition, DragAvatar<dynamic> avatar) {
    if (avatar.data is T &&
        _candidateAvatar == null &&
        (widget.onWillAccept == null || widget.onWillAccept(avatar.data as T))) {
      _candidateAvatar = avatar as DragAvatar<T>;
      updateDragAvatarPosition(globalPosition);
      return true;
    } else {
      return false;
    }
  }

  @override
  void didLeave(DragAvatar<dynamic> avatar) {
    if (avatar == _candidateAvatar) {
      if (mounted) {
        setState(() {
          _candidateAvatar = null;
          _hoverIndex = null;
        });
        if (widget.onLeave != null) widget.onLeave(avatar.data as T);
      }
    }
  }

  @override
  void didDrop(DragAvatar<dynamic> avatar) {
    if (avatar == _candidateAvatar) {
      if (mounted) {
        final index = _hoverIndex;
        setState(() {
          _hoverIndex = null;
          _candidateAvatar = null;
        });
        if (widget.onAccept != null) widget.onAccept(avatar.data as T, index);
      }
    }
  }

  /// Copied from [RenderBox.globalToLocal] as our [RenderSliver] doesn't have an equivalent
  Offset _globalToLocal(Offset point, Matrix4 transform) {
    // We want to find point (p) that corresponds to a given point on the
    // screen (s), but that also physically resides on the local render plane,
    // so that it is useful for visually accurate gesture processing in the
    // local space. For that, we can't simply transform 2D screen point to
    // the 3D local space since the screen space lacks the depth component |z|,
    // and so there are many 3D points that correspond to the screen point.
    // We must first unproject the screen point onto the render plane to find
    // the true 3D point that corresponds to the screen point.
    // We do orthogonal unprojection after undoing perspective, in local space.
    // The render plane is specified by renderBox offset (o) and Z axis (n).
    // Unprojection is done by finding the intersection of the view vector (d)
    // with the local X-Y plane: (o-s).dot(n) == (p-s).dot(n), (p-s) == |z|*d.
    final det = transform.invert();
    if (det == 0.0) return Offset.zero;
    final n = Vector3(0.0, 0.0, 1.0);
    final i = transform.perspectiveTransform(Vector3(0.0, 0.0, 0.0));
    final d = transform.perspectiveTransform(Vector3(0.0, 0.0, 1.0)) - i;
    final s = transform.perspectiveTransform(Vector3(point.dx, point.dy, 0.0));
    final p = s - d * (n.dot(s) / n.dot(d));
    return Offset(p.x, p.y);
  }

  @override
  Widget build(BuildContext context) => SliverMetaData(
        metaData: this,
        behavior: HitTestBehavior.opaque,
        child: SliverGridWithAnimatedHole(
          delegate: widget.delegate,
          gridDelegate: widget.gridDelegate,
          duration: const Duration(milliseconds: 300),
          holeIndex: _hoverIndex,
          animationController: widget.animationController,
        ),
      );
}
