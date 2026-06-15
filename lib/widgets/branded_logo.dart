import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Renders the company logo from any source the Branding studio produces:
///   - a `data:` URI (uploaded image, base64)
///   - an `http(s)` URL
///   - empty → the bundled Smart Industrial Alert mark
///
/// When [backgroundless] is true the white plate is dropped AND the image's own
/// near-white background is knocked out (made transparent) for uploaded/bundled
/// logos, so the mark sits cleanly on the theme. (Remote URLs can't be processed
/// cross-origin, so they only lose the plate.)
class BrandedLogo extends StatefulWidget {
  final String value;
  final bool backgroundless;
  final double size;
  final Color primary;

  const BrandedLogo({
    super.key,
    required this.value,
    required this.primary,
    this.backgroundless = false,
    this.size = 48,
  });

  @override
  State<BrandedLogo> createState() => _BrandedLogoState();
}

class _BrandedLogoState extends State<BrandedLogo> {
  Future<ui.Image?>? _knockout;
  String _key = '';

  String get _cacheKey => '${widget.value}|${widget.backgroundless}';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant BrandedLogo old) {
    super.didUpdateWidget(old);
    if (_cacheKey != _key) _refresh();
  }

  void _refresh() {
    _key = _cacheKey;
    _knockout = (widget.backgroundless && _canKnockout(widget.value))
        ? _removeWhite()
        : null;
  }

  bool _canKnockout(String v) {
    v = v.trim();
    if (v.startsWith('data:')) return !v.contains('svg');
    if (v.startsWith('http')) return false; // cross-origin
    return true; // bundled asset
  }

  Future<Uint8List?> _sourceBytes() async {
    final v = widget.value.trim();
    if (v.startsWith('data:')) {
      try {
        return base64Decode(v.substring(v.indexOf(',') + 1));
      } catch (_) {
        return null;
      }
    }
    if (v.startsWith('http')) return null;
    try {
      final bd = await rootBundle.load('media/sia_logo.png');
      return bd.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<ui.Image?> _removeWhite() async {
    final bytes = await _sourceBytes();
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return img;
      final px = data.buffer.asUint8List();
      for (var i = 0; i < px.length; i += 4) {
        if (px[i] > 232 && px[i + 1] > 232 && px[i + 2] > 232) px[i + 3] = 0;
      }
      final c = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          px, img.width, img.height, ui.PixelFormat.rgba8888, c.complete);
      return c.future;
    } catch (_) {
      return null;
    }
  }

  Widget _fallback(double h) =>
      Icon(Icons.factory, color: widget.primary, size: h * 0.82);

  Widget _plain(double h) {
    final v = widget.value.trim();
    if (v.startsWith('data:')) {
      try {
        return Image.memory(base64Decode(v.substring(v.indexOf(',') + 1)),
            height: h, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _fallback(h));
      } catch (_) {
        return _fallback(h);
      }
    }
    if (v.startsWith('http')) {
      return Image.network(v,
          height: h, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _fallback(h));
    }
    return Image.asset('media/sia_logo.png',
        height: h, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _fallback(h));
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.size * 0.74;
    if (widget.backgroundless) {
      final content = _knockout == null
          ? _plain(h)
          : FutureBuilder<ui.Image?>(
              future: _knockout,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.done) {
                  return snap.data != null
                      ? RawImage(image: snap.data, height: h, fit: BoxFit.contain)
                      : _plain(h);
                }
                return SizedBox(height: h);
              },
            );
      return SizedBox(
          width: widget.size, height: widget.size, child: Center(child: content));
    }
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(widget.size * 0.24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)
        ],
      ),
      child: Center(child: _plain(h)),
    );
  }
}
