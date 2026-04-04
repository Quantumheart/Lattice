import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';

class WebPushService {
  WebPushService({
    required this.matrixService,
    required this.preferencesService,
  });

  final MatrixService matrixService;
  final PreferencesService preferencesService;

  static Future<bool> requestPermission() async => false;

  Future<void> register() async {}

  Future<void> unregister() async {}

  void listenForSubscriptionChanges() {}

  void dispose() {}
}
