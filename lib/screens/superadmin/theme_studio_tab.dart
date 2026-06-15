import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/company_config.dart';
import '../../providers/theme_provider.dart';
import '../../services/branding_config_service.dart';
import '../../widgets/branded_logo.dart';
import 'superadmin_theme.dart';

/// Branding & Theme studio — configure the logo and color identity with live,
/// faithful previews of the supervisor, Production Manager, and SuperAdmin
/// dashboards, then apply it across the whole product.
class ThemeStudioTab extends StatefulWidget {
  const ThemeStudioTab({super.key});

  @override
  State<ThemeStudioTab> createState() => _ThemeStudioTabState();
}

class _ThemeStudioTabState extends State<ThemeStudioTab> {
  final _service = BrandingConfigService();
  final _logoCtrl = TextEditingController();

  Color _primary = CompanyConfig.brandColor;
  Color _accent = CompanyConfig.brandColor;
  String _logoValue = ''; // url or data: URI
  bool _backgroundless = false;
  bool _previewDark = false;
  bool _loaded = false;
  bool _saving = false;
  bool _dirty = false;
  String _savedAt = '';

  static const _maxLogoBytes = 180 * 1024; // keep RTDB + per-load download sane

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _service.fetch();
      if (!mounted) return;
      setState(() {
        _primary = c.primaryColor ?? CompanyConfig.brandColor;
        _accent = c.accentColor ?? c.primaryColor ?? CompanyConfig.brandColor;
        _logoValue = c.logoUrl;
        if (!_logoValue.startsWith('data:')) _logoCtrl.text = _logoValue;
        _backgroundless = c.logoBackgroundless;
        _savedAt = c.updatedAt;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    super.dispose();
  }

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _pickLogo() async {
    final res =
        await FilePicker.pickFiles(type: FileType.image, withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return;
    if (bytes.length > _maxLogoBytes) {
      _toast('Image is ${(bytes.length / 1024).round()} KB — keep it under '
          '180 KB or paste a URL instead.', Sa.amber);
      return;
    }
    final name = (res!.files.single.name).toLowerCase();
    final mime = name.endsWith('.svg')
        ? 'image/svg+xml'
        : name.endsWith('.jpg') || name.endsWith('.jpeg')
            ? 'image/jpeg'
            : 'image/png';
    setState(() {
      _logoValue = 'data:$mime;base64,${base64Encode(bytes)}';
      _logoCtrl.clear();
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final cfg = BrandingConfig(
      primaryColor: _primary,
      accentColor: _accent,
      logoUrl: _logoValue,
      logoBackgroundless: _backgroundless,
    );
    try {
      await _service.save(cfg);
      if (!mounted) return;
      context.read<ThemeProvider>().applyBranding(
            primary: _primary,
            logoUrl: _logoValue,
            logoBackgroundless: _backgroundless,
          );
      setState(() {
        _saving = false;
        _dirty = false;
        _savedAt = DateTime.now().toIso8601String();
      });
      _toast('Branding applied across the platform.', Sa.green);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('Save failed: $e', Sa.red);
      }
    }
  }

  void _toast(String m, Color c) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text(m, style: Sa.body(color: c, weight: FontWeight.w600)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return Center(child: CircularProgressIndicator(color: Sa.cyan));
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1060;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _intro(),
            const SizedBox(height: 18),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 430, child: _controls()),
                  const SizedBox(width: 20),
                  Expanded(child: _previews()),
                ],
              )
            else ...[
              _controls(),
              const SizedBox(height: 20),
              _previews(),
            ],
          ],
        ),
      );
    });
  }

  Widget _intro() => Row(children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_primary, _accent]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: _primary.withValues(alpha: 0.45), blurRadius: 18)],
          ),
          child: const Icon(Icons.palette_outlined, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BRANDING & THEME', style: Sa.display(size: 18)),
              const SizedBox(height: 3),
              Text(
                'Logo and color identity, applied across login, supervisor, '
                'Production Manager, and SuperAdmin surfaces.',
                style: Sa.body(size: 12, color: Sa.textDim),
              ),
            ],
          ),
        ),
        if (_savedAt.isNotEmpty)
          GlowChip(label: 'LIVE', color: Sa.green, icon: Icons.check, pulse: true),
      ]);

  // ── controls ───────────────────────────────────────────────────────────────
  Widget _controls() => Column(children: [
        _logoCard(),
        const SizedBox(height: 16),
        _ColorField(
          title: 'PRIMARY · BRAND',
          subtitle: 'App bars, buttons, nav, accents.',
          color: _primary,
          onChanged: (c) => setState(() {
            _primary = c;
            _markDirty();
          }),
        ),
        const SizedBox(height: 16),
        _ColorField(
          title: 'ACCENT',
          subtitle: 'Secondary highlights and gradients.',
          color: _accent,
          onChanged: (c) => setState(() {
            _accent = c;
            _markDirty();
          }),
        ),
        const SizedBox(height: 16),
        _saveBar(),
      ]);

  Widget _logoCard() => GlassPanel(
        accent: _primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(Icons.image_outlined, 'LOGO'),
            const SizedBox(height: 14),
            Row(children: [
              BrandedLogo(
                  value: _logoValue,
                  backgroundless: _backgroundless,
                  primary: _primary,
                  size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _logoValue.startsWith('data:')
                      ? 'Uploaded image.'
                      : _logoValue.isEmpty
                          ? 'Default Smart Industrial Alert mark.'
                          : 'Logo from URL.',
                  style: Sa.body(size: 11.5, color: Sa.textDim),
                ),
              ),
              SaButton(
                label: 'Upload',
                icon: Icons.upload_outlined,
                outlined: true,
                onPressed: _pickLogo,
              ),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _logoCtrl,
              onChanged: (v) => setState(() {
                _logoValue = v.trim();
                _markDirty();
              }),
              style: Sa.body(size: 12.5, color: Sa.text),
              decoration: _dec('…or paste an image URL (https://…/logo.png)'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: _primary,
              value: _backgroundless,
              onChanged: (v) => setState(() {
                _backgroundless = v;
                _markDirty();
              }),
              title: Text('Backgroundless logo',
                  style: Sa.body(size: 13, color: Sa.text, weight: FontWeight.w600)),
              subtitle: Text('Drop the plate so the logo sits transparently.',
                  style: Sa.body(size: 11, color: Sa.muted)),
            ),
          ],
        ),
      );

  Widget _saveBar() => GlassPanel(
        child: Row(children: [
          SaButton(
            label: 'Reset',
            icon: Icons.restart_alt,
            outlined: true,
            onPressed: _saving ? null : _resetDefaults,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_dirty ? 'Unsaved changes' : 'All changes applied',
                textAlign: TextAlign.right,
                style: Sa.body(
                    size: 12,
                    color: _dirty ? Sa.amber : Sa.green,
                    weight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          SaButton(
            label: _saving ? 'Applying…' : 'Apply & Deploy',
            icon: Icons.rocket_launch_outlined,
            busy: _saving,
            color: _primary,
            onPressed: _saving ? null : _save,
          ),
        ]),
      );

  Future<void> _resetDefaults() async {
    setState(() => _saving = true);
    try {
      await _service.reset();
      if (!mounted) return;
      context.read<ThemeProvider>().resetBranding();
      setState(() {
        _primary = CompanyConfig.brandColor;
        _accent = CompanyConfig.brandColor;
        _logoValue = '';
        _logoCtrl.clear();
        _backgroundless = false;
        _saving = false;
        _dirty = false;
      });
      _toast('Reset to default branding.', Sa.cyan);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('Reset failed: $e', Sa.red);
      }
    }
  }

  // ── previews ─────────────────────────────────────────────────────────────
  Widget _previews() => GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _header(Icons.visibility_outlined, 'LIVE PREVIEW'),
              const Spacer(),
              _modeToggle(),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 16, children: [
              _frame('SUPERVISOR',
                  _SupervisorPreview(primary: _primary, accent: _accent, dark: _previewDark, logo: _logoValue, bgless: _backgroundless)),
              _frame('PRODUCTION MANAGER',
                  _PmPreview(primary: _primary, accent: _accent, dark: _previewDark, logo: _logoValue, bgless: _backgroundless)),
              _frame('SUPERADMIN',
                  _SuperAdminPreview(primary: _primary, accent: _accent, dark: _previewDark)),
            ]),
          ],
        ),
      );

  Widget _modeToggle() {
    Widget seg(String label, IconData icon, bool dark) {
      final active = _previewDark == dark;
      return GestureDetector(
        onTap: () => setState(() => _previewDark = dark),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? _primary.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: active ? _primary : Sa.border, width: active ? 1.4 : 1),
          ),
          child: Row(children: [
            Icon(icon, size: 14, color: active ? _primary : Sa.muted),
            const SizedBox(width: 6),
            Text(label, style: Sa.mono(size: 10, color: active ? Sa.text : Sa.muted, weight: FontWeight.w700)),
          ]),
        ),
      );
    }

    return Row(children: [
      seg('LIGHT', Icons.light_mode_outlined, false),
      const SizedBox(width: 8),
      seg('NIGHT', Icons.dark_mode_outlined, true),
    ]);
  }

  Widget _frame(String label, Widget child) => _PreviewFrame(label: label, child: child);

  Widget _header(IconData icon, String label) => Row(children: [
        Icon(icon, size: 16, color: Sa.cyan),
        const SizedBox(width: 8),
        Text(label, style: Sa.heading(size: 13)),
      ]);

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: Sa.body(size: 12, color: Sa.muted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: Sa.bg.withValues(alpha: 0.5),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Sa.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _primary, width: 1.5)),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Color field: swatch + hex + presets + a 2D saturation/value box + hue slider.
// ═══════════════════════════════════════════════════════════════════════════
class _ColorField extends StatefulWidget {
  final String title;
  final String subtitle;
  final Color color;
  final ValueChanged<Color> onChanged;
  const _ColorField(
      {required this.title,
      required this.subtitle,
      required this.color,
      required this.onChanged});

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  static const _presets = <int>[
    0xFF0D4A75, 0xFF1565C0, 0xFF2563EB, 0xFF0EA5E9, 0xFF06B6D4, 0xFF14B8A6,
    0xFF10B981, 0xFF22C55E, 0xFF84CC16, 0xFFEAB308, 0xFFF59E0B, 0xFFEA580C,
    0xFFEF4444, 0xFFDC2626, 0xFFE11D48, 0xFFEC4899, 0xFFD946EF, 0xFFA855F7,
    0xFF8B5CF6, 0xFF6366F1, 0xFF334155, 0xFF0F172A,
  ];

  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hex = TextEditingController(text: _hex6(widget.color));
  }

  @override
  void didUpdateWidget(covariant _ColorField old) {
    super.didUpdateWidget(old);
    final cur = _hex6(widget.color);
    if (_hex.text.toUpperCase() != cur) _hex.text = cur;
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static String _hex6(Color c) =>
      (c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _emit(Color c) => widget.onChanged(c);

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(widget.color);
    return GlassPanel(
      accent: widget.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 14)],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: Sa.heading(size: 13)),
                  Text(widget.subtitle, style: Sa.body(size: 10.5, color: Sa.muted)),
                ],
              ),
            ),
            SizedBox(
              width: 92,
              child: TextField(
                controller: _hex,
                style: Sa.mono(size: 12, color: Sa.text),
                textAlign: TextAlign.center,
                onSubmitted: (v) {
                  final c = BrandingConfig.parseColor(v);
                  if (c != null) _emit(c);
                },
                decoration: InputDecoration(
                  prefixText: '#',
                  prefixStyle: Sa.mono(size: 12, color: Sa.muted),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Sa.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.color, width: 1.4)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          // Custom color box (saturation × brightness).
          _SatValBox(
            hue: hsv.hue,
            sat: hsv.saturation,
            val: hsv.value,
            onChanged: (s, v) => _emit(HSVColor.fromAHSV(1, hsv.hue, s, v).toColor()),
          ),
          const SizedBox(height: 12),
          _HueSlider(
            hue: hsv.hue,
            onChanged: (h) => _emit(HSVColor.fromAHSV(
                    1, h, hsv.saturation == 0 ? 1 : hsv.saturation, hsv.value == 0 ? 1 : hsv.value)
                .toColor()),
          ),
          const SizedBox(height: 14),
          Text('PALETTE', style: Sa.mono(size: 9.5, color: Sa.muted, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: _presets.map((v) {
              final c = Color(v);
              final sel = (c.value & 0xFFFFFF) == (widget.color.value & 0xFFFFFF);
              return GestureDetector(
                onTap: () => _emit(c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                        color: sel ? Colors.white : Colors.white.withValues(alpha: 0.12),
                        width: sel ? 2 : 1),
                    boxShadow: sel ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 10)] : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// A visible draggable handle (white ring + dark outline + shadow) that reads on
/// any background — fixes the invisible-thumb problem.
class _Handle extends StatelessWidget {
  final double diameter;
  const _Handle({this.diameter = 18});
  @override
  Widget build(BuildContext context) => Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 4),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: 0.5), width: 1),
          ),
        ),
      );
}

class _SatValBox extends StatelessWidget {
  final double hue, sat, val;
  final void Function(double s, double v) onChanged;
  const _SatValBox(
      {required this.hue, required this.sat, required this.val, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      const h = 130.0;
      void handle(Offset p) {
        final s = (p.dx / w).clamp(0.0, 1.0);
        final v = (1 - p.dy / h).clamp(0.0, 1.0);
        onChanged(s, v);
      }

      return GestureDetector(
        onPanDown: (d) => handle(d.localPosition),
        onPanUpdate: (d) => handle(d.localPosition),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: HSVColor.fromAHSV(1, hue, 1, 1).toColor()),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.white, Colors.transparent]),
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black]),
                  ),
                ),
              ),
              Positioned(
                left: (sat * w - 9).clamp(0.0, w - 18),
                top: ((1 - val) * h - 9).clamp(0.0, h - 18),
                child: const _Handle(),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueSlider({required this.hue, required this.onChanged});

  static const _spectrum = [
    Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
    Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      void handle(double dx) => onChanged((dx / w).clamp(0.0, 1.0) * 360);
      return GestureDetector(
        onPanDown: (d) => handle(d.localPosition.dx),
        onPanUpdate: (d) => handle(d.localPosition.dx),
        child: SizedBox(
          width: w,
          height: 22,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: const LinearGradient(colors: _spectrum),
                ),
              ),
            ),
            Positioned(
              left: (hue / 360 * w - 9).clamp(0.0, w - 18),
              top: 2,
              child: const _Handle(),
            ),
          ]),
        ),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Preview frame with hover-lift.
// ═══════════════════════════════════════════════════════════════════════════
class _PreviewFrame extends StatefulWidget {
  final String label;
  final Widget child;
  const _PreviewFrame({required this.label, required this.child});
  @override
  State<_PreviewFrame> createState() => _PreviewFrameState();
}

class _PreviewFrameState extends State<_PreviewFrame> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.label, style: Sa.mono(size: 9.5, color: Sa.muted)),
            const SizedBox(height: 7),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Sa.shadow, blurRadius: _hover ? 28 : 14, offset: const Offset(0, 8)),
                ],
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(20), child: widget.child),
            ),
          ],
        ),
      ),
    );
  }
}

// ── theme palette for the mock dashboards ────────────────────────────────────
class _M {
  final Color bg, card, navBar, text, sub, border;
  const _M(this.bg, this.card, this.navBar, this.text, this.sub, this.border);
  factory _M.light() => const _M(Color(0xFFF8FAFC), Colors.white, Colors.white,
      Color(0xFF1E293B), Color(0xFF94A3B8), Color(0xFFE2E8F0));
  factory _M.dark() => const _M(Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF1E293B),
      Color(0xFFF1F5F9), Color(0xFF64748B), Color(0xFF334155));
}

const _supWidth = 244.0;
const _supHeight = 340.0;

// ═══════════════════════════════════════════════════════════════════════════
// SUPERVISOR — header + alert cards + real bottom nav (Dashboard/Locator/
// Station Scan/Collab) with the primary-filled selected pill.
// ═══════════════════════════════════════════════════════════════════════════
class _SupervisorPreview extends StatelessWidget {
  final Color primary, accent;
  final bool dark, bgless;
  final String logo;
  const _SupervisorPreview(
      {required this.primary,
      required this.accent,
      required this.dark,
      required this.logo,
      required this.bgless});

  @override
  Widget build(BuildContext context) {
    final m = dark ? _M.dark() : _M.light();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: _supWidth,
      height: _supHeight,
      color: m.bg,
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 12, 14),
          color: m.card,
          child: Row(children: [
            BrandedLogo(value: logo, backgroundless: bgless, primary: primary, size: 30),
            const SizedBox(width: 9),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hi, Ahmed',
                    style: TextStyle(color: m.text, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Production Line 2', style: TextStyle(color: m.sub, fontSize: 9)),
              ],
            ),
            const Spacer(),
            Icon(Icons.notifications_none, color: m.sub, size: 18),
            const SizedBox(width: 8),
            CircleAvatar(radius: 12, backgroundColor: primary, child: const Text('A',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Column(children: [
              _alert(m, const Color(0xFFDC2626), 'CRITICAL', 'Conveyor A · Stn 3', '#1042', true),
              const SizedBox(height: 9),
              _alert(m, accent, 'EN COURS', 'Conveyor B · Stn 7', '#1041', false),
            ]),
          ),
        ),
        _bottomNav(m),
      ]),
    );
  }

  Widget _alert(_M m, Color tag, String status, String loc, String num, bool claim) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: m.card,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: tag, width: 3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(num, style: TextStyle(color: m.text, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          Text('Mechanical', style: TextStyle(color: m.sub, fontSize: 10)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: tag.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(5)),
            child: Text(status, style: TextStyle(color: tag, fontSize: 7.5, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.place_outlined, size: 11, color: m.sub),
          const SizedBox(width: 3),
          Text(loc, style: TextStyle(color: m.sub, fontSize: 9.5)),
          const Spacer(),
          Text('04:21', style: TextStyle(color: tag, fontSize: 10, fontWeight: FontWeight.w700, fontFeatures: const [])),
        ]),
        if (claim) ...[
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            height: 30,
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.4), blurRadius: 10)],
            ),
            child: const Center(
              child: Text('CLAIM ALERT',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _bottomNav(_M m) {
    Widget item(IconData icon, String label, bool sel) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: sel ? BoxDecoration(color: primary, borderRadius: BorderRadius.circular(10)) : null,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: sel ? Colors.white : m.sub),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 7.5,
                    color: sel ? Colors.white : m.sub,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: m.navBar, border: Border(top: BorderSide(color: m.border))),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(children: [
        item(Icons.dashboard, 'Dashboard', true),
        item(Icons.map, 'Locator', false),
        item(Icons.qr_code_scanner, 'Scan', false),
        item(Icons.handshake, 'Collab', false),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRODUCTION MANAGER — PillTabBar + EliteStatCard grid (Total/Solved/In
// Progress/Pending) with icon tiles, trend pills, and sparklines.
// ═══════════════════════════════════════════════════════════════════════════
class _PmPreview extends StatelessWidget {
  final Color primary, accent;
  final bool dark, bgless;
  final String logo;
  const _PmPreview(
      {required this.primary,
      required this.accent,
      required this.dark,
      required this.logo,
      required this.bgless});

  @override
  Widget build(BuildContext context) {
    final m = dark ? _M.dark() : _M.light();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 320,
      height: _supHeight,
      color: m.bg,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
          color: m.card,
          child: Row(children: [
            BrandedLogo(value: logo, backgroundless: bgless, primary: primary, size: 26),
            const SizedBox(width: 9),
            Text('Production Manager',
                style: TextStyle(color: m.text, fontSize: 12.5, fontWeight: FontWeight.w800)),
            const Spacer(),
            CircleAvatar(radius: 11, backgroundColor: accent, child: const Icon(Icons.person, size: 13, color: Colors.white)),
          ]),
        ),
        // Pill tab bar
        Container(
          color: m.card,
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Row(children: [
            _pill('Overview', true, m),
            _pill('Supervisors', false, m),
            _pill('Shifts', false, m),
            _pill('Alerts', false, m),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              childAspectRatio: 1.36,
              children: [
                _stat(m, 'Total', 128, Icons.layers_outlined, primary, 12, true),
                _stat(m, 'Solved', 92, Icons.check_circle_outline, const Color(0xFF16A34A), 8, false),
                _stat(m, 'In Progress', 22, Icons.timelapse, accent, -4, false),
                _stat(m, 'Pending', 14, Icons.pending_outlined, const Color(0xFF2563EB), 3, false),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _pill(String label, bool sel, _M m) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: sel ? primary : m.bg,
            borderRadius: BorderRadius.circular(20),
            border: sel ? null : Border.all(color: m.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 8.5,
                  color: sel ? Colors.white : m.sub,
                  fontWeight: FontWeight.w700)),
        ),
      );

  Widget _stat(_M m, String label, int value, IconData icon, Color color, double trend, bool active) {
    final up = trend >= 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
      decoration: BoxDecoration(
        gradient: active
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.16), m.card])
            : null,
        color: active ? null : m.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: active ? color : m.border, width: active ? 1.5 : 1),
        boxShadow: [BoxShadow(color: (active ? color : Colors.black).withValues(alpha: active ? 0.14 : 0.04), blurRadius: active ? 12 : 6, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 13, color: color),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
                color: (up ? const Color(0xFF16A34A) : const Color(0xFFDC2626)).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 8, color: up ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
              Text('${trend.abs().toInt()}%',
                  style: TextStyle(
                      fontSize: 7.5,
                      fontWeight: FontWeight.w800,
                      color: up ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
            ]),
          ),
        ]),
        const Spacer(),
        Text(label.toUpperCase(),
            style: TextStyle(fontSize: 7.5, color: m.sub, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 1),
        Text('$value',
            style: TextStyle(fontSize: 24, height: 1, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 3),
        SizedBox(height: 12, child: CustomPaint(painter: _SparkPainter(color), size: Size.infinite)),
      ]),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final Color color;
  _SparkPainter(this.color);
  static const _d = [3, 5, 4, 7, 5, 9, 6, 8];
  @override
  void paint(Canvas canvas, Size size) {
    final maxV = _d.reduce((a, b) => a > b ? a : b).toDouble();
    final step = size.width / (_d.length - 1);
    final path = Path();
    for (var i = 0; i < _d.length; i++) {
      final x = i * step;
      final y = size.height - (_d[i] / maxV) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// SUPERADMIN — command center (deep-space dark / arctic light per the toggle).
// ═══════════════════════════════════════════════════════════════════════════
class _SuperAdminPreview extends StatelessWidget {
  final Color primary, accent;
  final bool dark;
  const _SuperAdminPreview({required this.primary, required this.accent, required this.dark});

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xFF040A18) : const Color(0xFFEDF2FA);
    final panel = dark ? const Color(0xFF0B1530) : Colors.white;
    final border = dark ? const Color(0xFF1B2A4A) : const Color(0xFFD4DEF0);
    final text = dark ? const Color(0xFFE2E8F0) : const Color(0xFF14233E);
    final dim = dark ? const Color(0xFF94A3B8) : const Color(0xFF7787A3);
    final cyan = dark ? const Color(0xFF22D3EE) : const Color(0xFF0E7490);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 320,
      height: _supHeight,
      color: bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [primary, accent]),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.shield_outlined, color: Colors.white, size: 13),
            ),
            const SizedBox(width: 9),
            Text('COMMAND CENTER',
                style: TextStyle(color: text, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const Spacer(),
            _dot(accent),
          ]),
        ),
        // tab strip
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 4),
          child: Row(children: [
            _tab('AI', true, primary, dim, border),
            _tab('AGENTS', false, primary, dim, border),
            _tab('LOGS', false, primary, dim, border),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _glass(panel, border, primary, 'AGENTS', '6', Icons.hub_outlined, text, dim),
            const SizedBox(width: 9),
            _glass(panel, border, cyan, 'UPTIME', '99.9', Icons.bolt_outlined, text, dim),
            const SizedBox(width: 9),
            _glass(panel, border, accent, 'MODELS', '3', Icons.psychology_outlined, text, dim),
          ]),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: dark ? panel.withValues(alpha: 0.7) : panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < 4; i++) ...[
                Row(children: [
                  Container(width: 5, height: 5, decoration: BoxDecoration(color: i == 0 ? accent : primary, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Container(width: 150.0 - i * 22, height: 6, decoration: BoxDecoration(color: dim.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3))),
                  const Spacer(),
                  Container(width: 20, height: 6, decoration: BoxDecoration(color: primary.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(3))),
                ]),
                if (i < 3) const SizedBox(height: 12),
              ]
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _dot(Color c) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
          color: c, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: 8)]));

  Widget _tab(String label, bool sel, Color primary, Color dim, Color border) => Padding(
        padding: const EdgeInsets.only(right: 7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? primary.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: sel ? primary : border, width: sel ? 1.2 : 1),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 8,
                  color: sel ? primary : dim,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ),
      );

  Widget _glass(Color panel, Color border, Color c, String label, String n, IconData icon, Color text, Color dim) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: panel.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(height: 7),
          Text(n, style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: dim, fontSize: 7, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
