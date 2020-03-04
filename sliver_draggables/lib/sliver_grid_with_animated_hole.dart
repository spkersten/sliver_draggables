import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// SliverGrid with an (optional) hole that animates the items in the grid when the hole changes
/// location or (dis)appears.
///
class SliverGridWithAnimatedHole extends StatefulWidget {
  const SliverGridWithAnimatedHole({
    @required this.delegate,
    @required this.gridDelegate,
    @required this.duration,
    this.holeIndex,
    this.animatedInitialState = false,
    this.animationController,
    Key key,
  })  : assert(delegate != null),
        assert(gridDelegate != null),
        assert(duration != null),
        super(key: key);

  final SliverChildDelegate delegate;
  final SliverGridDelegate gridDelegate;

  /// The index of the hole. That is, all grid items with an index larger or equal to it are shifted one place further.
  final int holeIndex;

  /// Duration of the animation of hole to a new place.
  final Duration duration;

  /// Whether to animate the hole (if present) on the initial build
  final bool animatedInitialState;

  final SliverGridWithAnimatedHoleAnimationController animationController;

  @override
  _SliverGridWithAnimatedHoleState createState() => _SliverGridWithAnimatedHoleState();
}

class _SliverGridWithAnimatedHoleState extends State<SliverGridWithAnimatedHole>
    with SingleTickerProviderStateMixin<SliverGridWithAnimatedHole> {
  SliverGridDelegateWithDisplacements _wrapper;
  Ticker _ticker;
  int _holeIndex;
  Duration _previousTimestamp;
  final Map<int, _Displacement> _displacements = {};

  bool get displacementsInProgress => _displacements.values.any((mutation) => mutation.inProgress);

  SliverGridWithAnimatedHoleAnimationController get _effectiveAnimationController =>
      widget.animationController ?? SliverGridWithAnimatedHoleAnimationController();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _changeHole(widget.holeIndex);
    if (displacementsInProgress) {
      if (widget.animatedInitialState) {
        _startTicker();
      } else {
        _animateDisplacements(widget.duration);
      }
    }
    _updateGridDelegate();
  }

  void _tick(Duration time) {
    _animateDisplacements(time - _previousTimestamp);
    _previousTimestamp = time;
    if (!displacementsInProgress) {
      _ticker.stop();
    }
    _updateGridDelegate();
    setState(() {});
  }

  void _startTicker() {
    _previousTimestamp = const Duration();
    _ticker.start();
  }

  void _updateGridDelegate() {
    _wrapper = SliverGridDelegateWithDisplacements(
      child: widget.gridDelegate,
      displacements: _displacements.map((k, v) => MapEntry(k, v.displacement)),
    );
  }

  void _animateDisplacements(Duration duration) {
    final delta = duration.inMilliseconds / widget.duration.inMilliseconds;

    for (final mutation in _displacements.values) {
      switch (mutation.direction) {
        case _DisplacementDirection.forward:
          mutation.displacement = (mutation.displacement + delta).clamp(0.0, 1.0).toDouble();
          break;
        case _DisplacementDirection.backward:
          mutation.displacement = (mutation.displacement - delta).clamp(0.0, 1.0).toDouble();
          break;
      }
    }

    _displacements.removeWhere((_, mutation) => mutation.redundant);
  }

  @override
  void didUpdateWidget(SliverGridWithAnimatedHole oldWidget) {
    super.didUpdateWidget(oldWidget);
    _changeHole(widget.holeIndex);
    if (widget.gridDelegate != oldWidget.gridDelegate) {
      _updateGridDelegate();
    }
    if (displacementsInProgress && !_ticker.isActive) _startTicker();
  }

  // change the direction of displacements
  void _changeHole(int newHoleIndex) {
    if (newHoleIndex != _holeIndex) {
      if (newHoleIndex == null && !_effectiveAnimationController.animateHoleDisappearance) {
        _displacements.clear();
        _holeIndex = newHoleIndex;
        _updateGridDelegate();
        setState(() {});
        return;
      }
      if (_holeIndex == null && !_effectiveAnimationController.animateHoleAppearance) {
        _displacements.clear();
        _displacements[newHoleIndex] = _Displacement(1, _DisplacementDirection.forward);
        _holeIndex = newHoleIndex;
        _updateGridDelegate();
        setState(() {});
        return;
      }

      if (newHoleIndex == null) {
        _displacements.values.forEach((displacement) => displacement.direction = _DisplacementDirection.backward);
      } else {
        // Only items between (inclusive) the new and old hole are affected
        final first = _holeIndex != null ? math.min(newHoleIndex, _holeIndex) : newHoleIndex;
        final last = _holeIndex != null ? math.max(newHoleIndex, _holeIndex) : newHoleIndex;

        // All grid items after the last (explicit) displacement implicitly take on the same displacement
        // see SliverGridLayoutWithDisplacements
        final lastDisplacement = _displacements.isNotEmpty ? _displacements.lastMutation : null;

        for (var index = first; index <= last + 1; index++) {
          if (index >= newHoleIndex) {
            if (lastDisplacement != null && index > lastDisplacement.key) {
              // Make implicit displacement explicit:
              _displacements[index] ??=
                  _Displacement(lastDisplacement.value.displacement, _DisplacementDirection.forward);
            } else {
              _displacements[index] ??= _Displacement(0.0, _DisplacementDirection.forward);
            }
            _displacements[index].direction = _DisplacementDirection.forward;
          } else {
            // Make implicit displacement explicit: (index > lastDisplacement.key if it didn't exist yet)
            _displacements[index] ??=
                _Displacement(lastDisplacement.value.displacement, _DisplacementDirection.backward);

            _displacements[index].direction = _DisplacementDirection.backward;
          }
        }
      }
      _holeIndex = newHoleIndex;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SliverGrid(
        delegate: widget.delegate,
        gridDelegate: _wrapper,
      );
}

class SliverGridWithAnimatedHoleAnimationController {
  bool animateHoleAppearance = true;
  bool animateHoleDisappearance = true;
}

extension _DisplacementsExtremes on Map<int, _Displacement> {
  MapEntry<int, _Displacement> get lastMutation =>
      entries.fold<MapEntry<int, _Displacement>>(entries.first, (p, element) => p.key > element.key ? p : element);
}

enum _DisplacementDirection {
  forward,
  backward,
}

/// A displacement of a grid element.
class _Displacement {
  _Displacement(this.displacement, this.direction);

  /// A relative displacement, where a displacement of 1 means a shift to the next spot
  double displacement;

  /// Direction in which the displacement should progress
  _DisplacementDirection direction;

  bool get inProgress =>
      (direction == _DisplacementDirection.forward && displacement < 1) ||
      (direction == _DisplacementDirection.backward && displacement > 0);

  bool get redundant => direction == _DisplacementDirection.backward && displacement == 0;

  @override
  String toString() => "$_Displacement($displacement, $direction)";
}

extension _ExtremesInt on Iterable<int> {
  int get max => fold(first, (m, v) => m > v ? m : v);

  int get min => fold(first, (m, v) => m < v ? m : v);
}

extension _ExtremesDouble on Iterable<double> {
  double get max => fold(first, (m, v) => m > v ? m : v);

  double get min => fold(first, (m, v) => m < v ? m : v);
}

@immutable
class SliverGridDelegateWithDisplacements extends SliverGridDelegate {
  const SliverGridDelegateWithDisplacements({@required this.displacements, @required this.child})
      : assert(displacements != null),
        assert(child != null);

  final SliverGridDelegate child;

  /// The last offset applies to all cards with a higher index
  final Map<int, double> displacements;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) => SliverGridLayoutWithDisplacements(
        child: child.getLayout(constraints),
        displacements: displacements,
      );

  @override
  bool shouldRelayout(SliverGridDelegateWithDisplacements oldDelegate) => true;
}

class SliverGridLayoutWithDisplacements extends SliverGridLayout {
  const SliverGridLayoutWithDisplacements({@required this.child, @required this.displacements})
      : assert(child != null),
        assert(displacements != null);

  final SliverGridLayout child;

  /// The last offset applies to all cards with a higher index
  final Map<int, double> displacements;

  @override
  double computeMaxScrollOffset(int childCount) {
    if (displacements.isNotEmpty) {
      final endIndex = displacements.keys.max;
      final end = displacements[endIndex];
      return lerpDouble(child.computeMaxScrollOffset(childCount), child.computeMaxScrollOffset(childCount + 1), end);
    } else {
      return child.computeMaxScrollOffset(childCount);
    }
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    var offset = displacements[index];
    if (offset == null && displacements.isNotEmpty) {
      final end = displacements.keys.max;
      if (index > end) offset = displacements[end];
    }
    if (offset != null) {
      final start = child.getGeometryForChildIndex(index);
      final end = child.getGeometryForChildIndex(index + 1);
      return lerpSliverGridGeometry(start, end, offset);
    } else {
      return child.getGeometryForChildIndex(index);
    }
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) => child.getMaxChildIndexForScrollOffset(scrollOffset);

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) => child.getMinChildIndexForScrollOffset(scrollOffset);
}

SliverGridGeometry lerpSliverGridGeometry(SliverGridGeometry a, SliverGridGeometry b, double t) => SliverGridGeometry(
      scrollOffset: lerpDouble(a.scrollOffset, b.scrollOffset, t),
      crossAxisOffset: lerpDouble(a.crossAxisOffset, b.crossAxisOffset, t),
      mainAxisExtent: lerpDouble(a.mainAxisExtent, b.mainAxisExtent, t),
      crossAxisExtent: lerpDouble(a.crossAxisExtent, b.crossAxisExtent, t),
    );
