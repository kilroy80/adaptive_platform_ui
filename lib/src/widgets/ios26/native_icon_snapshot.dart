import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Small, premultiplied RGBA bitmap for a native icon, without PNG work.
class NativeIconPixels {
  const NativeIconPixels({
    required this.rgba,
    required this.width,
    required this.height,
    required this.scale,
  });
  final Uint8List rgba;
  final int width;
  final int height;
  final double scale;
}

/// Captures only changes in this icon's layer subtree, never unrelated frames.
class NativeIconSnapshot extends StatefulWidget {
  const NativeIconSnapshot({
    super.key,
    required this.child,
    required this.onPixels,
    this.onCapture,
  });

  final Widget child;
  final ValueChanged<NativeIconPixels> onPixels;

  /// Instrumentation for tests; called before GPU readback.
  @visibleForTesting
  final VoidCallback? onCapture;

  @override
  State<NativeIconSnapshot> createState() => _NativeIconSnapshotState();
}

class _NativeIconSnapshotState extends State<NativeIconSnapshot> {
  final _boundaryKey = GlobalKey();
  Uint8List? _lastRgba;
  bool _encoding = false;
  bool _dirty = false;
  bool _frameQueued = false;
  Timer? _pendingCapture;
  final Stopwatch _captureClock = Stopwatch()..start();
  Duration? _lastCapture;
  int _generation = 0;
  double _pixelRatio = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scale = MediaQuery.devicePixelRatioOf(context);
    if (scale != _pixelRatio) {
      _pixelRatio = scale;
      _generation++;
      _layerChanged();
    }
  }

  @override
  void didUpdateWidget(covariant NativeIconSnapshot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {
      _generation++;
    }
  }

  void _layerChanged() {
    if (!mounted) return;
    _dirty = true;
    if (_frameQueued) return;
    _frameQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameQueued = false;
      if (mounted) _scheduleCapture();
    });
  }

  void _scheduleCapture() {
    if (!_dirty || _encoding || _pendingCapture != null) return;
    final elapsed = _lastCapture == null
        ? const Duration(milliseconds: 100)
        : _captureClock.elapsed - _lastCapture!;
    final delay = const Duration(milliseconds: 100) - elapsed;
    _pendingCapture = Timer(delay.isNegative ? Duration.zero : delay, () {
      _pendingCapture = null;
      _capture();
    });
  }

  Future<void> _capture() async {
    if (!mounted || !_dirty || _encoding) return;
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! _RenderSnapshotBoundary ||
        boundary.debugNeedsPaint ||
        boundary.size.isEmpty) {
      return;
    }
    final generation = _generation;
    _dirty = false;
    _encoding = true;
    _lastCapture = _captureClock.elapsed;
    ui.Image? image;
    try {
      widget.onCapture?.call();
      final scale = _pixelRatio;
      image = await boundary.capture(scale);
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (!mounted || generation != _generation || rgba == null) return;
      final raw = rgba.buffer.asUint8List(
        rgba.offsetInBytes,
        rgba.lengthInBytes,
      );
      // Even an identical repaint needs no channel transfer. Native code can
      // create a CGImage directly from these bytes, avoiding PNG encode/decode.
      if (listEquals(raw, _lastRgba)) return;
      _lastRgba = raw;
      widget.onPixels(
        NativeIconPixels(
          rgba: raw,
          width: image.width,
          height: image.height,
          scale: scale,
        ),
      );
    } finally {
      image?.dispose();
      _encoding = false;
      if (mounted) {
        if (generation != _generation) _dirty = true;
        _scheduleCapture();
      }
    }
  }

  @override
  void dispose() {
    _pendingCapture?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: _TransparentPaint(
        child: _SnapshotBoundary(
          key: _boundaryKey,
          onChanged: _layerChanged,
          child: SizedBox(width: 26, height: 26, child: widget.child),
        ),
      ),
    ),
  );
}

class _SnapshotBoundary extends SingleChildRenderObjectWidget {
  const _SnapshotBoundary({
    super.key,
    required this.onChanged,
    required super.child,
  });
  final VoidCallback onChanged;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSnapshotBoundary(onChanged);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSnapshotBoundary renderObject,
  ) {
    renderObject.onChanged = onChanged;
  }
}

class _RenderSnapshotBoundary extends RenderRepaintBoundary {
  _RenderSnapshotBoundary(this.onChanged);
  VoidCallback onChanged;

  Future<ui.Image> capture(double pixelRatio) {
    // toImage builds its scene synchronously. Do not suppress real frames
    // arriving while the resulting GPU readback is pending.
    final snapshotLayer = layer! as _SnapshotLayer;
    snapshotLayer.suppressNotification = true;
    try {
      return toImage(pixelRatio: pixelRatio);
    } finally {
      snapshotLayer.suppressNotification = false;
    }
  }

  @override
  OffsetLayer updateCompositedLayer({required OffsetLayer? oldLayer}) {
    final result = oldLayer as _SnapshotLayer? ?? _SnapshotLayer();
    result.onChanged = () => onChanged();
    return result;
  }
}

class _SnapshotLayer extends OffsetLayer {
  VoidCallback? onChanged;
  bool suppressNotification = false;
  List<Object?> _contents = [];

  @override
  void addToScene(ui.SceneBuilder builder) {
    super.addToScene(builder);
    // Compare actual drawing inputs, not engine-cache identities. Nested
    // opacity/transform layers can update without repainting this boundary.
    // Ignore this boundary's own offset: moving the icon does not change pixels.
    final contents = <Object?>[];
    void visit(Layer child) {
      contents.add(child);
      if (child is PictureLayer) contents.add(child.picture);
      if (child is OffsetLayer) contents.add(child.offset);
      if (child is OpacityLayer) contents.add(child.alpha);
      if (child is TransformLayer) {
        contents.addAll(child.transform?.storage ?? const <double>[]);
      }
      if (child is ClipRectLayer) {
        contents.addAll([child.clipRect, child.clipBehavior]);
      }
      if (child is ClipRRectLayer) {
        contents.addAll([child.clipRRect, child.clipBehavior]);
      }
      if (child is ClipPathLayer) {
        contents.addAll([child.clipPath, child.clipBehavior]);
      }
      if (child is ColorFilterLayer) contents.add(child.colorFilter);
      if (child is ImageFilterLayer) contents.add(child.imageFilter);
      if (child is ShaderMaskLayer) {
        contents.addAll([child.shader, child.maskRect, child.blendMode]);
      }
      if (child is BackdropFilterLayer) {
        contents.addAll([child.filter, child.blendMode]);
      }
      if (child is ContainerLayer) {
        for (
          Layer? nested = child.firstChild;
          nested != null;
          nested = nested.nextSibling
        ) {
          visit(nested);
        }
      }
    }

    for (Layer? child = firstChild; child != null; child = child.nextSibling) {
      visit(child);
    }
    final changed = !listEquals(contents, _contents);
    _contents = contents;
    if (changed && !suppressNotification) onChanged?.call();
  }
}

class _TransparentPaint extends SingleChildRenderObjectWidget {
  const _TransparentPaint({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTransparentPaint();
}

class _RenderTransparentPaint extends RenderProxyBox {
  @override
  bool get alwaysNeedsCompositing => child != null;
  final LayerHandle<OpacityLayer> _opacity = LayerHandle<OpacityLayer>();
  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    _opacity.layer ??= OpacityLayer(alpha: 0);
    context.pushLayer(_opacity.layer!, (context, offset) {
      context.paintChild(child!, offset);
    }, offset);
  }

  @override
  void dispose() {
    _opacity.layer = null;
    super.dispose();
  }
}
