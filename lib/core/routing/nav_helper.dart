import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/features/home/screens/home_shell.dart';

extension NavHelper on BuildContext {
  bool get _isNarrow =>
      MediaQuery.sizeOf(this).width < HomeShell.wideBreakpoint;

  void pushOrGo(
    String name, {
    Map<String, String> pathParameters = const {},
  }) {
    if (_isNarrow) {
      unawaited(pushNamed(name, pathParameters: pathParameters));
    } else {
      goNamed(name, pathParameters: pathParameters);
    }
  }

  void popOrGo(
    String parentName, {
    Map<String, String> pathParameters = const {},
  }) {
    if (canPop()) {
      pop();
    } else {
      goNamed(parentName, pathParameters: pathParameters);
    }
  }
}
