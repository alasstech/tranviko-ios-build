import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class ProfilePhotoPicker {
  static Future<Uint8List?> pick(BuildContext context) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 92,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (!context.mounted || bytes.isEmpty) return null;
    return Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CircularPhotoCropScreen(bytes: bytes),
      ),
    );
  }
}

class _CircularPhotoCropScreen extends StatefulWidget {
  final Uint8List bytes;

  const _CircularPhotoCropScreen({required this.bytes});

  @override
  State<_CircularPhotoCropScreen> createState() =>
      _CircularPhotoCropScreenState();
}

class _CircularPhotoCropScreenState extends State<_CircularPhotoCropScreen> {
  final _captureKey = GlobalKey();
  final _transformation = TransformationController();
  bool _saving = false;
  double _zoom = 1;

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final rendered = await boundary.toImage(pixelRatio: 2);
      final byteData = await rendered.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return;
      final decoded = img.decodePng(byteData.buffer.asUint8List());
      if (decoded == null) return;
      final resized = img.copyResize(decoded, width: 640, height: 640);
      final output = Uint8List.fromList(img.encodeJpg(resized, quality: 84));
      if (mounted) Navigator.pop(context, output);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setZoom(double value, double viewportSize) {
    final next = value.clamp(1.0, 5.0);
    final viewportCenter = Offset(viewportSize / 2, viewportSize / 2);
    final sceneCenter = _transformation.toScene(viewportCenter);
    _transformation.value = Matrix4.identity()
      ..translateByDouble(viewportCenter.dx, viewportCenter.dy, 0, 1)
      ..scaleByDouble(next, next, 1, 1)
      ..translateByDouble(-sceneCenter.dx, -sceneCenter.dy, 0, 1);
    setState(() => _zoom = next);
  }

  void _resetCrop() {
    _transformation.value = Matrix4.identity();
    setState(() => _zoom = 1);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF05070B) : Colors.white,
      appBar: AppBar(title: const Text('Ajuster la photo')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.maxWidth.clamp(260.0, 430.0) - 32;
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 14),
                  child: Text(
                    'Deplacez et zoomez la photo pour choisir exactement ce qui apparaitra dans le cercle.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SizedBox.square(
                      dimension: size,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(
                            key: _captureKey,
                            child: ClipRect(
                              child: InteractiveViewer(
                                transformationController: _transformation,
                                minScale: 1,
                                maxScale: 5,
                                panEnabled: true,
                                scaleEnabled: true,
                                onInteractionUpdate: (_) {
                                  final scale = _transformation.value
                                      .getMaxScaleOnAxis()
                                      .clamp(1.0, 5.0);
                                  if ((scale - _zoom).abs() > .02) {
                                    setState(() => _zoom = scale);
                                  }
                                },
                                clipBehavior: Clip.hardEdge,
                                child: SizedBox.square(
                                  dimension: size,
                                  child: Image.memory(
                                    widget.bytes,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _CircularCropMaskPainter(
                                dark: dark,
                                inset: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Dezoomer',
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: _zoom <= 1.01
                            ? null
                            : () => _setZoom(_zoom - .25, size),
                        icon: const Icon(Icons.remove_rounded),
                      ),
                      Expanded(
                        child: Slider(
                          value: _zoom.clamp(1.0, 5.0),
                          min: 1,
                          max: 5,
                          divisions: 16,
                          label: '${_zoom.toStringAsFixed(1)}x',
                          onChanged: (value) => _setZoom(value, size),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Zoomer',
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: _zoom >= 4.99
                            ? null
                            : () => _setZoom(_zoom + .25, size),
                        icon: const Icon(Icons.add_rounded),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Reinitialiser',
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: _resetCrop,
                        icon: const Icon(Icons.center_focus_strong_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Annuler'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: const Text('Utiliser'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CircularCropMaskPainter extends CustomPainter {
  final bool dark;
  final double inset;

  const _CircularCropMaskPainter({required this.dark, required this.inset});

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addOval(circle)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: dark ? .68 : .52),
    );
    canvas.drawOval(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularCropMaskPainter oldDelegate) {
    return oldDelegate.dark != dark || oldDelegate.inset != inset;
  }
}
