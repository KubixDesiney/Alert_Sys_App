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
import '../../services/predictive_scope.dart';
import 'superadmin_theme.dart';

part 'ai_agents_tab_panels1.dart';
part 'ai_agents_tab_panels2.dart';
part 'ai_agents_tab_panels3.dart';

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
  factory _AgentSpec.fromRegistry(String id, Map<String, dynamic> m,
      {String? apiToken}) {
    return _AgentSpec(
      id: id,
      name: (m['name'] ?? 'AGENT').toString(),
      codename: (m['codename'] ?? 'CUSTOM UNIT').toString(),
      role: (m['role'] ?? m['description'] ?? 'Operator-deployed agent')
          .toString(),
      icon: _kAgentIcons[(m['iconKey'] ?? '').toString()] ??
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
        gradient: LinearGradient(colors: [
          accent.withValues(alpha: 0.30),
          accent.withValues(alpha: 0.08),
        ]),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Center(
          child: _AgentGlyph(spec: spec, size: size, radius: radius)),
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
        child: Image.asset(spec.logoAsset!,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) =>
                Icon(spec.icon, size: size * 0.52, color: accent)),
      );
    }
    if (bytes != null) {
      return Padding(
        padding: EdgeInsets.all(size * 0.1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius * 0.6),
          child: Image.memory(bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) =>
                  Icon(spec.icon, size: size * 0.52, color: accent)),
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
    return list.firstWhere((p) => p.id == id,
        orElse: () => list.last); // 'other'
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
      child: CustomPaint(painter: _ProviderMarkPainter(id: id, color: c)),
    );
  }
}

class _ProviderLogo extends StatelessWidget {
  final _Provider provider;
  final double size;
  final Color? color;

  const _ProviderLogo({
    required this.provider,
    this.size = 18,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ??
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
    final fill = Paint()..color = color..isAntiAlias = true;
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
          canvas.drawCircle(p, r * 0.42, fill..color = color.withValues(alpha: 0.85));
        }
        canvas.drawCircle(c, r * 0.30,
            Paint()..color = color.withValues(alpha: 0.0001)..blendMode = BlendMode.clear);
        break;
      case 'gemini':
        // Four-point spark (Google Gemini star).
        final path = Path();
        for (var i = 0; i < 4; i++) {
          final a = i * math.pi / 2;
          final tip = c + Offset(math.cos(a), math.sin(a)) * r;
          final l = c + Offset(math.cos(a + math.pi / 4), math.sin(a + math.pi / 4)) * r * 0.30;
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
            Rect.fromLTWH(size.width * 0.12, i * h + h * 0.12,
                size.width * 0.76, h * 0.76),
            Paint()..color = bands[i],
          );
        }
        break;
      case 'anthropic':
        // Radiating sunburst.
        for (var i = 0; i < 10; i++) {
          final a = i * math.pi / 5;
          canvas.drawLine(
              c, c + Offset(math.cos(a), math.sin(a)) * r * 0.92, stroke);
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
        canvas.drawLine(c + Offset(-r * 0.6, -r * 0.6),
            c + Offset(r * 0.6, r * 0.6), stroke);
        canvas.drawLine(c + Offset(r * 0.6, -r * 0.6),
            c + Offset(-r * 0.6, r * 0.6), stroke);
        break;
      case 'cloudflare':
        // Cloud arc.
        canvas.drawCircle(c + Offset(-r * 0.25, r * 0.1), r * 0.4, fill);
        canvas.drawCircle(c + Offset(r * 0.3, r * 0.15), r * 0.5, fill);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * 0.18, size.height * 0.5,
                size.width * 0.7, size.height * 0.28),
            Radius.circular(r * 0.3),
          ),
          fill,
        );
        break;
      default:
        // Monogram fallback (Meta, Cohere, Perplexity, Azure, Other).
        final letter = (_Providers.of(id).name.isNotEmpty
                ? _Providers.of(id).name[0]
                : '?')
            .toUpperCase();
        canvas.drawCircle(c, r * 0.92, stroke..strokeWidth = math.max(1.2, r * 0.12));
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
            if (selected) BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: 14),
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
              child: Center(child: _ProviderLogo(provider: provider, size: 22, color: c)),
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
      _subs.add(FirebaseDatabase.instance
          .ref('ai_agents/${agent.id}/enabled')
          .onValue
          .listen((event) {
        if (mounted) {
          setState(() => _enabled[agent.id] = event.snapshot.value != false);
        }
      }, onError: (_) {}));
    }
    // Operator-created agents live in a lightweight registry so discovery never
    // streams the heavy worker logs/stats under the built-in agent nodes. The
    // API token never lives in this record — it is stored separately under
    // `ai_agent_secrets/{id}`, which only superadmin can read.
    _subs.add(FirebaseDatabase.instance
        .ref('ai_agents/registry')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      final raw = <String, Map<String, dynamic>>{};
      if (v is Map) {
        v.forEach((k, val) {
          if (val is Map) raw[k.toString()] = Map<String, dynamic>.from(val);
        });
      }
      _registryRaw = raw;
      _rebuildCustom();
    }, onError: (_) {}));
    _subs.add(FirebaseDatabase.instance
        .ref('ai_agent_secrets')
        .onValue
        .listen((event) {
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
    }, onError: (_) {}));
    _subs.add(FirebaseDatabase.instance
        .ref('workers/health/lastRun')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted && v is Map) {
        setState(() => _health = Map<String, dynamic>.from(v));
      }
    }, onError: (_) {}));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text(
            value
                ? '${agent.name} is back online.'
                : '${agent.name} taken offline — the worker stands down within 60s.',
            style: Sa.body(size: 12.5),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enabled[agent.id] = !value);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Could not update ${agent.name}: $e',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
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
    final id = editing?.id ??
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text(
            editing == null
                ? '${record['name']} deployed to the fleet.'
                : '${record['name']} updated.',
            style: Sa.body(size: 12.5),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Could not save agent: $e',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
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
        FirebaseDatabase.instance
            .ref('ai_agent_secrets/${agent.id}')
            .remove(),
      ]);
      if (mounted) {
        setState(() {
          if (_selectedId == agent.id) _selectedId = 'shift';
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('${agent.name} decommissioned and wiped.',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Delete failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final agents = _agents;
    final agent =
        agents.firstWhere((a) => a.id == _selectedId, orElse: () => agents.first);
    final online =
        agents.where((a) => !a.maintenance && _isEnabled(a.id)).length;
    final cronAt = DateTime.tryParse((_health?['timestamp'] ?? '').toString());
    final cronFresh = cronAt != null &&
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
                      onDelete:
                          a.custom ? () => _deleteAgent(a) : null,
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
                    spec: agent, enabled: _isEnabled('shift'), health: _health),
                'briefing' => _BriefingAgentPanel(
                    spec: agent, enabled: _isEnabled('briefing')),
                'assist' =>
                  _AssistAgentPanel(spec: agent, enabled: _isEnabled('assist')),
                'security' => _SecurityAgentPanel(
                    spec: agent, enabled: _isEnabled('security'), health: _health),
                'predictive' => _PredictiveAgentPanel(
                    spec: agent, enabled: _isEnabled('predictive')),
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
                Text('AI AGENT FLEET', style: Sa.display(size: 15)),
                Text(
                  'Six autonomous units · toggles propagate to the edge worker within 60 seconds',
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
                label: '$online/$total UNITS ONLINE',
                color: online == total ? Sa.green : Sa.amber,
                pulse: true,
              ),
              GlowChip(
                label: cronFresh ? 'EDGE LINK LIVE' : 'EDGE LINK STALE',
                color: cronFresh ? Sa.cyan : Sa.red,
                icon: Icons.cell_tower,
              ),
              GlowChip(
                label: '$assignments ASSIGNED · LAST CRON',
                color: Sa.violet,
                icon: Icons.auto_awesome,
              ),
              if (secActions > 0)
                GlowChip(
                  label: '$secActions THREATS BLOCKED',
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
        c, r * 0.42, Paint()..color = color.withValues(alpha: 0.12 + 0.1 * glow));
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
                    color: accent.withValues(alpha: 0.22), blurRadius: 18),
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
                        Text(spec.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Sa.heading(size: 11.5)),
                        Text(spec.codename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Sa.mono(size: 7.5, color: Sa.muted)),
                      ],
                    ),
                  ),
                  if (widget.onDelete != null && (_hover || widget.selected))
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.delete_outline,
                            size: 15, color: Sa.red.withValues(alpha: 0.85)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  spec.role,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.body(size: 10.5, color: Sa.textDim),
                ),
              ),
              Row(
                children: [
                  if (spec.maintenance)
                    GlowChip(label: 'MAINTENANCE', color: Sa.amber)
                  else if (spec.custom)
                    GlowChip(
                      label: live ? 'ONLINE' : 'OFFLINE',
                      color: live ? accent : Sa.muted,
                      pulse: live,
                    )
                  else
                    GlowChip(
                      label: live ? 'ONLINE' : 'OFFLINE',
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
                  gradient: RadialGradient(colors: [
                    accent.withValues(alpha: 0.22),
                    accent.withValues(alpha: 0.02),
                  ]),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Icon(Icons.add, color: accent, size: 22),
              ),
              const SizedBox(height: 10),
              Text('DEPLOY AGENT', style: Sa.heading(size: 11.5)),
              const SizedBox(height: 2),
              Text('Add a unit to the fleet',
                  textAlign: TextAlign.center,
                  style: Sa.mono(size: 7.5, color: Sa.muted)),
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
              color: value ? accent : Sa.muted.withValues(alpha: 0.6)),
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
              '${spec.name} is OFFLINE. The edge worker skips its duties until you re-enable it; '
              'history below stays readable.',
              style: Sa.body(size: 12, color: Sa.red),
            ),
          ),
        ],
      ),
    );
  }
}

String _agoIso(Object? iso) {
  final t = DateTime.tryParse((iso ?? '').toString());
  if (t == null) return '—';
  final d = DateTime.now().toUtc().difference(t.toUtc());
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
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
    list.sort((a, b) =>
        (b[sortKey] ?? '').toString().compareTo((a[sortKey] ?? '').toString()));
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
                    Text(_agoIso(at), style: Sa.mono(size: 10, color: Sa.muted)),
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
                            .where((e) =>
                                e.key != 'id' &&
                                (e.value ?? '').toString().isNotEmpty)
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
                  style:
                      Sa.mono(size: 9, color: color, weight: FontWeight.w700),
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
              Text(_agoIso(at), style: Sa.mono(size: 9.5, color: Sa.muted)),
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
            color: value ? accent.withValues(alpha: 0.35) : Sa.border),
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
                Text(description,
                    style: Sa.body(size: 10.5, color: Sa.textDim)),
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
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Sa.mono(size: 9.5, color: Sa.textDim)),
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
                            gradient: LinearGradient(colors: [
                              color,
                              color.withValues(alpha: 0.55),
                            ]),
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
            child: Text('$count',
                textAlign: TextAlign.right,
                style: Sa.mono(size: 10.5, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-01 · SHIFT COMMANDER
// ═══════════════════════════════════════════════════════════════════════════

