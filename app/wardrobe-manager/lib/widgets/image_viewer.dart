import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/platform_image.dart';

/// 统一的大图查看器：双指缩放、拖拽平移、双击复位。
/// 试穿结果、历史记录、衣物图片都走这一个组件，避免各页各写一套。
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    this.path,
    this.bytes,
    this.title,
  });

  final String? path;
  final Uint8List? bytes;
  final String? title;

  static Future<void> open(
    BuildContext context, {
    String? path,
    Uint8List? bytes,
    String? title,
  }) {
    if ((path == null || path.isEmpty) && bytes == null) {
      return Future<void>.value();
    }
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            ImageViewerPage(path: path, bytes: bytes, title: title),
      ),
    );
  }

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() => _controller.value = Matrix4.identity();

  Widget _content() {
    if (widget.bytes != null) {
      return Image.memory(widget.bytes!, fit: BoxFit.contain, gaplessPlayback: true);
    }
    final local = fileImageWidget(widget.path, fit: BoxFit.contain);
    return local ??
        const Center(
          child: Text('当前平台无法读取这张本地图片',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title ?? '查看大图',
            style: const TextStyle(fontSize: 15, color: Colors.white)),
        actions: [
          IconButton(
            tooltip: '恢复原始大小',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _reset,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: _reset,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1,
                maxScale: 6,
                panEnabled: true,
                scaleEnabled: true,
                child: Center(child: _content()),
              ),
            ),
          ),
          Positioned(
            bottom: 22,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Text(
                '双指缩放 · 拖动查看 · 双击复位',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: .55), fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
