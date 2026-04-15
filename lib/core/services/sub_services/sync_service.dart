import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class SyncService extends ChangeNotifier {
  SyncService({
    required Client client,
    required Future<void> Function() onPostSyncBackup,
  })  : _client = client,
        _onPostSyncBackup = onPostSyncBackup;

  final Client _client;
  final Future<void> Function() _onPostSyncBackup;

  // ── Sync ─────────────────────────────────────────────────────
  bool _syncing = false;
  bool get syncing => _syncing;

  String? _autoUnlockError;
  String? get autoUnlockError => _autoUnlockError;

  StreamSubscription<SyncUpdate>? _syncSub;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> startSync({Duration? timeout = const Duration(seconds: 30)}) async {
    _syncing = true;
    notifyListeners();

    final firstSync = Completer<void>();
    unawaited(_syncSub?.cancel());
    _syncSub = _client.onSync.stream.listen((_) {
      if (!firstSync.isCompleted) firstSync.complete();
    });

    unawaited(firstSync.future.then((_) {
      _autoUnlockError = null;
      return _onPostSyncBackup();
    }).catchError((Object e) {
      debugPrint('[Kohera] Background E2EE auto-unlock error: $e');
      if (_disposed) return;
      _autoUnlockError = e.toString();
      notifyListeners();
    },),);

    if (timeout != null) {
      await firstSync.future.timeout(
        timeout,
        onTimeout: () {
          debugPrint('[Kohera] First sync timed out after ${timeout.inSeconds}s');
          throw TimeoutException('Initial sync timed out. Check your connection.');
        },
      );
    } else {
      await firstSync.future;
    }
  }

  void cancelSyncSub() {
    unawaited(_syncSub?.cancel());
    _syncSub = null;
    _syncing = false;
  }
}
