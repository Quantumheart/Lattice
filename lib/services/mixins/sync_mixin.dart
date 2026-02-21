import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Client sync lifecycle management.
mixin SyncMixin on ChangeNotifier {
  Client get client;

  // Cross-mixin dependencies (satisfied by ChatBackupMixin).
  Future<void> checkChatBackupStatus();
  bool? get chatBackupNeeded;
  Future<void> tryAutoUnlockBackup();

  // ── Sync ─────────────────────────────────────────────────────
  bool _syncing = false;
  bool get syncing => _syncing;

  StreamSubscription? _syncSub;

  @protected
  Future<void> startSync() async {
    _syncing = true;
    notifyListeners();

    // Wait for the first sync so account data & device keys are available,
    // then keep notifying on subsequent syncs.
    final firstSync = Completer<void>();
    _syncSub?.cancel();
    _syncSub = client.onSync.stream.listen((_) {
      if (!firstSync.isCompleted) firstSync.complete();
      notifyListeners();
    });

    await firstSync.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('[Lattice] First sync timed out after 30s');
        throw TimeoutException('Initial sync timed out. Check your connection.');
      },
    );

    await checkChatBackupStatus();
    if (chatBackupNeeded == true) {
      await tryAutoUnlockBackup();
    }
  }

  /// Cancel sync subscription (e.g. on dispose).
  @protected
  void cancelSyncSub() {
    _syncSub?.cancel();
  }
}
