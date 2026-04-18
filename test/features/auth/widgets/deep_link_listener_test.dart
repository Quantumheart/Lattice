import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/auth/services/deep_link_service.dart';
import 'package:kohera/features/auth/widgets/deep_link_listener.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../../widgets/login_controller_test.mocks.dart';

class _FakeSource implements DeepLinkSource {
  Uri? initial;
  final _controller = StreamController<Uri>.broadcast(sync: true);

  void emit(Uri uri) => _controller.add(uri);

  @override
  Future<Uri?> getInitialLink() async => initial;

  @override
  Stream<Uri> get uriLinkStream => _controller.stream;
}

void main() {
  late MockClientManager manager;
  late MockMatrixService matrix;
  late _FakeSource source;
  late DeepLinkService service;
  late GoRouter router;

  setUp(() {
    manager = MockClientManager();
    matrix = MockMatrixService();
    source = _FakeSource();
    service = DeepLinkService(source: source);

    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('home'))),
        ),
        GoRoute(
          path: '/register',
          builder: (_, state) => Scaffold(
            body: Center(child: Text('register:${state.uri}')),
          ),
        ),
        GoRoute(
          path: '/add-account/register',
          builder: (_, state) => Scaffold(
            body: Center(child: Text('add:${state.uri}')),
          ),
        ),
      ],
    );
  });

  Widget buildApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ClientManager>.value(value: manager),
        ChangeNotifierProvider<MatrixService>.value(value: matrix),
        ChangeNotifierProvider<DeepLinkService>.value(value: service),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => DeepLinkListener(
          service: service,
          router: router,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  testWidgets('logged-out intent navigates to /register', (tester) async {
    when(matrix.isLoggedIn).thenReturn(false);

    await service.start();
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    source.emit(Uri.parse('kohera://register?server=matrix.org&token=abc'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.textContaining('register:/register?'),
      findsOneWidget,
    );
    expect(find.textContaining('server=matrix.org'), findsOneWidget);
    expect(find.textContaining('token=abc'), findsOneWidget);
    expect(service.pending, isNull);
  });

  testWidgets('logged-in intent shows confirm dialog', (tester) async {
    when(matrix.isLoggedIn).thenReturn(true);

    await service.start();
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    source.emit(Uri.parse('kohera://register?server=matrix.org&token=abc'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Use this invite?'), findsOneWidget);
    expect(find.textContaining('matrix.org'), findsWidgets);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('confirm creates pending service + navigates', (tester) async {
    when(matrix.isLoggedIn).thenReturn(true);
    when(manager.createLoginService())
        .thenAnswer((_) async => MockMatrixService());

    await service.start();
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    source.emit(Uri.parse('kohera://register?server=matrix.org&token=abc'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    verify(manager.createLoginService()).called(1);
    expect(find.textContaining('add:/add-account/register?'), findsOneWidget);
    expect(find.textContaining('server=matrix.org'), findsOneWidget);
    expect(service.pending, isNull);
  });

  testWidgets('cancel dismisses dialog without navigation', (tester) async {
    when(matrix.isLoggedIn).thenReturn(true);

    await service.start();
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    source.emit(Uri.parse('kohera://register?server=matrix.org&token=abc'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(manager.createLoginService());
    expect(find.text('home'), findsOneWidget);
    expect(service.pending, isNull);
  });

  testWidgets('token with special characters is URL-encoded on navigation',
      (tester) async {
    when(matrix.isLoggedIn).thenReturn(false);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    source.emit(
      Uri.parse('kohera://register?server=matrix.org&token=abc%20xyz'),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('token=abc+xyz'), findsOneWidget);
  });

  testWidgets('createLoginService failure shows error dialog',
      (tester) async {
    when(matrix.isLoggedIn).thenReturn(true);
    when(manager.createLoginService())
        .thenThrow(StateError('boom'));

    await service.start();
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    source.emit(Uri.parse('kohera://register?server=matrix.org&token=abc'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't start new account"), findsOneWidget);
    expect(find.textContaining('try the invite link again'), findsOneWidget);
    expect(find.textContaining('add:/add-account/register?'), findsNothing);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't start new account"), findsNothing);
    expect(service.pending, isNull);
  });
}
