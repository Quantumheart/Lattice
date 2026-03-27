import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lattice/core/services/preferences_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum UpdateStatus { idle, checking, updateAvailable, error }

class UpdateService extends ChangeNotifier {
  UpdateService({required PreferencesService prefs, http.Client? httpClient})
      : _prefs = prefs,
        _httpClient = httpClient;

  PreferencesService _prefs;
  final http.Client? _httpClient;
  bool _disposed = false;
  Timer? _periodicTimer;

  String? _currentVersion;
  String? _latestVersion;
  String? _releaseUrl;
  UpdateStatus _status = UpdateStatus.idle;
  String? _errorMessage;

  static final bool _isDesktopPlatform =
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  // ── Public getters ──────────────────────────────────────────

  String? get currentVersion => _currentVersion;
  String? get latestVersion => _latestVersion;
  String? get releaseUrl => _releaseUrl;
  UpdateStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isDesktop => _isDesktopPlatform;

  @visibleForTesting
  set currentVersion(String? v) => _currentVersion = v;

  // ── Lifecycle ───────────────────────────────────────────────

  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
    } catch (_) {
      _currentVersion = '0.0.0';
    }
    _notify();

    if (!isDesktop) return;

    if (_prefs.autoUpdateEnabled) {
      unawaited(checkForUpdate());
    }
    _periodicTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) {
        if (_prefs.autoUpdateEnabled) unawaited(checkForUpdate());
      },
    );
  }

  void updatePrefs(PreferencesService prefs) {
    _prefs = prefs;
  }

  @override
  void dispose() {
    _disposed = true;
    _periodicTimer?.cancel();
    super.dispose();
  }

  void _setStatus(UpdateStatus newStatus, {String? error}) {
    final changed = _status != newStatus || _errorMessage != error;
    _status = newStatus;
    _errorMessage = error;
    if (changed) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Update check ────────────────────────────────────────────

  static const _latestReleaseUrl =
      'https://api.github.com/repos/Quantumheart/Lattice/releases/latest';

  Future<void> checkForUpdate() async {
    if (!isDesktop) return;
    if (_status == UpdateStatus.checking) return;

    _setStatus(UpdateStatus.checking);

    try {
      final uri = Uri.parse(_latestReleaseUrl);
      final headers = {'Accept': 'application/vnd.github+json'};
      final response = _httpClient != null
          ? await _httpClient!.get(uri, headers: headers)
          : await http.get(uri, headers: headers);

      if (response.statusCode == 403) {
        _setStatus(
          UpdateStatus.error,
          error: 'GitHub API rate limit reached. Try again later.',
        );
        debugPrint('[Lattice] Update check rate limited');
        return;
      }

      if (response.statusCode != 200) {
        _setStatus(
          UpdateStatus.error,
          error: 'GitHub returned status ${response.statusCode}',
        );
        debugPrint('[Lattice] Update check failed: ${response.statusCode}');
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['draft'] == true || json['prerelease'] == true) {
        debugPrint('[Lattice] Latest release is draft/prerelease, skipping');
        _setStatus(UpdateStatus.idle);
        return;
      }

      final tagName = json['tag_name'] as String?;
      if (tagName == null) {
        _setStatus(UpdateStatus.error, error: 'Invalid response from GitHub');
        return;
      }

      final remoteVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;

      if (isNewer(remoteVersion, _currentVersion ?? '0.0.0')) {
        _latestVersion = remoteVersion;
        _releaseUrl = json['html_url'] as String?;
        _setStatus(UpdateStatus.updateAvailable);
        debugPrint('[Lattice] Update available: v$remoteVersion');
      } else {
        _setStatus(UpdateStatus.idle);
        debugPrint('[Lattice] App is up to date (v$_currentVersion)');
      }
    } on SocketException {
      _setStatus(
        UpdateStatus.error,
        error: 'Could not reach GitHub. Check your internet connection.',
      );
      debugPrint('[Lattice] Update check failed: no internet');
    } on FormatException {
      _setStatus(
        UpdateStatus.error,
        error: 'Invalid response from GitHub',
      );
      debugPrint('[Lattice] Update check failed: invalid JSON');
    } catch (e) {
      _setStatus(UpdateStatus.error, error: 'Update check failed');
      debugPrint('[Lattice] Update check failed: $e');
    }
  }

  // ── Version comparison ──────────────────────────────────────

  @visibleForTesting
  static bool isNewer(String latest, String current) {
    final latestParts = latest.split('.').map(int.tryParse).toList();
    final currentParts = current.split('.').map(int.tryParse).toList();
    final length =
        latestParts.length > currentParts.length ? latestParts.length : currentParts.length;
    for (var i = 0; i < length; i++) {
      final l = i < latestParts.length ? (latestParts[i] ?? 0) : 0;
      final c = i < currentParts.length ? (currentParts[i] ?? 0) : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}
