import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/home/widgets/narrow_layout.dart';
import 'package:lattice/features/home/widgets/wide_layout.dart';
import 'package:lattice/features/spaces/widgets/space_reparent_controller.dart';
import 'package:provider/provider.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.routerChild, required this.routerState, super.key,
  });

  final Widget routerChild;
  final GoRouterState routerState;

  static const double wideBreakpoint = 720;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool _showRoomDetails = false;
  bool _syncScheduled = false;
  bool _wasWide = false;

  static const double _wideBreakpoint = HomeShell.wideBreakpoint;

  // ── Route → MatrixService sync ──────────────────────────────

  String? get _routeRoomId => widget.routerState.pathParameters['roomId'];
  String? get _routeName => widget.routerState.topRoute?.name;

  void _syncRoomSelection() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final matrix = context.read<MatrixService>();
      final roomId = _routeRoomId;
      if (matrix.selectedRoomId != roomId) {
        matrix.selectRoom(roomId);
      }
    });
  }

  @override
  void didUpdateWidget(covariant HomeShell old) {
    super.didUpdateWidget(old);
    final oldRoomId = old.routerState.pathParameters['roomId'];
    final newRoomId = _routeRoomId;

    if (oldRoomId != newRoomId) {
      _syncRoomSelection();
      _showRoomDetails = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncRoomSelection();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= _wideBreakpoint;
    if (_wasWide && !isWide) {
      _showRoomDetails = false;
    }
    _wasWide = isWide;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= _wideBreakpoint;

    final matrix = context.read<MatrixService>();
    context.select<MatrixService, int>((m) {
      final ids = m.spaces.map((s) => s.id);
      return Object.hash(ids.length, Object.hashAll(ids));
    });

    final child = isWide
        ? WideLayout(
            width: width,
            routerChild: widget.routerChild,
            routeName: _routeName,
            roomId: _routeRoomId,
            showRoomDetails: _showRoomDetails,
            onToggleDetails: () => setState(() => _showRoomDetails = !_showRoomDetails),
          )
        : NarrowLayout(
            routerChild: widget.routerChild,
            routeName: _routeName,
            roomId: _routeRoomId,
          );

    return ChangeNotifierProvider<SpaceReparentController>(
      create: (_) => SpaceReparentController(),
      child: CallbackShortcuts(
        bindings: _buildKeyBindings(matrix),
        child: Focus(
          autofocus: true,
          child: child,
        ),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildKeyBindings(MatrixService matrix) {
    final spaces = matrix.topLevelSpaces;
    final bindings = <ShortcutActivator, VoidCallback>{};

    bindings[const SingleActivator(LogicalKeyboardKey.digit0,
        control: true,)] = () => matrix.clearSpaceSelection();

    final digitKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    for (var i = 0; i < digitKeys.length && i < spaces.length; i++) {
      final spaceId = spaces[i].id;
      bindings[SingleActivator(digitKeys[i], control: true)] =
          () => matrix.selectSpace(spaceId);
      bindings[SingleActivator(digitKeys[i], control: true, shift: true)] =
          () => matrix.toggleSpaceSelection(spaceId);
    }

    return bindings;
  }
}
