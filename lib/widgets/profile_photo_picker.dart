import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

const _profileGalleryChannel = MethodChannel('mali_compagnie/media_gallery');

class ProfilePhotoPicker {
  static Future<Uint8List?> pick(BuildContext context) async {
    Uint8List? bytes;
    if (Platform.isAndroid) {
      final uri = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const _ProfileGalleryScreen(),
        ),
      );
      if (!context.mounted || uri == null || uri.isEmpty) return null;
      final loading = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      );
      try {
        bytes = await _profileGalleryChannel.invokeMethod<Uint8List>(
          'readMedia',
          {'uri': uri},
        );
      } finally {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        unawaited(loading);
      }
    } else {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 92,
      );
      if (picked == null) return null;
      bytes = await picked.readAsBytes();
    }
    if (!context.mounted || bytes == null || bytes.isEmpty) return null;
    return Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CircularPhotoCropScreen(bytes: bytes!),
      ),
    );
  }
}

class _ProfileGalleryItem {
  final String uri;
  final String name;
  final Uint8List? thumbnail;

  const _ProfileGalleryItem({
    required this.uri,
    required this.name,
    this.thumbnail,
  });

  factory _ProfileGalleryItem.fromNative(Map<dynamic, dynamic> value) {
    final thumbnail = value['thumbnail'];
    return _ProfileGalleryItem(
      uri: value['uri']?.toString() ?? '',
      name: value['name']?.toString() ?? 'Photo',
      thumbnail: thumbnail is Uint8List ? thumbnail : null,
    );
  }
}

class _ProfileGalleryScreen extends StatefulWidget {
  const _ProfileGalleryScreen();

  @override
  State<_ProfileGalleryScreen> createState() => _ProfileGalleryScreenState();
}

class _ProfileGalleryScreenState extends State<_ProfileGalleryScreen> {
  final _search = TextEditingController();
  List<_ProfileGalleryItem> _items = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hasAccess =
          await _profileGalleryChannel.invokeMethod<bool>('hasMediaAccess') ??
          false;
      final granted =
          hasAccess ||
          (await _profileGalleryChannel.invokeMethod<bool>(
                'requestMediaAccess',
              ) ??
              false);
      if (!granted) {
        throw PlatformException(
          code: 'permission_required',
          message: 'Autorisez l acces aux photos pour ouvrir la galerie.',
        );
      }
      final raw = await _profileGalleryChannel.invokeMethod<List<dynamic>>(
        'listMedia',
        {'kind': 'image', 'limit': 100},
      );
      final items = (raw ?? const [])
          .whereType<Map>()
          .map(_ProfileGalleryItem.fromNative)
          .where((item) => item.uri.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is PlatformException
            ? (error.message ?? 'Galerie indisponible.')
            : 'Impossible de charger vos photos.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final query = _query.trim().toLowerCase();
    final items = query.isEmpty
        ? _items
        : _items
              .where((item) => item.name.toLowerCase().contains(query))
              .toList(growable: false);
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF070B11) : Colors.white,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Photo de profil'),
            Text(
              'Choisissez une photo',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Rechercher une photo',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: dark ? const Color(0xFF111827) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _GalleryError(message: _error!, onRetry: _load)
                  : items.isEmpty
                  ? const Center(child: Text('Aucune photo trouvee.'))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 20),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 7,
                            mainAxisSpacing: 7,
                          ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Material(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.pop(context, item.uri),
                            child: item.thumbnail == null
                                ? const Icon(Icons.image_rounded, size: 34)
                                : Image.memory(
                                    item.thumbnail!,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _GalleryError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reessayer'),
            ),
          ],
        ),
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
