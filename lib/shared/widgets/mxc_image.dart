import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/media_auth.dart';
import 'package:matrix/matrix.dart';

class MxcImage extends StatefulWidget {
  const MxcImage({
    required this.mxcUrl,
    required this.client,
    required this.fallbackText,
    required this.fallbackStyle,
    this.width,
    this.height,
    super.key,
  });

  final String mxcUrl;
  final Client? client;
  final double? width;
  final double? height;
  final String fallbackText;
  final TextStyle? fallbackStyle;

  @override
  State<MxcImage> createState() => _MxcImageState();
}

class _MxcImageState extends State<MxcImage> {
  String? _resolvedUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(MxcImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mxcUrl != widget.mxcUrl) {
      unawaited(_resolve());
    }
  }

  Future<void> _resolve() async {
    final src = widget.mxcUrl;
    final client = widget.client;

    if (!src.startsWith('mxc://') || client == null) {
      if (mounted) {
        setState(() {
          _resolvedUrl = src.startsWith('http') ? src : null;
          _loading = false;
        });
      }
      return;
    }

    final mxc = Uri.tryParse(src);
    if (mxc == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final useThumb = widget.width != null && widget.width! <= 96;
      final Uri uri;
      if (useThumb) {
        uri = await mxc.getThumbnailUri(
          client,
          width: 48,
          height: 48,
          method: ThumbnailMethod.scale,
        );
      } else {
        uri = await mxc.getDownloadUri(client);
      }
      if (mounted) {
        setState(() {
          _resolvedUrl = uri.toString();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to resolve mxc image: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
      );
    }

    if (_resolvedUrl == null) {
      return Text(widget.fallbackText, style: widget.fallbackStyle);
    }

    return Image.network(
      _resolvedUrl!,
      width: widget.width,
      height: widget.height,
      headers: widget.client != null
          ? mediaAuthHeaders(widget.client!, _resolvedUrl!)
          : null,
      errorBuilder: (_, __, ___) =>
          Text(widget.fallbackText, style: widget.fallbackStyle),
    );
  }
}
