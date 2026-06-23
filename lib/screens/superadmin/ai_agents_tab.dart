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

/// Static identity of one fleet agent.
///
/// Built-in agents are declared in [_kAgents] with a bundled PNG [logoAsset].
/// Operator-created agents are reconstructed from `ai_agents/registry/{id}` via
/// [_AgentSpec.custom] — they carry an uploaded base64 [logoData] (or a chosen
/// [iconCode] + [accentHex]) and an attached LLM provider + credential.
class _AgentSpec {
  final String id;
  final String name;
  final String role;
  final String codename;
  final IconData icon;
  final bool maintenance;

  /// Bundled brand logo for a built-in agent (asset path), or null.
  final String? logoAsset;

  /// True for operator-created agents (deletable, generic detail panel).
  final bool custom;

  /// Custom-agent payload (all null for built-ins).
  final String? logoData; // base64 PNG of the uploaded logo
  final String? accentHex; // chosen accent for custom agents
  final String? description;
  final String? tasks;
  final String? tasksFile;
  final String? skills;
  final String? skillsFile;
  final String? provider; // provider id (openai/anthropic/…)
  final String? model;
  final String? apiToken;
  final String? createdAt;

  const _AgentSpec({
    required this.id,
    required this.name,
    required this.role,
    required this.codename,
    required this.icon,
    this.maintenance = false,
    this.logoAsset,
    this.custom = false,
    this.logoData,
    this.accentHex,
    this.description,
    this.tasks,
    this.tasksFile,
    this.skills,
    this.skillsFile,
    this.provider,
    this.model,
    this.apiToken,
    this.createdAt,
  });

  /// Rebuilds a custom agent spec from its registry record. [apiToken] is
  /// supplied separately from `ai_agent_secrets/{id}` — the registry record
  /// itself never holds the credential.
  factory _AgentSpec.fromRegistry(
    String id,
    Map<String, dynamic> m, {
    String? apiToken,
  }) {
    return _AgentSpec(
      id: id,
      name: (m['name'] ?? 'AGENT').toString(),
      codename: (m['codename'] ?? 'CUSTOM UNIT').toString(),
      role: (m['role'] ?? m['description'] ?? 'Operator-deployed agent')
          .toString(),
      icon:
          _kAgentIcons[(m['iconKey'] ?? '').toString()] ??
          Icons.smart_toy_outlined,
      custom: true,
      logoData: (m['logoData'] ?? '').toString().isEmpty
          ? null
          : m['logoData'].toString(),
      accentHex: (m['accentHex'] ?? '').toString().isEmpty
          ? null
          : m['accentHex'].toString(),
      description: (m['description'] ?? '').toString(),
      tasks: (m['tasks'] ?? '').toString(),
      tasksFile: (m['tasksFile'] ?? '').toString().isEmpty
          ? null
          : m['tasksFile'].toString(),
      skills: (m['skills'] ?? '').toString(),
      skillsFile: (m['skillsFile'] ?? '').toString().isEmpty
          ? null
          : m['skillsFile'].toString(),
      provider: (m['provider'] ?? '').toString(),
      model: (m['model'] ?? '').toString(),
      apiToken: apiToken ?? '',
      createdAt: (m['createdAt'] ?? '').toString(),
    );
  }

  Color get accent {
    if (custom) {
      final hex = accentHex;
      if (hex != null && hex.isNotEmpty) {
        final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
        if (v != null) return Color(0xFF000000 | v);
      }
      return _Providers.of(provider).color;
    }
    return switch (id) {
      'shift' => Sa.cyan,
      'briefing' => Sa.blue,
      'assist' => Sa.green,
      'security' => Sa.red,
      'predictive' => Sa.violet,
      _ => Sa.amber,
    };
  }

  /// Decoded logo bytes for a custom agent (or null).
  Uint8List? get logoBytes {
    final d = logoData;
    if (d == null || d.isEmpty) return null;
    try {
      return base64Decode(d.contains(',') ? d.split(',').last : d);
    } catch (_) {
      return null;
    }
  }
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

/// Just the brand glyph (asset logo / uploaded bytes / themed icon) with no
/// surrounding tile — used inside [_AgentAvatar] and as the [SaSectionHeader]
/// leading so panel hero headers carry the agent's logo.
class _AgentGlyph extends StatelessWidget {
  final _AgentSpec spec;
  final double size;
  final double radius;
  const _AgentGlyph({required this.spec, this.size = 32, this.radius = 9});

  @override
  Widget build(BuildContext context) {
    final accent = spec.accent;
    final bytes = spec.logoBytes;
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
    if (bytes != null) {
      return Padding(
        padding: EdgeInsets.all(size * 0.1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius * 0.6),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                Icon(spec.icon, size: size * 0.52, color: accent),
          ),
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

/// Square brand tile (logo mark + name) used in the provider picker grid and
/// the credential card.
class _ProviderTile extends StatelessWidget {
  final _Provider provider;
  final bool selected;
  final VoidCallback? onTap;
  const _ProviderTile({
    required this.provider,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = provider.color == const Color(0xFF111827) && !Sa.isDark
        ? const Color(0xFF334155)
        : provider.color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 116,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? c.withValues(alpha: Sa.isDark ? 0.16 : 0.10)
              : Sa.bgRaised.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? c : Sa.border,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: 14),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: _ProviderLogo(provider: provider, size: 22, color: c),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Sa.mono(
                size: 9.5,
                color: selected ? Sa.text : Sa.textDim,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  List<_AgentSpec> _custom = const [];
  Map<String, Map<String, dynamic>> _registryRaw = {};
  Map<String, String> _secrets = {};
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
    // Operator-created agents live in a lightweight registry so discovery never
    // streams the heavy worker logs/stats under the built-in agent nodes. The
    // API token never lives in this record — it is stored separately under
    // `ai_agent_secrets/{id}`, which only superadmin can read.
    _subs.add(
      FirebaseDatabase.instance.ref('ai_agents/registry').onValue.listen((
        event,
      ) {
        final v = event.snapshot.value;
        final raw = <String, Map<String, dynamic>>{};
        if (v is Map) {
          v.forEach((k, val) {
            if (val is Map) raw[k.toString()] = Map<String, dynamic>.from(val);
          });
        }
        _registryRaw = raw;
        _rebuildCustom();
      }, onError: (_) {}),
    );
    _subs.add(
      FirebaseDatabase.instance.ref('ai_agent_secrets').onValue.listen((event) {
        final v = event.snapshot.value;
        final secrets = <String, String>{};
        if (v is Map) {
          v.forEach((k, val) {
            if (val is Map && val['apiToken'] != null) {
              secrets[k.toString()] = val['apiToken'].toString();
            }
          });
        }
        _secrets = secrets;
        _rebuildCustom();
      }, onError: (_) {}),
    );
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

  /// Recomputes [_custom] from the latest registry + secrets snapshots.
  void _rebuildCustom() {
    final list = <_AgentSpec>[];
    _registryRaw.forEach((id, val) {
      final spec = _AgentSpec.fromRegistry(id, val, apiToken: _secrets[id]);
      list.add(spec);
      _enabled[spec.id] = val['enabled'] != false;
    });
    list.sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
    if (mounted) setState(() => _custom = list);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _railCtrl.dispose();
    super.dispose();
  }

  List<_AgentSpec> get _agents => [..._kAgents, ..._custom];

  bool _isEnabled(String id) => _enabled[id] ?? true;

  Future<void> _setEnabled(_AgentSpec agent, bool value) async {
    setState(() => _enabled[agent.id] = value);
    final path = agent.custom
        ? 'ai_agents/registry/${agent.id}'
        : 'ai_agents/${agent.id}';
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

  Future<void> _openEditor({_AgentSpec? editing}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => _AgentEditorDialog(editing: editing),
    );
    if (result == null) return;
    final id =
        editing?.id ??
        'custom_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final apiToken = (result['apiToken'] ?? '').toString().trim();
    final record = <String, dynamic>{
      ...result,
      'custom': true,
      'enabled': editing == null ? true : _isEnabled(editing.id),
      'createdAt':
          editing?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    // The API token is a credential — it never lands in the registry record,
    // which is readable by any authenticated user. It lives in
    // `ai_agent_secrets/{id}`, which only superadmin can read or write.
    record.remove('apiToken');
    try {
      final secretRef = FirebaseDatabase.instance.ref('ai_agent_secrets/$id');
      await Future.wait([
        FirebaseDatabase.instance.ref('ai_agents/registry/$id').set(record),
        apiToken.isEmpty
            ? secretRef.remove()
            : secretRef.set({
                'apiToken': apiToken,
                'updatedAt': DateTime.now().toUtc().toIso8601String(),
              }),
      ]);
      if (mounted) {
        setState(() => _selectedId = id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              editing == null
                  ? context.tr('{name} deployed to the fleet.', {
                      'name': '${record['name']}',
                    })
                  : context.tr('{name} updated.', {
                      'name': '${record['name']}',
                    }),
              style: Sa.body(size: 12.5),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              context.tr('Could not save agent: {error}', {'error': '$e'}),
              style: Sa.body(size: 12.5, color: Sa.red),
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteAgent(_AgentSpec agent) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => _DeleteAgentDialog(agent: agent),
    );
    if (confirmed != true) return;
    try {
      await Future.wait([
        FirebaseDatabase.instance
            .ref('ai_agents/registry/${agent.id}')
            .remove(),
        FirebaseDatabase.instance.ref('ai_agent_secrets/${agent.id}').remove(),
      ]);
      if (mounted) {
        setState(() {
          if (_selectedId == agent.id) _selectedId = 'shift';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              context.tr('{name} decommissioned and wiped.', {
                'name': agent.name,
              }),
              style: Sa.body(size: 12.5, color: Sa.red),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              context.tr('Delete failed: {error}', {'error': '$e'}),
              style: Sa.body(size: 12.5, color: Sa.red),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final agents = _agents;
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
                  itemCount: agents.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    if (i == agents.length) {
                      return _AddAgentCard(onTap: () => _openEditor());
                    }
                    final a = agents[i];
                    return _AgentCard(
                      spec: a,
                      selected: a.id == _selectedId,
                      enabled: _isEnabled(a.id),
                      onTap: () => setState(() => _selectedId = a.id),
                      onToggle: a.maintenance ? null : (v) => _setEnabled(a, v),
                      onDelete: a.custom ? () => _deleteAgent(a) : null,
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
                _ => _CustomAgentPanel(
                  spec: agent,
                  enabled: _isEnabled(agent.id),
                  onEdit: () => _openEditor(editing: agent),
                  onDelete: () => _deleteAgent(agent),
                ),
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
  final VoidCallback? onDelete;

  const _AgentCard({
    required this.spec,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onToggle,
    this.onDelete,
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
                  if (widget.onDelete != null && (_hover || widget.selected))
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.delete_outline,
                          size: 15,
                          color: Sa.red.withValues(alpha: 0.85),
                        ),
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
                  else if (spec.custom)
                    GlowChip(
                      label: live
                          ? context.tr('ONLINE')
                          : context.tr('OFFLINE'),
                      color: live ? accent : Sa.muted,
                      pulse: live,
                    )
                  else
                    GlowChip(
                      label: live
                          ? context.tr('ONLINE')
                          : context.tr('OFFLINE'),
                      color: live ? Sa.green : Sa.muted,
                      pulse: live,
                    ),
                  const SizedBox(width: 6),
                  if (spec.custom)
                    Icon(Icons.auto_awesome, size: 11, color: accent),
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

/// The trailing "+ DEPLOY AGENT" tile on the fleet rail.
class _AddAgentCard extends StatefulWidget {
  final VoidCallback onTap;
  const _AddAgentCard({required this.onTap});

  @override
  State<_AddAgentCard> createState() => _AddAgentCardState();
}

class _AddAgentCardState extends State<_AddAgentCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = Sa.cyan;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hover
                ? accent.withValues(alpha: Sa.isDark ? 0.10 : 0.06)
                : Sa.panel.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hover ? accent : Sa.border,
              style: BorderStyle.solid,
            ),
            boxShadow: [
              if (_hover)
                BoxShadow(color: accent.withValues(alpha: 0.2), blurRadius: 16),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.02),
                    ],
                  ),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Icon(Icons.add, color: accent, size: 22),
              ),
              const SizedBox(height: 10),
              Text(context.tr('DEPLOY AGENT'), style: Sa.heading(size: 11.5)),
              const SizedBox(height: 2),
              Text(
                context.tr('Add a unit to the fleet'),
                textAlign: TextAlign.center,
                style: Sa.mono(size: 7.5, color: Sa.muted),
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

class _ShiftAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  final Map<String, dynamic>? health;
  const _ShiftAgentPanel({
    required this.spec,
    required this.enabled,
    required this.health,
  });

  @override
  State<_ShiftAgentPanel> createState() => _ShiftAgentPanelState();
}

class _ShiftAgentPanelState extends State<_ShiftAgentPanel> {
  StreamSubscription<DatabaseEvent>? _sub;
  StreamSubscription<DatabaseEvent>? _fbSub;
  List<Map<String, dynamic>> _logs = const [];
  List<_BrainMemory> _memory = const [];
  String? _error;
  int _view = 0; // 0 = command deck, 1 = brain

  @override
  void initState() {
    super.initState();
    // Learned signals: per-supervisor reinforcement feedback — the commander's memory.
    _fbSub = FirebaseDatabase.instance
        .ref('ai_feedback/summary')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          final mem = <_BrainMemory>[];
          if (v is Map) {
            v.forEach((id, row) {
              if (row is Map) mem.add(_BrainMemory.fromMap(id.toString(), row));
            });
            mem.sort((a, b) => b.weight.compareTo(a.weight));
          }
          if (mounted) setState(() => _memory = mem);
        }, onError: (_) {});
    _sub = FirebaseDatabase.instance
        .ref('shift_ai_logs')
        .limitToLast(25)
        .onValue
        .listen(
          (event) {
            final v = event.snapshot.value;
            final flat = <Map<String, dynamic>>[];
            if (v is Map) {
              v.forEach((shiftId, logs) {
                if (logs is Map) {
                  logs.forEach((logId, entry) {
                    if (entry is Map) {
                      final m = Map<String, dynamic>.from(entry);
                      m['id'] = logId.toString();
                      m['shiftId'] = (m['shiftId'] ?? shiftId).toString();
                      flat.add(m);
                    }
                  });
                }
              });
              flat.sort(
                (a, b) => (b['at'] ?? '').toString().compareTo(
                  (a['at'] ?? '').toString(),
                ),
              );
            }
            if (mounted) setState(() => _logs = flat.take(120).toList());
          },
          onError: (e) {
            if (mounted) setState(() => _error = '$e');
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _fbSub?.cancel();
    super.dispose();
  }

  String _bucket(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('assign') || k.contains('transfer')) {
      return context.tr('Assignments');
    }
    if (k.contains('collab')) return context.tr('Collaborations');
    if (k.contains('handover')) return context.tr('Handovers');
    if (k.contains('presence')) return context.tr('Presence checks');
    if (k.contains('block') || k.contains('skip')) {
      return context.tr('Blocked / skipped');
    }
    return context.tr('Other');
  }

  Color _kindColor(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('block') || k.contains('skip')) return Sa.amber;
    if (k.contains('handover')) return Sa.violet;
    if (k.contains('collab')) return Sa.blue;
    if (k.contains('presence')) return Sa.muted;
    return Sa.cyan;
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final dayAgo = DateTime.now().toUtc().subtract(const Duration(hours: 24));
    final last24 = _logs.where((l) {
      final t = DateTime.tryParse((l['at'] ?? '').toString());
      return t != null && t.toUtc().isAfter(dayAgo);
    }).toList();
    final buckets = <String, int>{};
    for (final l in _logs) {
      final b = _bucket((l['kind'] ?? '').toString());
      buckets[b] = (buckets[b] ?? 0) + 1;
    }
    final maxBucket = buckets.values.isEmpty
        ? 0
        : buckets.values.reduce(math.max);
    final health = widget.health;

    return _AgentScroll(
      children: [
        if (!widget.enabled) _OfflineBanner(spec: spec),
        _SegTabs(
          tabs: [context.tr('COMMAND DECK'), context.tr('BRAIN')],
          icons: const [Icons.dashboard_customize_outlined, Icons.psychology],
          index: _view,
          accent: spec.accent,
          onChanged: (i) => setState(() => _view = i),
        ),
        if (_view == 1)
          _ShiftBrainView(
            logs: _logs,
            memory: _memory,
            accent: spec.accent,
            enabled: widget.enabled,
          ),
        if (_view == 0)
          GlassPanel(
            accent: spec.accent,
            glow: widget.enabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: spec.icon,
                  leading: _AgentGlyph(spec: spec, size: 36, radius: 10),
                  title: context.tr('COMMAND DECK'),
                  subtitle: context.tr(
                    'Every decision the AI commander takes across active shifts — assignments, collaborations, handovers, presence.',
                  ),
                  accent: spec.accent,
                  trailing: GlowChip(
                    label: context.tr('MODEL ENGINE'),
                    color: spec.accent,
                    icon: Icons.hub_outlined,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SaStatTile(
                      label: context.tr('Actions · 24h'),
                      value: '${last24.length}',
                      icon: Icons.bolt_outlined,
                      color: spec.accent,
                    ),
                    SaStatTile(
                      label: context.tr('Assignments · last cron'),
                      value:
                          '${(health?['assignmentsMade'] as num?)?.toInt() ?? 0}',
                      icon: Icons.assignment_turned_in_outlined,
                      color: Sa.green,
                    ),
                    SaStatTile(
                      label: context.tr('Collabs · last cron'),
                      value:
                          '${(health?['collaborationsApproved'] as num?)?.toInt() ?? 0}',
                      icon: Icons.handshake_outlined,
                      color: Sa.blue,
                    ),
                    SaStatTile(
                      label: context.tr('Handovers · last cron'),
                      value:
                          '${(health?['handoversGenerated'] as num?)?.toInt() ?? 0}',
                      icon: Icons.swap_horiz,
                      color: Sa.violet,
                    ),
                    SaStatTile(
                      label: context.tr('Last pulse'),
                      value: _agoIso(context, health?['timestamp']),
                      icon: Icons.monitor_heart_outlined,
                      color: Sa.amber,
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_view == 0)
          _ModelEnginePanel(
            agent: 'shift',
            accent: spec.accent,
            enabled: widget.enabled,
          ),
        if (_view == 0)
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: Icons.stacked_bar_chart,
                  title: context.tr('TASK BREAKDOWN'),
                  subtitle: context.tr(
                    'Distribution of the commander’s recent decisions.',
                  ),
                  accent: spec.accent,
                ),
                const SizedBox(height: 14),
                if (buckets.isEmpty)
                  Text(
                    context.tr('No shift AI activity recorded yet.'),
                    style: Sa.body(size: 12, color: Sa.textDim),
                  )
                else
                  ...buckets.entries.map(
                    (e) => _KindBar(
                      label: e.key,
                      count: e.value,
                      max: maxBucket,
                      color: spec.accent,
                    ),
                  ),
              ],
            ),
          ),
        if (_view == 0)
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: Icons.receipt_long_outlined,
                  title: context.tr('ACTION LOG'),
                  subtitle: context.tr(
                    'Tap any entry for the full unredacted reasoning, confidence and gate diagnostics.',
                  ),
                  accent: spec.accent,
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  SaEmptyState(
                    icon: Icons.lock_outline,
                    title: context.tr('Cannot read shift AI logs'),
                    message: _error!,
                    accent: Sa.red,
                  )
                else if (_logs.isEmpty)
                  SaEmptyState(
                    icon: Icons.nights_stay_outlined,
                    title: context.tr('No actions yet'),
                    message: context.tr(
                      'The commander logs here the moment a shift with AI Commander enabled goes live.',
                    ),
                    accent: spec.accent,
                  )
                else
                  ..._logs.take(40).map((l) {
                    final kind = (l['kind'] ?? 'action').toString();
                    final who = (l['supervisorName'] ?? '').toString();
                    final alert = (l['alertLabel'] ?? '').toString();
                    final reason = (l['reason'] ?? '').toString();
                    final title = [
                      if (alert.isNotEmpty) alert,
                      if (who.isNotEmpty) '→ $who',
                      if (alert.isEmpty && who.isEmpty) reason,
                    ].join(' ');
                    return _LogTile(
                      kind: kind,
                      color: _kindColor(kind),
                      title: title.isEmpty ? '—' : title,
                      at: (l['at'] ?? '').toString(),
                      details: l,
                    );
                  }),
              ],
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-02 · BRIEFING OFFICER
// ═══════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────
// SHIFT COMMANDER · BRAIN — "inside his head"
// A live visualisation of how the commander weighs supervisors, what it has
// learned (reinforcement memory), and the reasoning behind recent decisions.
// ─────────────────────────────────────────────────────────────────────────

/// Segmented sub-tab control (COMMAND DECK / BRAIN).
class _SegTabs extends StatelessWidget {
  final List<String> tabs;
  final List<IconData> icons;
  final int index;
  final Color accent;
  final ValueChanged<int> onChanged;
  const _SegTabs({
    required this.tabs,
    required this.icons,
    required this.index,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Sa.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == index
                        ? accent.withValues(alpha: Sa.isDark ? 0.18 : 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: i == index
                          ? accent.withValues(alpha: 0.6)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icons[i],
                        size: 16,
                        color: i == index ? accent : Sa.muted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tabs[i],
                        style: Sa.body(
                          size: 12.5,
                          color: i == index ? Sa.text : Sa.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One of the commander's seven scoring signals.
class _BrainFactor {
  final String label;
  final String desc;
  final double
  weight; // 0..1 — the *baseline* influence (also the RTDB default)
  final Color color;
  final List<String> keys; // keywords detected in decision reasons
  final String slug; // stable id used as the RTDB key and worker component key
  const _BrainFactor(
    this.label,
    this.desc,
    this.weight,
    this.color,
    this.keys,
    this.slug,
  );
}

// The [slug]s here MUST mirror `_SHIFT_ASSIGN_DEFAULTS` in cloudflare_ai_worker.js —
// they are the live RTDB keys the worker reads to retune assignment scoring.
const List<_BrainFactor> _kShiftFactors = [
  _BrainFactor(
    'Factory fit',
    'Same plant as the alert.',
    0.95,
    Color(0xFF378ADD),
    ['factory', 'plant', 'usine', 'same site'],
    'factory',
  ),
  _BrainFactor(
    'Type skill',
    'Proven experience with this alert type.',
    0.80,
    Color(0xFF7F77DD),
    ['type', 'experience', 'skill'],
    'type',
  ),
  _BrainFactor(
    'Speed',
    'How fast they resolve, historically.',
    0.62,
    Color(0xFF1D9E75),
    ['fast', 'speed', 'resolution time', 'quick'],
    'speed',
  ),
  _BrainFactor(
    'Station familiarity',
    'Knows this conveyor / workstation.',
    0.55,
    Color(0xFFBA7517),
    ['station', 'conveyor', 'convoyeur', 'workstation', 'poste'],
    'station',
  ),
  _BrainFactor(
    'Load balance',
    'Current workload — avoids overloading.',
    0.70,
    Color(0xFFD4537E),
    ['load', 'workload', 'busy', 'balance'],
    'load',
  ),
  _BrainFactor(
    'Critical record',
    'Track record on critical alerts.',
    0.50,
    Color(0xFFE24B4A),
    ['critical'],
    'critical',
  ),
  _BrainFactor(
    'Reinforcement',
    'Learned bias from accept / reject feedback.',
    0.65,
    Color(0xFF534AB7),
    ['feedback', 'reinforcement', 'adjust', 'learned'],
    'reinforcement',
  ),
];

/// How the commander weighs whether to approve a collaboration and who assists.
const List<_BrainFactor> _kShiftCollabFactors = [
  _BrainFactor(
    'Assistant consensus',
    'Every requested assistant accepted.',
    0.92,
    Color(0xFF378ADD),
    ['accept', 'consensus', 'agreed', 'assistant'],
    'consensus',
  ),
  _BrainFactor(
    'Requester need',
    'How badly the owner needs a hand.',
    0.78,
    Color(0xFF7F77DD),
    ['help', 'request', 'need', 'backup'],
    'need',
  ),
  _BrainFactor(
    'Workload room',
    'The assistant still has capacity to help.',
    0.70,
    Color(0xFFD4537E),
    ['load', 'workload', 'busy', 'capacity'],
    'room',
  ),
  _BrainFactor(
    'Skill overlap',
    'The assistant knows this alert type.',
    0.66,
    Color(0xFF1D9E75),
    ['type', 'skill', 'experience'],
    'skill',
  ),
  _BrainFactor(
    'Same factory',
    'Assistant is in the same plant.',
    0.58,
    Color(0xFFBA7517),
    ['factory', 'plant', 'usine', 'same site'],
    'factory',
  ),
  _BrainFactor(
    'Critical priority',
    'Critical alerts get backup first.',
    0.55,
    Color(0xFFE24B4A),
    ['critical'],
    'critical',
  ),
  _BrainFactor(
    'Commander authority',
    'Can skip PM approval under his command.',
    0.48,
    Color(0xFF534AB7),
    ['approval', 'commander', 'authority', 'pm'],
    'authority',
  ),
];

/// How the commander weighs pulling a supervisor across plants.
const List<_BrainFactor> _kShiftCrossFactors = [
  _BrainFactor(
    'Proximity',
    'Distance from home plant to the alert.',
    0.95,
    Color(0xFF378ADD),
    ['distance', 'km', 'proximity', 'haversine', 'near'],
    'proximity',
  ),
  _BrainFactor(
    'Distance cap',
    'Stays within the shift transfer limit.',
    0.85,
    Color(0xFFE24B4A),
    ['limit', 'cap', 'threshold', 'blocked', 'too far'],
    'cap',
  ),
  _BrainFactor(
    'Roster eligibility',
    'On the active shift roster.',
    0.74,
    Color(0xFF7F77DD),
    ['roster', 'shift', 'rostered'],
    'roster',
  ),
  _BrainFactor(
    'Coverage gap',
    'The target plant is short-handed.',
    0.68,
    Color(0xFFBA7517),
    ['coverage', 'gap', 'short', 'understaffed'],
    'coverage',
  ),
  _BrainFactor(
    'Type skill',
    'Proven on this alert type.',
    0.62,
    Color(0xFF1D9E75),
    ['type', 'skill', 'experience'],
    'skill',
  ),
  _BrainFactor(
    'Availability',
    'Free to take a transfer right now.',
    0.56,
    Color(0xFFD4537E),
    ['available', 'free', 'idle', 'load'],
    'availability',
  ),
  _BrainFactor(
    'Commander authority',
    'Cross-factory transfer is enabled.',
    0.50,
    Color(0xFF1AA8B0),
    ['cross', 'transfer', 'commander', 'authority'],
    'authority',
  ),
];

/// One selectable "mind" of the Shift Commander — a brain visual plus the
/// reasoning factors behind one class of decision (assignments, collaborations,
/// or cross-factory transfers).
class _ShiftBrainCategory {
  final String tab;
  final String slug; // RTDB key: ai_agents/shift/settings/weights/{slug}
  final IconData icon;
  final String brainSubtitle;
  final String description;
  final String coreBottom; // verb shown on the brain core ("DECIDES"…)
  final IconData outIcon;
  final String outTop;
  final String outBottom;
  final Color outColor;
  final String reasoningSubtitle;
  final List<_BrainFactor> factors;
  final bool liveScoring; // true ⇒ the worker reads these weights to score
  const _ShiftBrainCategory({
    required this.tab,
    required this.slug,
    required this.icon,
    required this.brainSubtitle,
    required this.description,
    required this.coreBottom,
    required this.outIcon,
    required this.outTop,
    required this.outBottom,
    required this.outColor,
    required this.reasoningSubtitle,
    required this.factors,
    this.liveScoring = false,
  });
}

// Not const: the per-category [outColor] reads `Sa.*` palette getters.
final List<_ShiftBrainCategory> _kShiftBrains = [
  _ShiftBrainCategory(
    tab: 'Assignments',
    slug: 'assignments',
    liveScoring: true,
    icon: Icons.assignment_ind_outlined,
    brainSubtitle:
        'How the AI weighs every supervisor before it assigns an alert.',
    description:
        'When an alert needs an owner, the commander checks who’s nearby, skilled and free — and remembers who handled similar alerts well — then assigns the best fit automatically.',
    coreBottom: 'DECIDES',
    outIcon: Icons.how_to_reg_outlined,
    outTop: 'Best',
    outBottom: 'supervisor',
    outColor: Sa.green,
    reasoningSubtitle:
        'The seven signals he scores, and how often each drove a recent assignment.',
    factors: _kShiftFactors,
  ),
  _ShiftBrainCategory(
    tab: 'Collaborations',
    slug: 'collaborations',
    icon: Icons.groups_2_outlined,
    brainSubtitle:
        'How the AI decides to approve a collaboration and who assists.',
    description:
        'When a supervisor asks for backup, the commander checks who already agreed, who has room to help and who knows the alert — then approves the collaboration without waiting on a manager.',
    coreBottom: 'APPROVES',
    outIcon: Icons.handshake_outlined,
    outTop: 'Approve',
    outBottom: 'collaboration',
    outColor: Sa.blue,
    reasoningSubtitle:
        'The signals behind every collaboration approval, and how often each fired.',
    factors: _kShiftCollabFactors,
  ),
  _ShiftBrainCategory(
    tab: 'Cross-factory',
    slug: 'crossFactory',
    icon: Icons.swap_horiz,
    brainSubtitle: 'How the AI weighs pulling a supervisor across plants.',
    description:
        'When one plant is short-handed, the commander measures how far each rostered supervisor is, respects the shift distance cap, and transfers only when the help is close and worth it.',
    coreBottom: 'TRANSFERS',
    outIcon: Icons.alt_route,
    outTop: 'Cross-plant',
    outBottom: 'transfer',
    outColor: Sa.amber,
    reasoningSubtitle:
        'The signals behind a cross-factory transfer, and how often each fired.',
    factors: _kShiftCrossFactors,
  ),
];

/// What the commander has learned about one supervisor (reinforcement memory).
class _BrainMemory {
  final String id;
  final String name;
  final int accepted;
  final int rejected;
  final int aborted;
  final int resolved;
  final double adjustment; // rank bias, + favours / - penalises

  const _BrainMemory({
    required this.id,
    required this.name,
    required this.accepted,
    required this.rejected,
    required this.aborted,
    required this.resolved,
    required this.adjustment,
  });

  double get weight =>
      (accepted + rejected + aborted + resolved).toDouble() + adjustment.abs();

  factory _BrainMemory.fromMap(String id, Map row) {
    int n(String k) => (row[k] is num) ? (row[k] as num).round() : 0;
    final rawName = (row['name'] ?? row['supervisorName'] ?? '').toString();
    final accepted = n('accepted');
    final rejected = n('rejected');
    final aborted = n('aborted');
    final resolved = n('resolved');
    double adj;
    if (row['rankAdjustment'] is num) {
      adj = (row['rankAdjustment'] as num).toDouble();
    } else {
      adj = (accepted * 4 + resolved * 2 - rejected * 5 - aborted * 3)
          .toDouble()
          .clamp(-20.0, 20.0);
    }
    final name = rawName.isNotEmpty
        ? rawName
        : (id.length > 6 ? '${id.substring(0, 6)}…' : id);
    return _BrainMemory(
      id: id,
      name: name,
      accepted: accepted,
      rejected: rejected,
      aborted: aborted,
      resolved: resolved,
      adjustment: adj,
    );
  }
}

/// The BRAIN sub-view: cognition core, memory, factors, learned signals, replay.
///
/// The cognition core and the reasoning factors are split into three selectable
/// "minds" — Assignments, Collaborations, Cross-factory transfer — each with its
/// own 3D brain visual and its own weighted reasoning factors. A single shared
/// sub-tab drives both panels so the brain and its factors always agree.
class _ShiftBrainView extends StatefulWidget {
  final List<Map<String, dynamic>> logs;
  final List<_BrainMemory> memory;
  final Color accent;
  final bool enabled;
  const _ShiftBrainView({
    required this.logs,
    required this.memory,
    required this.accent,
    required this.enabled,
  });

  @override
  State<_ShiftBrainView> createState() => _ShiftBrainViewState();
}

class _ShiftBrainViewState extends State<_ShiftBrainView> {
  int _brainTab = 0; // 0=Assignments, 1=Collaborations, 2=Cross-factory

  static const String _kWeightsPath = 'ai_agents/shift/settings/weights';

  // category slug → factor slug → live weight (0..1). Seeded from the factor
  // defaults, kept in sync with RTDB, and the single source the brain visual,
  // the factor bars and the warning checks all read.
  final Map<String, Map<String, double>> _weights = {};
  // Edits not yet flushed to RTDB (keyed 'categorySlug/factorSlug'); they win
  // over incoming stream values so a live drag never fights the echo.
  final Map<String, double> _dirty = {};
  StreamSubscription<DatabaseEvent>? _weightsSub;
  Timer? _writeDebounce;

  @override
  void initState() {
    super.initState();
    for (final c in _kShiftBrains) {
      _weights[c.slug] = {for (final f in c.factors) f.slug: f.weight};
    }
    _weightsSub = FirebaseDatabase.instance.ref(_kWeightsPath).onValue.listen((
      event,
    ) {
      final v = event.snapshot.value;
      if (v is! Map || !mounted) return;
      setState(() {
        v.forEach((catKey, factorMap) {
          if (factorMap is! Map) return;
          final cat = catKey.toString();
          final target = _weights[cat] ??= {};
          factorMap.forEach((slug, val) {
            if (_dirty.containsKey('$cat/$slug')) return; // keep pending edit
            if (val is num) {
              target[slug.toString()] = val.toDouble().clamp(0.0, 1.0);
            }
          });
        });
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _writeDebounce?.cancel();
    if (_dirty.isNotEmpty) _flushWeights(); // best-effort fire-and-forget
    _weightsSub?.cancel();
    super.dispose();
  }

  double _w(String catSlug, String slug) => _weights[catSlug]?[slug] ?? 0.0;

  void _setWeight(String catSlug, String slug, double value) {
    final v = value.clamp(0.0, 1.0);
    setState(() => (_weights[catSlug] ??= {})[slug] = v);
    _dirty['$catSlug/$slug'] = v;
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(milliseconds: 350), _flushWeights);
  }

  Future<void> _flushWeights() async {
    if (_dirty.isEmpty) return;
    final batch = Map<String, double>.from(_dirty);
    try {
      await FirebaseDatabase.instance.ref(_kWeightsPath).update(
        <String, Object?>{for (final e in batch.entries) e.key: e.value},
      );
      // Drop only the keys that weren't re-edited mid-flight.
      for (final e in batch.entries) {
        if (_dirty[e.key] == e.value) _dirty.remove(e.key);
      }
    } catch (_) {
      // Leave _dirty intact so the next edit/flush retries.
    }
  }

  void _resetCategory(_ShiftBrainCategory cat) {
    setState(() {
      final m = _weights[cat.slug] ??= {};
      for (final f in cat.factors) {
        m[f.slug] = f.weight;
      }
    });
    for (final f in cat.factors) {
      _dirty['${cat.slug}/${f.slug}'] = f.weight;
    }
    _writeDebounce?.cancel();
    _flushWeights();
  }

  /// Plain-language checks for weightings that would make the commander behave
  /// strangely. Empty ⇒ the current mix is sane.
  List<String> _warningsFor(_ShiftBrainCategory cat) {
    final out = <String>[];
    final vals = [for (final f in cat.factors) _w(cat.slug, f.slug)];
    final avg = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a + b) / vals.length;
    if (avg < 0.12) {
      out.add(
        context.tr(
          'Almost every factor is near zero — the commander has little left to weigh, so picks become close to random.',
        ),
      );
    }
    for (final f in cat.factors) {
      if (_w(cat.slug, f.slug) <= 0.02) {
        out.add(
          context.tr(
            '“{label}” is switched off — it no longer sways the decision.',
            {'label': context.tr(f.label)},
          ),
        );
      }
    }
    if (cat.factors.length >= 3) {
      final sorted = [...vals]..sort();
      if (sorted.last >= 0.9 && sorted[sorted.length - 2] <= 0.12) {
        out.add(
          context.tr(
            'One factor dominates everything else — the commander will mostly ignore the rest.',
          ),
        );
      }
    }
    double v(String s) => _w(cat.slug, s);
    switch (cat.slug) {
      case 'assignments':
        if (v('factory') < 0.15) {
          out.add(
            context.tr(
              'Factory fit is near zero — supervisors from any plant score the same, so alerts can land on a distant factory.',
            ),
          );
        }
        if (v('load') < 0.10) {
          out.add(
            context.tr(
              'Load balancing is off — a single supervisor can be piled with every new alert.',
            ),
          );
        }
        break;
      case 'crossFactory':
        if (v('cap') < 0.15) {
          out.add(
            context.tr(
              'Distance cap barely counts — the commander may pull supervisors from far-away plants.',
            ),
          );
        }
        if (v('proximity') < 0.15) {
          out.add(
            context.tr(
              'Proximity barely counts — distant supervisors compete as if they were next door.',
            ),
          );
        }
        break;
      case 'collaborations':
        if (v('consensus') < 0.15) {
          out.add(
            context.tr(
              'Assistant consensus barely counts — collaborations may be approved before everyone agrees.',
            ),
          );
        }
        break;
    }
    final seen = <String>{};
    final dedup = [
      for (final w in out)
        if (seen.add(w)) w,
    ];
    return dedup.take(6).toList();
  }

  void _showWeightWarnings(_ShiftBrainCategory cat, List<String> warnings) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Sa.amber.withValues(alpha: 0.5)),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Sa.amber, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('Check the {tab} weighting', {
                  'tab': context.tr(cat.tab).toLowerCase(),
                }),
                style: Sa.heading(size: 16, color: Sa.text),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'These settings may make the Shift Commander behave in ways you might not expect:',
                ),
                style: Sa.body(size: 12.5, color: Sa.textDim),
              ),
              const SizedBox(height: 14),
              for (final w in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Icon(Icons.circle, size: 7, color: Sa.amber),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          w,
                          style: Sa.body(size: 12.5, color: Sa.text),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetCategory(cat);
            },
            child: Text(
              context.tr('Reset to defaults'),
              style: TextStyle(color: Sa.amber, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              context.tr('Keep anyway'),
              style: TextStyle(color: Sa.muted),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = widget.logs;
    final memory = widget.memory;
    final accent = widget.accent;
    final enabled = widget.enabled;

    final cat = _kShiftBrains[_brainTab];
    final factors = cat.factors;
    final brainTabs = [for (final b in _kShiftBrains) b.tab];
    final brainIcons = [for (final b in _kShiftBrains) b.icon];

    final confs = <double>[];
    for (final l in logs) {
      final c = l['confidence'];
      if (c is num) {
        confs.add(c.toDouble() > 1 ? c.toDouble() / 100 : c.toDouble());
      }
    }
    final avgConf = confs.isEmpty
        ? 0.0
        : confs.reduce((a, b) => a + b) / confs.length;
    final learned = memory.where((m) => m.adjustment.abs() >= 0.5).length;

    final fireCounts = <int>[for (final _ in factors) 0];
    for (final l in logs) {
      final r = (l['reason'] ?? '').toString().toLowerCase();
      for (var i = 0; i < factors.length; i++) {
        if (factors[i].keys.any((k) => r.contains(k))) fireCounts[i]++;
      }
    }
    final maxFire = fireCounts.isEmpty ? 0 : fireCounts.reduce(math.max);

    void selectBrain(int i) => setState(() => _brainTab = i);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          accent: accent,
          glow: enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.psychology,
                title: context.tr('INSIDE THE COMMANDER’S MIND'),
                subtitle: context.tr(cat.brainSubtitle),
                accent: accent,
                trailing: GlowChip(
                  label: context.tr('COGNITION'),
                  color: accent,
                  icon: Icons.bolt,
                  pulse: enabled,
                ),
              ),
              const SizedBox(height: 12),
              _SegTabs(
                tabs: brainTabs,
                icons: brainIcons,
                index: _brainTab,
                accent: accent,
                onChanged: selectBrain,
              ),
              const SizedBox(height: 12),
              _CortexHero(
                accent: accent,
                animate: enabled,
                inputs: [
                  for (var i = 0; i < factors.length; i++)
                    _CortexInput(
                      factors[i].label,
                      factors[i].color,
                      _w(cat.slug, factors[i].slug),
                      maxFire == 0
                          ? 0.25
                          : (fireCounts[i] / maxFire).clamp(0.0, 1.0),
                    ),
                ],
                inHeader: 'WHAT IT WEIGHS',
                coreTop: 'WEIGHS',
                coreBottom: cat.coreBottom,
                outIcon: cat.outIcon,
                outTop: cat.outTop,
                outBottom: cat.outBottom,
                outColor: cat.outColor,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(cat.description),
                style: Sa.body(size: 11.5, color: Sa.textDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.memory,
                title: context.tr('WHAT HE KNOWS'),
                subtitle: context.tr(
                  'The memory the commander carries into each decision.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SaStatTile(
                    label: context.tr('Supervisors profiled'),
                    value: '${memory.length}',
                    icon: Icons.badge_outlined,
                    color: accent,
                  ),
                  SaStatTile(
                    label: context.tr('Decisions in memory'),
                    value: '${logs.length}',
                    icon: Icons.history_toggle_off,
                    color: Sa.blue,
                  ),
                  SaStatTile(
                    label: context.tr('Signals learned'),
                    value: '$learned',
                    icon: Icons.auto_graph,
                    color: Sa.green,
                  ),
                  SaStatTile(
                    label: context.tr('Avg confidence'),
                    value: '${(avgConf * 100).round()}%',
                    icon: Icons.speed,
                    color: Sa.amber,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Builder(
          builder: (context) {
            final warnings = _warningsFor(cat);
            return GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SaSectionHeader(
                    icon: Icons.tune,
                    title: context.tr('REASONING FACTORS'),
                    subtitle: context.tr(cat.reasoningSubtitle),
                    accent: accent,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (warnings.isNotEmpty) ...[
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _showWeightWarnings(cat, warnings),
                            child: GlowChip(
                              label: warnings.length > 1
                                  ? context.tr('{count} WARNINGS', {
                                      'count': '${warnings.length}',
                                    })
                                  : context.tr('{count} WARNING', {
                                      'count': '${warnings.length}',
                                    }),
                              color: Sa.amber,
                              icon: Icons.warning_amber_rounded,
                              pulse: true,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        _ResetWeightsButton(onReset: () => _resetCategory(cat)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.drag_indicator, size: 15, color: Sa.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          cat.liveScoring
                              ? context.tr(
                                  'Drag any bar to retune — changes feed the Shift Commander’s live assignment scoring instantly.',
                                )
                              : context.tr(
                                  'Drag any bar to retune — changes save to the Shift Commander instantly.',
                                ),
                          style: Sa.body(size: 11, color: Sa.textDim),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SegTabs(
                    tabs: brainTabs,
                    icons: brainIcons,
                    index: _brainTab,
                    accent: accent,
                    onChanged: selectBrain,
                  ),
                  if (warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _WeightWarningBanner(
                      message: warnings.first,
                      extra: warnings.length - 1,
                      onTap: () => _showWeightWarnings(cat, warnings),
                    ),
                  ],
                  const SizedBox(height: 6),
                  for (var i = 0; i < factors.length; i++)
                    _BrainFactorRow(
                      factor: factors[i],
                      value: _w(cat.slug, factors[i].slug),
                      fired: fireCounts[i],
                      maxFired: maxFire,
                      onChanged: (v) =>
                          _setWeight(cat.slug, factors[i].slug, v),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.model_training,
                title: context.tr('LEARNED SIGNALS'),
                subtitle: context.tr(
                  'Per-supervisor reinforcement from accepted, rejected and resolved assignments.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 12),
              if (memory.isEmpty)
                SaEmptyState(
                  icon: Icons.school_outlined,
                  title: context.tr('Nothing learned yet'),
                  message: context.tr(
                    'Once supervisors accept or reject AI assignments, the commander starts tuning their rank here.',
                  ),
                  accent: accent,
                )
              else
                ...memory
                    .take(12)
                    .map((m) => _BrainMemoryTile(memory: m, accent: accent)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.alt_route,
                title: context.tr('THOUGHT REPLAY'),
                subtitle: context.tr(
                  'Recent decisions — the situation, the pick, the confidence, the reasoning.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 12),
              if (logs.isEmpty)
                SaEmptyState(
                  icon: Icons.nights_stay_outlined,
                  title: context.tr('No thoughts yet'),
                  message: context.tr(
                    'When a shift with AI Commander goes live, each decision replays here.',
                  ),
                  accent: accent,
                )
              else
                ...logs
                    .take(8)
                    .map((l) => _ThoughtCard(log: l, accent: accent)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// THE CORTEX — a premium, self-explanatory picture of an agent's mind.
//
// The signals it weighs (left, labelled — sized by influence) flow as glowing
// axons into a slowly-rotating 3D neural-mesh brain. The brain integrates them
// in a luminous nucleus and emits one confident decision (right). Thought-
// pulses travel each axon; the busier a signal has been, the faster and
// brighter it fires — so a glance reads "what it stores" and "how it thinks".
//
// Pure vector motion graphics — no SVG assets, no platform deps — painted in a
// handful of depth-banded path calls behind a RepaintBoundary. Shared by the
// Shift Commander and Predictive Core brain tabs.
// ─────────────────────────────────────────────────────────────────────────

/// A point in the brain mesh (model space).
class _P3 {
  final double x, y, z;
  const _P3(this.x, this.y, this.z);
}

/// A projected mesh point (screen space + camera depth + perspective scale).
class _Proj {
  final double x, y, z, scale;
  const _Proj(this.x, this.y, this.z, this.scale);
}

/// One weighted signal the agent reads. [weight] (0..1) sizes the node and its
/// axon; [activity] (0..1) drives how fast and bright its thought-pulses fire.
class _CortexInput {
  final String label;
  final Color color;
  final double weight;
  final double activity;
  const _CortexInput(this.label, this.color, this.weight, this.activity);
}

/// The hero visual: a rotating 3D mesh brain fed by labelled neuro-links and
/// emitting one decision. Fully self-contained — owns one slow animation clock.
class _CortexHero extends StatefulWidget {
  final Color accent;
  final bool animate;
  final List<_CortexInput> inputs;
  final String inHeader;
  final String coreTop;
  final String coreBottom;
  final IconData outIcon;
  final String outTop;
  final String outBottom;
  final Color outColor;

  const _CortexHero({
    required this.accent,
    required this.animate,
    required this.inputs,
    required this.inHeader,
    required this.coreTop,
    required this.coreBottom,
    required this.outIcon,
    required this.outTop,
    required this.outBottom,
    required this.outColor,
  });

  @override
  State<_CortexHero> createState() => _CortexHeroState();
}

class _CortexHeroState extends State<_CortexHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_P3> _nodes;
  late final List<List<int>> _edges;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    _buildMesh();
    if (widget.animate) {
      _c.repeat();
    } else {
      _c.value = 0.08;
    }
  }

  // A parametric two-lobe brain surface (lat/long grid) with cortical fold
  // displacement plus cerebellum and temporal-lobe bulges, emitted as a
  // wireframe mesh (built once, projected every frame).
  void _buildMesh() {
    const nu = 40; // longitudes (front→back→front)
    const nv = 20; // latitudes (crown→underside)
    final verts = <_P3>[];

    double bump(
      double u,
      double v,
      double u0,
      double v0,
      double amp,
      double su,
      double sv,
    ) {
      var du = (u - u0).abs();
      if (du > math.pi) du = 2 * math.pi - du; // wrap on the ring
      final dv = v - v0;
      return amp *
          math.exp(-(du * du) / (2 * su * su) - (dv * dv) / (2 * sv * sv));
    }

    for (var j = 0; j < nv; j++) {
      final v = 0.08 * math.pi + (0.84 * math.pi) * (j / (nv - 1));
      for (var i = 0; i < nu; i++) {
        final u = 2 * math.pi * (i / nu);
        final fold =
            0.055 * math.sin(7 * u) * math.sin(6 * v) +
            0.035 * math.sin(11 * u + 2) * math.sin(9 * v + 1) +
            0.025 * math.cos(5 * u) * math.sin(8 * v);
        var r = 1.0 + fold;
        r += bump(
          u,
          v,
          math.pi,
          0.72 * math.pi,
          0.16,
          0.55,
          0.34,
        ); // cerebellum
        r += bump(
          u,
          v,
          0.18 * math.pi,
          0.66 * math.pi,
          0.10,
          0.60,
          0.30,
        ); // temporal
        final x = r * math.sin(v) * math.cos(u) * 1.16;
        var y = r * math.cos(v) * 0.82;
        final z = r * math.sin(v) * math.sin(u) * 0.80;
        if (y < 0) y *= 0.86; // flatten the underside
        verts.add(_P3(x, y, z));
      }
    }

    int idx(int i, int j) => j * nu + (i % nu);
    final edges = <List<int>>[];
    for (var j = 0; j < nv; j++) {
      for (var i = 0; i < nu; i++) {
        edges.add([idx(i, j), idx(i + 1, j)]); // longitude ring
        if (j < nv - 1) edges.add([idx(i, j), idx(i, j + 1)]); // latitude line
      }
    }
    _nodes = verts;
    _edges = edges;
  }

  @override
  void didUpdateWidget(covariant _CortexHero old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate && _c.isAnimating) {
      _c.stop();
      _c.value = 0.08;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, cons) {
        final showLabels = cons.maxWidth >= 540;
        return RepaintBoundary(
          child: SizedBox(
            height: 300,
            width: double.infinity,
            child: CustomPaint(
              painter: _CortexPainter(
                tick: _c,
                accent: widget.accent,
                inputs: [
                  for (final inp in widget.inputs)
                    _CortexInput(
                      ctx.tr(inp.label),
                      inp.color,
                      inp.weight,
                      inp.activity,
                    ),
                ],
                nodes: _nodes,
                edges: _edges,
                showLabels: showLabels,
                dim: widget.animate ? 1.0 : 0.5,
                inHeader: ctx.tr(widget.inHeader),
                coreTop: ctx.tr(widget.coreTop),
                coreBottom: ctx.tr(widget.coreBottom),
                outIcon: widget.outIcon,
                outTop: ctx.tr(widget.outTop),
                outBottom: ctx.tr(widget.outBottom),
                outHeader: ctx.tr('DECISION'),
                outColor: widget.outColor,
                isDark: Sa.isDark,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CortexPainter extends CustomPainter {
  final Animation<double> tick;
  final Color accent;
  final List<_CortexInput> inputs;
  final List<_P3> nodes;
  final List<List<int>> edges;
  final bool showLabels;
  final double dim;
  final String inHeader;
  final String coreTop;
  final String coreBottom;
  final IconData outIcon;
  final String outTop;
  final String outBottom;
  final String outHeader;
  final Color outColor;
  final bool isDark;

  _CortexPainter({
    required this.tick,
    required this.accent,
    required this.inputs,
    required this.nodes,
    required this.edges,
    required this.showLabels,
    required this.dim,
    required this.inHeader,
    required this.coreTop,
    required this.coreBottom,
    required this.outIcon,
    required this.outTop,
    required this.outBottom,
    required this.outHeader,
    required this.outColor,
    required this.isDark,
  }) : super(repaint: tick);

  void _text(
    Canvas c,
    String s,
    Offset at,
    Color col,
    double size, {
    bool center = false,
    bool rightAlign = false,
    double maxW = 240,
    FontWeight weight = FontWeight.w600,
    bool mono = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: mono
            ? Sa.mono(size: size, color: col, weight: weight)
            : Sa.body(size: size, color: col, weight: weight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    Offset o;
    if (center) {
      o = at - Offset(tp.width / 2, tp.height / 2);
    } else if (rightAlign) {
      o = at - Offset(tp.width, tp.height / 2);
    } else {
      o = at - Offset(0, tp.height / 2);
    }
    tp.paint(c, o);
  }

  void _glyph(Canvas c, IconData icon, Offset center, Color col, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: col,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final t = tick.value;
    final rot = t * 2 * math.pi; // slow brain rotation (one turn / 24s)
    final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 5); // nucleus pulse

    final labelW = showLabels ? w * 0.27 : 0.0;
    final nodeX = showLabels ? labelW + 16 : w * 0.085;
    final cx = showLabels ? w * 0.60 : w * 0.52;
    final cy = h * 0.52;
    final r = math.min((cx - nodeX) * 0.78, h * 0.40);
    const orbR = 15.0;
    final ox = w - (showLabels ? 56.0 : 38.0);
    final oy = cy;
    final n = inputs.length;
    const topPad = 30.0;
    const botPad = 26.0;

    // Theme-aware hologram palette: front bands glow, back bands fade to depth.
    final near = isDark ? Color.lerp(accent, Colors.white, 0.42)! : accent;
    final far = isDark
        ? Color.lerp(accent, const Color(0xFF071226), 0.55)!
        : Color.lerp(accent, Colors.white, 0.62)!;

    // ── soft depth vignette behind the brain
    canvas.drawCircle(
      Offset(cx, cy),
      r * 1.55,
      Paint()
        ..shader = ui.Gradient.radial(Offset(cx, cy), r * 1.55, [
          accent.withValues(alpha: 0.10 * dim),
          accent.withValues(alpha: 0.0),
        ]),
    );

    // ── input axons (signal → core), drawn under the brain
    final paths = <Path>[];
    final nodeYs = <double>[];
    for (var i = 0; i < n; i++) {
      final frac = n == 1 ? 0.5 : i / (n - 1);
      final ny = topPad + (h - topPad - botPad) * frac;
      nodeYs.add(ny);
      final node = Offset(nodeX, ny);
      final entry = Offset(cx - r * 0.66, cy + (ny - cy) * 0.34);
      final midX = (node.dx + entry.dx) / 2;
      final p = Path()
        ..moveTo(node.dx, node.dy)
        ..cubicTo(midX, node.dy, midX, entry.dy, entry.dx, entry.dy);
      paths.add(p);
      final inp = inputs[i];
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 + 1.5 * inp.weight
          ..strokeCap = StrokeCap.round
          ..color = inp.color.withValues(
            alpha: (0.13 + 0.22 * inp.weight) * dim,
          ),
      );
    }

    // ── 3D brain wireframe (rotated, tilted, perspective-projected)
    final cosY = math.cos(rot), sinY = math.sin(rot);
    const ax = -0.18; // slight downward tilt
    final cosX = math.cos(ax), sinX = math.sin(ax);
    const focal = 3.4;
    final proj = List<_Proj>.generate(nodes.length, (i) {
      final p = nodes[i];
      final x = p.x * cosY + p.z * sinY;
      var z = -p.x * sinY + p.z * cosY;
      var y = p.y;
      final y2 = y * cosX - z * sinX;
      final z2 = y * sinX + z * cosX;
      y = y2;
      z = z2;
      final scale = focal / (focal - z);
      return _Proj(cx + x * scale * r, cy + y * scale * r, z, scale);
    });

    const bands = 6;
    final bandPaths = List.generate(bands, (_) => Path());
    for (final e in edges) {
      final a = proj[e[0]];
      final b = proj[e[1]];
      final depth = ((a.z + b.z) / 2).clamp(-1.0, 1.0);
      var bi = (((depth + 1) / 2) * bands).floor();
      if (bi < 0) bi = 0;
      if (bi >= bands) bi = bands - 1;
      bandPaths[bi].moveTo(a.x, a.y);
      bandPaths[bi].lineTo(b.x, b.y);
    }
    for (var bi = 0; bi < bands; bi++) {
      final f = bands == 1 ? 1.0 : bi / (bands - 1);
      final col = Color.lerp(far, near, f) ?? near;
      canvas.drawPath(
        bandPaths[bi],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 + 0.6 * f
          ..isAntiAlias = true
          ..color = col.withValues(alpha: (0.12 + 0.46 * f) * dim),
      );
    }

    // bright sparkle on the closest vertices
    for (var i = 0; i < proj.length; i++) {
      final p = proj[i];
      final dn = (p.z + 1) / 2;
      if (dn > 0.74) {
        canvas.drawCircle(
          Offset(p.x, p.y),
          0.7 + 1.1 * ((dn - 0.74) / 0.26),
          Paint()..color = near.withValues(alpha: 0.55 * dn * dim),
        );
      }
    }

    // inner nucleus glow
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.42 * (0.85 + 0.15 * breathe),
      Paint()..color = near.withValues(alpha: (0.05 + 0.05 * breathe) * dim),
    );

    // integration rings — one faint full ring, one sweeping arc
    canvas.drawCircle(
      Offset(cx, cy),
      r + 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.14 * dim),
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r + 7),
      rot,
      math.pi * 1.1,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.5 * dim),
    );

    // ── core nucleus label (legible disc over the busy mesh)
    canvas.drawCircle(
      Offset(cx, cy),
      23,
      Paint()..color = Sa.bg.withValues(alpha: 0.58),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      23,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.55 * dim),
    );
    _text(
      canvas,
      coreTop,
      Offset(cx, cy - 6),
      Sa.text,
      8.5,
      center: true,
      mono: true,
      weight: FontWeight.w700,
      maxW: 60,
    );
    _text(
      canvas,
      coreBottom,
      Offset(cx, cy + 6),
      accent,
      8,
      center: true,
      mono: true,
      weight: FontWeight.w700,
      maxW: 60,
    );

    // ── input nodes, labels and travelling thought-pulses
    for (var i = 0; i < n; i++) {
      final inp = inputs[i];
      final ny = nodeYs[i];
      final node = Offset(nodeX, ny);
      final nr = 3.2 + 4.2 * inp.weight;
      canvas.drawCircle(
        node,
        nr + 4,
        Paint()
          ..color = inp.color.withValues(
            alpha: (0.10 + 0.28 * inp.activity) * dim,
          ),
      );
      canvas.drawCircle(
        node,
        nr,
        Paint()..color = inp.color.withValues(alpha: 0.85 * dim),
      );
      canvas.drawCircle(
        node,
        nr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = inp.color.withValues(alpha: 0.9 * dim),
      );
      if (showLabels) {
        _text(
          canvas,
          inp.label,
          Offset(nodeX - 13, ny),
          Sa.textDim,
          10.5,
          rightAlign: true,
          maxW: labelW - 16,
          weight: FontWeight.w500,
        );
      }
      final metrics = paths[i].computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final m = metrics.first;
        final sp = 0.5 + inp.activity * 1.5;
        final count = inp.activity > 0.55 ? 2 : 1;
        for (var k = 0; k < count; k++) {
          final ph = (t * 6 * sp + i * 0.13 + k * 0.5) % 1.0;
          final tan = m.getTangentForOffset(m.length * ph);
          if (tan == null) continue;
          final pr = 1.5 + 1.4 * inp.activity;
          canvas.drawCircle(
            tan.position,
            pr + 2,
            Paint()..color = inp.color.withValues(alpha: 0.18 * dim),
          );
          canvas.drawCircle(
            tan.position,
            pr,
            Paint()
              ..color = inp.color.withValues(
                alpha: (0.45 + 0.5 * inp.activity) * dim,
              ),
          );
        }
      }
    }

    // ── input column header
    if (showLabels) {
      _text(
        canvas,
        inHeader,
        Offset(nodeX - 13, 15),
        Sa.muted,
        8.5,
        rightAlign: true,
        mono: true,
        weight: FontWeight.w700,
        maxW: labelW,
      );
    }

    // ── output: connector, travelling pulse, arrowhead, decision orb, label
    final rim = Offset(cx + r * 0.62, cy);
    final orbCenter = Offset(ox, oy);
    final approach = orbCenter - const Offset(orbR + 3, 0);
    canvas.drawLine(
      rim,
      approach,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = outColor.withValues(alpha: 0.42 * dim),
    );
    final op = (t * 6) % 1.0;
    final opp = Offset.lerp(rim, approach, op)!;
    canvas.drawCircle(
      opp,
      2.6,
      Paint()..color = outColor.withValues(alpha: 0.85 * dim),
    );
    final ah = Path()
      ..moveTo(orbCenter.dx - orbR - 1, oy)
      ..lineTo(orbCenter.dx - orbR - 8, oy - 4)
      ..lineTo(orbCenter.dx - orbR - 8, oy + 4)
      ..close();
    canvas.drawPath(ah, Paint()..color = outColor.withValues(alpha: 0.6 * dim));
    canvas.drawCircle(
      orbCenter,
      orbR + 8,
      Paint()
        ..color = outColor.withValues(alpha: (0.10 + 0.12 * breathe) * dim),
    );
    canvas.drawCircle(
      orbCenter,
      orbR,
      Paint()
        ..shader = ui.Gradient.radial(orbCenter, orbR, [
          outColor.withValues(alpha: 0.95 * dim),
          outColor.withValues(alpha: 0.55 * dim),
        ]),
    );
    canvas.drawCircle(
      orbCenter,
      orbR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = outColor,
    );
    _glyph(canvas, outIcon, orbCenter, Sa.onAccent, 16);
    final outMaxW = (w - ox) * 2 - 8;
    _text(
      canvas,
      outTop,
      Offset(ox, oy + orbR + 14),
      Sa.text,
      10,
      center: true,
      weight: FontWeight.w600,
      maxW: outMaxW,
    );
    _text(
      canvas,
      outBottom,
      Offset(ox, oy + orbR + 27),
      Sa.muted,
      9,
      center: true,
      maxW: outMaxW,
    );
    if (showLabels) {
      _text(
        canvas,
        outHeader,
        Offset(ox, 15),
        Sa.muted,
        8.5,
        center: true,
        mono: true,
        weight: FontWeight.w700,
        maxW: 120,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CortexPainter old) =>
      old.accent != accent ||
      old.inputs != inputs ||
      old.dim != dim ||
      old.showLabels != showLabels ||
      old.outColor != outColor ||
      old.isDark != isDark;
}

/// A reasoning factor with a draggable influence bar and recent firing count.
///
/// Dragging the bar changes [value] (0..1) and reports it through [onChanged];
/// the parent persists it live to the Shift Commander. The percentage and the
/// fill follow the live value so the edit reads back immediately.
class _BrainFactorRow extends StatelessWidget {
  final _BrainFactor factor;
  final double value;
  final int fired;
  final int maxFired;
  final ValueChanged<double> onChanged;
  const _BrainFactorRow({
    required this.factor,
    required this.value,
    required this.fired,
    required this.maxFired,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final influence = value.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: factor.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  factor.label,
                  style: Sa.body(size: 13, color: Sa.text),
                ),
              ),
              Text(
                '${(influence * 100).round()}% weight',
                style: Sa.mono(size: 11, color: factor.color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(
              factor.desc,
              style: Sa.body(size: 11, color: Sa.textDim),
            ),
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Row(
              children: [
                Expanded(
                  child: _WeightSlider(
                    value: influence,
                    color: factor.color,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 56,
                  child: Text(
                    fired > 0 ? 'fired $fired×' : 'idle',
                    textAlign: TextAlign.right,
                    style: Sa.mono(
                      size: 10,
                      color: fired > 0 ? factor.color : Sa.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A self-contained horizontal drag slider styled to match the factor bars:
/// a rounded track, a colored fill and a grabbable thumb. Tap or drag anywhere
/// on the track to set the value.
class _WeightSlider extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final ValueChanged<double> onChanged;
  const _WeightSlider({
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, cons) {
        final w = cons.maxWidth;
        void emit(double dx) =>
            onChanged((dx / (w <= 0 ? 1 : w)).clamp(0.0, 1.0));
        final fillW = (w * value).clamp(0.0, w);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => emit(d.localPosition.dx),
          onHorizontalDragStart: (d) => emit(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => emit(d.localPosition.dx),
          child: SizedBox(
            height: 20,
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                // track
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Sa.panelSolid,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                // fill
                Container(
                  height: 8,
                  width: fillW,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 7,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                ),
                // thumb
                Positioned(
                  left: (fillW - 9).clamp(0.0, math.max(0.0, w - 18)),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Sa.isDark ? Sa.panelSolid : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: -1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Compact "Reset" affordance for the reasoning-factor weights.
class _ResetWeightsButton extends StatelessWidget {
  final VoidCallback onReset;
  const _ResetWeightsButton({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onReset,
      icon: Icon(Icons.restart_alt, size: 15, color: Sa.muted),
      label: Text(
        context.tr('Reset'),
        style: Sa.body(size: 11.5, color: Sa.muted),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Inline orange banner shown when a weight mix looks incoherent. Tappable to
/// open the full list of warnings.
class _WeightWarningBanner extends StatelessWidget {
  final String message;
  final int extra; // additional warnings beyond [message]
  final VoidCallback onTap;
  const _WeightWarningBanner({
    required this.message,
    required this.extra,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Sa.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Sa.amber.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Sa.amber, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                extra > 0
                    ? context.tr('{message}  (+{extra} more)', {
                        'message': message,
                        'extra': '$extra',
                      })
                    : message,
                style: Sa.body(size: 11.5, color: Sa.text),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              context.tr('Review'),
              style: Sa.body(size: 11.5, color: Sa.amber),
            ),
            Icon(Icons.chevron_right, color: Sa.amber, size: 18),
          ],
        ),
      ),
    );
  }
}

/// One supervisor's reinforcement memory row.
class _BrainMemoryTile extends StatelessWidget {
  final _BrainMemory memory;
  final Color accent;
  const _BrainMemoryTile({required this.memory, required this.accent});

  static String _initials(String n) {
    final parts = n
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Widget _miniChip(String s, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      s,
      style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w500),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final adj = memory.adjustment;
    final adjColor = adj > 0 ? Sa.green : (adj < 0 ? Sa.red : Sa.muted);
    final adjLabel =
        '${adj > 0 ? '+' : ''}${adj.toStringAsFixed(adj.abs() < 10 ? 1 : 0)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Sa.panelSolid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _initials(memory.name),
              style: Sa.body(size: 11, color: accent),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  memory.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.body(size: 12.5, color: Sa.text),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _miniChip('${memory.accepted} accepted', Sa.green),
                    _miniChip('${memory.rejected} rejected', Sa.red),
                    _miniChip('${memory.resolved} resolved', Sa.blue),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(adjLabel, style: Sa.heading(size: 15, color: adjColor)),
              Text('rank bias', style: Sa.mono(size: 8.5, color: Sa.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single recent decision rendered as a "thought": situation → pick → reason.
class _ThoughtCard extends StatelessWidget {
  final Map<String, dynamic> log;
  final Color accent;
  const _ThoughtCard({required this.log, required this.accent});

  Widget _pill(String s, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      s,
      style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.w500),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final kind = (log['kind'] ?? 'decision').toString();
    final who = (log['supervisorName'] ?? '').toString();
    final alert = (log['alertLabel'] ?? '').toString();
    final factory = (log['factory'] ?? log['usine'] ?? '').toString();
    final reason = (log['reason'] ?? '').toString();
    final cRaw = log['confidence'];
    final conf = cRaw is num
        ? (cRaw.toDouble() > 1 ? cRaw.toDouble() : cRaw.toDouble() * 100)
        : null;
    final blocked =
        kind.toLowerCase().contains('block') ||
        kind.toLowerCase().contains('skip');
    final tone = blocked ? Sa.amber : accent;
    final head = [
      if (alert.isNotEmpty) alert,
      if (factory.isNotEmpty) '· $factory',
    ].join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Sa.panelSolid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(blocked ? Icons.block : Icons.bolt, size: 14, color: tone),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  head.isEmpty ? context.tr('Decision') : head,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.body(size: 12.5, color: Sa.text),
                ),
              ),
              if (conf != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${conf.round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: tone,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _pill(kind, tone),
              if (who.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 13, color: Sa.muted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Sa.body(size: 12.5, color: Sa.text),
                  ),
                ),
              ],
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Sa.termBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Sa.termBorder),
              ),
              child: Text(
                reason,
                style: Sa.mono(size: 10.5, color: Sa.termText),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BriefingAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  const _BriefingAgentPanel({required this.spec, required this.enabled});

  @override
  State<_BriefingAgentPanel> createState() => _BriefingAgentPanelState();
}

class _BriefingAgentPanelState extends State<_BriefingAgentPanel> {
  StreamSubscription<DatabaseEvent>? _latestSub;
  StreamSubscription<DatabaseEvent>? _statsSub;
  Map<String, dynamic>? _latest;
  Map<String, dynamic>? _stats;
  int _historyCount = 0;
  int _factoryCount = 0;
  bool _regenerating = false;
  List<String> _factories = const [];
  // null = global (all-factories) briefing.
  String? _selectedFactory;

  @override
  void initState() {
    super.initState();
    _subscribeLatest();
    _statsSub = FirebaseDatabase.instance
        .ref('ai_agents/briefing/stats')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          if (mounted && v is Map) {
            setState(() => _stats = Map<String, dynamic>.from(v));
          }
        }, onError: (_) {});
    _probeCounts();
    _loadFactories();
  }

  void _subscribeLatest() {
    _latestSub?.cancel();
    _latestSub = FirebaseDatabase.instance
        .ref(predictiveBriefingPath(_selectedFactory))
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          if (mounted) {
            setState(
              () => _latest = v is Map ? Map<String, dynamic>.from(v) : null,
            );
          }
        }, onError: (_) {});
  }

  Future<void> _loadFactories() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('hierarchy/factories')
          .get();
      if (snap.value is Map && mounted) {
        final names =
            (snap.value as Map).values
                .whereType<Map>()
                .map((f) => (f['name'] ?? '').toString())
                .where((n) => n.isNotEmpty)
                .toList()
              ..sort();
        setState(() => _factories = names);
      }
    } catch (_) {}
  }

  Future<void> _probeCounts() async {
    try {
      final slug = predictiveFactorySlug(_selectedFactory);
      final histPath = slug == null
          ? 'ai_briefing/history'
          : 'ai_briefing/factory/$slug/history';
      final hist = await FirebaseDatabase.instance.ref(histPath).get();
      final fact = await FirebaseDatabase.instance
          .ref('ai_briefing/factory')
          .get();
      if (mounted) {
        setState(() {
          _historyCount = hist.children.length;
          _factoryCount = fact.children.length;
        });
      }
    } catch (_) {}
  }

  void _selectFactory(String? factory) {
    if (factory == _selectedFactory) return;
    setState(() {
      _selectedFactory = factory;
      _latest = null;
    });
    _subscribeLatest();
    _probeCounts();
  }

  Future<void> _regenerate() async {
    setState(() => _regenerating = true);
    try {
      final scope = normalizePredictiveFactory(_selectedFactory);
      final factoryQuery = scope != null
          ? 'factory=${Uri.encodeQueryComponent(scope)}&'
          : '';
      final res = await http
          .get(
            Uri.parse('${AppConfig.briefingEndpoint}?${factoryQuery}force=1'),
          )
          .timeout(const Duration(seconds: 25));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              res.statusCode == 200
                  ? 'Briefing regenerated — PM dashboards update live.'
                  : 'Briefing endpoint replied ${res.statusCode}.',
              style: Sa.body(size: 12.5),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              'Regeneration failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  @override
  void dispose() {
    _latestSub?.cancel();
    _statsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final latest = _latest;
    final model = (latest?['model'] ?? '—').toString();

    return _AgentScroll(
      children: [
        if (!widget.enabled) _OfflineBanner(spec: spec),
        GlassPanel(
          accent: spec.accent,
          glow: widget.enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: spec.icon,
                leading: _AgentGlyph(spec: spec, size: 36, radius: 10),
                title: context.tr('BRIEFING DESK'),
                subtitle: context.tr(
                  'Writes the factory-aware morning briefing each Production Manager wakes up to.',
                ),
                accent: spec.accent,
                trailing: SaButton(
                  label: context.tr('REGENERATE NOW'),
                  icon: Icons.bolt,
                  color: spec.accent,
                  busy: _regenerating,
                  onPressed: widget.enabled ? _regenerate : null,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SaStatTile(
                    label: context.tr('Briefings archived'),
                    value: '$_historyCount',
                    icon: Icons.inventory_2_outlined,
                    color: spec.accent,
                  ),
                  SaStatTile(
                    label: context.tr('Factory scopes'),
                    value: '$_factoryCount',
                    icon: Icons.factory_outlined,
                    color: Sa.violet,
                  ),
                  SaStatTile(
                    label: context.tr('Generated total'),
                    value: '${(_stats?['generated'] as num?)?.toInt() ?? '—'}',
                    icon: Icons.auto_awesome,
                    color: Sa.green,
                  ),
                  SaStatTile(
                    label: context.tr('Last generated'),
                    value: _agoIso(
                      context,
                      _stats?['lastGeneratedAt'] ?? latest?['generatedAt'],
                    ),
                    icon: Icons.schedule,
                    color: Sa.amber,
                  ),
                ],
              ),
            ],
          ),
        ),
        _ModelEnginePanel(
          agent: 'briefing',
          accent: spec.accent,
          enabled: widget.enabled,
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.article_outlined,
                title: context.tr('LATEST DISPATCH'),
                subtitle: context.tr(
                  'The exact words the PMs are reading right now.',
                ),
                accent: spec.accent,
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    GlowChip(
                      label: model.contains('llama')
                          ? 'LLAMA 3.2 3B'
                          : model.toUpperCase(),
                      color: spec.accent,
                      icon: Icons.memory,
                    ),
                    if ((latest?['date'] ?? '').toString().isNotEmpty)
                      GlowChip(
                        label: (latest?['date'] ?? '').toString(),
                        color: Sa.muted,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _FactoryScopeBar(
                factories: _factories,
                selected: _selectedFactory,
                onSelect: _selectFactory,
                accent: spec.accent,
              ),
              const SizedBox(height: 14),
              if (latest == null)
                SaEmptyState(
                  icon: Icons.hourglass_empty,
                  title: _selectedFactory == null
                      ? context.tr('No briefing yet today')
                      : context.tr('No briefing yet for {factory}', {
                          'factory': _selectedFactory!,
                        }),
                  message: context.tr(
                    'The officer writes the first dispatch when a PM opens their dashboard (or hit REGENERATE NOW).',
                  ),
                  accent: spec.accent,
                )
              else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Sa.termBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Sa.termBorder),
                  ),
                  child: SelectableText(
                    (latest['summary'] ?? '—').toString(),
                    style: Sa.mono(size: 11.5, color: Sa.termText),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (latest['accuracyPct'] != null)
                      GlowChip(
                        label: context.tr('MODEL ACCURACY {pct}%', {
                          'pct': '${latest['accuracyPct']}',
                        }),
                        color: Sa.violet,
                      ),
                    if (latest['topSupervisor'] is Map)
                      GlowChip(
                        label: context
                            .tr('TOP: {name}', {
                              'name':
                                  ((latest['topSupervisor']
                                              as Map)['name'] ??
                                          '—')
                                      .toString(),
                            })
                            .toUpperCase(),
                        color: Sa.green,
                        icon: Icons.emoji_events_outlined,
                      ),
                    if (latest['predictiveInsight'] is Map &&
                        (latest['predictiveInsight'] as Map)['type'] != null)
                      GlowChip(
                        label: context
                            .tr('PREDICTS {type}', {
                              'type':
                                  ((latest['predictiveInsight'] as Map)['type'] ??
                                          '')
                                      .toString(),
                            })
                            .toUpperCase(),
                        color: Sa.amber,
                        icon: Icons.online_prediction,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Horizontal "ALL FACTORIES" + per-factory chip row letting the SuperAdmin
/// pick which plant's morning briefing the dispatch panel is showing.
/// Each factory has its own briefing scope written to
/// `ai_briefing/factory/{slug}/latest` by the worker (see CLAUDE.md briefing
/// personalization section); `null` selects the global `ai_briefing/latest`.
class _FactoryScopeBar extends StatelessWidget {
  final List<String> factories;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final Color accent;

  const _FactoryScopeBar({
    required this.factories,
    required this.selected,
    required this.onSelect,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (factories.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(Icons.tune, size: 14, color: Sa.muted),
          ),
          _ScopeChip(
            label: context.tr('ALL FACTORIES'),
            selected: selected == null,
            color: accent,
            onTap: () => onSelect(null),
          ),
          for (final f in factories)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _ScopeChip(
                label: f.toUpperCase(),
                selected: selected == f,
                color: accent,
                onTap: () => onSelect(f),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.32),
                    color.withValues(alpha: 0.14),
                  ],
                )
              : null,
          color: selected ? null : Sa.termBg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.7) : Sa.termBorder,
          ),
        ),
        child: Text(
          label,
          style: Sa.mono(
            size: 10.5,
            color: selected ? color : Sa.muted,
            weight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-03 · AI ASSIST
// ═══════════════════════════════════════════════════════════════════════════

/// The worker's built-in prompt, kept verbatim so the SuperAdmin sees exactly
/// what runs when no override is deployed. Placeholders are substituted by
/// the Cloudflare worker at request time.
const String kAssistDefaultPrompt =
    '''You are an industrial operations assistant. A supervisor needs a resolution suggestion.

Alert type: {type}
Description: {description}
Location: Factory: {usine}, Conveyor line: {convoyeur}, Workstation: #{poste}

{history}

Provide a concise, actionable resolution in 2-3 bullet points. Base it on the past fixes when available; otherwise suggest the most likely root cause and immediate action.''';

class _AssistAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  const _AssistAgentPanel({required this.spec, required this.enabled});

  @override
  State<_AssistAgentPanel> createState() => _AssistAgentPanelState();
}

class _AssistAgentPanelState extends State<_AssistAgentPanel> {
  StreamSubscription<DatabaseEvent>? _statsSub;
  StreamSubscription<DatabaseEvent>? _logsSub;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _logs = const [];
  List<Map<String, dynamic>> _knowledge = const [];
  bool _knowledgeLoading = true;

  final TextEditingController _prompt = TextEditingController();
  bool _overrideActive = false;
  bool _savingPrompt = false;

  @override
  void initState() {
    super.initState();
    _statsSub = FirebaseDatabase.instance
        .ref('ai_agents/assist/stats')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          if (mounted && v is Map) {
            setState(() => _stats = Map<String, dynamic>.from(v));
          }
        }, onError: (_) {});
    _logsSub = FirebaseDatabase.instance
        .ref('ai_agents/assist/logs')
        .limitToLast(40)
        .onValue
        .listen((event) {
          if (mounted) {
            setState(
              () => _logs = _mapToSortedList(event.snapshot.value, 'at'),
            );
          }
        }, onError: (_) {});
    _loadPrompt();
    _loadKnowledge();
  }

  Future<void> _loadPrompt() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('ai_agents/assist/promptTemplate')
          .get();
      final v = (snap.value ?? '').toString();
      if (mounted) {
        setState(() {
          _overrideActive = v.trim().isNotEmpty;
          _prompt.text = _overrideActive ? v : kAssistDefaultPrompt;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _prompt.text = kAssistDefaultPrompt);
    }
  }

  Future<void> _loadKnowledge() async {
    setState(() => _knowledgeLoading = true);
    try {
      final snap = await FirebaseDatabase.instance
          .ref('alerts')
          .orderByChild('status')
          .equalTo('validee')
          .limitToLast(30)
          .get();
      final list = <Map<String, dynamic>>[];
      for (final child in snap.children) {
        final v = child.value;
        if (v is Map && (v['resolutionReason'] ?? '').toString().isNotEmpty) {
          final m = Map<String, dynamic>.from(v);
          m['id'] = child.key ?? '';
          list.add(m);
        }
      }
      list.sort(
        (a, b) => (b['resolvedAt'] ?? '').toString().compareTo(
          (a['resolvedAt'] ?? '').toString(),
        ),
      );
      if (mounted) setState(() => _knowledge = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _knowledgeLoading = false);
    }
  }

  Future<void> _savePrompt() async {
    final text = _prompt.text.trim();
    if (text.isEmpty) return;
    setState(() => _savingPrompt = true);
    try {
      await FirebaseDatabase.instance.ref('ai_agents/assist').update({
        'promptTemplate': text,
        'promptUpdatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        setState(() => _overrideActive = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              'Prompt override deployed — live within 60s.',
              style: Sa.body(size: 12.5),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              'Save failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPrompt = false);
    }
  }

  Future<void> _resetPrompt() async {
    setState(() => _savingPrompt = true);
    try {
      await FirebaseDatabase.instance
          .ref('ai_agents/assist/promptTemplate')
          .remove();
      if (mounted) {
        setState(() {
          _overrideActive = false;
          _prompt.text = kAssistDefaultPrompt;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _savingPrompt = false);
    }
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    _logsSub?.cancel();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return _AgentScroll(
      children: [
        if (!widget.enabled) _OfflineBanner(spec: spec),
        GlassPanel(
          accent: spec.accent,
          glow: widget.enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: spec.icon,
                leading: _AgentGlyph(spec: spec, size: 36, radius: 10),
                title: context.tr('CO-PILOT STATUS'),
                subtitle: context.tr(
                  'Serves resolution suggestions to supervisors, grounded in this plant’s real past fixes.',
                ),
                accent: spec.accent,
                trailing: GlowChip(
                  label: context.tr('MODEL ENGINE'),
                  color: spec.accent,
                  icon: Icons.hub_outlined,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SaStatTile(
                    label: context.tr('Suggestions served'),
                    value: '${(_stats?['served'] as num?)?.toInt() ?? 0}',
                    icon: Icons.tips_and_updates_outlined,
                    color: spec.accent,
                  ),
                  SaStatTile(
                    label: context.tr('Last served'),
                    value: _agoIso(context, _stats?['lastServedAt']),
                    icon: Icons.schedule,
                    color: Sa.amber,
                  ),
                  SaStatTile(
                    label: context.tr('Knowledge entries'),
                    value: '${_knowledge.length}',
                    icon: Icons.school_outlined,
                    color: Sa.violet,
                  ),
                  SaStatTile(
                    label: context.tr('Prompt'),
                    value: _overrideActive
                        ? context.tr('CUSTOM')
                        : context.tr('FACTORY DEFAULT'),
                    icon: Icons.edit_note,
                    color: _overrideActive ? Sa.green : Sa.muted,
                  ),
                ],
              ),
            ],
          ),
        ),
        _ModelEnginePanel(
          agent: 'assist',
          accent: spec.accent,
          enabled: widget.enabled,
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.edit_note,
                title: context.tr('PROMPT LAB'),
                subtitle: context.tr(
                  'The exact instruction sent to Llama on Cloudflare for every suggestion. Edit, deploy, or revert to the factory default.',
                ),
                accent: spec.accent,
                trailing: _overrideActive
                    ? GlowChip(
                        label: context.tr('OVERRIDE ACTIVE'),
                        color: Sa.green,
                        pulse: true,
                      )
                    : GlowChip(label: context.tr('DEFAULT'), color: Sa.muted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final ph in const [
                    '{type}',
                    '{description}',
                    '{usine}',
                    '{convoyeur}',
                    '{poste}',
                    '{history}',
                  ])
                    Tooltip(
                      message: switch (ph) {
                        '{type}' => context.tr('Human-readable alert type'),
                        '{description}' => context.tr(
                          'Supervisor’s sanitized description',
                        ),
                        '{usine}' => context.tr('Factory name'),
                        '{convoyeur}' => context.tr('Conveyor line number'),
                        '{poste}' => context.tr('Workstation number'),
                        _ => context.tr(
                          'Block of past resolutions for this exact location',
                        ),
                      },
                      child: GlowChip(label: ph, color: spec.accent),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Sa.termBg.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Sa.termBorder, width: 1.5),
                ),
                child: TextField(
                  controller: _prompt,
                  maxLines: 12,
                  minLines: 6,
                  style: Sa.mono(size: 11, color: Sa.termText),
                  cursorColor: spec.accent,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                    filled: true,
                    fillColor: Colors.transparent,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SaButton(
                    label: context.tr('DEPLOY PROMPT'),
                    icon: Icons.rocket_launch_outlined,
                    color: spec.accent,
                    busy: _savingPrompt,
                    onPressed: _savePrompt,
                  ),
                  const SizedBox(width: 10),
                  SaButton(
                    label: context.tr('REVERT TO DEFAULT'),
                    icon: Icons.history,
                    color: Sa.amber,
                    outlined: true,
                    onPressed: _overrideActive ? _resetPrompt : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.school_outlined,
                title: context.tr('KNOWLEDGE BASE'),
                subtitle: context.tr(
                  'What the agent learns from: the latest validated resolutions it cites when supervisors ask for help.',
                ),
                accent: spec.accent,
                trailing: IconButton(
                  tooltip: context.tr('Refresh'),
                  onPressed: _loadKnowledge,
                  icon: Icon(Icons.refresh, size: 16, color: spec.accent),
                ),
              ),
              const SizedBox(height: 12),
              if (_knowledgeLoading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: spec.accent,
                    ),
                  ),
                )
              else if (_knowledge.isEmpty)
                SaEmptyState(
                  icon: Icons.menu_book_outlined,
                  title: context.tr('No learned fixes yet'),
                  message: context.tr(
                    'Resolved alerts with a written resolution become this agent’s study material automatically.',
                  ),
                  accent: spec.accent,
                )
              else
                ..._knowledge
                    .take(20)
                    .map(
                      (k) => _LogTile(
                        kind: (k['type'] ?? 'fix').toString(),
                        color: spec.accent,
                        title:
                            '${k['usine'] ?? ''} · L${k['convoyeur'] ?? '?'} WS${k['poste'] ?? '?'} — ${k['resolutionReason'] ?? ''}',
                        at: (k['resolvedAt'] ?? '').toString(),
                        details: k,
                      ),
                    ),
            ],
          ),
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.receipt_long_outlined,
                title: context.tr('SERVICE LOG'),
                subtitle: context.tr(
                  'Recent suggestion requests answered at the edge.',
                ),
                accent: spec.accent,
              ),
              const SizedBox(height: 12),
              if (_logs.isEmpty)
                Text(
                  context.tr(
                    'No requests logged yet — entries appear the moment a supervisor asks for an AI suggestion.',
                  ),
                  style: Sa.body(size: 12, color: Sa.textDim),
                )
              else
                ..._logs
                    .take(30)
                    .map(
                      (l) => _LogTile(
                        kind: (l['outcome'] ?? 'served').toString(),
                        color: (l['outcome'] ?? '') == 'fallback'
                            ? Sa.amber
                            : spec.accent,
                        title: context.tr('{prefix} · {count} past fixes cited', {
                          'prefix':
                              '${l['type'] ?? ''} @ ${l['usine'] ?? ''} L${l['convoyeur'] ?? '?'} WS${l['poste'] ?? '?'}',
                          'count': '${l['historyUsed'] ?? 0}',
                        }),
                        at: (l['at'] ?? '').toString(),
                        details: l,
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-04 · SECURITY SENTINEL
// ═══════════════════════════════════════════════════════════════════════════

/// MODEL ENGINE — lets IT point the Assist or Briefing agent at any supported
/// LLM and paste the company's own API key. Llama (Cloudflare Workers AI) is the
/// default and needs no key. Reads/writes ai_model_config/{agent}.
class _ModelEnginePanel extends StatefulWidget {
  final String agent; // 'assist' | 'briefing'
  final Color accent;
  final bool enabled;
  const _ModelEnginePanel({
    required this.agent,
    required this.accent,
    required this.enabled,
  });

  @override
  State<_ModelEnginePanel> createState() => _ModelEnginePanelState();
}

class _ModelEnginePanelState extends State<_ModelEnginePanel> {
  final _svc = AiModelConfigService();
  final TextEditingController _key = TextEditingController();
  String _modelId = kDefaultAiModelId;
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;
  bool _testing = false;
  ModelEvalResult? _eval;
  StreamSubscription<DatabaseEvent>? _driftSub;
  Map<String, dynamic>? _drift;

  @override
  void initState() {
    super.initState();
    _load();
    _driftSub = FirebaseDatabase.instance
        .ref('ai_model_evals/${widget.agent}/driftStatus')
        .onValue
        .listen((e) {
          final v = e.snapshot.value;
          if (mounted) {
            setState(
              () => _drift = v is Map ? Map<String, dynamic>.from(v) : null,
            );
          }
        }, onError: (_) {});
  }

  Future<void> _load() async {
    try {
      final cfg = await _svc.fetch(widget.agent);
      if (mounted) {
        setState(() {
          _modelId = cfg.modelId;
          _key.text = cfg.apiKey;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final model = aiModelById(_modelId);
    final key = _key.text.trim();
    if (model.needsKey && key.isEmpty) {
      _toast(
        context.tr('{label} needs an API key — paste it first.', {
          'label': model.label,
        }),
        err: true,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.save(
        widget.agent,
        AiModelConfig(modelId: _modelId, apiKey: model.needsKey ? key : ''),
      );
      _toast(
        context.tr('Model saved — {label}. Live within 60s.', {
          'label': model.label,
        }),
      );
    } catch (e) {
      _toast(context.tr('Save failed: {error}', {'error': '$e'}), err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    final model = aiModelById(_modelId);
    final key = _key.text.trim();
    if (model.needsKey && key.isEmpty) {
      _toast(
        context.tr('{label} needs an API key to test.', {
          'label': model.label,
        }),
        err: true,
      );
      return;
    }
    setState(() => _testing = true);
    try {
      final result = await _svc.evaluate(
        widget.agent,
        AiModelConfig(modelId: _modelId, apiKey: model.needsKey ? key : ''),
      );
      if (mounted) setState(() => _eval = result);
    } catch (e) {
      _toast(context.tr('Test failed: {error}', {'error': '$e'}), err: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Widget _driftStripWidget() {
    final d = _drift!;
    final drifting = d['drift'] == true;
    final score = (d['score'] is num) ? (d['score'] as num).toDouble() : 0.0;
    final baseline = (d['baseline'] is num)
        ? (d['baseline'] as num).toDouble()
        : null;
    final c = drifting ? Sa.red : Sa.green;
    final reason = (d['reason'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            drifting ? Icons.warning_amber_rounded : Icons.verified_outlined,
            size: 16,
            color: c,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              drifting
                  ? context.tr('Drift detected — {reason}', {
                      'reason': reason.isNotEmpty
                          ? reason
                          : context.tr('quality regressed'),
                    })
                  : context.tr('Quality stable · {pct}%{baseline}', {
                      'pct': '${(score * 100).round()}',
                      'baseline': baseline != null
                          ? context.tr(' vs {pct}% baseline', {
                              'pct': '${(baseline * 100).round()}',
                            })
                          : '',
                    }),
              style: Sa.body(size: 11.5, color: Sa.text),
            ),
          ),
          Text(
            context.tr('checked {time}', {
              'time': _agoIso(context, d['at']),
            }),
            style: Sa.mono(size: 9.5, color: Sa.muted),
          ),
        ],
      ),
    );
  }

  void _toast(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Sa.panelSolid,
        content: Text(
          msg,
          style: Sa.body(size: 12.5, color: err ? Sa.red : Sa.text),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _driftSub?.cancel();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = aiModelById(_modelId);
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.hub_outlined,
            title: context.tr('MODEL ENGINE'),
            subtitle: context.tr(
              'Choose which AI model writes this agent’s output. Llama runs free on the edge; any other provider uses your own API key — stored in a SuperAdmin-only node and used edge-side only.',
            ),
            accent: widget.accent,
            trailing: GlowChip(
              label: selected.needsKey
                  ? context.tr('BRING-YOUR-OWN-KEY')
                  : context.tr('BUILT-IN'),
              color: selected.needsKey ? Sa.amber : Sa.green,
              icon: selected.needsKey ? Icons.vpn_key_outlined : Icons.bolt,
            ),
          ),
          const SizedBox(height: 14),
          if (_drift != null) _driftStripWidget(),
          if (_loading)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.accent,
                ),
              ),
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in kAiModels)
                  _ModelOptionTile(
                    model: m,
                    selected: m.id == _modelId,
                    onTap: () => setState(() {
                      _modelId = m.id;
                      if (!m.needsKey) _key.clear();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (selected.needsKey) ...[
              Text(
                context.tr('{label} — API key', {'label': selected.label}),
                style: Sa.body(size: 12, color: Sa.muted),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Sa.termBg.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Sa.termBorder, width: 1.5),
                ),
                child: TextField(
                  controller: _key,
                  obscureText: _obscure,
                  style: Sa.mono(size: 11.5, color: Sa.termText),
                  cursorColor: widget.accent,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    hintText: context.tr('Paste your {provider} API key', {
                      'provider': selected.provider,
                    }),
                    hintStyle: Sa.mono(size: 11.5, color: Sa.muted),
                    suffixIcon: IconButton(
                      tooltip: _obscure
                          ? context.tr('Show')
                          : context.tr('Hide'),
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        size: 16,
                        color: Sa.muted,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 12, color: Sa.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.tr(
                        'The key is read only by the edge worker and SuperAdmin. It never reaches supervisor or PM devices. If a call fails, the agent falls back to built-in Llama automatically.',
                      ),
                      style: Sa.body(size: 11, color: Sa.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Sa.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Sa.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.bolt, size: 16, color: Sa.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr(
                          'Built-in Llama 3.2 runs on Cloudflare Workers AI — no API key, no extra cost. Pick another provider above to use a stronger model.',
                        ),
                        style: Sa.body(size: 12, color: Sa.text),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaButton(
                  label: context.tr('TEST THIS MODEL'),
                  icon: Icons.science_outlined,
                  color: widget.accent,
                  outlined: true,
                  busy: _testing,
                  onPressed: widget.enabled ? _test : null,
                ),
                SaButton(
                  label: context.tr('SAVE MODEL'),
                  icon: Icons.save_outlined,
                  color: widget.accent,
                  busy: _saving,
                  onPressed: widget.enabled ? _save : null,
                ),
              ],
            ),
            if (_testing)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  context.tr(
                    'Running both models on golden tasks and scoring them…',
                  ),
                  style: Sa.body(size: 11, color: Sa.muted),
                ),
              ),
            if (_eval != null)
              _EvalResultCard(eval: _eval!, accent: widget.accent),
          ],
        ],
      ),
    );
  }
}

/// Head-to-head eval result: candidate vs current champion, with a verdict.
class _EvalResultCard extends StatelessWidget {
  final ModelEvalResult eval;
  final Color accent;
  const _EvalResultCard({required this.eval, required this.accent});

  static String _short(BuildContext context, String id) =>
      id.isEmpty ? context.tr('built-in') : id;

  Widget _scoreRow(String label, double score, Color color, bool strong) {
    final pct = score.clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 132,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Sa.body(size: 11.5, color: strong ? Sa.text : Sa.textDim),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, cons) => Container(
              height: 10,
              width: double.infinity,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: Sa.panelSolid,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Container(
                height: 10,
                width: cons.maxWidth * pct,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 42,
          child: Text(
            '${(pct * 100).round()}%',
            textAlign: TextAlign.right,
            style: Sa.mono(size: 11.5, color: strong ? Sa.text : Sa.muted),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = eval.verdict;
    final vColor = v == 'better'
        ? Sa.green
        : (v == 'worse' ? Sa.red : Sa.amber);
    final vLabel = v == 'better'
        ? context.tr('BETTER — safe to deploy')
        : v == 'worse'
        ? context.tr('WORSE — keep current')
        : context.tr('SIMILAR — no real gain');
    final vIcon = v == 'better'
        ? Icons.trending_up
        : v == 'worse'
        ? Icons.trending_down
        : Icons.drag_handle;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: vColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: vColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(vIcon, size: 18, color: vColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(vLabel, style: Sa.heading(size: 13, color: vColor)),
              ),
              Text(
                '${eval.delta >= 0 ? '+' : ''}${(eval.delta * 100).round()} pts',
                style: Sa.mono(size: 12, color: vColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _scoreRow(context.tr('This model'), eval.candidate.score, accent, true),
          const SizedBox(height: 8),
          _scoreRow(
            context.tr('Current · {model}', {
              'model': _short(context, eval.champion.modelId),
            }),
            eval.champion.score,
            Sa.muted,
            false,
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Both models ran the same golden tasks; we score grounding, structure, on-topic accuracy and length. Higher is better.',
            ),
            style: Sa.body(size: 10.5, color: Sa.muted),
          ),
        ],
      ),
    );
  }
}

/// One selectable model in the MODEL ENGINE grid: brand icon + label, with a
/// "no key" hint for the built-in default and a check when selected.
class _ModelOptionTile extends StatelessWidget {
  final AiModel model;
  final bool selected;
  final VoidCallback onTap;
  const _ModelOptionTile({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 176,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? model.color.withValues(alpha: 0.14)
              : Sa.termBg.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? model.color : Sa.termBorder,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: model.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _ProviderLogo(
                provider: _Providers.of(model.brandId),
                size: 17,
                color: model.color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    model.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Sa.body(
                      size: 11.5,
                      color: selected ? Sa.text : Sa.textDim,
                    ),
                  ),
                  if (!model.needsKey)
                    Text(
                      context.tr('default · no key'),
                      style: Sa.body(size: 9.5, color: Sa.green),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 16, color: model.color),
          ],
        ),
      ),
    );
  }
}

class _SecurityAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  final Map<String, dynamic>? health;
  const _SecurityAgentPanel({
    required this.spec,
    required this.enabled,
    required this.health,
  });

  @override
  State<_SecurityAgentPanel> createState() => _SecurityAgentPanelState();
}

class _SecurityAgentPanelState extends State<_SecurityAgentPanel> {
  StreamSubscription<DatabaseEvent>? _actionsSub;
  StreamSubscription<DatabaseEvent>? _settingsSub;
  List<Map<String, dynamic>> _actions = const [];
  Map<String, dynamic> _settings = const {};
  String? _error;

  static const _defenses = [
    (
      key: 'promptInjection',
      title: 'Prompt-injection shield',
      desc:
          'Scans every user text field for 12 attack signatures before it can reach Llama.',
      icon: Icons.shield_outlined,
    ),
    (
      key: 'rateLimiting',
      title: 'Rate limiting',
      desc:
          'Per-fingerprint sliding-window budgets on every endpoint (DDoS / quota-burn protection).',
      icon: Icons.speed_outlined,
    ),
    (
      key: 'sanitization',
      title: 'Input sanitization',
      desc:
          'Strips control characters and clamps text length so payloads cannot break prompt framing.',
      icon: Icons.cleaning_services_outlined,
    ),
    (
      key: 'anomalyScan',
      title: 'Anomaly scan',
      desc:
          'Every 30 min: alert floods, malformed records, notification backlogs, auth-failure surges.',
      icon: Icons.radar_outlined,
    ),
    (
      key: 'siemExport',
      title: 'SIEM export',
      desc: 'Ships security events to the external Elastic SOC pipeline.',
      icon: Icons.outbox_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _actionsSub = FirebaseDatabase.instance
        .ref('security/actions')
        .limitToLast(50)
        .onValue
        .listen(
          (event) {
            if (mounted) {
              setState(
                () => _actions = _mapToSortedList(event.snapshot.value, 'at'),
              );
            }
          },
          onError: (e) {
            if (mounted) setState(() => _error = '$e');
          },
        );
    _settingsSub = FirebaseDatabase.instance
        .ref('ai_agents/security/settings')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          if (mounted) {
            setState(
              () => _settings = v is Map
                  ? Map<String, dynamic>.from(v)
                  : const {},
            );
          }
        }, onError: (_) {});
  }

  @override
  void dispose() {
    _actionsSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  bool _defenseOn(String key) => _settings[key] != false;

  Future<void> _setDefense(String key, bool value) async {
    try {
      await FirebaseDatabase.instance
          .ref('ai_agents/security/settings/$key')
          .set(value);
      if (!value && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              context.tr(
                'Defense disabled. The edge worker drops this shield within 60s — re-arm it when done testing.',
              ),
              style: Sa.body(size: 12.5, color: Sa.amber),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              context.tr('Update failed: {error}', {'error': '$e'}),
              style: Sa.body(size: 12.5, color: Sa.red),
            ),
          ),
        );
      }
    }
  }

  Color _kindColor(String kind) {
    if (kind.contains('injection')) return Sa.red;
    if (kind.contains('rate')) return Sa.amber;
    if (kind.contains('flood') || kind.contains('backlog')) return Sa.violet;
    if (kind.contains('auth')) return Sa.pink;
    return Sa.blue;
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final dayAgo = DateTime.now().toUtc().subtract(const Duration(hours: 24));
    final recent = _actions.where((a) {
      final t = DateTime.tryParse((a['at'] ?? '').toString());
      return t != null && t.toUtc().isAfter(dayAgo);
    }).toList();
    final byKind = <String, int>{};
    for (final a in recent) {
      final k = (a['kind'] ?? 'other').toString();
      byKind[k] = (byKind[k] ?? 0) + 1;
    }
    final maxKind = byKind.values.isEmpty ? 0 : byKind.values.reduce(math.max);
    final armed = _defenses.where((d) => _defenseOn(d.key)).length;

    return _AgentScroll(
      children: [
        if (!widget.enabled) _OfflineBanner(spec: spec),
        GlassPanel(
          accent: spec.accent,
          glow: widget.enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: spec.icon,
                title: context.tr('THREAT CONSOLE'),
                subtitle: context.tr(
                  'Standing guard on every worker endpoint. Blocks are logged with the exact signature that fired.',
                ),
                accent: spec.accent,
                trailing: GlowChip(
                  label: context.tr('{armed}/{total} DEFENSES ARMED', {
                    'armed': '$armed',
                    'total': '${_defenses.length}',
                  }),
                  color: armed == _defenses.length ? Sa.green : Sa.amber,
                  pulse: true,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SaStatTile(
                    label: context.tr('Blocks · 24h'),
                    value: '${recent.length}',
                    icon: Icons.block_outlined,
                    color: spec.accent,
                  ),
                  SaStatTile(
                    label: context.tr('Actions · last cron'),
                    value:
                        '${(widget.health?['securityActions'] as num?)?.toInt() ?? 0}',
                    icon: Icons.gpp_maybe_outlined,
                    color: Sa.amber,
                  ),
                  SaStatTile(
                    label: context.tr('Attack signatures'),
                    value: '12',
                    icon: Icons.fingerprint,
                    color: Sa.violet,
                  ),
                  SaStatTile(
                    label: context.tr('Last block'),
                    value: _actions.isEmpty
                        ? '—'
                        : _agoIso(context, _actions.first['at']),
                    icon: Icons.schedule,
                    color: Sa.blue,
                  ),
                ],
              ),
            ],
          ),
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.tune,
                title: context.tr('DEFENSE GRID'),
                subtitle: context.tr(
                  'Arm or stand down individual shields. Changes reach the edge worker within 60 seconds.',
                ),
                accent: spec.accent,
              ),
              const SizedBox(height: 12),
              for (final d in _defenses)
                _SettingTile(
                  title: context.tr(d.title),
                  description: context.tr(d.desc),
                  icon: d.icon,
                  accent: spec.accent,
                  value: _defenseOn(d.key),
                  onChanged: (v) => _setDefense(d.key, v),
                ),
            ],
          ),
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.stacked_bar_chart,
                title: context.tr('THREAT MIX · 24H'),
                subtitle: context.tr('What the sentinel has been deflecting.'),
                accent: spec.accent,
              ),
              const SizedBox(height: 14),
              if (byKind.isEmpty)
                Text(
                  context.tr('Clean skies — no blocks in the last 24 hours.'),
                  style: Sa.body(size: 12, color: Sa.textDim),
                )
              else
                ...byKind.entries.map(
                  (e) => _KindBar(
                    label: e.key,
                    count: e.value,
                    max: maxKind,
                    color: _kindColor(e.key),
                  ),
                ),
            ],
          ),
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.receipt_long_outlined,
                title: context.tr('ENFORCEMENT LOG'),
                subtitle: context.tr(
                  'Every block with endpoint, fingerprint and matched patterns. Tap for the full record.',
                ),
                accent: spec.accent,
              ),
              const SizedBox(height: 12),
              if (_error != null)
                SaEmptyState(
                  icon: Icons.lock_outline,
                  title: context.tr('Cannot read security actions'),
                  message: _error!,
                  accent: Sa.red,
                )
              else if (_actions.isEmpty)
                SaEmptyState(
                  icon: Icons.verified_user_outlined,
                  title: context.tr('No enforcement actions'),
                  message: context.tr(
                    'The sentinel has not needed to block anything yet.',
                  ),
                  accent: Sa.green,
                )
              else
                ..._actions.take(30).map((a) {
                  final kind = (a['kind'] ?? 'action').toString();
                  final fp = (a['fingerprint'] ?? '').toString();
                  return _LogTile(
                    kind: kind,
                    color: _kindColor(kind),
                    title:
                        '${a['endpoint'] ?? '—'} · ${fp.length > 10 ? fp.substring(fp.length - 10) : fp}',
                    at: (a['at'] ?? '').toString(),
                    details: a,
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-05 · PREDICTIVE CORE
// ═══════════════════════════════════════════════════════════════════════════

class _PredictiveAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  const _PredictiveAgentPanel({required this.spec, required this.enabled});

  @override
  State<_PredictiveAgentPanel> createState() => _PredictiveAgentPanelState();
}

class _PredictiveAgentPanelState extends State<_PredictiveAgentPanel> {
  StreamSubscription<DatabaseEvent>? _accSub;
  StreamSubscription<DatabaseEvent>? _histSub;
  StreamSubscription<DatabaseEvent>? _versionSub;
  StreamSubscription<DatabaseEvent>? _forecastSub;
  StreamSubscription<DatabaseEvent>? _settingsSub;

  Map<String, dynamic>? _accuracy;
  List<Map<String, dynamic>> _gradeHistory = const [];
  Map<String, dynamic> _modelMeta = const {};
  Map<String, dynamic>? _liveForecast;
  Map<String, dynamic> _settings = const {};
  int _view = 0; // 0 = model core, 1 = brain

  @override
  void initState() {
    super.initState();
    _accSub = FirebaseDatabase.instance
        .ref('ai_forecast/accuracy/latest')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          if (mounted) {
            setState(
              () => _accuracy = v is Map ? Map<String, dynamic>.from(v) : null,
            );
          }
        }, onError: (_) {});
    _histSub = FirebaseDatabase.instance
        .ref('ai_forecast/accuracy/history')
        .limitToLast(30)
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          final list = <Map<String, dynamic>>[];
          if (v is Map) {
            v.forEach((k, val) {
              if (val is Map) {
                final m = Map<String, dynamic>.from(val);
                m['day'] = k.toString();
                list.add(m);
              }
            });
            list.sort(
              (a, b) => (a['day'] ?? '').toString().compareTo(
                (b['day'] ?? '').toString(),
              ),
            );
          }
          if (mounted) setState(() => _gradeHistory = list);
        }, onError: (_) {});
    // Watch the version only; re-fetch the light metadata children when it
    // bumps (the weights blob never enters this screen).
    _versionSub = FirebaseDatabase.instance
        .ref('ai_forecast/model/version')
        .onValue
        .listen((_) => _loadModelMeta(), onError: (_) {});
    _forecastSub = FirebaseDatabase.instance
        .ref('ai_predictions/forecast')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          if (mounted) {
            setState(
              () => _liveForecast = v is Map
                  ? Map<String, dynamic>.from(v)
                  : null,
            );
          }
        }, onError: (_) {});
    _settingsSub = FirebaseDatabase.instance
        .ref('ai_agents/predictive/settings')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          if (mounted) {
            setState(
              () => _settings = v is Map
                  ? Map<String, dynamic>.from(v)
                  : const {},
            );
          }
        }, onError: (_) {});
  }

  Future<void> _loadModelMeta() async {
    const keys = [
      'version',
      'trainedAt',
      'lastAdaptedAt',
      'datasetName',
      'sampleCount',
      'valLoss',
      'valAccuracy',
      'rounds',
      'adaptedRounds',
      'learning',
      'algo',
    ];
    try {
      final reads = await Future.wait([
        for (final k in keys)
          FirebaseDatabase.instance.ref('ai_forecast/model/$k').get(),
      ]);
      final meta = <String, dynamic>{};
      for (var i = 0; i < keys.length; i++) {
        meta[keys[i]] = reads[i].value;
      }
      if (mounted) setState(() => _modelMeta = meta);
    } catch (_) {}
  }

  Future<void> _setSetting(String key, bool value) async {
    try {
      await FirebaseDatabase.instance
          .ref('ai_agents/predictive/settings/$key')
          .set(value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _accSub?.cancel();
    _histSub?.cancel();
    _versionSub?.cancel();
    _forecastSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final deployed = _modelMeta['trainedAt'] != null;
    final version = (_modelMeta['version'] as num?)?.toInt() ?? 0;
    final adapted = (_modelMeta['adaptedRounds'] as num?)?.toInt() ?? 0;
    final pairs = (_accuracy?['gradedPairs'] as num?)?.toInt() ?? 0;
    final tp = (_accuracy?['tp'] as num?)?.toInt() ?? 0;
    final fp = (_accuracy?['fp'] as num?)?.toInt() ?? 0;
    final fn = (_accuracy?['fn'] as num?)?.toInt() ?? 0;
    final precision = (tp + fp) == 0 ? 0.0 : tp / (tp + fp);
    final recall = (tp + fn) == 0 ? 0.0 : tp / (tp + fn);
    final brier = pairs == 0
        ? 0.0
        : ((_accuracy?['brierSum'] as num?)?.toDouble() ?? 0) / pairs;
    final machines = (_liveForecast?['machineCount'] as num?)?.toInt() ?? 0;

    return _AgentScroll(
      children: [
        if (!widget.enabled) _OfflineBanner(spec: spec),
        _SegTabs(
          tabs: [context.tr('MODEL CORE'), context.tr('BRAIN')],
          icons: const [Icons.dashboard_customize_outlined, Icons.psychology],
          index: _view,
          accent: spec.accent,
          onChanged: (i) => setState(() => _view = i),
        ),
        if (_view == 1)
          _PredictiveBrainView(
            modelMeta: _modelMeta,
            accuracy: _accuracy,
            gradeHistory: _gradeHistory,
            liveForecast: _liveForecast,
            accent: spec.accent,
            enabled: widget.enabled,
          ),
        if (_view == 0)
          GlassPanel(
            accent: spec.accent,
            glow: widget.enabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: spec.icon,
                  leading: _AgentGlyph(spec: spec, size: 36, radius: 10),
                  title: context.tr('MODEL CORE'),
                  subtitle: deployed
                      ? context.tr(
                          'On-device gradient-boosted forecaster, live on every Production Manager dashboard.',
                        )
                      : context.tr(
                          'No model deployed yet — train one in the AI Training tab.',
                        ),
                  accent: spec.accent,
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      GlowChip(
                        label: 'SIA-GBDT v$version',
                        color: spec.accent,
                        icon: Icons.account_tree_outlined,
                      ),
                      if (_modelMeta['learning'] == true)
                        GlowChip(
                          label: context.tr('LEARNING ✓'),
                          color: Sa.green,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SaStatTile(
                      label: context.tr('Dataset'),
                      value: (_modelMeta['datasetName'] ?? '—').toString(),
                      icon: Icons.dataset_outlined,
                      color: spec.accent,
                    ),
                    SaStatTile(
                      label: context.tr('Training samples'),
                      value:
                          '${(_modelMeta['sampleCount'] as num?)?.toInt() ?? 0}',
                      icon: Icons.grain,
                      color: Sa.blue,
                    ),
                    SaStatTile(
                      label: context.tr('Boosted rounds'),
                      value: context.tr('{rounds} + {adapted} adapted', {
                        'rounds':
                            '${(_modelMeta['rounds'] as num?)?.toInt() ?? 0}',
                        'adapted': '$adapted',
                      }),
                      icon: Icons.forest_outlined,
                      color: Sa.green,
                    ),
                    SaStatTile(
                      label: context.tr('Val accuracy'),
                      value:
                          '${(((_modelMeta['valAccuracy'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%',
                      icon: Icons.verified_outlined,
                      color: Sa.violet,
                    ),
                    SaStatTile(
                      label: context.tr('Machines forecast'),
                      value: '$machines',
                      icon: Icons.precision_manufacturing_outlined,
                      color: Sa.amber,
                    ),
                    SaStatTile(
                      label: context.tr('Trained'),
                      value: _agoIso(context, _modelMeta['trainedAt']),
                      icon: Icons.schedule,
                      color: Sa.muted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_view == 0)
          GlassPanel(
            accent: spec.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: Icons.psychology_outlined,
                  title: context.tr('CONTINUOUS LEARNING'),
                  subtitle: context.tr(
                    'The core snapshots tomorrow’s forecast daily, grades itself against the alerts that really happened, and boosts adaptation trees on fresh data.',
                  ),
                  accent: spec.accent,
                  trailing: GlowChip(
                    label: _accuracy == null
                        ? context.tr('AWAITING FIRST GRADE')
                        : context.tr('{count} DAYS GRADED', {
                            'count':
                                '${(_accuracy?['gradedDays'] as num?)?.toInt() ?? 0}',
                          }),
                    color: _accuracy == null ? Sa.muted : Sa.green,
                    pulse: _accuracy != null,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (ctx, c) {
                    final wide = c.maxWidth >= 760;
                    final gauges = Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RingGauge(
                          label: context.tr('PRECISION'),
                          value: precision,
                          color: spec.accent,
                        ),
                        _RingGauge(
                          label: context.tr('RECALL'),
                          value: recall,
                          color: Sa.cyan,
                        ),
                        _RingGauge(
                          label: context.tr('BRIER'),
                          value: (1 - brier).clamp(0.0, 1.0),
                          display: brier.toStringAsFixed(3),
                          color: Sa.green,
                        ),
                      ],
                    );
                    final chart = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(
                            'FORECAST QUALITY TREND · BRIER PER GRADED DAY',
                          ),
                          style: Sa.mono(size: 8.5, color: Sa.muted),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 110,
                          child: _gradeHistory.isEmpty
                              ? Center(
                                  child: Text(
                                    context.tr(
                                      'Trend appears after the first graded day.',
                                    ),
                                    style: Sa.body(size: 11, color: Sa.muted),
                                  ),
                                )
                              : CustomPaint(
                                  size: Size.infinite,
                                  painter: _BrierTrendPainter(
                                    history: _gradeHistory,
                                    color: spec.accent,
                                    gridColor: Sa.border,
                                    textColor: Sa.muted,
                                  ),
                                ),
                        ),
                      ],
                    );
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 330, child: gauges),
                          const SizedBox(width: 20),
                          Expanded(child: chart),
                        ],
                      );
                    }
                    return Column(
                      children: [gauges, const SizedBox(height: 16), chart],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          context.tr('DATA ABSORPTION · ADAPTATION BUDGET'),
                          style: Sa.mono(size: 8.5, color: Sa.muted),
                        ),
                        const Spacer(),
                        Text(
                          context.tr('{adapted} / 60 extra trees per type', {
                            'adapted': '$adapted',
                          }),
                          style: Sa.mono(size: 9.5, color: spec.accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: SizedBox(
                        height: 8,
                        child: Stack(
                          children: [
                            Container(color: Sa.border.withValues(alpha: 0.5)),
                            FractionallySizedBox(
                              widthFactor: (adapted / 60).clamp(0.0, 1.0),
                              alignment: Alignment.centerLeft,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [spec.accent, Sa.cyan],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr(
                        'Graded {pairs} machine-type pairs · {hits} confirmed hits · last adapted {time} · a full retrain resets the budget.',
                        {
                          'pairs': '$pairs',
                          'hits': '$tp',
                          'time': _agoIso(context, _modelMeta['lastAdaptedAt']),
                        },
                      ),
                      style: Sa.body(size: 10.5, color: Sa.textDim),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_view == 0)
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: Icons.tune,
                  title: context.tr('LEARNING CONTROLS'),
                  subtitle: context.tr(
                    'Pause parts of the learning loop without undeploying the model.',
                  ),
                  accent: spec.accent,
                ),
                const SizedBox(height: 12),
                _SettingTile(
                  title: context.tr('Continuous adaptation'),
                  description: context.tr(
                    'Boost a few stiffly-regularized trees onto the live ensemble (~daily) from recent production alerts.',
                  ),
                  icon: Icons.auto_mode,
                  accent: spec.accent,
                  value: _settings['adaptationEnabled'] != false,
                  onChanged: (v) => _setSetting('adaptationEnabled', v),
                ),
                _SettingTile(
                  title: context.tr('Outcome grading'),
                  description: context.tr(
                    'Snapshot tomorrow’s forecast each day and grade it against reality (precision/recall/Brier above).',
                  ),
                  icon: Icons.fact_check_outlined,
                  accent: spec.accent,
                  value: _settings['outcomeGrading'] != false,
                  onChanged: (v) => _setSetting('outcomeGrading', v),
                ),
              ],
            ),
          ),
        if (_view == 0)
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: Icons.receipt_long_outlined,
                  title: context.tr('GRADED DAYS'),
                  subtitle: context.tr(
                    'Each elapsed forecast day, scored against the alerts that materialized.',
                  ),
                  accent: spec.accent,
                ),
                const SizedBox(height: 12),
                if (_gradeHistory.isEmpty)
                  SaEmptyState(
                    icon: Icons.pending_actions_outlined,
                    title: context.tr('No graded days yet'),
                    message: context.tr(
                      'The first grade lands the day after a forecast snapshot — fully automatic, server-side.',
                    ),
                    accent: spec.accent,
                  )
                else
                  ..._gradeHistory.reversed
                      .take(20)
                      .map(
                        (g) => _LogTile(
                          kind: 'graded',
                          color: spec.accent,
                          title: context.tr(
                            '{day} · {pairs} pairs · {hits} hits · Brier {brier}',
                            {
                              'day': '${g['day']}',
                              'pairs': '${g['pairs'] ?? 0}',
                              'hits': '${g['tp'] ?? 0}',
                              'brier': ((g['brier'] as num?)?.toDouble() ?? 0)
                                  .toStringAsFixed(3),
                            },
                          ),
                          at: (g['gradedAt'] ?? '').toString(),
                          details: g,
                        ),
                      ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// PREDICTIVE CORE · BRAIN — a 3D neural mesh of the GBDT forecaster.
// ─────────────────────────────────────────────────────────────────────────

/// One engineered feature family the forecaster scores on.
class _Signal {
  final String label;
  final String desc;
  final double weight;
  final Color color;
  const _Signal(this.label, this.desc, this.weight, this.color);
}

const List<_Signal> _kForecastSignals = [
  _Signal(
    'Recent alert rate',
    'Yesterday & the day before (lags t-1, t-2).',
    0.92,
    Color(0xFF378ADD),
  ),
  _Signal(
    '7-day rolling counts',
    'Per-type frequency over the last week.',
    0.85,
    Color(0xFF7F77DD),
  ),
  _Signal(
    '7 / 14-day totals',
    'Short vs medium-term load.',
    0.70,
    Color(0xFF1D9E75),
  ),
  _Signal(
    'Week-over-week trend',
    'Is this machine heating up or cooling down?',
    0.78,
    Color(0xFFBA7517),
  ),
  _Signal(
    'Per-type recency',
    'Days since each type last fired (capped 30).',
    0.66,
    Color(0xFFD4537E),
  ),
  _Signal(
    'Critical pressure',
    'Weight of recent critical alerts.',
    0.60,
    Color(0xFFE24B4A),
  ),
  _Signal(
    'Calendar context',
    'Day-of-week / tomorrow seasonality.',
    0.42,
    Color(0xFF534AB7),
  ),
  _Signal(
    "Today's snapshot",
    'The machine state the forecast starts from.',
    0.55,
    Color(0xFF2AA7A0),
  ),
];

/// The Predictive Core BRAIN sub-view: 3D mesh, anatomy, signals, self-grading.
class _PredictiveBrainView extends StatelessWidget {
  final Map<String, dynamic> modelMeta;
  final Map<String, dynamic>? accuracy;
  final List<Map<String, dynamic>> gradeHistory;
  final Map<String, dynamic>? liveForecast;
  final Color accent;
  final bool enabled;
  const _PredictiveBrainView({
    required this.modelMeta,
    required this.accuracy,
    required this.gradeHistory,
    required this.liveForecast,
    required this.accent,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final deployed = modelMeta['trainedAt'] != null;
    final version = (modelMeta['version'] as num?)?.toInt() ?? 0;
    final rounds = (modelMeta['rounds'] as num?)?.toInt() ?? 0;
    final adapted = (modelMeta['adaptedRounds'] as num?)?.toInt() ?? 0;
    final samples = (modelMeta['sampleCount'] as num?)?.toInt() ?? 0;
    final valAcc = ((modelMeta['valAccuracy'] as num?)?.toDouble() ?? 0) * 100;
    final pairs = (accuracy?['gradedPairs'] as num?)?.toInt() ?? 0;
    final tp = (accuracy?['tp'] as num?)?.toInt() ?? 0;
    final fp = (accuracy?['fp'] as num?)?.toInt() ?? 0;
    final fn = (accuracy?['fn'] as num?)?.toInt() ?? 0;
    final precision = (tp + fp) == 0 ? 0.0 : tp / (tp + fp);
    final recall = (tp + fn) == 0 ? 0.0 : tp / (tp + fn);
    final brier = pairs == 0
        ? 0.0
        : ((accuracy?['brierSum'] as num?)?.toDouble() ?? 0) / pairs;
    final gradedDays = (accuracy?['gradedDays'] as num?)?.toInt() ?? 0;
    final machines = (liveForecast?['machineCount'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          accent: accent,
          glow: enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.psychology,
                title: context.tr('INSIDE THE FORECASTER’S MIND'),
                subtitle: deployed
                    ? context.tr(
                        'A gradient-boosted ensemble — hundreds of decision trees, rendered as one rotating neural mesh.',
                      )
                    : context.tr(
                        'No model deployed yet — train one in the AI Training tab to wake the mind.',
                      ),
                accent: accent,
                trailing: GlowChip(
                  label: 'SIA-GBDT v$version',
                  color: accent,
                  icon: Icons.account_tree_outlined,
                  pulse: enabled && deployed,
                ),
              ),
              const SizedBox(height: 10),
              _CortexHero(
                accent: accent,
                animate: enabled && deployed,
                inputs: [
                  for (final s in _kForecastSignals)
                    _CortexInput(
                      s.label,
                      s.color,
                      s.weight,
                      deployed ? s.weight : 0.15,
                    ),
                ],
                inHeader: 'SIGNALS IT READS',
                coreTop: 'GBDT',
                coreBottom: deployed ? 'FORECASTS' : 'IDLE',
                outIcon: Icons.online_prediction,
                outTop: 'Tomorrow’s',
                outBottom: 'risk · 24h',
                outColor: accent,
              ),
              const SizedBox(height: 8),
              Text(
                deployed
                    ? context.tr(
                        'It studies the last weeks of alerts, learns which machines tend to fail and when, then forecasts each machine’s risk for the next 24 hours — a weather forecast for the factory ({machines} machines covered).',
                        {'machines': '$machines'},
                      )
                    : context.tr(
                        'Once a model is trained, it forecasts each machine’s risk for the next 24 hours — like a weather forecast for the factory.',
                      ),
                style: Sa.body(size: 11.5, color: Sa.textDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.account_tree,
                title: context.tr('MODEL ANATOMY'),
                subtitle: context.tr(
                  'Four boosted ensembles — one prediction head per alert type.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SaStatTile(
                    label: context.tr('Boosted rounds'),
                    value: '$rounds',
                    icon: Icons.forest_outlined,
                    color: accent,
                  ),
                  SaStatTile(
                    label: context.tr('Adapted trees'),
                    value: '$adapted',
                    icon: Icons.auto_mode,
                    color: Sa.green,
                  ),
                  SaStatTile(
                    label: context.tr('Training samples'),
                    value: '$samples',
                    icon: Icons.grain,
                    color: Sa.blue,
                  ),
                  SaStatTile(
                    label: context.tr('Val accuracy'),
                    value: '${valAcc.toStringAsFixed(1)}%',
                    icon: Icons.verified_outlined,
                    color: Sa.violet,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TypeHeadChip(label: context.tr('Quality')),
                  _TypeHeadChip(label: context.tr('Maintenance')),
                  _TypeHeadChip(label: context.tr('Damaged Product')),
                  _TypeHeadChip(label: context.tr('Resource Deficiency')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.sensors,
                title: context.tr('SIGNALS IT READS'),
                subtitle: context.tr(
                  'The engineered features each machine-day is scored on.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 12),
              for (final s in _kForecastSignals) _SignalBar(s: s),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.fact_check_outlined,
                title: context.tr('SELF-ASSESSMENT'),
                subtitle: context.tr(
                  'How the model grades its own forecasts against reality.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 14),
              if (accuracy == null)
                SaEmptyState(
                  icon: Icons.pending_actions_outlined,
                  title: context.tr('No grades yet'),
                  message: context.tr(
                    'The first self-grade lands the day after a forecast snapshot — fully automatic.',
                  ),
                  accent: accent,
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SaStatTile(
                      label: context.tr('Precision'),
                      value: '${(precision * 100).round()}%',
                      icon: Icons.center_focus_strong,
                      color: accent,
                    ),
                    SaStatTile(
                      label: context.tr('Recall'),
                      value: '${(recall * 100).round()}%',
                      icon: Icons.radar,
                      color: Sa.cyan,
                    ),
                    SaStatTile(
                      label: context.tr('Brier score'),
                      value: brier.toStringAsFixed(3),
                      icon: Icons.show_chart,
                      color: Sa.green,
                    ),
                    SaStatTile(
                      label: context.tr('Days graded'),
                      value: '$gradedDays',
                      icon: Icons.event_available,
                      color: Sa.amber,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One alert-type prediction head chip.
class _TypeHeadChip extends StatelessWidget {
  final String label;
  const _TypeHeadChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Sa.panelSolid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree_outlined, size: 14, color: Sa.muted),
          const SizedBox(width: 8),
          Text(label, style: Sa.body(size: 12, color: Sa.text)),
          const SizedBox(width: 8),
          Text(context.tr('ensemble'), style: Sa.mono(size: 8.5, color: Sa.muted)),
        ],
      ),
    );
  }
}

/// Feature-influence bar (illustrative weighting).
class _SignalBar extends StatelessWidget {
  final _Signal s;
  const _SignalBar({required this.s});

  @override
  Widget build(BuildContext context) {
    final influence = s.weight.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: s.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr(s.label),
                  style: Sa.body(size: 13, color: Sa.text),
                ),
              ),
              Text(
                '${(influence * 100).round()}%',
                style: Sa.mono(size: 10.5, color: Sa.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(
              context.tr(s.desc),
              style: Sa.body(size: 11, color: Sa.textDim),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: LayoutBuilder(
              builder: (ctx, cons) => Container(
                height: 7,
                width: double.infinity,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Sa.panelSolid,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Container(
                  height: 7,
                  width: cons.maxWidth * influence,
                  decoration: BoxDecoration(
                    color: s.color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular gauge with a sweeping arc — precision/recall/Brier display.
class _RingGauge extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final String? display;

  const _RingGauge({
    required this.label,
    required this.value,
    required this.color,
    this.display,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 84,
          height: 84,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CustomPaint(
              painter: _RingPainter(value: v, color: color, track: Sa.border),
              child: Center(
                child: Text(
                  display ?? '${(v * 100).round()}%',
                  style: Sa.mono(size: 13, weight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Sa.mono(size: 8.5, color: Sa.muted)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  _RingPainter({required this.value, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = track.withValues(alpha: 0.6);
    canvas.drawCircle(c, r, base);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [color.withValues(alpha: 0.5), color],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      arc,
    );
    canvas.drawCircle(
      c,
      r + 4,
      Paint()..color = color.withValues(alpha: 0.06 * value),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}

/// Brier-per-day trend: line + soft area + hit markers. Lower is better.
class _BrierTrendPainter extends CustomPainter {
  final List<Map<String, dynamic>> history;
  final Color color;
  final Color gridColor;
  final Color textColor;

  _BrierTrendPainter({
    required this.history,
    required this.color,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    final briers = [
      for (final h in history) ((h['brier'] as num?)?.toDouble() ?? 0),
    ];
    var maxB = briers.reduce(math.max);
    if (maxB <= 0) maxB = 0.1;
    maxB *= 1.2;

    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.45)
      ..strokeWidth = 0.7;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    Offset pt(int i) {
      final x = history.length == 1
          ? size.width / 2
          : size.width * i / (history.length - 1);
      final y = size.height * (1 - (briers[i] / maxB).clamp(0.0, 1.0));
      return Offset(x, y);
    }

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    final area = Path()..moveTo(pt(0).dx, size.height);
    area.lineTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < history.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
      area.lineTo(pt(i).dx, pt(i).dy);
    }
    area.lineTo(pt(history.length - 1).dx, size.height);
    area.close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    for (var i = 0; i < history.length; i++) {
      canvas.drawCircle(pt(i), 2.4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _BrierTrendPainter old) =>
      old.history != history || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-06 · GUARDIAN
// ═══════════════════════════════════════════════════════════════════════════

class _GuardianAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  const _GuardianAgentPanel({required this.spec});

  @override
  State<_GuardianAgentPanel> createState() => _GuardianAgentPanelState();
}

class _GuardianAgentPanelState extends State<_GuardianAgentPanel> {
  // The GitHub proxy worker URL + shared secret come from build-time config so
  // the live Actions/PR subtabs work in CI builds without per-widget defines.
  static const _ghUrl = AppConfig.githubWorkerBase;
  static const _wSecret = AppConfig.workerSharedSecret;

  final _cfg = FirebaseDatabase.instance.ref('ai_agents/guardian');
  final _sec = FirebaseDatabase.instance.ref('ai_agent_secrets/guardian');

  static const _gGreen = Color(0xFF3FB950);
  static const _gRed = Color(0xFFF85149);
  static const _gAmber = Color(0xFFD29922);
  static const _gPurple = Color(0xFFA371F7);

  Map<dynamic, dynamic> _secrets = {};
  Offset _simOffset = const Offset(10, 96);
  bool _deployAuto = false;
  Timer? _simTimer;
  int _subtab = 0; // 0 = Control · 1 = Actions · 2 = Pull requests

  // Live GitHub engine: drives the 3D pipeline + terminal + connection badge.
  late final GuardianLiveTracker _tracker = GuardianLiveTracker(
    baseUrl: _ghUrl,
    secret: _wSecret,
  );

  // One-shot "verify connection" affordance state.
  bool _verifying = false;
  bool? _verifyOk;
  String _verifyMsg = '';

  @override
  void initState() {
    super.initState();
    _tracker.start();
    _sec.get().then((s) {
      if (mounted && s.value is Map)
        setState(() => _secrets = s.value as Map<dynamic, dynamic>);
    });
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _tracker.dispose();
    super.dispose();
  }

  bool _hasSecret(String k) => (_secrets[k]?.toString() ?? '').isNotEmpty;
  String _ts() => DateTime.now().toIso8601String().substring(11, 19);

  bool _githubLatched(Map cfg) {
    if (cfg['githubConnected'] != true) return false;
    final repo = GithubService.normalizeRepo((cfg['repo'] ?? '').toString());
    final verifiedRepo = GithubService.normalizeRepo(
      (cfg['githubVerifiedRepo'] ?? '').toString(),
    );
    return repo.isNotEmpty && (verifiedRepo.isEmpty || verifiedRepo == repo);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: _cfg.onValue,
      builder: (context, snap) {
        final raw = snap.data?.snapshot.value;
        final cfg = (raw is Map) ? raw : const {};
        final settings = (cfg['settings'] is Map)
            ? cfg['settings'] as Map
            : const {};
        final enabled = cfg['enabled'] != false;
        final repo = GithubService.normalizeRepo(
          (cfg['repo'] ?? '').toString(),
        );
        final githubLatched = _githubLatched(cfg);
        if (raw is Map) _tracker.setRepo(repo);
        _deployAuto = (settings['deployMode'] ?? 'human') == 'auto';
        _tracker.mode = _deployAuto ? 'auto' : 'human';
        return LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight.isFinite ? c.maxHeight : 1600.0;
            return SizedBox(
              height: h,
              child: Column(
                children: [
                  _subtabBar(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: IndexedStack(
                      index: _subtab,
                      children: [
                        _controlBody(cfg, settings, enabled),
                        GuardianActionsView(
                          baseUrl: _ghUrl,
                          sharedSecret: _wSecret,
                          repo: repo,
                          connectionLatched: githubLatched,
                        ),
                        GuardianPullsView(
                          baseUrl: _ghUrl,
                          sharedSecret: _wSecret,
                          repo: repo,
                          connectionLatched: githubLatched,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Subtab selector: Control · Actions · Pull requests. The two GitHub subtabs
  /// render in authentic GitHub styling inside [GuardianActionsView] /
  /// [GuardianPullsView]; this bar stays in the command-center theme.
  Widget _subtabBar() {
    const items = [
      (i: 0, label: 'CONTROL', icon: Icons.tune),
      (i: 1, label: 'ACTIONS', icon: Icons.sync_alt),
      (i: 2, label: 'PULL REQUESTS', icon: Icons.merge_type),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _subtab = it.i),
                borderRadius: BorderRadius.circular(9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _subtab == it.i
                        ? widget.spec.accent.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: _subtab == it.i
                          ? widget.spec.accent.withValues(alpha: 0.5)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        it.icon,
                        size: 15,
                        color: _subtab == it.i ? widget.spec.accent : Sa.muted,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          context.tr(it.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Sa.body(
                            size: 11.5,
                            color: _subtab == it.i
                                ? widget.spec.accent
                                : Sa.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The Control subtab: header + live pipeline + terminal + AI/GitHub config.
  Widget _controlBody(Map cfg, Map settings, bool enabled) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      // Rebuild on every live-tracker tick so the pipeline, terminal and the
      // GitHub connection badge stay in lock-step with the real workflow run.
      child: ListenableBuilder(
        listenable: _tracker,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(enabled, settings),
            const SizedBox(height: 14),
            _livePipeline(settings, cfg),
            const SizedBox(height: 14),
            _liveTerminal(),
            const SizedBox(height: 14),
            _aiConfig(settings),
            const SizedBox(height: 14),
            _github(cfg),
            const SizedBox(height: 14),
            _knowledge(cfg),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  // Legacy drill helper, kept private and unreachable from the UI.
  // ignore: unused_element
  Widget _simToolbar() {
    final sims = <List<dynamic>>[
      [
        'Login error',
        Icons.login,
        'high',
        'login screen error — users cannot sign in',
        'claude-opus-4-8',
      ],
      [
        'Notifications',
        Icons.notifications_off,
        'high',
        'alerts not reaching supervisors',
        'claude-opus-4-8',
      ],
      [
        'Worker fail',
        Icons.dns,
        'high',
        'cloudflare worker endpoint failing',
        'claude-opus-4-8',
      ],
      [
        'Version',
        Icons.sync_problem,
        'medium',
        'dependency version mismatch breaks build',
        'claude-sonnet-4-6',
      ],
      [
        'Tab broken',
        Icons.tab_unselected,
        'medium',
        'supervisor tab blank / not loading',
        'claude-sonnet-4-6',
      ],
      [
        'Test fail',
        Icons.science,
        'low',
        'flutter test failing on a widget test',
        'claude-haiku-4-5',
      ],
    ];
    return Container(
      width: 166,
      decoration: BoxDecoration(
        color: Sa.panelSolid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.borderBright),
        boxShadow: [
          BoxShadow(
            color: Sa.shadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onPanUpdate: (d) => setState(() => _simOffset += d.delta),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: widget.spec.accent.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.drag_indicator, size: 15, color: Sa.muted),
                  const SizedBox(width: 5),
                  Text('', style: Sa.body(size: 10.5, color: Sa.textDim)),
                ],
              ),
            ),
          ),
          for (final s in sims)
            InkWell(
              onTap: () => _simulateIncident(
                s[0] as String,
                s[2] as String,
                s[3] as String,
                s[4] as String,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      s[1] as IconData,
                      size: 14,
                      color: s[2] == 'high'
                          ? _gRed
                          : (s[2] == 'medium' ? _gAmber : Sa.muted),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s[0] as String,
                      style: Sa.body(size: 12, color: Sa.text),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── header ──
  Widget _header(bool enabled, Map settings) {
    return GlassPanel(
      accent: widget.spec.accent,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: _AgentGlyph(spec: widget.spec, size: 40, radius: 11),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('GUARDIAN'), style: Sa.display(size: 17)),
                Text(
                  context.tr('autonomous fix pipeline'),
                  style: Sa.body(size: 12, color: Sa.muted),
                ),
              ],
            ),
          ),
          _deployToggle(
            context.tr('Automatic'),
            _deployAuto,
            _confirmAutomaticMode,
          ),
          const SizedBox(width: 6),
          _deployToggle(
            context.tr('Human review'),
            !_deployAuto,
            () => _saveSetting('deployMode', 'human'),
          ),
          const SizedBox(width: 12),
          GlowChip(
            label: enabled ? context.tr('ARMED') : context.tr('OFF'),
            color: enabled ? _gGreen : Sa.muted,
            pulse: enabled,
          ),
          Switch(value: enabled, onChanged: (v) => _cfg.update({'enabled': v})),
        ],
      ),
    );
  }

  Widget _deployToggle(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? widget.spec.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? widget.spec.accent.withValues(alpha: 0.5)
                : Sa.border,
          ),
        ),
        child: Text(
          label,
          style: Sa.body(
            size: 11.5,
            color: active ? widget.spec.accent : Sa.textDim,
          ),
        ),
      ),
    );
  }

  // ── live 3D pipeline (driven by the real GitHub run) ──
  Widget _livePipeline(Map settings, Map cfg) {
    final liveConnected = _tracker.connected;
    final connected = liveConnected || _githubLatched(cfg);
    final nodes = liveConnected
        ? _tracker.nodes
        : computePipelineNodes(
            connected: connected,
            frontier: 0,
            failPhase: -1,
            done: false,
            running: false,
            idleArmed: connected,
            mode: 'human',
          );
    return GuardianPipeline(
      nodes: nodes,
      connected: connected,
      statusLabel: liveConnected
          ? _tracker.stageLabel
          : connected
          ? context.tr('Connected - waiting for live sync')
          : _tracker.stageLabel,
      failed: liveConnected && _tracker.failed,
      running: liveConnected && _tracker.running,
      fixAiLabel: _aiSchemaLabel(settings, 'fix'),
      reviewAiLabel: _aiSchemaLabel(settings, 'review'),
    );
  }

  // ── live terminal (real job/step + raw stdout, or offline preview) ──
  Widget _liveTerminal() {
    return GuardianTerminal(tracker: _tracker);
  }

  String _aiSchemaLabel(Map settings, String role) {
    final provId =
        (settings['${role}Provider'] ??
                (role == 'fix' ? 'anthropic' : 'openai'))
            .toString();
    final prov = _Providers.list.firstWhere(
      (p) => p.id == provId,
      orElse: () => _Providers.list.first,
    );
    final model = (settings['${role}Model'] ?? prov.defaultModel).toString();
    return model.isEmpty ? prov.name : '${prov.name} - $model';
  }

  // ── AI config ──
  Widget _aiConfig(Map settings) {
    final auto = settings['autoModelSelect'] != false;
    return _panel(
      context.tr('AI CONFIGURATION'),
      Icons.memory,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _aiCard(context.tr('Fix AI'), 'fix', settings, Sa.blue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _aiCard(
                  context.tr('Review AI'),
                  'review',
                  settings,
                  _gPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                context.tr('Auto-select model by severity'),
                style: Sa.body(size: 12, color: Sa.textDim),
              ),
              const Spacer(),
              Switch(
                value: auto,
                onChanged: (v) => _saveSetting('autoModelSelect', v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aiCard(String title, String role, Map settings, Color accent) {
    final provId =
        (settings['${role}Provider'] ??
                (role == 'fix' ? 'anthropic' : 'openai'))
            .toString();
    final prov = _Providers.list.firstWhere(
      (p) => p.id == provId,
      orElse: () => _Providers.list.first,
    );
    final model = (settings['${role}Model'] ?? prov.defaultModel).toString();
    final keySet = _hasSecret('${role}ApiKey');
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Sa.bgRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Sa.body(size: 12.5, color: accent)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _pickProvider(role, settings),
            child: _fieldRow(Icons.expand_more, '${prov.name} · $model'),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _setSecret(
              '${role}ApiKey',
              context.tr('{title} API key', {'title': title}),
              prov.tokenHint,
            ),
            child: _fieldRow(
              Icons.key,
              keySet ? context.tr('•••••••• set') : context.tr('set API key'),
              trailing: keySet
                  ? Icon(Icons.check, size: 14, color: _gGreen)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(IconData ic, String text, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Sa.bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          Icon(ic, size: 14, color: Sa.muted),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: Sa.body(size: 12, color: Sa.text),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ── github connection ──
  Widget _github(Map cfg) {
    final repo = GithubService.normalizeRepo((cfg['repo'] ?? '').toString());
    return GlassPanel(
      accent: widget.spec.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, size: 14, color: Sa.muted),
              const SizedBox(width: 7),
              Text(
                context.tr('GITHUB CONNECTION'),
                style: Sa.body(size: 11, color: Sa.muted),
              ),
              const Spacer(),
              _connBadge(cfg),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _setRepo(repo),
                  child: _fieldRow(
                    Icons.account_tree,
                    repo.isEmpty
                        ? context.tr('link repository (owner/name)')
                        : repo,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _setSecret(
                    'githubToken',
                    context.tr('GitHub token'),
                    'github_pat_…',
                  ),
                  child: _fieldRow(
                    Icons.vpn_key,
                    _hasSecret('githubToken')
                        ? context.tr('•••••••• set')
                        : context.tr('set token'),
                    trailing: _hasSecret('githubToken')
                        ? Icon(Icons.check, size: 14, color: _gGreen)
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _verifyRow(repo),
        ],
      ),
    );
  }

  /// Live "Connected / Not connected" badge — fed by the same tracker that polls
  /// the proxy worker's /config, so it flips the moment the worker can reach the repo.
  Widget _connBadge(Map cfg) {
    final ok = _tracker.connected || _githubLatched(cfg);
    final c = ok ? _gGreen : _gRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            ok ? context.tr('Connected') : context.tr('Not connected'),
            style: Sa.body(size: 11, color: c),
          ),
        ],
      ),
    );
  }

  /// Verify button + animated result line: spinner → green check / red cross.
  Widget _verifyRow(String repo) {
    return Row(
      children: [
        SaButton(
          label: _verifying
              ? context.tr('Verifying…')
              : context.tr('Verify connection'),
          icon: Icons.wifi_tethering,
          outlined: true,
          onPressed: () {
            if (!_verifying) _verifyConnection(repo);
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(
                sizeFactor: anim,
                axis: Axis.horizontal,
                child: child,
              ),
            ),
            child: _verifyStatus(),
          ),
        ),
      ],
    );
  }

  Widget _verifyStatus() {
    if (_verifying) {
      return Row(
        key: const ValueKey('verifying'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: _gAmber),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              context.tr('contacting GitHub…'),
              overflow: TextOverflow.ellipsis,
              style: Sa.body(size: 11.5, color: Sa.textDim),
            ),
          ),
        ],
      );
    }
    if (_verifyOk == null) return const SizedBox.shrink();
    final ok = _verifyOk!;
    final c = ok ? _gGreen : _gRed;
    return Row(
      key: ValueKey('result_$ok'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ok ? Icons.check_circle : Icons.error, size: 15, color: c),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _verifyMsg,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: Sa.body(size: 11.5, color: c),
          ),
        ),
      ],
    );
  }

  Future<void> _verifyConnection(String repo) async {
    setState(() {
      _verifying = true;
      _verifyOk = null;
      _verifyMsg = '';
    });
    final svc = GithubService(
      baseUrl: _ghUrl,
      sharedSecret: _wSecret,
      repo: repo,
    );
    ({bool ok, String repo, int runs, String message}) r;
    try {
      r = await svc.verify();
    } catch (error) {
      r = (
        ok: false,
        repo: '',
        runs: 0,
        message: context.tr(
          'Guardian proxy check failed before credentials were verified: {error}',
          {'error': '$error'},
        ),
      );
    } finally {
      svc.close();
    }
    if (!mounted) return;
    final verifiedRepo = GithubService.normalizeRepo(
      r.repo.isNotEmpty ? r.repo : repo,
    );
    if (r.ok) {
      final now = DateTime.now().toUtc().toIso8601String();
      await _cfg.update({
        if (verifiedRepo.isNotEmpty) 'repo': verifiedRepo,
        'githubConnected': true,
        'githubVerifiedAt': now,
        'githubVerifiedRepo': verifiedRepo,
        'githubConnectionMessage': r.message,
      });
      _tracker.rememberConnected(verifiedRepo);
    }
    setState(() {
      _verifying = false;
      _verifyOk = r.ok;
      _verifyMsg = r.message;
    });
    _tracker.refreshNow();
  }

  /// Guard rail: switching from human review to fully-automatic deploy ships AI
  /// fixes to production with no person in the loop, so confirm it deliberately.
  Future<void> _confirmAutomaticMode() async {
    if (_deployAuto) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _AutomaticModeWarningDialog(),
    );
    if (ok == true) {
      await _saveSetting('deployMode', 'auto');
      _tracker.mode = 'auto';
    }
  }

  // ── knowledge ──
  Widget _knowledge(Map cfg) {
    List<String> listOf(String k) {
      final v = cfg[k];
      if (v is List)
        return v
            .map(
              (e) => e is Map ? (e['name'] ?? 'file').toString() : e.toString(),
            )
            .toList();
      return const [];
    }

    return _panel(
      context.tr('KNOWLEDGE · upload .md'),
      Icons.menu_book_outlined,
      Row(
        children: [
          Expanded(
            child: _mdColumn(
              context.tr('Instructions'),
              'instructions',
              listOf('instructions'),
              Sa.blue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _mdColumn(
              context.tr('Skills'),
              'skills',
              listOf('skills'),
              _gGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mdColumn(String title, String key, List<String> files, Color accent) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Sa.bgRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: Sa.body(size: 12.5, color: accent)),
              const Spacer(),
              Text(
                '${files.length}',
                style: Sa.body(size: 11, color: Sa.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < files.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 13, color: Sa.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      files[i],
                      overflow: TextOverflow.ellipsis,
                      style: Sa.body(size: 11.5, color: Sa.textDim),
                    ),
                  ),
                  InkWell(
                    onTap: () => _deleteMd(key, i),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.delete_outline, size: 15, color: _gRed),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          SaButton(
            label: context.tr('Upload .md'),
            icon: Icons.upload_file,
            outlined: true,
            onPressed: () => _uploadMd(key),
          ),
        ],
      ),
    );
  }

  // ── helpers ──
  Widget _panel(String label, IconData ic, Widget child) {
    return GlassPanel(
      accent: widget.spec.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ic, size: 14, color: Sa.muted),
              const SizedBox(width: 7),
              Text(label, style: Sa.body(size: 11, color: Sa.muted)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Future<void> _saveSetting(String k, dynamic v) => _cfg
      .child('settings')
      .update({k: v, 'updatedAt': DateTime.now().toUtc().toIso8601String()});

  Future<void> _simulateIncident(
    String title,
    String severity,
    String description,
    String model,
  ) async {
    _simTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    final mode = _deployAuto ? 'automatic' : 'human';
    const target = 'tool/guardian_drill_target.mjs';

    // Register the drill in the bug pipeline so the rest of the platform sees it.
    FirebaseDatabase.instance.ref('bugs/client').push().set({
      'area': 'simulation',
      'severity': severity,
      'message': description,
      'at': DateTime.now().toUtc().toIso8601String(),
      'simulated': true,
    });

    var dispatched = false;
    if (_ghUrl.isNotEmpty) {
      final svc = GithubService(
        baseUrl: _ghUrl,
        sharedSecret: _wSecret,
        repo: _tracker.repo,
      );
      try {
        dispatched = await svc.dispatchDrill(mode: mode, target: target);
      } catch (_) {
      } finally {
        svc.close();
      }
    }

    if (dispatched) {
      // The REAL guardian-drill workflow now drives the pipeline + terminal,
      // stage by stage, straight from GitHub. No synthetic preview needed.
      _tracker.expectDrill();
      await _cfg.child('activeRun').remove();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text(
            'Guardian drill dispatched on GitHub (mode=$mode) — the pipeline is now live.',
            style: Sa.body(size: 12.5, color: Sa.text),
          ),
        ),
      );
      return;
    }

    // Offline fallback: staged textual PREVIEW in the terminal (the pipeline
    // stays in its grey "not connected" state until the worker is linked).
    final stages = ['detect', 'context', 'fix', 'review', 'gate', 'deploy'];
    String line(String st) {
      switch (st) {
        case 'detect':
          return 'detect   > $description';
        case 'context':
          return 'context  > pulling source files + stack traces + DB state';
        case 'fix':
          return 'fix      > $model generating minimal patch…';
        case 'review':
          return 'review   > flutter analyze + flutter test + AI review…';
        case 'gate':
          return 'gate     > tests passed, review approved';
        default:
          return _deployAuto
              ? 'deploy   > merged to main, production live'
              : 'deploy   > opened PR, awaiting human review';
      }
    }

    final logs = <String>[
      '[${_ts()}] dispatch  > local preview (link the GitHub worker to go live)',
      '[${_ts()}] incident: $title ($severity)',
      '[${_ts()}] ${line('detect')}',
    ];
    await _cfg.child('activeRun').set({
      'title': title,
      'severity': severity,
      'description': description,
      'model': model,
      'stage': 'detect',
      'status': 'running',
      'log': logs,
      'simulated': true,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    var i = 0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 1700), (t) async {
      i++;
      if (i >= stages.length) {
        t.cancel();
        logs.add('[${_ts()}] ${line('deploy')}');
        logs.add(
          '[${_ts()}] ${_deployAuto ? '✔ resolved & deployed' : '✔ PR opened — awaiting review'}',
        );
        await _cfg.child('activeRun').update({
          'stage': 'deploy',
          'status': _deployAuto ? 'deployed' : 'pr_open',
          'log': logs,
        });
        return;
      }
      logs.add('[${_ts()}] ${line(stages[i])}');
      await _cfg.child('activeRun').update({
        'stage': stages[i],
        'status': 'running',
        'log': logs,
      });
    });
  }

  Future<void> _deleteMd(String key, int index) async {
    final snap = await _cfg.child(key).get();
    if (snap.value is! List) return;
    final list = List<dynamic>.from(snap.value as List);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _cfg.child(key).set(list);
  }

  Future<void> _pickProvider(String role, Map settings) async {
    final chosen = await showModalBottomSheet<_Provider>(
      context: context,
      backgroundColor: Sa.panelSolid,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in _Providers.list)
                ListTile(
                  leading: Icon(Icons.bolt, color: p.color),
                  title: Text(p.name, style: Sa.body(size: 14, color: Sa.text)),
                  subtitle: Text(
                    p.defaultModel.isEmpty
                        ? context.tr('custom endpoint')
                        : p.defaultModel,
                    style: Sa.body(size: 11, color: Sa.muted),
                  ),
                  onTap: () => Navigator.pop(ctx, p),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) {
      await _saveSetting('${role}Provider', chosen.id);
      await _saveSetting('${role}Model', chosen.defaultModel);
    }
  }

  Future<void> _setSecret(String field, String title, String hint) async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        title: Text(title, style: Sa.body(size: 15, color: Sa.text)),
        content: TextField(
          controller: ctl,
          obscureText: true,
          style: Sa.body(size: 13, color: Sa.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: Sa.body(size: 13, color: Sa.muted),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: Text(
              context.tr('Save'),
              style: Sa.body(size: 13, color: Sa.cyan),
            ),
          ),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      await _sec.update({
        field: v,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      if (field == 'githubToken') {
        await _markGithubCredentialsChanged();
      }
      final s = await _sec.get();
      if (mounted && s.value is Map)
        setState(() => _secrets = s.value as Map<dynamic, dynamic>);
    }
  }

  Future<void> _setRepo(String currentRepo) async {
    final ctl = TextEditingController(text: currentRepo);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        title: Text(
          context.tr('Link GitHub repository'),
          style: Sa.body(size: 15, color: Sa.text),
        ),
        content: TextField(
          controller: ctl,
          style: Sa.body(size: 13, color: Sa.text),
          decoration: InputDecoration(
            hintText: context.tr('owner/repository'),
            hintStyle: Sa.body(size: 13, color: Sa.muted),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: Text(
              context.tr('Save'),
              style: Sa.body(size: 13, color: Sa.cyan),
            ),
          ),
        ],
      ),
    );
    if (v != null) {
      final trimmed = v.trim();
      if (trimmed.isEmpty) {
        await _cfg.update({'repo': null});
        await _markGithubCredentialsChanged(repo: '');
        _tracker.setRepo('');
        if (mounted) {
          setState(() {
            _verifyOk = false;
            _verifyMsg = context.tr('GitHub repository cleared.');
          });
        }
        return;
      }
      final repo = GithubService.normalizeRepo(v);
      if (repo.isNotEmpty) {
        await _cfg.update({'repo': repo});
        await _markGithubCredentialsChanged(repo: repo);
        _tracker.setRepo(repo);
        return;
      }
      await _cfg.update({'repo': null});
      await _markGithubCredentialsChanged(repo: '');
      _tracker.setRepo('');
      if (mounted) {
        setState(() {
          _verifyOk = false;
          _verifyMsg = context.tr(
            'Invalid GitHub repository. Use owner/name or a GitHub URL.',
          );
        });
      }
    }
  }

  Future<void> _markGithubCredentialsChanged({String? repo}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final currentRepo = repo ?? _tracker.repo;
    GithubService.forgetCachedStatus(baseUrl: _ghUrl, repo: currentRepo);
    _tracker.forgetConnection();
    await _cfg.update({
      'githubConnected': false,
      'githubVerifiedAt': null,
      'githubVerifiedRepo': null,
      'githubConnectionMessage': null,
      'githubCredentialsUpdatedAt': now,
    });
  }

  Future<void> _uploadMd(String key) async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;
    final content = utf8.decode(bytes, allowMalformed: true);
    final snap = await _cfg.child(key).get();
    final list = (snap.value is List)
        ? List<dynamic>.from(snap.value as List)
        : <dynamic>[];
    list.add({
      'name': f.name,
      'content': content,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    await _cfg.child(key).set(list);
  }
}

/// Deliberate, premium warning before arming fully-autonomous deployment.
class _AutomaticModeWarningDialog extends StatelessWidget {
  const _AutomaticModeWarningDialog();

  static const _red = Color(0xFFF85149);
  static const _amber = Color(0xFFD29922);
  static const _green = Color(0xFF3FB950);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          decoration: BoxDecoration(
            color: Sa.panelSolid,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _red.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: _red.withValues(alpha: 0.18),
                blurRadius: 40,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _red.withValues(alpha: 0.22),
                      _amber.withValues(alpha: 0.10),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _red.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _red.withValues(alpha: 0.5)),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: _red,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('Enable automatic deployment?'),
                            style: Sa.display(size: 16),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            context.tr(
                              'Guardian will ship fixes with no human in the loop',
                            ),
                            style: Sa.body(size: 12, color: Sa.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bullet(
                      Icons.merge,
                      context.tr('Verified AI fixes are pushed straight to '),
                      'main',
                      context.tr(' — no pull request, no review.'),
                    ),
                    _bullet(
                      Icons.rocket_launch_outlined,
                      context.tr('Each healed commit '),
                      context.tr('auto-deploys to production'),
                      context.tr(' (web + app builds).'),
                    ),
                    _bullet(
                      Icons.person_off_outlined,
                      context.tr('A person is only notified '),
                      context.tr('after the fact'),
                      context.tr(', or when a fix fails to verify.'),
                    ),
                    _bullet(
                      Icons.health_and_safety_outlined,
                      context.tr('A safety-restore still protects '),
                      'main',
                      context.tr(' if a fix can’t be validated.'),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _amber.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 15, color: _amber),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        context.tr(
                          'Recommended only once you trust the Fix + Review AI pairing on your codebase.',
                        ),
                        style: Sa.body(size: 11.5, color: Sa.textDim),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: _btn(
                        context,
                        context.tr('Keep human review'),
                        _green,
                        false,
                        filled: false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _btn(
                        context,
                        context.tr('Enable automatic'),
                        _red,
                        true,
                        filled: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullet(IconData ic, String a, String bold, String b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(ic, size: 15, color: _red.withValues(alpha: 0.85)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: Sa.body(size: 12.5, color: Sa.textDim),
                children: [
                  TextSpan(text: a),
                  TextSpan(
                    text: bold,
                    style: Sa.body(
                      size: 12.5,
                      color: Sa.text,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: b),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(
    BuildContext ctx,
    String label,
    Color c,
    bool value, {
    required bool filled,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? c.withValues(alpha: 0.92) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: filled ? 0.0 : 0.6)),
        ),
        child: Text(
          label,
          style: Sa.body(
            size: 12.5,
            color: filled ? Colors.white : c,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM AGENTS · ICON PALETTE
// ═══════════════════════════════════════════════════════════════════════════

/// Fixed icon palette for operator-created agents. Keys (not raw code points)
/// are stored in RTDB so every [IconData] used by the app stays const — that
/// keeps Flutter's release icon tree-shaking working.
const Map<String, IconData> _kAgentIcons = {
  'robot': Icons.smart_toy_outlined,
  'bolt': Icons.bolt,
  'shield': Icons.shield_outlined,
  'brain': Icons.psychology_outlined,
  'radar': Icons.radar,
  'chat': Icons.forum_outlined,
  'eye': Icons.visibility_outlined,
  'gear': Icons.settings_suggest_outlined,
  'rocket': Icons.rocket_launch_outlined,
  'chart': Icons.insights_outlined,
  'flask': Icons.science_outlined,
  'hub': Icons.hub_outlined,
  'translate': Icons.translate,
  'inventory': Icons.inventory_2_outlined,
  'bug': Icons.bug_report_outlined,
  'bell': Icons.notifications_active_outlined,
};

const List<int> _kAccentSwatches = [
  0x22D3EE,
  0x3B82F6,
  0xA78BFA,
  0x34D399,
  0xFBBF24,
  0xF87171,
  0xF472B6,
  0xF6821F,
  0x10A37F,
  0x64748B,
];

String _hexOf(int rgb) => rgb.toRadixString(16).padLeft(6, '0');

/// Decode-resize-PNG-encode an uploaded logo to a small base64 string so the
/// registry record stays light (the screen streams it live). Falls back to the
/// raw bytes when decoding is unavailable and the file is already small.
Future<String?> _encodeLogoBase64(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 192);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data != null) return base64Encode(data.buffer.asUint8List());
  } catch (_) {}
  if (bytes.length <= 220 * 1024) return base64Encode(bytes);
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM AGENT · DETAIL PANEL
// ═══════════════════════════════════════════════════════════════════════════

class _CustomAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomAgentPanel({
    required this.spec,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_CustomAgentPanel> createState() => _CustomAgentPanelState();
}

class _CustomAgentPanelState extends State<_CustomAgentPanel> {
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final provider = _Providers.of(spec.provider);
    final token = (spec.apiToken ?? '');
    final masked = token.isEmpty
        ? context.tr('NO CREDENTIAL ON FILE')
        : token.length <= 4
        ? '••••'
        : '${'•' * (token.length - 4).clamp(4, 24)}${token.substring(token.length - 4)}';

    return _AgentScroll(
      children: [
        if (!widget.enabled) _OfflineBanner(spec: spec),
        // ── HERO ──────────────────────────────────────────────────────────
        GlassPanel(
          accent: spec.accent,
          glow: widget.enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: spec.icon,
                leading: _AgentGlyph(spec: spec, size: 36, radius: 10),
                title: context.tr(spec.name),
                subtitle: spec.codename,
                accent: spec.accent,
                trailing: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    GlowChip(
                      label: context.tr('CUSTOM UNIT'),
                      color: spec.accent,
                      icon: Icons.auto_awesome,
                    ),
                    GlowChip(
                      label: widget.enabled
                          ? context.tr('ONLINE')
                          : context.tr('OFFLINE'),
                      color: widget.enabled ? Sa.green : Sa.muted,
                      pulse: widget.enabled,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SaStatTile(
                    label: context.tr('Provider'),
                    value: provider.name,
                    icon: Icons.cloud_outlined,
                    color: spec.accent,
                  ),
                  SaStatTile(
                    label: context.tr('Model'),
                    value: (spec.model ?? '').isEmpty ? '—' : spec.model!,
                    icon: Icons.memory,
                    color: Sa.blue,
                  ),
                  SaStatTile(
                    label: context.tr('Credential'),
                    value: token.isEmpty
                        ? context.tr('MISSING')
                        : context.tr('ON FILE'),
                    icon: Icons.vpn_key_outlined,
                    color: token.isEmpty ? Sa.amber : Sa.green,
                  ),
                  SaStatTile(
                    label: context.tr('Deployed'),
                    value: _agoIso(context, spec.createdAt),
                    icon: Icons.schedule,
                    color: Sa.muted,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  SaButton(
                    label: context.tr('EDIT AGENT'),
                    icon: Icons.tune,
                    color: spec.accent,
                    outlined: true,
                    onPressed: widget.onEdit,
                  ),
                  const SizedBox(width: 10),
                  SaButton(
                    label: context.tr('DELETE'),
                    icon: Icons.delete_forever_outlined,
                    color: Sa.red,
                    outlined: true,
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
        // ── PROFILE ───────────────────────────────────────────────────────
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.badge_outlined,
                title: context.tr('PROFILE'),
                subtitle: context.tr(
                  'Who this agent is and what it stands for.',
                ),
                accent: spec.accent,
              ),
              const SizedBox(height: 12),
              if ((spec.description ?? '').trim().isEmpty)
                Text(
                  context.tr('No description provided.'),
                  style: Sa.body(size: 12, color: Sa.textDim),
                )
              else
                Text(spec.description!, style: Sa.body(size: 12.5)),
            ],
          ),
        ),
        // ── MISSION / TASKS ───────────────────────────────────────────────
        _CustomDocPanel(
          icon: Icons.assignment_outlined,
          title: context.tr('MISSION BRIEF'),
          subtitle: context.tr('The tasks this agent is responsible for.'),
          accent: spec.accent,
          body: spec.tasks ?? '',
          fileName: spec.tasksFile,
          emptyMsg: context.tr(
            'No tasks defined yet — edit the agent to brief it.',
          ),
        ),
        // ── SKILLS ────────────────────────────────────────────────────────
        _CustomDocPanel(
          icon: Icons.school_outlined,
          title: context.tr('SKILLS & CAPABILITIES'),
          subtitle: context.tr('What this agent knows how to do.'),
          accent: spec.accent,
          body: spec.skills ?? '',
          fileName: spec.skillsFile,
          emptyMsg: context.tr('No skills listed yet.'),
        ),
        // ── CREDENTIALS ───────────────────────────────────────────────────
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.vpn_key_outlined,
                title: context.tr('CREDENTIALS'),
                subtitle: context.tr(
                  'The LLM provider and API token this agent authenticates with.',
                ),
                accent: spec.accent,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: provider.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: provider.color.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Center(
                      child: _ProviderLogo(
                        provider: provider,
                        size: 28,
                        color: provider.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(provider.name, style: Sa.heading(size: 14)),
                        Text(
                          (spec.model ?? '').isEmpty
                              ? context.tr('Default model')
                              : spec.model!,
                          style: Sa.mono(size: 10.5, color: Sa.textDim),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Sa.termBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Sa.termBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key, size: 14, color: Sa.termMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectableText(
                        _reveal && token.isNotEmpty ? token : masked,
                        style: Sa.mono(size: 11.5, color: Sa.termText),
                      ),
                    ),
                    if (token.isNotEmpty) ...[
                      IconButton(
                        tooltip: _reveal
                            ? context.tr('Hide')
                            : context.tr('Reveal'),
                        onPressed: () => setState(() => _reveal = !_reveal),
                        icon: Icon(
                          _reveal
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 16,
                          color: Sa.termDim,
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('Copy'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: token));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Sa.panelSolid,
                              content: Text(
                                context.tr('Token copied to clipboard.'),
                                style: Sa.body(size: 12.5),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.copy_all_outlined,
                          size: 15,
                          color: Sa.termDim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 12, color: Sa.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.tr(
                        'Stored separately in a superadmin-only credential vault. Treat it as a secret — rotate it from EDIT AGENT if it leaks.',
                      ),
                      style: Sa.body(size: 10.5, color: Sa.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reusable read-only document panel (tasks / skills) with an optional source
/// file chip.
class _CustomDocPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String body;
  final String? fileName;
  final String emptyMsg;

  const _CustomDocPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.body,
    required this.fileName,
    required this.emptyMsg,
  });

  @override
  Widget build(BuildContext context) {
    final hasBody = body.trim().isNotEmpty;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: icon,
            title: title,
            subtitle: subtitle,
            accent: accent,
            trailing: (fileName ?? '').isEmpty
                ? null
                : GlowChip(
                    label: fileName!.toUpperCase(),
                    color: accent,
                    icon: Icons.attach_file,
                  ),
          ),
          const SizedBox(height: 12),
          if (!hasBody)
            Text(emptyMsg, style: Sa.body(size: 12, color: Sa.textDim))
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Sa.termBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Sa.termBorder),
              ),
              child: SelectableText(
                body,
                style: Sa.mono(size: 11.5, color: Sa.termText),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AGENT EDITOR DIALOG (add / edit a custom agent)
// ═══════════════════════════════════════════════════════════════════════════

class _AgentEditorDialog extends StatefulWidget {
  final _AgentSpec? editing;
  const _AgentEditorDialog({this.editing});

  @override
  State<_AgentEditorDialog> createState() => _AgentEditorDialogState();
}

class _AgentEditorDialogState extends State<_AgentEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _codename;
  late final TextEditingController _description;
  late final TextEditingController _tasks;
  late final TextEditingController _skills;
  late final TextEditingController _model;
  late final TextEditingController _token;

  String? _logoData;
  bool _logoBusy = false;
  String _iconKey = 'robot';
  String _accentHex = '22D3EE';
  String? _provider;
  String? _tasksFile;
  String? _skillsFile;
  bool _revealToken = false;
  bool _modelEdited = false;
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _name = TextEditingController(text: e?.name ?? '');
    _codename = TextEditingController(
      text: (e?.codename ?? '') == 'CUSTOM UNIT' ? '' : (e?.codename ?? ''),
    );
    _description = TextEditingController(text: e?.description ?? '');
    _tasks = TextEditingController(text: e?.tasks ?? '');
    _skills = TextEditingController(text: e?.skills ?? '');
    _model = TextEditingController(text: e?.model ?? '');
    _token = TextEditingController(text: e?.apiToken ?? '');
    _logoData = e?.logoData;
    _tasksFile = e?.tasksFile;
    _skillsFile = e?.skillsFile;
    _provider = (e?.provider ?? '').isEmpty ? null : e!.provider;
    _accentHex = (e?.accentHex ?? '').isEmpty ? '22D3EE' : e!.accentHex!;
    _modelEdited = (e?.model ?? '').isNotEmpty;
    // Resolve the stored icon back to its palette key.
    if (e != null) {
      _kAgentIcons.forEach((k, v) {
        if (v == e.icon) _iconKey = k;
      });
    }
    _model.addListener(() => _modelEdited = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _codename.dispose();
    _description.dispose();
    _tasks.dispose();
    _skills.dispose();
    _model.dispose();
    _token.dispose();
    super.dispose();
  }

  Color get _accent {
    final v = int.tryParse(_accentHex, radix: 16);
    return v == null ? Sa.cyan : Color(0xFF000000 | v);
  }

  Future<void> _attachLogo() async {
    setState(() => _logoBusy = true);
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final files = res?.files ?? const [];
      final bytes = files.isNotEmpty ? files.first.bytes : null;
      if (bytes != null) {
        final encoded = await _encodeLogoBase64(bytes);
        if (encoded != null && mounted) setState(() => _logoData = encoded);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _attachText({required bool tasks}) async {
    try {
      final res = await FilePicker.pickFiles(withData: true);
      final files = res?.files ?? const [];
      if (files.isEmpty) return;
      final f = files.first;
      String? content;
      final bytes = f.bytes;
      if (bytes != null && bytes.length <= 200 * 1024) {
        try {
          content = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {}
      }
      setState(() {
        if (tasks) {
          _tasksFile = f.name;
          if (content != null && content.trim().isNotEmpty) {
            _tasks.text = content;
          }
        } else {
          _skillsFile = f.name;
          if (content != null && content.trim().isNotEmpty) {
            _skills.text = content;
          }
        }
      });
    } catch (_) {}
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || _provider == null) {
      setState(() => _showError = true);
      return;
    }
    final map = <String, dynamic>{
      'name': name.toUpperCase(),
      'codename': _codename.text.trim().isEmpty
          ? 'CUSTOM UNIT'
          : _codename.text.trim().toUpperCase(),
      'description': _description.text.trim(),
      'tasks': _tasks.text.trim(),
      'skills': _skills.text.trim(),
      'provider': _provider,
      'model': _model.text.trim(),
      'apiToken': _token.text.trim(),
      'iconKey': _iconKey,
      'accentHex': _accentHex,
    };
    if ((_logoData ?? '').isNotEmpty) map['logoData'] = _logoData;
    if ((_tasksFile ?? '').isNotEmpty) map['tasksFile'] = _tasksFile;
    if ((_skillsFile ?? '').isNotEmpty) map['skillsFile'] = _skillsFile;
    Navigator.pop(context, map);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final editing = widget.editing != null;
    final logoBytes = () {
      final d = _logoData;
      if (d == null || d.isEmpty) return null;
      try {
        return base64Decode(d.contains(',') ? d.split(',').last : d);
      } catch (_) {
        return null;
      }
    }();

    return Dialog(
      backgroundColor: Sa.panelSolid,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: 0.45)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: Sa.isDark ? 0.18 : 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.3),
                          accent.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withValues(alpha: 0.5)),
                    ),
                    child: logoBytes != null
                        ? Padding(
                            padding: const EdgeInsets.all(5),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                logoBytes,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                          )
                        : Icon(_kAgentIcons[_iconKey], color: accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          editing
                              ? context.tr('EDIT AGENT')
                              : context.tr('DEPLOY NEW AGENT'),
                          style: Sa.display(size: 16),
                        ),
                        Text(
                          context.tr(
                            'Configure a custom autonomous unit for the fleet',
                          ),
                          style: Sa.mono(size: 9, color: Sa.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, size: 18, color: Sa.muted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Sa.border),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(context.tr('IDENTITY'), accent),
                    const SizedBox(height: 10),
                    _textField(
                      _name,
                      hint: context.tr('Agent name (e.g. Quality Inspector)'),
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 10),
                    _textField(
                      _codename,
                      hint: context.tr(
                        'Codename (optional, e.g. UNIT-07 · SENTRY)',
                      ),
                      icon: Icons.tag,
                    ),
                    const SizedBox(height: 10),
                    _textField(
                      _description,
                      hint: context.tr(
                        'Short description of what this agent is for',
                      ),
                      icon: Icons.notes_outlined,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),

                    _label(context.tr('APPEARANCE'), accent),
                    const SizedBox(height: 10),
                    _appearanceRow(accent, logoBytes != null),
                    const SizedBox(height: 20),

                    _label(context.tr('MISSION · TASKS'), accent),
                    const SizedBox(height: 6),
                    Text(
                      context.tr(
                        'Describe the tasks, or attach a brief / spec file.',
                      ),
                      style: Sa.body(size: 10.5, color: Sa.textDim),
                    ),
                    const SizedBox(height: 10),
                    _textField(
                      _tasks,
                      hint: context.tr(
                        'e.g. Review incoming quality alerts, draft a containment checklist…',
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 8),
                    _attachRow(
                      fileName: _tasksFile,
                      onAttach: () => _attachText(tasks: true),
                      onClear: () => setState(() => _tasksFile = null),
                      accent: accent,
                    ),
                    const SizedBox(height: 20),

                    _label(context.tr('SKILLS · CAPABILITIES'), accent),
                    const SizedBox(height: 6),
                    Text(
                      context.tr(
                        'List the skills, or attach a capability sheet.',
                      ),
                      style: Sa.body(size: 10.5, color: Sa.textDim),
                    ),
                    const SizedBox(height: 10),
                    _textField(
                      _skills,
                      hint: context.tr(
                        'e.g. Root-cause analysis, ISO 9001 knowledge, French + English…',
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 8),
                    _attachRow(
                      fileName: _skillsFile,
                      onAttach: () => _attachText(tasks: false),
                      onClear: () => setState(() => _skillsFile = null),
                      accent: accent,
                    ),
                    const SizedBox(height: 20),

                    _label(context.tr('MODEL PROVIDER'), accent),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final p in _Providers.list)
                          _ProviderTile(
                            provider: p,
                            selected: _provider == p.id,
                            onTap: () => setState(() {
                              _provider = p.id;
                              if (!_modelEdited) {
                                _model.text = p.defaultModel;
                                _modelEdited = false;
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      _model,
                      hint: context.tr('Model id (e.g. {hint})', {
                        'hint': _providerHint(),
                      }),
                      icon: Icons.memory,
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      _token,
                      hint: _provider == null
                          ? context.tr('API token / key')
                          : context.tr('API token — {hint}', {
                              'hint': _Providers.of(_provider).tokenHint,
                            }),
                      icon: Icons.vpn_key_outlined,
                      obscure: !_revealToken,
                      suffix: IconButton(
                        onPressed: () =>
                            setState(() => _revealToken = !_revealToken),
                        icon: Icon(
                          _revealToken
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 16,
                          color: Sa.muted,
                        ),
                      ),
                    ),
                    if (_showError) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.error_outline, size: 14, color: Sa.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr(
                                'A name and a model provider are required.',
                              ),
                              style: Sa.body(size: 11.5, color: Sa.red),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: Sa.border),
            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SaButton(
                    label: context.tr('CANCEL'),
                    icon: Icons.close,
                    color: Sa.muted,
                    outlined: true,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  SaButton(
                    label: editing
                        ? context.tr('SAVE CHANGES')
                        : context.tr('DEPLOY AGENT'),
                    icon: editing ? Icons.save_outlined : Icons.rocket_launch,
                    color: accent,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _providerHint() =>
      _provider == null ? 'gpt-4o' : _Providers.of(_provider).defaultModel;

  Widget _label(String text, Color accent) => Row(
    children: [
      Container(width: 3, height: 14, color: accent),
      const SizedBox(width: 8),
      Text(text, style: Sa.heading(size: 12.5, color: accent)),
    ],
  );

  Widget _textField(
    TextEditingController c, {
    String? hint,
    IconData? icon,
    int maxLines = 1,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: c,
      maxLines: obscure ? 1 : maxLines,
      obscureText: obscure,
      style: Sa.body(size: 13),
      cursorColor: _accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: Sa.body(size: 12, color: Sa.muted),
        prefixIcon: icon != null ? Icon(icon, size: 17, color: Sa.muted) : null,
        suffixIcon: suffix,
        isDense: true,
        filled: true,
        fillColor: Sa.bgRaised.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Sa.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _accent),
        ),
      ),
    );
  }

  Widget _appearanceRow(Color accent, bool hasLogo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SaButton(
              label: hasLogo
                  ? context.tr('REPLACE LOGO')
                  : context.tr('UPLOAD LOGO'),
              icon: Icons.image_outlined,
              color: accent,
              outlined: true,
              busy: _logoBusy,
              onPressed: _attachLogo,
            ),
            const SizedBox(width: 10),
            if (hasLogo)
              SaButton(
                label: context.tr('REMOVE'),
                icon: Icons.delete_outline,
                color: Sa.red,
                outlined: true,
                onPressed: () => setState(() => _logoData = null),
              ),
            const Spacer(),
            Text(
              hasLogo
                  ? context.tr('Custom logo set')
                  : context.tr('No logo · pick an icon'),
              style: Sa.mono(size: 9, color: Sa.muted),
            ),
          ],
        ),
        if (!hasLogo) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _kAgentIcons.entries)
                GestureDetector(
                  onTap: () => setState(() => _iconKey = entry.key),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _iconKey == entry.key
                          ? accent.withValues(alpha: 0.16)
                          : Sa.bgRaised.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _iconKey == entry.key ? accent : Sa.border,
                        width: _iconKey == entry.key ? 1.4 : 1,
                      ),
                    ),
                    child: Icon(
                      entry.value,
                      size: 18,
                      color: _iconKey == entry.key ? accent : Sa.textDim,
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Text(context.tr('ACCENT'), style: Sa.mono(size: 9, color: Sa.muted)),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final rgb in _kAccentSwatches)
                    GestureDetector(
                      onTap: () => setState(() => _accentHex = _hexOf(rgb)),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Color(0xFF000000 | rgb),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _accentHex == _hexOf(rgb)
                                ? Sa.text
                                : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: [
                            if (_accentHex == _hexOf(rgb))
                              BoxShadow(
                                color: Color(
                                  0xFF000000 | rgb,
                                ).withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _attachRow({
    required String? fileName,
    required VoidCallback onAttach,
    required VoidCallback onClear,
    required Color accent,
  }) {
    return Row(
      children: [
        InkWell(
          onTap: onAttach,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.upload_file_outlined, size: 15, color: accent),
                const SizedBox(width: 6),
                Text(
                  context.tr('ATTACH FILE'),
                  style: Sa.mono(
                    size: 9.5,
                    color: accent,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if ((fileName ?? '').isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Sa.bgRaised.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Sa.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 12, color: Sa.textDim),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      fileName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Sa.mono(size: 9.5, color: Sa.textDim),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onClear,
                    child: Icon(Icons.close, size: 12, color: Sa.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DELETE CONFIRMATION (blood red)
// ═══════════════════════════════════════════════════════════════════════════

class _DeleteAgentDialog extends StatefulWidget {
  final _AgentSpec agent;
  const _DeleteAgentDialog({required this.agent});

  @override
  State<_DeleteAgentDialog> createState() => _DeleteAgentDialogState();
}

class _DeleteAgentDialogState extends State<_DeleteAgentDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  static const Color _blood = Color(0xFFE11D2E);
  static const Color _bloodDeep = Color(0xFF7F0E18);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A0608),
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _blood, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Stack(
          children: [
            // Pulsing danger glow.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.7),
                      radius: 1.2,
                      colors: [
                        _blood.withValues(alpha: 0.12 + 0.10 * _c.value),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _c,
                    builder: (_, __) => Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [_blood, _bloodDeep],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _blood.withValues(
                              alpha: 0.4 + 0.3 * _c.value,
                            ),
                            blurRadius: 24 + 10 * _c.value,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    context.tr('DECOMMISSION AGENT'),
                    style: Sa.display(size: 18, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _blood.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: _blood.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      widget.agent.name,
                      style: Sa.mono(
                        size: 11,
                        color: const Color(0xFFFFB4BC),
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr(
                      'This permanently removes the agent, its mission brief, skills and stored API credential from the fleet registry.\n\nThis action cannot be undone.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: Color(0xFFE9C4C8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE9C4C8),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.tr('CANCEL'),
                            style: Sa.heading(
                              size: 12.5,
                              color: const Color(0xFFE9C4C8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: _blood,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.delete_forever,
                                size: 17,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                context.tr('DELETE PERMANENTLY'),
                                style: Sa.heading(
                                  size: 12.5,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
