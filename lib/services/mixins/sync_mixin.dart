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

  // Cross-mixin dependency (satisfied by SelectionMixin).
  void invalidateSpaceTree();

  // ── Sync ─────────────────────────────────────────────────────
  bool _syncing = false;
  bool get syncing => _syncing;

  StreamSubscription? _syncSub;

  @protected
  Future<void> startSync({Duration? timeout = const Duration(seconds: 30)}) async {
    _syncing = true;
    notifyListeners();

    // Wait for the first sync so account data & device keys are available,
    // then keep notifying on subsequent syncs.
    final firstSync = Completer<void>();
    _syncSub?.cancel();
    _syncSub = client.onSync.stream.listen((_) {
      if (!firstSync.isCompleted) firstSync.complete();
      invalidateSpaceTree();
      notifyListeners();
    });

    if (timeout != null) {
      await firstSync.future.timeout(
        timeout,
        onTimeout: () {
          debugPrint('[Lattice] First sync timed out after ${timeout.inSeconds}s');
          throw TimeoutException('Initial sync timed out. Check your connection.');
        },
      );
    } else {
      await firstSync.future;
    }

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
