import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';

class FixedServiceFactory extends MatrixServiceFactory {
  FixedServiceFactory(this._service);
  final MatrixService _service;

  @override
  Future<(Client, MatrixService)> create({
    required String clientName,
    FlutterSecureStorage? storage,
  }) async {
    return (_service.client, _service);
  }
}

int _eventIdCounter = 0;

String nextEventId() => '\$evt_${_eventIdCounter++}';
