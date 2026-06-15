import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/company_config.dart';
import '../../providers/theme_provider.dart';
import '../../services/branding_config_service.dart';
import 'superadmin_theme.dart';

/// Branding & Theme studio — the IT team configures the company logo and the
/// app-wide color identity here, with live previews of every dashboard, and
/// applies it across the whole product (login, supervisor, PM, SuperAdmin).
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
  bool _backgroundless = false;
  bool _previewDark = false;
  bool _loaded = false;
  bool _saving = false;
  bool _dirty = false;
  String _savedAt = '';

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
        _logoCtrl.text = c.logoUrl;
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

  Future<void> _save() async {
    setState(() => _saving = true);
    final cfg = BrandingConfig(
      primaryColor: _primary,
      accentColor: _accent,
      logoUrl: _logoCtrl.text.trim(),
      logoBackgroundless: _backgroundless,
    );
    try {
      await _service.save(cfg);
      // Apply instantly on this device; other dashboards pick it up via stream.
      if (mounted) {
        context.read<ThemeProvider>().applyBranding(
              primary: _primary,
              logoUrl: _logoCtrl.text.trim(),
              logoBackgroundless: _backgroundless,
            );
        setState(() {
          _saving = false;
          _dirty = false;
          _savedAt = DateTime.now().toIso8601String();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Branding applied across the platform.',
              style: Sa.body(color: Sa.text)),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.red,
          content: Text('Save failed: $e',
              style: Sa.body(color: Colors.white)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Center(child: CircularProgressIndicator(color: Sa.cyan));
    }
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1040;
      final controls = _controlsColumn();
      final previews = _previewsColumn();
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
                  SizedBox(width: 420, child: controls),
                  const SizedBox(width: 20),
                  Expanded(child: previews),
                ],
              )
            else ...[
              controls,
              const SizedBox(height: 20),
              previews,
            ],
          ],
        ),
      );
    });
  }

  Widget _intro() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_primary, _accent]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: _primary.withValues(alpha: 0.45), blurRadius: 18)
            ],
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
                'Customize the logo and color identity. Changes apply across login, '
                'supervisor, Production Manager, and SuperAdmin surfaces.',
                style: Sa.body(size: 12, color: Sa.textDim),
              ),
            ],
          ),
        ),
        if (_savedAt.isNotEmpty)
          GlowChip(label: 'LIVE', color: Sa.green, icon: Icons.check, pulse: true),
      ],
    );
  }

  // ── controls ───────────────────────────────────────────────────────────────
  Widget _controlsColumn() {
    return Column(
      children: [
        _logoCard(),
        const SizedBox(height: 16),
        _ColorField(
          title: 'PRIMARY · BRAND',
          subtitle: 'Drives app bars, buttons, nav and accents.',
          color: _primary,
          onChanged: (c) => setState(() {
            _primary = c;
            _markDirty();
          }),
        ),
        const SizedBox(height: 16),
        _ColorField(
          title: 'ACCENT',
          subtitle: 'Secondary highlights, gradients and chips.',
          color: _accent,
          onChanged: (c) => setState(() {
            _accent = c;
            _markDirty();
          }),
        ),
        const SizedBox(height: 16),
        _saveBar(),
      ],
    );
  }

  Widget _logoCard() {
    return GlassPanel(
      accent: _primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.image_outlined, 'LOGO'),
          const SizedBox(height: 14),
          Row(
            children: [
              _LogoBadge(
                logoUrl: _logoCtrl.text.trim(),
                backgroundless: _backgroundless,
                primary: _primary,
                size: 60,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _logoCtrl.text.trim().isEmpty
                      ? 'No custom logo — the default Smart Industrial Alert mark is used.'
                      : 'Custom logo from URL.',
                  style: Sa.body(size: 11.5, color: Sa.textDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _logoCtrl,
            onChanged: (_) => _markDirty(),
            style: Sa.body(size: 12.5, color: Sa.text),
            decoration: _inputDecoration('Logo image URL (https://…/logo.png)'),
          ),
          const SizedBox(height: 6),
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
            subtitle: Text(
              'Drop the plate behind the logo so it sits transparently on the theme.',
              style: Sa.body(size: 11, color: Sa.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveBar() {
    return GlassPanel(
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dirty ? 'Unsaved changes' : 'All changes applied',
              style: Sa.body(
                  size: 12,
                  color: _dirty ? Sa.amber : Sa.green,
                  weight: FontWeight.w600),
            ),
          ),
          SaButton(
            label: _saving ? 'Applying…' : 'Apply & Deploy',
            icon: Icons.rocket_launch_outlined,
            busy: _saving,
            color: _primary,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  // ── previews ─────────────────────────────────────────────────────────────
  Widget _previewsColumn() {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionHeader(Icons.visibility_outlined, 'LIVE PREVIEW'),
              const Spacer(),
              _segToggle(),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _PreviewFrame(
                label: 'SUPERVISOR · ${_previewDark ? 'NIGHT' : 'LIGHT'}',
                child: _SupervisorPreview(
                    primary: _primary,
                    accent: _accent,
                    dark: _previewDark,
                    logoUrl: _logoCtrl.text.trim(),
                    backgroundless: _backgroundless),
              ),
              _PreviewFrame(
                label: 'PRODUCTION MANAGER',
                child: _PmPreview(
                    primary: _primary,
                    accent: _accent,
                    logoUrl: _logoCtrl.text.trim(),
                    backgroundless: _backgroundless),
              ),
              _PreviewFrame(
                label: 'SUPERADMIN · COMMAND CENTER',
                child: _SuperAdminPreview(primary: _primary, accent: _accent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segToggle() {
    Widget seg(String label, IconData icon, bool dark) {
      final active = _previewDark == dark;
      return GestureDetector(
        onTap: () => setState(() => _previewDark = dark),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? _primary.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: active ? _primary : Sa.border, width: active ? 1.4 : 1),
          ),
          child: Row(children: [
            Icon(icon, size: 14, color: active ? _primary : Sa.muted),
            const SizedBox(width: 6),
            Text(label,
                style: Sa.mono(
                    size: 10,
                    color: active ? Sa.text : Sa.muted,
                    weight: FontWeight.w700)),
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

  // ── shared bits ──────────────────────────────────────────────────────────
  Widget _sectionHeader(IconData icon, String label) {
    return Row(children: [
      Icon(icon, size: 16, color: Sa.cyan),
      const SizedBox(width: 8),
      Text(label, style: Sa.heading(size: 13)),
    ]);
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: Sa.body(size: 12, color: Sa.muted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: Sa.bg.withValues(alpha: 0.5),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Sa.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _primary, width: 1.5),
        ),
      );
}

// ───────────────────────────────────────────────────────────────────────────
// Reusable full-spectrum color field: swatch + hex + presets + HSL sliders.
// ───────────────────────────────────────────────────────────────────────────
class _ColorField extends StatefulWidget {
  final String title;
  final String subtitle;
  final Color color;
  final ValueChanged<Color> onChanged;
  const _ColorField({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onChanged,
  });

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  static const _presets = <int>[
    0xFF0D4A75, 0xFF1565C0, 0xFF2563EB, 0xFF0EA5E9, 0xFF06B6D4, 0xFF14B8A6,
    0xFF10B981, 0xFF22C55E, 0xFF84CC16, 0xFFEAB308, 0xFFF59E0B, 0xFFEA580C,
    0xFFEF4444, 0xFFDC2626, 0xFFE11D48, 0xFFEC4899, 0xFFD946EF, 0xFFA855F7,
    0xFF8B5CF6, 0xFF6366F1, 0xFF6D28D9, 0xFF334155, 0xFF0F172A, 0xFF111827,
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
    final hsl = HSLColor.fromColor(widget.color);
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
                boxShadow: [
                  BoxShadow(
                      color: widget.color.withValues(alpha: 0.5), blurRadius: 14)
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: Sa.heading(size: 13)),
                  Text(widget.subtitle,
                      style: Sa.body(size: 10.5, color: Sa.muted)),
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Sa.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: widget.color, width: 1.4),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
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
                      width: sel ? 2 : 1,
                    ),
                    boxShadow: sel
                        ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 10)]
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _slider('H', hsl.hue / 360, (t) {
            _emit(hsl.withHue(t * 360).toColor());
          }, _hueGradient()),
          _slider('S', hsl.saturation, (t) {
            _emit(hsl.withSaturation(t).toColor());
          }, [
            HSLColor.fromAHSL(1, hsl.hue, 0, hsl.lightness).toColor(),
            HSLColor.fromAHSL(1, hsl.hue, 1, hsl.lightness).toColor(),
          ]),
          _slider('L', hsl.lightness, (t) {
            _emit(hsl.withLightness(t.clamp(0.05, 0.95)).toColor());
          }, [
            Colors.black,
            HSLColor.fromAHSL(1, hsl.hue, hsl.saturation, 0.5).toColor(),
            Colors.white,
          ]),
        ],
      ),
    );
  }

  List<Color> _hueGradient() => const [
        Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
        Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
      ];

  Widget _slider(String label, double value, ValueChanged<double> onChanged,
      List<Color> track) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        SizedBox(
          width: 14,
          child: Text(label,
              style: Sa.mono(size: 11, color: Sa.muted, weight: FontWeight.w700)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              trackShape: _GradientTrackShape(track),
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Paints a gradient under the slider track so H/S/L read like real pickers.
class _GradientTrackShape extends RoundedRectSliderTrackShape {
  final List<Color> colors;
  const _GradientTrackShape(this.colors);

  @override
  void paint(PaintingContext context, Offset offset,
      {required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required Animation<double> enableAnimation,
      required TextDirection textDirection,
      required Offset thumbCenter,
      Offset? secondaryOffset,
      bool isDiscrete = false,
      bool isEnabled = false,
      double additionalActiveTrackHeight = 0}) {
    final rect = getPreferredRect(
        parentBox: parentBox, offset: offset, sliderTheme: sliderTheme);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    final paint = Paint()
      ..shader = LinearGradient(colors: colors).createShader(rect);
    context.canvas.drawRRect(rrect, paint);
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Logo badge — respects the backgroundless toggle.
// ───────────────────────────────────────────────────────────────────────────
class _LogoBadge extends StatelessWidget {
  final String logoUrl;
  final bool backgroundless;
  final Color primary;
  final double size;
  const _LogoBadge({
    required this.logoUrl,
    required this.backgroundless,
    required this.primary,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = logoUrl.isNotEmpty
        ? Image.network(logoUrl,
            height: size * 0.72,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.factory, color: primary, size: size * 0.6))
        : Image.asset('media/sia_logo.png',
            height: size * 0.78,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.factory, color: primary, size: size * 0.6));
    if (backgroundless) {
      return SizedBox(width: size, height: size, child: Center(child: glyph));
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
      ),
      child: Center(child: glyph),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Preview frame with a soft hover-lift.
// ───────────────────────────────────────────────────────────────────────────
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
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: Sa.shadow,
                      blurRadius: _hover ? 26 : 14,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── mock palette helpers ─────────────────────────────────────────────────────
class _Mock {
  final Color bg, surface, text, sub, line;
  const _Mock(this.bg, this.surface, this.text, this.sub, this.line);
  factory _Mock.light() => const _Mock(Color(0xFFF4F7FB), Colors.white,
      Color(0xFF1E293B), Color(0xFF94A3B8), Color(0xFFE7ECF3));
  factory _Mock.dark() => const _Mock(Color(0xFF0E1726), Color(0xFF18233A),
      Color(0xFFE7ECF5), Color(0xFF7E8CA6), Color(0xFF253249));
}

// ── Supervisor preview (phone) ───────────────────────────────────────────────
class _SupervisorPreview extends StatelessWidget {
  final Color primary, accent;
  final bool dark, backgroundless;
  final String logoUrl;
  const _SupervisorPreview({
    required this.primary,
    required this.accent,
    required this.dark,
    required this.logoUrl,
    required this.backgroundless,
  });

  @override
  Widget build(BuildContext context) {
    final m = dark ? _Mock.dark() : _Mock.light();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 232,
      height: 300,
      color: m.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [primary, accent]),
            ),
            child: Row(children: [
              _LogoBadge(
                  logoUrl: logoUrl,
                  backgroundless: backgroundless,
                  primary: primary,
                  size: 30),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      width: 78,
                      height: 8,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 5),
                  Container(
                      width: 50,
                      height: 6,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(3))),
                ],
              ),
              const Spacer(),
              const Icon(Icons.notifications_none, color: Colors.white, size: 17),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _alertCard(m, const Color(0xFFDC2626), 'CRITICAL'),
                const SizedBox(height: 9),
                _alertCard(m, accent, 'IN PROGRESS'),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Container(
              width: double.infinity,
              height: 36,
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.45), blurRadius: 12)],
              ),
              child: Center(
                child: Text('CLAIM ALERT',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertCard(_Mock m, Color tag, String label) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: m.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border(left: BorderSide(color: tag, width: 3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Row(children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 96, height: 7, color: m.text.withValues(alpha: 0.8)),
            const SizedBox(height: 6),
            Container(width: 60, height: 6, color: m.sub),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
              color: tag.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(5)),
          child: Text(label,
              style: TextStyle(
                  color: tag, fontSize: 7.5, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

// ── PM preview (wide dashboard) ──────────────────────────────────────────────
class _PmPreview extends StatelessWidget {
  final Color primary, accent;
  final String logoUrl;
  final bool backgroundless;
  const _PmPreview({
    required this.primary,
    required this.accent,
    required this.logoUrl,
    required this.backgroundless,
  });

  @override
  Widget build(BuildContext context) {
    final m = _Mock.light();
    return Container(
      width: 320,
      height: 300,
      color: m.bg,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: m.surface,
            child: Row(children: [
              _LogoBadge(
                  logoUrl: logoUrl,
                  backgroundless: backgroundless,
                  primary: primary,
                  size: 26),
              const SizedBox(width: 9),
              Container(width: 90, height: 8, color: m.text.withValues(alpha: 0.85)),
              const Spacer(),
              for (final c in [primary, accent, m.sub])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: CircleAvatar(radius: 7, backgroundColor: c),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _stat(m, primary, '128', 'ACTIVE'),
                const SizedBox(width: 9),
                _stat(m, accent, '34', 'CRITICAL'),
                const SizedBox(width: 9),
                _stat(m, const Color(0xFF16A34A), '92%', 'SLA'),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: m.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.insights, size: 13, color: primary),
                    const SizedBox(width: 6),
                    Container(width: 110, height: 7, color: m.text.withValues(alpha: 0.7)),
                  ]),
                  const SizedBox(height: 12),
                  Expanded(child: _bars(primary, accent, m)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(_Mock m, Color c, String n, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: m.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border(top: BorderSide(color: c, width: 2.5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n,
                style: TextStyle(
                    color: c, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    color: m.sub, fontSize: 7.5, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _bars(Color primary, Color accent, _Mock m) {
    const heights = [0.45, 0.7, 0.4, 0.85, 0.6, 0.95, 0.55, 0.75];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < heights.length; i++) ...[
          Expanded(
            child: FractionallySizedBox(
              heightFactor: heights[i],
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [primary, accent]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          if (i < heights.length - 1) const SizedBox(width: 5),
        ]
      ],
    );
  }
}

// ── SuperAdmin preview (command center) ──────────────────────────────────────
class _SuperAdminPreview extends StatelessWidget {
  final Color primary, accent;
  const _SuperAdminPreview({required this.primary, required this.accent});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF040A18);
    const panel = Color(0xFF0B1530);
    return Container(
      width: 320,
      height: 300,
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1B2A4A))),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [primary, accent]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 13),
              ),
              const SizedBox(width: 9),
              Text('COMMAND CENTER',
                  style: TextStyle(
                      color: const Color(0xFFE2E8F0),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
              const Spacer(),
              _dot(accent),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _glass(panel, primary, 'AGENTS', '6', Icons.hub_outlined),
              const SizedBox(width: 9),
              _glass(panel, accent, 'UPTIME', '99.9', Icons.bolt_outlined),
            ]),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: panel.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1B2A4A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    Row(children: [
                      Container(width: 5, height: 5, decoration: BoxDecoration(
                          color: i == 0 ? accent : primary, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Container(
                          width: 150.0 - i * 24,
                          height: 6,
                          color: const Color(0xFF2C4370)),
                      const Spacer(),
                      Container(width: 22, height: 6, color: primary.withValues(alpha: 0.6)),
                    ]),
                    if (i < 2) const SizedBox(height: 11),
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
          color: c, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: 8)]));

  Widget _glass(Color panel, Color c, String label, String n, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: panel.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(height: 8),
            Text(n,
                style: TextStyle(color: c, fontSize: 17, fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF94A3B8), fontSize: 7.5, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
