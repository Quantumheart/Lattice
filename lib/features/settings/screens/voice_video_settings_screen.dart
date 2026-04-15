import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/settings/widgets/mic_level_indicator.dart';
import 'package:kohera/features/settings/widgets/push_to_talk_key_editor.dart';
import 'package:kohera/shared/widgets/section_header.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:provider/provider.dart';

class VoiceVideoSettingsScreen extends StatefulWidget {
  const VoiceVideoSettingsScreen({super.key});

  @override
  State<VoiceVideoSettingsScreen> createState() =>
      _VoiceVideoSettingsScreenState();
}

class _VoiceVideoSettingsScreenState extends State<VoiceVideoSettingsScreen> {
  List<livekit.MediaDevice> _audioInputs = [];
  List<livekit.MediaDevice> _audioOutputs = [];
  StreamSubscription<List<livekit.MediaDevice>>? _deviceChangeSub;
  bool _loopbackEnabled = false;
  bool _pttKeyHeld = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initDeviceMonitoring());
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  Future<void> _initDeviceMonitoring() async {
    try {
      await _loadDevices();
      _deviceChangeSub =
          livekit.Hardware.instance.onDeviceChange.stream.listen((_) {
        unawaited(_loadDevices());
      });
    } catch (e) {
      debugPrint('[Kohera] Failed to initialize audio device monitoring: $e');
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    unawaited(_deviceChangeSub?.cancel());
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    final prefs = context.read<PreferencesService>();
    if (!prefs.pushToTalkEnabled) return false;
    if (event.logicalKey.keyId != prefs.pushToTalkKeyId) return false;

    if (event is KeyDownEvent && !_pttKeyHeld) {
      setState(() => _pttKeyHeld = true);
      return true;
    }
    if (event is KeyUpEvent && _pttKeyHeld) {
      setState(() => _pttKeyHeld = false);
      return true;
    }
    return false;
  }

  Future<void> _loadDevices() async {
    try {
      final inputs = await livekit.Hardware.instance.audioInputs();
      final outputs = await livekit.Hardware.instance.audioOutputs();
      if (mounted) {
        setState(() {
          _audioInputs = inputs;
          _audioOutputs = outputs;
        });
        _clearStaleDevices();
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to enumerate audio devices: $e');
    }
  }

  void _clearStaleDevices() {
    final prefs = context.read<PreferencesService>();
    final inputId = prefs.inputDeviceId;
    if (inputId != null &&
        !_audioInputs.any((d) => d.deviceId == inputId)) {
      unawaited(prefs.setInputDeviceId(null));
    }
    final outputId = prefs.outputDeviceId;
    if (outputId != null &&
        !_audioOutputs.any((d) => d.deviceId == outputId)) {
      unawaited(prefs.setOutputDeviceId(null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesService>();
    final callService = context.watch<CallService>();
    final available = callService.isCallingAvailable;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(Routes.settings),
        ),
        title: const Text('Voice & Video'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Calling Status ──────────────────────────────────────
          const SectionHeader(label: 'CALLING STATUS'),
          Card(
            child: ListTile(
              leading: Icon(Icons.call_rounded, color: cs.onSurfaceVariant),
              title: const Text('Voice & video calls'),
              subtitle: Text(
                available
                    ? 'Supported by your homeserver'
                    : 'Your homeserver does not support calling '
                        '(LiveKit not configured)',
              ),
              trailing: Icon(
                available
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                color: available ? Colors.green : cs.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Microphone ──────────────────────────────────────────
          const SectionHeader(label: 'MICROPHONE'),
          Card(
            child: Column(
              children: [
                if (isNativeDesktop || !isNativeMobile)
                  _DeviceDropdown(
                    label: 'Input device',
                    icon: Icons.mic_rounded,
                    devices: _audioInputs,
                    selectedId: prefs.inputDeviceId,
                    onChanged: (id) => unawaited(prefs.setInputDeviceId(id)),
                  ),
                _VolumeRow(
                  label: 'Input volume',
                  value: prefs.inputVolume,
                  onChanged: (v) => unawaited(prefs.setInputVolume(v)),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: MicLevelIndicator(
                    deviceId: prefs.inputDeviceId,
                    loopbackEnabled: _loopbackEnabled,
                    pttMuted: prefs.pushToTalkEnabled && !_pttKeyHeld,
                  ),
                ),
                const Divider(height: 1, indent: 16),
                SwitchListTile(
                  secondary: const Icon(Icons.headphones_rounded),
                  title: const Text('Listen to yourself'),
                  subtitle: const Text('Hear your mic through speakers'),
                  value: _loopbackEnabled,
                  onChanged: (v) => setState(() => _loopbackEnabled = v),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.mic_off_rounded),
                  title: const Text('Auto-mute when joining'),
                  subtitle: const Text('Join calls with mic off'),
                  value: prefs.autoMuteOnJoin,
                  onChanged: (v) => unawaited(prefs.setAutoMuteOnJoin(v)),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.noise_aware_rounded),
                  title: const Text('Noise suppression'),
                  subtitle: const Text('Reduce background noise'),
                  value: prefs.noiseSuppression,
                  onChanged: (v) => unawaited(prefs.setNoiseSuppression(v)),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.spatial_audio_off_rounded),
                  title: const Text('Echo cancellation'),
                  subtitle: const Text('Prevent audio feedback'),
                  value: prefs.echoCancellation,
                  onChanged: (v) => unawaited(prefs.setEchoCancellation(v)),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.tune_rounded),
                  title: const Text('Auto gain control'),
                  subtitle: const Text('Normalize volume levels'),
                  value: prefs.autoGainControl,
                  onChanged: (v) => unawaited(prefs.setAutoGainControl(v)),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.person_rounded),
                  title: const Text('Voice isolation'),
                  subtitle: const Text('Filter non-voice sounds'),
                  value: prefs.voiceIsolation,
                  onChanged: (v) => unawaited(prefs.setVoiceIsolation(v)),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.keyboard_rounded),
                  title: const Text('Typing noise detection'),
                  subtitle: const Text('Suppress keyboard sounds'),
                  value: prefs.typingNoiseDetection,
                  onChanged: (v) =>
                      unawaited(prefs.setTypingNoiseDetection(v)),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.graphic_eq_rounded),
                  title: const Text('High pass filter'),
                  subtitle: const Text('Remove low-frequency rumble'),
                  value: prefs.highPassFilter,
                  onChanged: (v) => unawaited(prefs.setHighPassFilter(v)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Audio Quality ──────────────────────────────────────
          const SectionHeader(label: 'AUDIO QUALITY'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<AudioQuality>(
                segments: [
                  for (final quality in AudioQuality.values)
                    ButtonSegment(
                      value: quality,
                      label: Text(quality.label),
                    ),
                ],
                selected: {prefs.audioQuality},
                onSelectionChanged: (selected) =>
                    unawaited(prefs.setAudioQuality(selected.first)),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Speaker ─────────────────────────────────────────────
          const SectionHeader(label: 'SPEAKER'),
          Card(
            child: Column(
              children: [
                if (isNativeDesktop || !isNativeMobile)
                  _DeviceDropdown(
                    label: 'Output device',
                    icon: Icons.volume_up_rounded,
                    devices: _audioOutputs,
                    selectedId: prefs.outputDeviceId,
                    onChanged: (id) => unawaited(prefs.setOutputDeviceId(id)),
                  ),
                _VolumeRow(
                  label: 'Output volume',
                  value: prefs.outputVolume,
                  onChanged: (v) {
                    unawaited(prefs.setOutputVolume(v));
                    unawaited(callService.setOutputVolume(v));
                  },
                ),
              ],
            ),
          ),

          // ── Push to Talk (desktop only) ─────────────────────────
          if (isNativeDesktop) ...[
            const SizedBox(height: 24),
            const SectionHeader(label: 'PUSH TO TALK'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.keyboard_voice_rounded),
                    title: const Text('Enable push-to-talk'),
                    subtitle: const Text(
                      'Hold key to unmute — overrides auto-mute',
                    ),
                    value: prefs.pushToTalkEnabled,
                    onChanged: (v) =>
                        unawaited(prefs.setPushToTalkEnabled(v)),
                  ),
                  if (prefs.pushToTalkEnabled) ...[
                    const Divider(height: 1, indent: 56),
                    PushToTalkKeyEditor(
                      keyId: prefs.pushToTalkKeyId,
                      onKeyChanged: (id) =>
                          unawaited(prefs.setPushToTalkKeyId(id)),
                    ),
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(Icons.volume_up_rounded),
                      title: const Text('Activation sound'),
                      subtitle: const Text('Play sound on key press/release'),
                      value: prefs.pttSoundEnabled,
                      onChanged: (v) =>
                          unawaited(prefs.setPttSoundEnabled(v)),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Device Dropdown ──────────────────────────────────────────────

class _DeviceDropdown extends StatelessWidget {
  const _DeviceDropdown({
    required this.label,
    required this.icon,
    required this.devices,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final List<livekit.MediaDevice> devices;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveId =
        devices.any((d) => d.deviceId == selectedId) ? selectedId : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: DropdownButtonFormField<String?>(
        initialValue: effectiveId,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: cs.onSurfaceVariant),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String?>(
            child: Text('Default'),
          ),
          for (final device in devices)
            DropdownMenuItem<String?>(
              value: device.deviceId,
              child: Text(
                device.label.isNotEmpty ? device.label : device.deviceId,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

// ── Volume Row ───────────────────────────────────────────────────

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.label,
    required this.value,
    this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                '${(value * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          Slider(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
