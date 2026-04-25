import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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

/// Wrapper that intercepts pointer-scroll events for a scrollable widget
/// (e.g. [ListView]) and replaces the native snap-to-target behaviour with
/// a short ease-out animation.
///
/// The [controller] should be the same [ScrollController] attached to the
/// inner scrollable (e.g. a [SmoothScrollController]).
class SmoothWheelInterceptor extends StatefulWidget {
  final Widget child;
  final ScrollController controller;

  /// Multiplier applied to the raw wheel delta.
  /// Increase this if a single wheel notch scrolls too little.
  final double scrollScale;

  const SmoothWheelInterceptor({
    super.key,
    required this.child,
    required this.controller,
    this.scrollScale = 2.5,
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

      // Flush at the end of the current frame so multiple wheel events
      // that arrive in the same frame are coalesced, but the user never
      // feels a delay.
      _debounce = Timer(Duration.zero, () {
        if (!mounted) return;

        final delta = _pendingDelta * widget.scrollScale;
        _pendingDelta = 0;
        if (delta == 0) return;

        final controller = widget.controller;
        if (!controller.hasClients) return;

        final position = controller.position;
        final target = (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        final distance = (target - position.pixels).abs();

        // Always animate — even small movements get a short ease-out so
        // the scroll feels fluid rather than snapping.  The duration scales
        // with distance but is capped so large scrolls don't feel sluggish.
        final ms = (distance * 0.4).clamp(60, 220).round();
        controller.animateTo(
          target,
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
