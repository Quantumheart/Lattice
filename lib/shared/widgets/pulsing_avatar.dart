import 'dart:async';

import 'package:flutter/material.dart';

class PulsingAvatar extends StatefulWidget {
  const PulsingAvatar({
    required this.displayName,
    this.radius = 48,
    this.endScale = 1.1,
    super.key,
  });

  final String displayName;
  final double radius;
  final double endScale;

  @override
  State<PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    unawaited(_controller.repeat(reverse: true));
    _animation = Tween<double>(begin: 1, end: widget.endScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ScaleTransition(
      scale: _animation,
      child: CircleAvatar(
        radius: widget.radius,
        child: Text(
          widget.displayName.isNotEmpty
              ? widget.displayName[0].toUpperCase()
              : '?',
          style: tt.headlineLarge,
        ),
      ),
    );
  }
}
