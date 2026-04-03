import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';

class WebPushService {
  WebPushService({
    required this.matrixService,
    required this.preferencesService,
  });

  final MatrixService matrixService;
  final PreferencesService preferencesService;

  Future<void> register(String vapidPublicKey) async {}

  Future<void> unregister() async {}

  void dispose() {}
}
