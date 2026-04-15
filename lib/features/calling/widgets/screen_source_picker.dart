import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

// coverage:ignore-start

Future<rtc.DesktopCapturerSource?> showScreenSourcePicker(
  BuildContext context,
) {
  return showDialog<rtc.DesktopCapturerSource>(
    context: context,
    builder: (_) => const _ScreenSourcePicker(),
  );
}

class _ScreenSourcePicker extends StatefulWidget {
  const _ScreenSourcePicker();

  @override
  State<_ScreenSourcePicker> createState() => _ScreenSourcePickerState();
}

class _ScreenSourcePickerState extends State<_ScreenSourcePicker> {
  final Map<String, rtc.DesktopCapturerSource> _sources = {};
  final List<StreamSubscription<rtc.DesktopCapturerSource>> _subscriptions = [];
  rtc.SourceType _sourceType = rtc.SourceType.Screen;
  rtc.DesktopCapturerSource? _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _subscriptions.add(
      rtc.desktopCapturer.onAdded.stream.listen((s) {
        _sources[s.id] = s;
        if (mounted) setState(() {});
      }),
    );
    _subscriptions.add(
      rtc.desktopCapturer.onRemoved.stream.listen((s) {
        _sources.remove(s.id);
        if (_selected?.id == s.id) _selected = null;
        if (mounted) setState(() {});
      }),
    );
    unawaited(_loadSources());
  }

  Future<void> _loadSources() async {
    setState(() => _loading = true);
    try {
      final sources =
          await rtc.desktopCapturer.getSources(types: [_sourceType]);
      _sources.clear();
      for (final s in sources) {
        _sources[s.id] = s;
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to enumerate sources: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  List<rtc.DesktopCapturerSource> _filtered(rtc.SourceType type) =>
      _sources.values.where((s) => s.type == type).toList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Share your screen'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 480,
        height: 360,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                onTap: (i) {
                  _sourceType = i == 0
                      ? rtc.SourceType.Screen
                      : rtc.SourceType.Window;
                  _selected = null;
                  unawaited(_loadSources());
                },
                tabs: const [
                  Tab(text: 'Screens'),
                  Tab(text: 'Windows'),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _SourceList(
                            sources: _filtered(rtc.SourceType.Screen),
                            selected: _selected,
                            onSelect: (s) => setState(() => _selected = s),
                          ),
                          _SourceList(
                            sources: _filtered(rtc.SourceType.Window),
                            selected: _selected,
                            onSelect: (s) => setState(() => _selected = s),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            disabledBackgroundColor: cs.surfaceContainerHighest,
          ),
          child: const Text('Share'),
        ),
      ],
    );
  }
}

class _SourceList extends StatelessWidget {
  const _SourceList({
    required this.sources,
    required this.selected,
    required this.onSelect,
  });

  final List<rtc.DesktopCapturerSource> sources;
  final rtc.DesktopCapturerSource? selected;
  final ValueChanged<rtc.DesktopCapturerSource> onSelect;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const Center(child: Text('No sources found'));
    }
    return ListView.separated(
      itemCount: sources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, i) {
        final source = sources[i];
        final isSelected = selected?.id == source.id;
        final cs = Theme.of(context).colorScheme;

        return ListTile(
          leading: Icon(
            source.type == rtc.SourceType.Screen
                ? Icons.monitor
                : Icons.window,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
          title: Text(source.name),
          selected: isSelected,
          selectedTileColor: cs.primaryContainer.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? cs.primary : Colors.transparent,
              width: isSelected ? 2 : 0,
            ),
          ),
          onTap: () => onSelect(source),
        );
      },
    );
  }
}
// coverage:ignore-end
