import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../attachment_image_loader.dart';
import 'resizable_image.dart' show buildImageLoadingPlaceholder, buildImageLoadError;

class AttachmentImage extends StatefulWidget {
  const AttachmentImage({
    super.key,
    required this.loader,
    required this.attachmentId,
    required this.width,
    this.height,
  });

  final AttachmentImageLoader loader;
  final String attachmentId;
  final double width;
  final double? height;

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final bytes = await widget.loader.loadAttachment(widget.attachmentId);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return buildImageLoadingPlaceholder(context);
    if (_failed || _bytes == null) {
      return buildImageLoadError(context, imageWidth: widget.width);
    }
    return Image.memory(
      _bytes!,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          buildImageLoadError(context, imageWidth: widget.width),
    );
  }
}
