// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// This code was adapted from Flutter to enable more advanced drags. In particular:
///
/// - [BetterDragTargetState] was introduced as interface for [State] classes that want to receive updates when things are
///   dragged over it. Flutter's [BetterDragTarget] is a box widget; with [BetterDragTargetState] also slivers can be made
///   drag targets.
/// - [BetterDragTargetState.updateDragAvatarPosition] was introduced, so drag targets can keep receiving updates when
///   something is being dragged over it.
/// - [BetterDraggable.feedback]'s type was changed into a builder that include the size of the [BetterDraggable] at the moment
///   the drag started. This can be used to size the feedback widget (shown during dragging) the same as the widget
///   before dragging. The widget is otherwise unconstrained.
///
/// Other features we want that aren't possible without changes to this code include:
/// - Animating the widget back to its original location when a drag is canceled
/// - Animating the widget to its target location/shape when a drag is accepted

import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'sliver_meta_data.dart';

abstract class BetterDragTargetState {
  bool didEnter(Offset globalPosition, DragAvatar<dynamic> avatar);

  void didLeave(DragAvatar<dynamic> avatar) {}

  void didDrop(DragAvatar<dynamic> avatar) {}

  void updateDragAvatarPosition(Offset globalPosition) {}
}

/// A widget that can be dragged from to a [BetterDragTarget].
///
/// When a draggable widget recognizes the start of a drag gesture, it displays
/// a [feedback] widget that tracks the user's finger across the screen. If the
/// user lifts their finger while on top of a [BetterDragTarget], that target is given
/// the opportunity to accept the [data] carried by the draggable.
///
/// On multitouch devices, multiple drags can occur simultaneously because there
/// can be multiple pointers in contact with the device at once. To limit the
/// number of simultaneous drags, use the [maxSimultaneousDrags] property. The
/// default is to allow an unlimited number of simultaneous drags.
///
/// This widget displays [child] when zero drags are under way. If
/// [childWhenDragging] is non-null, this widget instead displays
/// [childWhenDragging] when one or more drags are underway. Otherwise, this
/// widget always displays [child].
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=QzA4c4QHZCY}
///
/// See also:
///
///  * [BetterDragTarget]
///  * [BetterLongPressDraggable]
class BetterDraggable<T> extends StatefulWidget {
  /// Creates a widget that can be dragged to a [BetterDragTarget] or [StatefulWidget] whose state extends [BetterDragTargetState].
  ///
  /// The [child] and [feedback] arguments must not be null. If
  /// [maxSimultaneousDrags] is non-null, it must be non-negative.
  const BetterDraggable({
    @required this.child,
    @required this.feedback,
    Key key,
    this.data,
    this.axis,
    this.childWhenDragging,
    this.feedbackOffset = Offset.zero,
    this.dragAnchor = DragAnchor.child,
    this.affinity,
    this.maxSimultaneousDrags,
    this.onDragStarted,
    this.onDraggableCanceled,
    this.onDragEnd,
    this.onDragCompleted,
    this.ignoringFeedbackSemantics = true,
  })  : assert(child != null),
        assert(feedback != null),
        assert(ignoringFeedbackSemantics != null),
        assert(maxSimultaneousDrags == null || maxSimultaneousDrags >= 0),
        super(key: key);

  /// The data that will be dropped by this draggable.
  final T data;

  /// The [Axis] to restrict this draggable's movement, if specified.
  ///
  /// When axis is set to [Axis.horizontal], this widget can only be dragged
  /// horizontally. Behavior is similar for [Axis.vertical].
  ///
  /// Defaults to allowing drag on both [Axis.horizontal] and [Axis.vertical].
  ///
  /// When null, allows drag on both [Axis.horizontal] and [Axis.vertical].
  ///
  /// For the direction of gestures this widget competes with to start a drag
  /// event, see [BetterDraggable.affinity].
  final Axis axis;

  /// The widget below this widget in the tree.
  ///
  /// This widget displays [child] when zero drags are under way. If
  /// [childWhenDragging] is non-null, this widget instead displays
  /// [childWhenDragging] when one or more drags are underway. Otherwise, this
  /// widget always displays [child].
  ///
  /// The [feedback] widget is shown under the pointer when a drag is under way.
  ///
  /// To limit the number of simultaneous drags on multitouch devices, see
  /// [maxSimultaneousDrags].
  ///
  /// {@macro flutter.widgets.child}
  final Widget child;

  /// The widget to display instead of [child] when one or more drags are under way.
  ///
  /// If this is null, then this widget will always display [child] (and so the
  /// drag source representation will not change while a drag is under
  /// way).
  ///
  /// The [feedback] widget is shown under the pointer when a drag is under way.
  ///
  /// To limit the number of simultaneous drags on multitouch devices, see
  /// [maxSimultaneousDrags].
  final Widget childWhenDragging;

  /// The widget to show under the pointer when a drag is under way. The [Size]
  /// argument is the size of this widget the moment the drag starts.
  ///
  /// See [child] and [childWhenDragging] for information about what is shown
  /// at the location of the [BetterDraggable] itself when a drag is under way.
  final Widget Function(BuildContext, Size) feedback;

  /// The feedbackOffset can be used to set the hit test target point for the
  /// purposes of finding a drag target. It is especially useful if the feedback
  /// is transformed compared to the child.
  final Offset feedbackOffset;

  /// Where this widget should be anchored during a drag.
  final DragAnchor dragAnchor;

  /// Whether the semantics of the [feedback] widget is ignored when building
  /// the semantics tree.
  ///
  /// This value should be set to false when the [feedback] widget is intended
  /// to be the same object as the [child].  Placing a [GlobalKey] on this
  /// widget will ensure semantic focus is kept on the element as it moves in
  /// and out of the feedback position.
  ///
  /// Defaults to true.
  final bool ignoringFeedbackSemantics;

  /// Controls how this widget competes with other gestures to initiate a drag.
  ///
  /// If affinity is null, this widget initiates a drag as soon as it recognizes
  /// a tap down gesture, regardless of any directionality. If affinity is
  /// horizontal (or vertical), then this widget will compete with other
  /// horizontal (or vertical, respectively) gestures.
  ///
  /// For example, if this widget is placed in a vertically scrolling region and
  /// has horizontal affinity, pointer motion in the vertical direction will
  /// result in a scroll and pointer motion in the horizontal direction will
  /// result in a drag. Conversely, if the widget has a null or vertical
  /// affinity, pointer motion in any direction will result in a drag rather
  /// than in a scroll because the draggable widget, being the more specific
  /// widget, will out-compete the [Scrollable] for vertical gestures.
  ///
  /// For the directions this widget can be dragged in after the drag event
  /// starts, see [BetterDraggable.axis].
  final Axis affinity;

  /// How many simultaneous drags to support.
  ///
  /// When null, no limit is applied. Set this to 1 if you want to only allow
  /// the drag source to have one item dragged at a time. Set this to 0 if you
  /// want to prevent the draggable from actually being dragged.
  ///
  /// If you set this property to 1, consider supplying an "empty" widget for
  /// [childWhenDragging] to create the illusion of actually moving [child].
  final int maxSimultaneousDrags;

  /// Called when the draggable starts being dragged.
  final VoidCallback onDragStarted;

  /// Called when the draggable is dropped without being accepted by a [BetterDragTarget].
  ///
  /// This function might be called after this widget has been removed from the
  /// tree. For example, if a drag was in progress when this widget was removed
  /// from the tree and the drag ended up being canceled, this callback will
  /// still be called. For this reason, implementations of this callback might
  /// need to check [State.mounted] to check whether the state receiving the
  /// callback is still in the tree.
  final DraggableCanceledCallback onDraggableCanceled;

  /// Called when the draggable is dropped and accepted by a [BetterDragTarget].
  ///
  /// This function might be called after this widget has been removed from the
  /// tree. For example, if a drag was in progress when this widget was removed
  /// from the tree and the drag ended up completing, this callback will
  /// still be called. For this reason, implementations of this callback might
  /// need to check [State.mounted] to check whether the state receiving the
  /// callback is still in the tree.
  final void Function(Offset) onDragCompleted;

  /// Called when the draggable is dropped.
  ///
  /// The velocity and offset at which the pointer was moving when it was
  /// dropped is available in the [DraggableDetails]. Also included in the
  /// `details` is whether the draggable's [BetterDragTarget] accepted it.
  ///
  /// This function will only be called while this widget is still mounted to
  /// the tree (i.e. [State.mounted] is true).
  final DragEndCallback onDragEnd;

  /// Creates a gesture recognizer that recognizes the start of the drag.
  ///
  /// Subclasses can override this function to customize when they start
  /// recognizing a drag.
  @protected
  MultiDragGestureRecognizer<MultiDragPointerState> createRecognizer(GestureMultiDragStartCallback onStart) {
    switch (affinity) {
      case Axis.horizontal:
        return HorizontalMultiDragGestureRecognizer()..onStart = onStart;
      case Axis.vertical:
        return VerticalMultiDragGestureRecognizer()..onStart = onStart;
    }
    return ImmediateMultiDragGestureRecognizer()..onStart = onStart;
  }

  @override
  _BetterDraggableState<T> createState() => _BetterDraggableState<T>();
}

/// Makes its child draggable starting from long press.
class BetterLongPressDraggable<T> extends BetterDraggable<T> {
  /// Creates a widget that can be dragged starting from long press.
  ///
  /// The [child] and [feedback] arguments must not be null. If
  /// [maxSimultaneousDrags] is non-null, it must be non-negative.
  const BetterLongPressDraggable({
    @required Widget child,
    @required Widget Function(BuildContext, Size) feedback,
    Key key,
    T data,
    Axis axis,
    Widget childWhenDragging,
    Offset feedbackOffset = Offset.zero,
    DragAnchor dragAnchor = DragAnchor.child,
    int maxSimultaneousDrags,
    VoidCallback onDragStarted,
    DraggableCanceledCallback onDraggableCanceled,
    DragEndCallback onDragEnd,
    void Function(Offset) onDragCompleted,
    this.hapticFeedbackOnStart = true,
    bool ignoringFeedbackSemantics = true,
  }) : super(
          key: key,
          child: child,
          feedback: feedback,
          data: data,
          axis: axis,
          childWhenDragging: childWhenDragging,
          feedbackOffset: feedbackOffset,
          dragAnchor: dragAnchor,
          maxSimultaneousDrags: maxSimultaneousDrags,
          onDragStarted: onDragStarted,
          onDraggableCanceled: onDraggableCanceled,
          onDragEnd: onDragEnd,
          onDragCompleted: onDragCompleted,
          ignoringFeedbackSemantics: ignoringFeedbackSemantics,
        );

  /// Whether haptic feedback should be triggered on drag start.
  final bool hapticFeedbackOnStart;

  @override
  DelayedMultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) =>
      DelayedMultiDragGestureRecognizer()
        ..onStart = (Offset position) {
          final result = onStart(position);
          if (result != null && hapticFeedbackOnStart) HapticFeedback.selectionClick();
          return result;
        };
}

class _BetterDraggableState<T> extends State<BetterDraggable<T>> {
  @override
  void initState() {
    super.initState();
    _recognizer = widget.createRecognizer(_startDrag);
  }

  @override
  void dispose() {
    _disposeRecognizerIfInactive();
    super.dispose();
  }

  // This gesture recognizer has an unusual lifetime. We want to support the use
  // case of removing the Draggable from the tree in the middle of a drag. That
  // means we need to keep this recognizer alive after this state object has
  // been disposed because it's the one listening to the pointer events that are
  // driving the drag.
  //
  // We achieve that by keeping count of the number of active drags and only
  // disposing the gesture recognizer after (a) this state object has been
  // disposed and (b) there are no more active drags.
  GestureRecognizer _recognizer;
  int _activeCount = 0;

  void _disposeRecognizerIfInactive() {
    if (_activeCount > 0) return;
    _recognizer.dispose();
    _recognizer = null;
  }

  void _routePointer(PointerDownEvent event) {
    if (widget.maxSimultaneousDrags != null && _activeCount >= widget.maxSimultaneousDrags) return;
    _recognizer.addPointer(event);
  }

  DragAvatar<T> _startDrag(Offset position) {
    if (widget.maxSimultaneousDrags != null && _activeCount >= widget.maxSimultaneousDrags) return null;
    Offset dragStartPoint;
    switch (widget.dragAnchor) {
      case DragAnchor.child:
        final renderObject = context.findRenderObject() as RenderBox;
        dragStartPoint = renderObject.globalToLocal(position);
        break;
      case DragAnchor.pointer:
        dragStartPoint = Offset.zero;
        break;
    }
    setState(() {
      _activeCount += 1;
    });
    final avatar = DragAvatar<T>(
      overlayState: Overlay.of(context, debugRequiredFor: widget),
      data: widget.data,
      axis: widget.axis,
      size: context.size,
      initialPosition: position,
      dragStartPoint: dragStartPoint,
      feedback: widget.feedback,
      feedbackOffset: widget.feedbackOffset,
      ignoringFeedbackSemantics: widget.ignoringFeedbackSemantics,
      onDragEnd: (Velocity velocity, Offset offset, bool wasAccepted) async {
        if (mounted && widget.onDragEnd != null) {
          widget.onDragEnd(DraggableDetails(
            wasAccepted: wasAccepted,
            velocity: velocity,
            offset: offset,
          ));
        }
        if (wasAccepted && widget.onDragCompleted != null) widget.onDragCompleted(offset);
        if (!wasAccepted && widget.onDraggableCanceled != null) widget.onDraggableCanceled(velocity, offset);
        if (mounted) {
          setState(() {
            _activeCount -= 1;
          });
        } else {
          _activeCount -= 1;
          _disposeRecognizerIfInactive();
        }
      },
    );
    if (widget.onDragStarted != null) widget.onDragStarted();
    return avatar;
  }

  @override
  Widget build(BuildContext context) {
    assert(Overlay.of(context, debugRequiredFor: widget) != null);
    final canDrag = widget.maxSimultaneousDrags == null || _activeCount < widget.maxSimultaneousDrags;
    final showChild = _activeCount == 0 || widget.childWhenDragging == null;
    return Listener(
      onPointerDown: canDrag ? _routePointer : null,
      child: showChild ? widget.child : widget.childWhenDragging,
    );
  }
}

/// A widget that receives data when a [BetterDraggable] widget is dropped.
///
/// When a draggable is dragged on top of a drag target, the drag target is
/// asked whether it will accept the data the draggable is carrying. If the user
/// does drop the draggable on top of the drag target (and the drag target has
/// indicated that it will accept the draggable's data), then the drag target is
/// asked to accept the draggable's data.
///
/// See also:
///
///  * [BetterDraggable]
///  * [BetterLongPressDraggable]
class BetterDragTarget<T> extends StatefulWidget {
  /// Creates a widget that receives drags.
  ///
  /// The [builder] argument must not be null.
  const BetterDragTarget({
    @required this.builder,
    Key key,
    this.onWillAccept,
    this.onAccept,
    this.onLeave,
  }) : super(key: key);

  /// Called to build the contents of this widget.
  ///
  /// The builder can build different widgets depending on what is being dragged
  /// into this drag target.
  final DragTargetBuilder<T> builder;

  /// Called to determine whether this widget is interested in receiving a given
  /// piece of data being dragged over this drag target.
  ///
  /// Called when a piece of data enters the target. This will be followed by
  /// either [onAccept], if the data is dropped, or [onLeave], if the drag
  /// leaves the target.
  final DragTargetWillAccept<T> onWillAccept;

  /// Called when an acceptable piece of data was dropped over this drag target.
  final DragTargetAccept<T> onAccept;

  /// Called when a given piece of data being dragged over this target leaves
  /// the target.
  final DragTargetLeave onLeave;

  @override
  _DragTargetState<T> createState() => _DragTargetState<T>();
}

List<T> _mapAvatarsToData<T>(List<DragAvatar<T>> avatars) =>
    avatars.map<T>((DragAvatar<T> avatar) => avatar.data).toList();

class _DragTargetState<T> extends State<BetterDragTarget<T>> implements BetterDragTargetState {
  final List<DragAvatar<T>> _candidateAvatars = <DragAvatar<T>>[];
  final List<DragAvatar<dynamic>> _rejectedAvatars = <DragAvatar<dynamic>>[];

  @override
  bool didEnter(Offset _, DragAvatar<dynamic> avatar) {
    assert(!_candidateAvatars.contains(avatar));
    assert(!_rejectedAvatars.contains(avatar));
    if (avatar.data is T && (widget.onWillAccept == null || widget.onWillAccept(avatar.data as T))) {
      setState(() {
        _candidateAvatars.add(avatar as DragAvatar<T>);
      });
      return true;
    } else {
      setState(() {
        _rejectedAvatars.add(avatar);
      });
      return false;
    }
  }

  @override
  void didLeave(DragAvatar<dynamic> avatar) {
    assert(_candidateAvatars.contains(avatar) || _rejectedAvatars.contains(avatar));
    if (!mounted) return;
    setState(() {
      _candidateAvatars.remove(avatar);
      _rejectedAvatars.remove(avatar);
    });
    if (widget.onLeave != null) widget.onLeave(avatar.data as T);
  }

  @override
  void didDrop(DragAvatar<dynamic> avatar) {
    assert(_candidateAvatars.contains(avatar));
    if (!mounted) return;
    setState(() {
      _candidateAvatars.remove(avatar);
    });
    if (widget.onAccept != null) widget.onAccept(avatar.data as T);
  }

  @override
  void updateDragAvatarPosition(Offset position) {}

  @override
  Widget build(BuildContext context) {
    assert(widget.builder != null);
    return MetaData(
      metaData: this,
      behavior: HitTestBehavior.translucent,
      child: widget.builder(
          context, _mapAvatarsToData<T>(_candidateAvatars), _mapAvatarsToData<dynamic>(_rejectedAvatars)),
    );
  }
}

enum _DragEndKind { dropped, canceled }

// ignore: avoid_private_typedef_functions
typedef _OnDragEnd = Future<void> Function(Velocity velocity, Offset offset, bool wasAccepted);

// The lifetime of this object is a little dubious right now. Specifically, it
// lives as long as the pointer is down. Arguably it should self-immolate if the
// overlay goes away. _DraggableState has some delicate logic to continue
// needing this object pointer events even after it has been disposed.
class DragAvatar<T> extends Drag {
  DragAvatar({
    @required this.overlayState,
    @required this.size,
    @required this.ignoringFeedbackSemantics,
    this.data,
    this.axis,
    Offset initialPosition,
    this.dragStartPoint = Offset.zero,
    this.feedback,
    this.feedbackOffset = Offset.zero,
    this.onDragEnd,
  })  : assert(overlayState != null),
        assert(ignoringFeedbackSemantics != null),
        assert(dragStartPoint != null),
        assert(feedbackOffset != null) {
    _entry = OverlayEntry(builder: _build);
    overlayState.insert(_entry);
    _position = initialPosition;
    updateDrag(initialPosition);
  }

  final T data;
  final Axis axis;
  final Offset dragStartPoint;
  final Widget Function(BuildContext, Size) feedback;
  final Offset feedbackOffset;
  final _OnDragEnd onDragEnd;
  final OverlayState overlayState;
  final bool ignoringFeedbackSemantics;
  final Size size;

  BetterDragTargetState _activeTarget;
  final List<BetterDragTargetState> _enteredTargets = <BetterDragTargetState>[];
  Offset _position;
  Offset _lastOffset;
  OverlayEntry _entry;

  @override
  void update(DragUpdateDetails details) {
    _position += _restrictAxis(details.delta);
    updateDrag(_position);
  }

  @override
  void end(DragEndDetails details) {
    finishDrag(_DragEndKind.dropped, _restrictVelocityAxis(details.velocity));
  }

  @override
  void cancel() {
    finishDrag(_DragEndKind.canceled);
  }

  void updateDrag(Offset globalPosition) {
    _lastOffset = globalPosition - dragStartPoint;
    _entry.markNeedsBuild();
    final result = HitTestResult();
    WidgetsBinding.instance.hitTest(result, globalPosition + feedbackOffset);

    final targets = _getDragTargets(result.path).toList();

    var listsMatch = false;
    if (targets.length >= _enteredTargets.length && _enteredTargets.isNotEmpty) {
      listsMatch = true;
      final iterator = targets.iterator;
      for (var i = 0; i < _enteredTargets.length; i += 1) {
        iterator.moveNext();
        if (iterator.current != _enteredTargets[i]) {
          listsMatch = false;
          break;
        }
      }
    }

    // If everything's the same, bail early.
    if (!listsMatch) {
      // Leave old targets.
      _leaveAllEntered();

      // Enter new targets.
      final newTarget = targets.firstWhere(
        (BetterDragTargetState target) {
          _enteredTargets.add(target);
          return target.didEnter(globalPosition + feedbackOffset, this);
        },
        orElse: () => null,
      );

      _activeTarget = newTarget;
    }

    _activeTarget?.updateDragAvatarPosition(globalPosition + feedbackOffset);
  }

  Iterable<BetterDragTargetState> _getDragTargets(Iterable<HitTestEntry> path) sync* {
    // Look for the RenderBoxes that corresponds to the hit target (the hit target
    // widgets build RenderMetaData boxes for us for this purpose).
    for (final entry in path) {
      if (entry.target is RenderSliverMetaData) {
        final renderMetaData = entry.target as RenderSliverMetaData;
        final dynamic metaData = renderMetaData.metaData;
        if (metaData is BetterDragTargetState) yield metaData;
      } else if (entry.target is RenderMetaData) {
        final renderMetaData = entry.target as RenderMetaData;
        final dynamic metaData = renderMetaData.metaData;
        if (metaData is BetterDragTargetState) yield metaData;
      }
    }
  }

  void _leaveAllEntered() {
    for (var i = 0; i < _enteredTargets.length; i += 1) _enteredTargets[i].didLeave(this);
    _enteredTargets.clear();
  }

  Future<void> finishDrag(_DragEndKind endKind, [Velocity velocity]) async {
    var wasAccepted = false;
    if (endKind == _DragEndKind.dropped && _activeTarget != null) {
      _activeTarget.didDrop(this);
      wasAccepted = true;
      _enteredTargets.remove(_activeTarget);
    }
    _leaveAllEntered();
    _entry.remove();
    _entry = null;
    if (onDragEnd != null) await onDragEnd(velocity ?? Velocity.zero, _lastOffset, wasAccepted);
    _activeTarget = null;
  }

  Widget _build(BuildContext context) {
    final box = overlayState.context.findRenderObject() as RenderBox;
    final overlayTopLeft = box.localToGlobal(Offset.zero);
    return Positioned(
      left: _lastOffset.dx - overlayTopLeft.dx,
      top: _lastOffset.dy - overlayTopLeft.dy,
      child: IgnorePointer(
        ignoringSemantics: ignoringFeedbackSemantics,
        child: feedback(context, size),
      ),
    );
  }

  Velocity _restrictVelocityAxis(Velocity velocity) {
    if (axis == null) {
      return velocity;
    }
    return Velocity(
      pixelsPerSecond: _restrictAxis(velocity.pixelsPerSecond),
    );
  }

  Offset _restrictAxis(Offset offset) {
    if (axis == null) {
      return offset;
    }
    if (axis == Axis.horizontal) {
      return Offset(offset.dx, 0.0);
    }
    return Offset(0.0, offset.dy);
  }
}
