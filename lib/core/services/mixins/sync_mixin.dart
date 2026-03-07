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

  String? _autoUnlockError;

  /// Non-null when the background E2EE auto-unlock failed.
  /// UI can observe this to hint that messages may be undecryptable.
  String? get autoUnlockError => _autoUnlockError;

  StreamSubscription<SyncUpdate>? _syncSub;

  @protected
  Future<void> startSync({Duration? timeout = const Duration(seconds: 30)}) async {
    _syncing = true;
    notifyListeners();

    // Wait for the first sync so account data & device keys are available,
    // then keep notifying on subsequent syncs.
    final firstSync = Completer<void>();
    unawaited(_syncSub?.cancel());
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

    // Run E2EE auto-unlock in background — don't block sync return.
    _autoUnlockError = null;
    unawaited(checkChatBackupStatus().then((_) {
      if (chatBackupNeeded == true) {
        return tryAutoUnlockBackup();
      }
    }).catchError((Object e) {
      debugPrint('[Lattice] Background E2EE auto-unlock error: $e');
      _autoUnlockError = e.toString();
      notifyListeners();
    },),);
  }

  /// Cancel sync subscription (e.g. on dispose).
  @protected
  void cancelSyncSub() {
    unawaited(_syncSub?.cancel());
  }
}
