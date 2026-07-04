import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';

import '../../services/github_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../services/ai_model_config_service.dart';
import '../../services/predictive_scope.dart';
import 'guardian_github_view.dart';
import 'guardian_pipeline_view.dart';
import '../../l10n/app_strings.dart';
import 'superadmin_theme.dart';

part 'ai_agents_tab_shift.dart';
part 'ai_agents_tab_briefing_assist.dart';
part 'ai_agents_tab_security_predictive.dart';
part 'ai_agents_tab_guardian.dart';

/// SuperAdmin tab: the AI AGENT FLEET.
///
/// Every autonomous intelligence in the platform gets a face here: the Shift
/// Commander, the Briefing officer, the AI Assist co-pilot, the Security
/// Sentinel, the Predictive Core and the (under construction) Guardian. Each
/// agent can be toggled on/off platform-wide, exposes its full action log
/// with in-depth details, a live stats deck, and agent-specific controls —
/// the AI Assist prompt template is editable, the Security Sentinel's
/// defenses can be armed per-feature, and the Predictive Core shows its
/// learning curves, absorption and self-graded forecast accuracy.
///
/// Master switches and per-agent settings live under `ai_agents/{id}` in
/// RTDB; the Cloudflare AI worker reads the same node (60s cache) and gates
/// its cron + HTTP behavior accordingly.
class AiAgentsTab extends StatefulWidget {
  const AiAgentsTab({super.key});

  @override
  State<AiAgentsTab> createState() => _AiAgentsTabState();
}

/// Static identity of one fleet agent. Agents are fixed — declared in
/// [_kAgents] with a bundled PNG [logoAsset].
class _AgentSpec {
  final String id;
  final String name;
  final String role;
  final String codename;
  final IconData icon;
  final bool maintenance;

  /// Bundled brand logo for the agent (asset path), or null.
  final String? logoAsset;

  const _AgentSpec({
    required this.id,
    required this.name,
    required this.role,
    required this.codename,
    required this.icon,
    this.maintenance = false,
    this.logoAsset,
  });

  Color get accent => switch (id) {
    'shift' => Sa.cyan,
    'briefing' => Sa.blue,
    'assist' => Sa.green,
    'security' => Sa.red,
    'predictive' => Sa.violet,
    _ => Sa.amber,
  };
}

const List<_AgentSpec> _kAgents = [
  _AgentSpec(
    id: 'shift',
    name: 'SHIFT COMMANDER',
    codename: 'UNIT-01 · ORCHESTRA',
    role: 'Runs shifts: AI assignments, collaborations, handovers',
    icon: Icons.military_tech_outlined,
    logoAsset: 'media/shift_agent_logo.png',
  ),
  _AgentSpec(
    id: 'briefing',
    name: 'BRIEFING OFFICER',
    codename: 'UNIT-02 · HERALD',
    role: 'Writes the morning briefings every PM reads',
    icon: Icons.campaign_outlined,
    logoAsset: 'media/briefing_agent_logo.png',
  ),
  _AgentSpec(
    id: 'assist',
    name: 'AI ASSIST',
    codename: 'UNIT-03 · MENTOR',
    role: 'Suggests resolutions to supervisors from past fixes',
    icon: Icons.support_agent_outlined,
    logoAsset: 'media/assist_agent_logo.png',
  ),
  _AgentSpec(
    id: 'security',
    name: 'SECURITY SENTINEL',
    codename: 'UNIT-04 · AEGIS',
    role: 'Blocks injections, floods and anomalies at the edge',
    icon: Icons.gpp_good_outlined,
  ),
  _AgentSpec(
    id: 'predictive',
    name: 'PREDICTIVE CORE',
    codename: 'UNIT-05 · ORACLE',
    role: 'Forecasts machine failures and grades itself daily',
    icon: Icons.online_prediction_outlined,
    logoAsset: 'media/predective_agent_logo.png',
  ),
  _AgentSpec(
    id: 'guardian',
    name: 'GUARDIAN',
    codename: 'UNIT-06 · CLASSIFIED',
    role: 'Under maintenance — capabilities not yet disclosed',
    icon: Icons.shield_moon_outlined,
    maintenance: false,
    logoAsset: 'media/guardian_agent_logo.png',
  ),
];

/// The rounded gradient tile that fronts every agent — shows the brand logo
/// (asset for built-ins, uploaded bytes for custom agents) or falls back to a
/// themed icon. Reused on fleet cards and inside panel headers.
class _AgentAvatar extends StatelessWidget {
  final _AgentSpec spec;
  final double size;
  final double radius;

  const _AgentAvatar({required this.spec, this.size = 32, this.radius = 9});

  @override
  Widget build(BuildContext context) {
    final accent = spec.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.30),
            accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Center(
        child: _AgentGlyph(spec: spec, size: size, radius: radius),
      ),
    );
  }
}

/// Just the brand glyph (asset logo / themed icon) with no surrounding tile —
/// used inside [_AgentAvatar] and as the [SaSectionHeader] leading so panel
/// hero headers carry the agent's logo.
class _AgentGlyph extends StatelessWidget {
  final _AgentSpec spec;
  final double size;
  final double radius;
  const _AgentGlyph({required this.spec, this.size = 32, this.radius = 9});

  @override
  Widget build(BuildContext context) {
    final accent = spec.accent;
    if (spec.logoAsset != null) {
      return Padding(
        padding: EdgeInsets.all(size * 0.12),
        child: Image.asset(
          spec.logoAsset!,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) =>
              Icon(spec.icon, size: size * 0.52, color: accent),
        ),
      );
    }
    return Icon(spec.icon, size: size * 0.52, color: accent);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LLM PROVIDER BRANDS
// ═══════════════════════════════════════════════════════════════════════════

/// A selectable model provider with brand color, a hand-drawn logo mark and a
/// short credential hint. Logos are painted in [_ProviderMark] so no binary
/// brand assets need to ship with the app.
class _Provider {
  final String id;
  final String name;
  final Color color;
  final String tokenHint;
  final String defaultModel;

  const _Provider({
    required this.id,
    required this.name,
    required this.color,
    required this.tokenHint,
    required this.defaultModel,
  });
}

class _Providers {
  static const list = <_Provider>[
    _Provider(
      id: 'anthropic',
      name: 'Anthropic',
      color: Color(0xFFD97757),
      tokenHint: 'sk-ant-…',
      defaultModel: 'claude-opus-4-8',
    ),
    _Provider(
      id: 'openai',
      name: 'OpenAI',
      color: Color(0xFF10A37F),
      tokenHint: 'sk-…',
      defaultModel: 'gpt-4o',
    ),
    _Provider(
      id: 'gemini',
      name: 'Google Gemini',
      color: Color(0xFF4285F4),
      tokenHint: 'AIza…',
      defaultModel: 'gemini-2.0-flash',
    ),
    _Provider(
      id: 'deepseek',
      name: 'DeepSeek',
      color: Color(0xFF4D6BFE),
      tokenHint: 'sk-…',
      defaultModel: 'deepseek-chat',
    ),
    _Provider(
      id: 'mistral',
      name: 'Mistral AI',
      color: Color(0xFFFA520F),
      tokenHint: 'API key',
      defaultModel: 'mistral-large-latest',
    ),
    _Provider(
      id: 'xai',
      name: 'xAI Grok',
      color: Color(0xFF111827),
      tokenHint: 'xai-…',
      defaultModel: 'grok-2',
    ),
    _Provider(
      id: 'meta',
      name: 'Meta Llama',
      color: Color(0xFF0866FF),
      tokenHint: 'API key',
      defaultModel: 'llama-3.3-70b',
    ),
    _Provider(
      id: 'cohere',
      name: 'Cohere',
      color: Color(0xFF39594D),
      tokenHint: 'API key',
      defaultModel: 'command-r-plus',
    ),
    _Provider(
      id: 'perplexity',
      name: 'Perplexity',
      color: Color(0xFF20808D),
      tokenHint: 'pplx-…',
      defaultModel: 'sonar-pro',
    ),
    _Provider(
      id: 'azure',
      name: 'Azure OpenAI',
      color: Color(0xFF0078D4),
      tokenHint: 'API key',
      defaultModel: 'gpt-4o',
    ),
    _Provider(
      id: 'cloudflare',
      name: 'Cloudflare AI',
      color: Color(0xFFF6821F),
      tokenHint: 'API token',
      defaultModel: '@cf/meta/llama-3.1-8b',
    ),
    _Provider(
      id: 'qwen',
      name: 'Alibaba Qwen',
      color: Color(0xFF615CED),
      tokenHint: 'sk-…',
      defaultModel: 'qwen-max',
    ),
    _Provider(
      id: 'groq',
      name: 'Groq',
      color: Color(0xFFF55036),
      tokenHint: 'gsk_…',
      defaultModel: 'llama-3.3-70b-versatile',
    ),
    _Provider(
      id: 'moonshot',
      name: 'Moonshot Kimi',
      color: Color(0xFF1F1F3A),
      tokenHint: 'sk-…',
      defaultModel: 'moonshot-v1-128k',
    ),
    _Provider(
      id: 'together',
      name: 'Together AI',
      color: Color(0xFF0F6FFF),
      tokenHint: 'API key',
      defaultModel: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
    ),
    _Provider(
      id: 'fireworks',
      name: 'Fireworks AI',
      color: Color(0xFF6B2FB3),
      tokenHint: 'fw_…',
      defaultModel: 'accounts/fireworks/models/llama-v3p3-70b-instruct',
    ),
    _Provider(
      id: 'openrouter',
      name: 'OpenRouter',
      color: Color(0xFF6467F2),
      tokenHint: 'sk-or-…',
      defaultModel: 'openai/gpt-4o',
    ),
    _Provider(
      id: 'other',
      name: 'Other / Custom',
      color: Color(0xFF64748B),
      tokenHint: 'API key',
      defaultModel: '',
    ),
  ];

  static _Provider of(String? id) {
    return list.firstWhere(
      (p) => p.id == id,
      orElse: () => list.last,
    ); // 'other'
  }
}

/// Hand-drawn brand mark for a provider, sized to [size]. Recognizable
/// geometry per brand (OpenAI blossom, Gemini spark, Mistral bands, …) with a
/// tasteful monogram fallback.
class _ProviderMark extends StatelessWidget {
  final String id;
  final double size;
  final Color? color;
  const _ProviderMark({required this.id, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) {
    final p = _Providers.of(id);
    final c = color ?? p.color;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ProviderMarkPainter(id: id, color: c),
      ),
    );
  }
}

class _ProviderLogo extends StatelessWidget {
  final _Provider provider;
  final double size;
  final Color? color;

  const _ProviderLogo({required this.provider, this.size = 18, this.color});

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        (provider.color == const Color(0xFF111827) && !Sa.isDark
            ? const Color(0xFF334155)
            : provider.color);
    final officialIcon = _officialProviderIcon(provider.id);
    if (officialIcon != null) {
      return FaIcon(officialIcon, size: size, color: c);
    }
    return _ProviderMark(id: provider.id, size: size, color: c);
  }

  IconData? _officialProviderIcon(String id) {
    switch (id) {
      case 'openai':
        return FontAwesomeIcons.openai;
      case 'meta':
        return FontAwesomeIcons.meta;
      case 'azure':
        return FontAwesomeIcons.microsoft;
      case 'cloudflare':
        return FontAwesomeIcons.cloudflare;
    }
    return null;
  }
}

class _ProviderMarkPainter extends CustomPainter {
  final String id;
  final Color color;
  _ProviderMarkPainter({required this.id, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, r * 0.16)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    switch (id) {
      case 'openai':
        // Six-lobed blossom approximated by six rotated rounded petals.
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          final p = c + Offset(math.cos(a), math.sin(a)) * r * 0.46;
          canvas.drawCircle(
            p,
            r * 0.42,
            fill..color = color.withValues(alpha: 0.85),
          );
        }
        canvas.drawCircle(
          c,
          r * 0.30,
          Paint()
            ..color = color.withValues(alpha: 0.0001)
            ..blendMode = BlendMode.clear,
        );
        break;
      case 'gemini':
        // Four-point spark (Google Gemini star).
        final path = Path();
        for (var i = 0; i < 4; i++) {
          final a = i * math.pi / 2;
          final tip = c + Offset(math.cos(a), math.sin(a)) * r;
          final l =
              c +
              Offset(math.cos(a + math.pi / 4), math.sin(a + math.pi / 4)) *
                  r *
                  0.30;
          if (i == 0) {
            path.moveTo(tip.dx, tip.dy);
          } else {
            path.lineTo(tip.dx, tip.dy);
          }
          path.lineTo(l.dx, l.dy);
        }
        path.close();
        canvas.drawPath(path, fill);
        break;
      case 'mistral':
        // Stacked color bands echoing the pixel-M logo.
        final bands = [
          color,
          color.withValues(alpha: 0.78),
          color.withValues(alpha: 0.55),
        ];
        final h = size.height / 3;
        for (var i = 0; i < 3; i++) {
          canvas.drawRect(
            Rect.fromLTWH(
              size.width * 0.12,
              i * h + h * 0.12,
              size.width * 0.76,
              h * 0.76,
            ),
            Paint()..color = bands[i],
          );
        }
        break;
      case 'anthropic':
        // Radiating sunburst.
        for (var i = 0; i < 10; i++) {
          final a = i * math.pi / 5;
          canvas.drawLine(
            c,
            c + Offset(math.cos(a), math.sin(a)) * r * 0.92,
            stroke,
          );
        }
        canvas.drawCircle(c, r * 0.20, fill);
        break;
      case 'deepseek':
        // Orbit: ring + traveling node.
        canvas.drawCircle(c, r * 0.55, stroke);
        canvas.drawCircle(c, r * 0.18, fill);
        canvas.drawCircle(c + Offset(r * 0.78, -r * 0.2), r * 0.16, fill);
        break;
      case 'xai':
        // Sharp X.
        canvas.drawLine(
          c + Offset(-r * 0.6, -r * 0.6),
          c + Offset(r * 0.6, r * 0.6),
          stroke,
        );
        canvas.drawLine(
          c + Offset(r * 0.6, -r * 0.6),
          c + Offset(-r * 0.6, r * 0.6),
          stroke,
        );
        break;
      case 'cloudflare':
        // Cloud arc.
        canvas.drawCircle(c + Offset(-r * 0.25, r * 0.1), r * 0.4, fill);
        canvas.drawCircle(c + Offset(r * 0.3, r * 0.15), r * 0.5, fill);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              size.width * 0.18,
              size.height * 0.5,
              size.width * 0.7,
              size.height * 0.28,
            ),
            Radius.circular(r * 0.3),
          ),
          fill,
        );
        break;
      default:
        // Monogram fallback (Meta, Cohere, Perplexity, Azure, Other).
        final letter =
            (_Providers.of(id).name.isNotEmpty
                    ? _Providers.of(id).name[0]
                    : '?')
                .toUpperCase();
        canvas.drawCircle(
          c,
          r * 0.92,
          stroke..strokeWidth = math.max(1.2, r * 0.12),
        );
        final tp = TextPainter(
          text: TextSpan(
            text: letter,
            style: TextStyle(
              color: color,
              fontSize: r * 1.05,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ProviderMarkPainter old) =>
      old.id != id || old.color != color;
}

/// Lets the fleet rail be dragged horizontally with a mouse / trackpad / touch
/// — the default web/desktop behavior only scrolls a horizontal list with a
/// shift+wheel, which is why agents past the fold (Guardian) felt unreachable.
class _DragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class _AiAgentsTabState extends State<AiAgentsTab> {
  String _selectedId = 'shift';
  final Map<String, bool> _enabled = {};
  final List<StreamSubscription<DatabaseEvent>> _subs = [];
  Map<String, dynamic>? _health;
  final ScrollController _railCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    for (final agent in _kAgents) {
      _subs.add(
        FirebaseDatabase.instance
            .ref('ai_agents/${agent.id}/enabled')
            .onValue
            .listen((event) {
              if (mounted) {
                setState(
                  () => _enabled[agent.id] = event.snapshot.value != false,
                );
              }
            }, onError: (_) {}),
      );
    }
    _subs.add(
      FirebaseDatabase.instance.ref('workers/health/lastRun').onValue.listen((
        event,
      ) {
        final v = event.snapshot.value;
        if (mounted && v is Map) {
          setState(() => _health = Map<String, dynamic>.from(v));
        }
      }, onError: (_) {}),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _railCtrl.dispose();
    super.dispose();
  }

  bool _isEnabled(String id) => _enabled[id] ?? true;

  Future<void> _setEnabled(_AgentSpec agent, bool value) async {
    setState(() => _enabled[agent.id] = value);
    final path = 'ai_agents/${agent.id}';
    try {
      await FirebaseDatabase.instance.ref(path).update({
        'enabled': value,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              value
                  ? context.tr('{name} is back online.', {'name': agent.name})
                  : context.tr(
                      '{name} taken offline — the worker stands down within 60s.',
                      {'name': agent.name},
                    ),
              style: Sa.body(size: 12.5),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enabled[agent.id] = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              context.tr('Could not update {name}: {error}', {
                'name': agent.name,
                'error': '$e',
              }),
              style: Sa.body(size: 12.5, color: Sa.red),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final agents = _kAgents;
    final agent = agents.firstWhere(
      (a) => a.id == _selectedId,
      orElse: () => agents.first,
    );
    final online = agents
        .where((a) => !a.maintenance && _isEnabled(a.id))
        .length;
    final cronAt = DateTime.tryParse((_health?['timestamp'] ?? '').toString());
    final cronFresh =
        cronAt != null &&
        DateTime.now().toUtc().difference(cronAt.toUtc()).inMinutes <= 3;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: _FleetStrip(
            online: online,
            total: agents.length,
            cronFresh: cronFresh,
            health: _health,
            enabledOf: _isEnabled,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: SizedBox(
            height: 144,
            child: ScrollConfiguration(
              behavior: _DragScrollBehavior(),
              child: Scrollbar(
                controller: _railCtrl,
                thumbVisibility: true,
                child: ListView.separated(
                  controller: _railCtrl,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: agents.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final a = agents[i];
                    return _AgentCard(
                      spec: a,
                      selected: a.id == _selectedId,
                      enabled: _isEnabled(a.id),
                      onTap: () => setState(() => _selectedId = a.id),
                      onToggle: a.maintenance ? null : (v) => _setEnabled(a, v),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            child: KeyedSubtree(
              key: ValueKey(agent.id),
              child: switch (agent.id) {
                'shift' => _ShiftAgentPanel(
                  spec: agent,
                  enabled: _isEnabled('shift'),
                  health: _health,
                ),
                'briefing' => _BriefingAgentPanel(
                  spec: agent,
                  enabled: _isEnabled('briefing'),
                ),
                'assist' => _AssistAgentPanel(
                  spec: agent,
                  enabled: _isEnabled('assist'),
                ),
                'security' => _SecurityAgentPanel(
                  spec: agent,
                  enabled: _isEnabled('security'),
                  health: _health,
                ),
                'predictive' => _PredictiveAgentPanel(
                  spec: agent,
                  enabled: _isEnabled('predictive'),
                ),
                'guardian' => _GuardianAgentPanel(spec: agent),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLEET STRIP + AGENT CARDS
// ═══════════════════════════════════════════════════════════════════════════

class _FleetStrip extends StatelessWidget {
  final int online;
  final int total;
  final bool cronFresh;
  final Map<String, dynamic>? health;
  final bool Function(String) enabledOf;

  const _FleetStrip({
    required this.online,
    required this.total,
    required this.cronFresh,
    required this.health,
    required this.enabledOf,
  });

  @override
  Widget build(BuildContext context) {
    final assignments = (health?['assignmentsMade'] as num?)?.toInt() ?? 0;
    final secActions = (health?['securityActions'] as num?)?.toInt() ?? 0;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: _FleetCorePulse(color: cronFresh ? Sa.cyan : Sa.amber),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('AI AGENT FLEET'), style: Sa.display(size: 15)),
                Text(
                  context.tr(
                    'Six autonomous units · toggles propagate to the edge worker within 60 seconds',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.mono(size: 9, color: Sa.muted),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              GlowChip(
                label: context.tr('{online}/{total} UNITS ONLINE', {
                  'online': '$online',
                  'total': '$total',
                }),
                color: online == total ? Sa.green : Sa.amber,
                pulse: true,
              ),
              GlowChip(
                label: cronFresh
                    ? context.tr('EDGE LINK LIVE')
                    : context.tr('EDGE LINK STALE'),
                color: cronFresh ? Sa.cyan : Sa.red,
                icon: Icons.cell_tower,
              ),
              GlowChip(
                label: context.tr('{count} ASSIGNED · LAST CRON', {
                  'count': '$assignments',
                }),
                color: Sa.violet,
                icon: Icons.auto_awesome,
              ),
              if (secActions > 0)
                GlowChip(
                  label: context.tr('{count} THREATS BLOCKED', {
                    'count': '$secActions',
                  }),
                  color: Sa.red,
                  icon: Icons.gpp_maybe_outlined,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pulsing reactor core for the fleet header.
class _FleetCorePulse extends StatefulWidget {
  final Color color;
  const _FleetCorePulse({required this.color});

  @override
  State<_FleetCorePulse> createState() => _FleetCorePulseState();
}

class _FleetCorePulseState extends State<_FleetCorePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _CorePainter(color: widget.color, tick: _c),
      ),
    );
  }
}

class _CorePainter extends CustomPainter {
  final Color color;
  final Animation<double> tick;
  _CorePainter({required this.color, required this.tick})
    : super(repaint: tick);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final t = tick.value;
    final r = size.shortestSide / 2;
    // Two counter-rotating orbital arcs.
    for (var k = 0; k < 2; k++) {
      final sweep = math.pi * (0.9 + 0.4 * k);
      final start = (k == 0 ? 1 : -1) * t * math.pi * 2 + k * 2.1;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 2 - k * 4),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.55 - k * 0.2),
      );
    }
    final glow = 0.5 + 0.5 * math.sin(t * math.pi * 4);
    canvas.drawCircle(
      c,
      r * 0.42,
      Paint()..color = color.withValues(alpha: 0.12 + 0.1 * glow),
    );
    canvas.drawCircle(c, r * 0.22, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CorePainter old) => old.color != color;
}

class _AgentCard extends StatefulWidget {
  final _AgentSpec spec;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<bool>? onToggle;

  const _AgentCard({
    required this.spec,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onToggle,
  });

  @override
  State<_AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<_AgentCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final accent = spec.accent;
    final live = widget.enabled && !spec.maintenance;
    final borderColor = widget.selected
        ? accent
        : _hover
        ? accent.withValues(alpha: 0.55)
        : Sa.border;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 234,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.selected
                ? accent.withValues(alpha: Sa.isDark ? 0.10 : 0.07)
                : Sa.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
            boxShadow: [
              if (widget.selected)
                BoxShadow(
                  color: accent.withValues(alpha: 0.22),
                  blurRadius: 18,
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AgentAvatar(spec: spec, size: 32, radius: 9),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(spec.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Sa.heading(size: 11.5),
                        ),
                        Text(
                          spec.codename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Sa.mono(size: 7.5, color: Sa.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  context.tr(spec.role),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.body(size: 10.5, color: Sa.textDim),
                ),
              ),
              Row(
                children: [
                  if (spec.maintenance)
                    GlowChip(label: context.tr('MAINTENANCE'), color: Sa.amber)
                  else
                    GlowChip(
                      label: live
                          ? context.tr('ONLINE')
                          : context.tr('OFFLINE'),
                      color: live ? Sa.green : Sa.muted,
                      pulse: live,
                    ),
                  const Spacer(),
                  if (widget.onToggle != null)
                    _NeonToggle(
                      value: widget.enabled,
                      accent: accent,
                      onChanged: widget.onToggle!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact glowing toggle used across the fleet.
class _NeonToggle extends StatelessWidget {
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const _NeonToggle({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 21,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: value
              ? accent.withValues(alpha: 0.30)
              : Sa.muted.withValues(alpha: 0.18),
          border: Border.all(
            color: value ? accent : Sa.muted.withValues(alpha: 0.6),
          ),
          boxShadow: [
            if (value)
              BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 9),
          ],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? accent : Sa.muted,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED PANEL SCAFFOLDING
// ═══════════════════════════════════════════════════════════════════════════

class _AgentScroll extends StatelessWidget {
  final List<Widget> children;
  const _AgentScroll({required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final _AgentSpec spec;
  const _OfflineBanner({required this.spec});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Sa.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.red.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.power_off_outlined, size: 16, color: Sa.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(
                  '{name} is OFFLINE. The edge worker skips its duties until you re-enable it; history below stays readable.',
                  {'name': context.tr(spec.name)}),
              style: Sa.body(size: 12, color: Sa.red),
            ),
          ),
        ],
      ),
    );
  }
}

String _agoIso(BuildContext context, Object? iso) {
  final t = DateTime.tryParse((iso ?? '').toString());
  if (t == null) return '—';
  final d = DateTime.now().toUtc().difference(t.toUtc());
  if (d.inSeconds < 60) {
    return context.tr('{n}s ago', {'n': '${d.inSeconds}'});
  }
  if (d.inMinutes < 60) {
    return context.tr('{n}m ago', {'n': '${d.inMinutes}'});
  }
  if (d.inHours < 24) {
    return context.tr('{n}h ago', {'n': '${d.inHours}'});
  }
  return context.tr('{n}d ago', {'n': '${d.inDays}'});
}

List<Map<String, dynamic>> _mapToSortedList(Object? value, String sortKey) {
  final list = <Map<String, dynamic>>[];
  if (value is Map) {
    value.forEach((k, v) {
      if (v is Map) {
        final m = Map<String, dynamic>.from(v);
        m['id'] = k.toString();
        list.add(m);
      }
    });
    list.sort(
      (a, b) => (b[sortKey] ?? '').toString().compareTo(
        (a[sortKey] ?? '').toString(),
      ),
    );
  }
  return list;
}

/// One activity row with an in-depth details dialog.
class _LogTile extends StatelessWidget {
  final String kind;
  final Color color;
  final String title;
  final String? at;
  final Map<String, dynamic> details;

  const _LogTile({
    required this.kind,
    required this.color,
    required this.title,
    required this.at,
    required this.details,
  });

  void _openDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Sa.panelSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GlowChip(label: kind.toUpperCase(), color: color),
                    const Spacer(),
                    Text(
                      _agoIso(ctx, at),
                      style: Sa.mono(size: 10, color: Sa.muted),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, size: 16, color: Sa.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(title, style: Sa.heading(size: 14)),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Sa.termBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Sa.termBorder),
                      ),
                      child: SelectableText(
                        details.entries
                            .where(
                              (e) =>
                                  e.key != 'id' &&
                                  (e.value ?? '').toString().isNotEmpty,
                            )
                            .map((e) => '${e.key.padRight(16)} ${e.value}')
                            .join('\n'),
                        style: Sa.mono(size: 10.5, color: Sa.termDim),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: InkWell(
        onTap: () => _openDetails(context),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 148,
                child: Text(
                  kind.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.mono(
                    size: 9,
                    color: color,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.body(size: 11.5, color: Sa.textDim),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _agoIso(context, at),
                style: Sa.mono(size: 9.5, color: Sa.muted),
              ),
              const SizedBox(width: 6),
              Icon(Icons.open_in_full, size: 11, color: Sa.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toggleable defense/setting row that writes straight to RTDB.
class _SettingTile extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value ? accent.withValues(alpha: 0.35) : Sa.border,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: value ? accent : Sa.muted),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Sa.heading(size: 12.5)),
                Text(
                  description,
                  style: Sa.body(size: 10.5, color: Sa.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _NeonToggle(value: value, accent: accent, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Horizontal labelled bar (used for per-kind activity breakdowns).
class _KindBar extends StatelessWidget {
  final String label;
  final int count;
  final int max;
  final Color color;

  const _KindBar({
    required this.label,
    required this.count,
    required this.max,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final frac = max <= 0 ? 0.0 : (count / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Sa.mono(size: 9.5, color: Sa.textDim),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(color: Sa.border.withValues(alpha: 0.5)),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: frac),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, w, __) => FractionallySizedBox(
                        widthFactor: w,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [color, color.withValues(alpha: 0.55)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: Sa.mono(size: 10.5, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-01 · SHIFT COMMANDER
// ═══════════════════════════════════════════════════════════════════════════
