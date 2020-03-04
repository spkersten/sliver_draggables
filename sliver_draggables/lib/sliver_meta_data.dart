import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A sliver variant of [MetaData].
///
class SliverMetaData extends SingleChildRenderObjectWidget {
  /// Creates a widget that hold opaque meta data.
  ///
  /// The [behavior] argument defaults to [HitTestBehavior.deferToChild].
  const SliverMetaData({
    Key key,
    this.metaData,
    this.behavior = HitTestBehavior.deferToChild,
    Widget child,
  }) : super(key: key, child: child);

  /// Opaque meta data ignored by the render tree
  final dynamic metaData;

  /// How to behave during hit testing.
  final HitTestBehavior behavior;

  @override
  RenderSliverMetaData createRenderObject(BuildContext context) => RenderSliverMetaData(
        metaData: metaData,
        behavior: behavior,
      );

  @override
  void updateRenderObject(BuildContext context, RenderSliverMetaData renderObject) {
    renderObject
      ..metaData = metaData
      ..behavior = behavior;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<HitTestBehavior>('behavior', behavior));
    properties.add(DiagnosticsProperty<dynamic>('metaData', metaData));
  }
}

/// See [SliverMetaData]
///
class RenderSliverMetaData extends RenderProxySliver {
  /// Creates a render object that hold opaque meta data.
  ///
  /// The [behavior] argument defaults to [HitTestBehavior.deferToChild].
  RenderSliverMetaData({
    this.metaData,
    this.behavior = HitTestBehavior.deferToChild,
    RenderSliver child,
  }) : super(sliver: child);

  /// Opaque meta data ignored by the render tree
  dynamic metaData;

  HitTestBehavior behavior;

  @override
  bool hitTest(SliverHitTestResult result, {double mainAxisPosition, double crossAxisPosition}) {
    var hitTarget = false;
    if (mainAxisPosition >= 0.0 &&
        mainAxisPosition < geometry.hitTestExtent &&
        crossAxisPosition >= 0.0 &&
        crossAxisPosition < constraints.crossAxisExtent) {
      hitTarget = hitTestChildren(result, mainAxisPosition: mainAxisPosition, crossAxisPosition: crossAxisPosition) ||
          hitTestSelf(mainAxisPosition: mainAxisPosition, crossAxisPosition: crossAxisPosition);
      if (hitTarget || behavior == HitTestBehavior.translucent) {
        result.add(SliverHitTestEntry(
          this,
          mainAxisPosition: mainAxisPosition,
          crossAxisPosition: crossAxisPosition,
        ));
      }
    }
    return hitTarget;
  }

  @override
  bool hitTestSelf({double mainAxisPosition, double crossAxisPosition}) => behavior == HitTestBehavior.opaque;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<dynamic>('metaData', metaData));
    properties.add(EnumProperty<HitTestBehavior>('behavior', behavior, defaultValue: null));
  }
}

/// A base class for render objects that resemble their children.
///
/// A proxy box has a single child and simply mimics all the properties of that
/// child by calling through to the child for each function in the render box
/// protocol. For example, a proxy box determines its size by asking its child
/// to layout with the same constraints and then matching the size.
///
/// A proxy box isn't useful on its own because you might as well just replace
/// the proxy box with its child. However, RenderProxyBox is a useful base class
/// for render objects that wish to mimic most, but not all, of the properties
/// of their child.
///
/// See also:
/// - [RenderProxyBox]
///
class RenderProxySliver extends RenderSliver with RenderObjectWithChildMixin<RenderSliver> {
  RenderProxySliver({
    RenderSliver sliver,
  }) {
    child = sliver;
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverPhysicalParentData) child.parentData = SliverPhysicalParentData();
  }

  @override
  void performLayout() {
    assert(child != null);
    child.layout(constraints, parentUsesSize: true);
    geometry = child.geometry;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(child, offset);
  }

  @override
  bool hitTestChildren(SliverHitTestResult result, {double mainAxisPosition, double crossAxisPosition}) =>
      child != null &&
      child.geometry.hitTestExtent > 0 &&
      child.hitTest(
        result,
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
      );

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    assert(child != null);
    final childParentData = child.parentData as SliverPhysicalParentData;
    childParentData.applyPaintTransform(transform);
  }
}
