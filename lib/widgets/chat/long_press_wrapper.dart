import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Detects long press using raw pointer events so it does not participate in
/// the gesture arena and therefore does not interfere with the horizontal drag
/// recogniser in [SwipeableMessage].
class LongPressWrapper extends StatefulWidget {
  const LongPressWrapper({super.key, required this.onLongPress, required this.child});

  final void Function(Rect bubbleRect) onLongPress;
  final Widget child;

  @override
  State<LongPressWrapper> createState() => _LongPressWrapperState();
}

class _LongPressWrapperState extends State<LongPressWrapper> {
  static const _longPressDuration = Duration(milliseconds: 500);
  static const _touchSlop = 18.0;

  Timer? _timer;
  Offset? _startPosition;

  void _onPointerDown(PointerDownEvent event) {
    _startPosition = event.position;
    _timer?.cancel();
    _timer = Timer(_longPressDuration, () {
      HapticFeedback.mediumImpact();
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final topLeft = box.localToGlobal(Offset.zero);
        final rect = topLeft & box.size;
        widget.onLongPress(rect);
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_startPosition != null &&
        (event.position - _startPosition!).distance > _touchSlop) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _timer?.cancel();
    _timer = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}
