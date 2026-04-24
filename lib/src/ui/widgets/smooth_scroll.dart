import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// A [ScrollPosition] that replaces instantaneous wheel scrolls with
/// smooth animations.
///
/// When the framework handles a mouse-wheel event it calls [pointerScroll]
/// which normally snaps directly to the target. We override it to use
/// [animateTo] so the wheel feels fluid instead of jerky.
class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  Timer? _debounce;
  double _pendingDelta = 0;

  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  @override
  void pointerScroll(double delta) {
    _debounce?.cancel();
    _pendingDelta += delta;

    // Batch rapid wheel events into a single animated scroll.
    _debounce = Timer(const Duration(milliseconds: 16), () {
      if (!hasPixels || !hasContentDimensions) return;

      final totalDelta = _pendingDelta;
      _pendingDelta = 0;

      final target =
          (pixels + totalDelta).clamp(minScrollExtent, maxScrollExtent);
      final distance = (target - pixels).abs();
      if (distance < 0.5) return;

      final ms = (distance * 0.6).clamp(80, 400).round();

      goIdle();
      beginActivity(
        DrivenScrollActivity(
          this,
          from: pixels,
          to: target,
          duration: Duration(milliseconds: ms),
          curve: Curves.easeOutCubic,
          vsync: context.vsync,
        ),
      );
    });
  }

  @override
  Future<void> moveTo(
    double to, {
    Duration? duration,
    Curve? curve,
    bool? clamp,
  }) {
    // Programmatic scrolls with Duration.zero (e.g. jumpTo) also benefit
    // from a short animation when they come from user gestures.
    if (duration == null || duration == Duration.zero) {
      final distance = (to - pixels).abs();
      final ms = (distance * 1.2).clamp(50, 250).round();
      return super.moveTo(
        to,
        duration: Duration(milliseconds: ms),
        curve: Curves.easeOutCubic,
        clamp: clamp ?? true,
      );
    }
    return super.moveTo(
      to,
      duration: duration,
      curve: curve,
      clamp: clamp,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// A [ScrollController] that creates [SmoothScrollPosition] instead of the
/// default [ScrollPositionWithSingleContext].
///
/// Drop-in replacement for [ScrollController]; no other code changes needed.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

/// Wrapper that intercepts pointer-scroll events for a
/// [ScrollablePositionedList] whose [physics] is set to
/// [NeverScrollableScrollPhysics].
///
/// Because the list itself ignores wheel input, this widget feeds smooth
/// animated scrolls via [ScrollOffsetController] instead.
class SmoothWheelInterceptor extends StatefulWidget {
  final Widget child;
  final ScrollOffsetController controller;

  const SmoothWheelInterceptor({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  State<SmoothWheelInterceptor> createState() => _SmoothWheelInterceptorState();
}

class _SmoothWheelInterceptorState extends State<SmoothWheelInterceptor> {
  double _pendingDelta = 0;
  Timer? _debounce;

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _debounce?.cancel();
      _pendingDelta += event.scrollDelta.dy;

      // Batch rapid wheel events into a single animated scroll.
      _debounce = Timer(const Duration(milliseconds: 16), () {
        if (!mounted) return;

        final delta = _pendingDelta;
        _pendingDelta = 0;

        final ms = (delta.abs() * 1.2).clamp(50, 250).round();
        widget.controller.animateScroll(
          offset: delta,
          duration: Duration(milliseconds: ms),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: widget.child,
    );
  }
}

/// A drop-in replacement for [SingleChildScrollView] that uses
/// [SmoothScrollController] for buttery wheel scrolling on desktop.
///
/// Wraps the child in a [SingleChildScrollView] with a self-managed
/// [SmoothScrollController] so callers do not need to handle lifecycle.
class SmoothSingleChildScrollView extends StatefulWidget {
  final Axis scrollDirection;
  final bool reverse;
  final EdgeInsetsGeometry? padding;
  final Widget child;
  final Clip clipBehavior;

  const SmoothSingleChildScrollView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    required this.child,
    this.clipBehavior = Clip.hardEdge,
  });

  @override
  State<SmoothSingleChildScrollView> createState() =>
      _SmoothSingleChildScrollViewState();
}

class _SmoothSingleChildScrollViewState
    extends State<SmoothSingleChildScrollView> {
  late final SmoothScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SmoothScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      padding: widget.padding,
      clipBehavior: widget.clipBehavior,
      child: widget.child,
    );
  }
}
