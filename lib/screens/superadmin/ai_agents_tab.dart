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

class _ShiftAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  final Map<String, dynamic>? health;
  const _ShiftAgentPanel(
      {required this.spec, required this.enabled, required this.health});

  @override
  State<_ShiftAgentPanel> createState() => _ShiftAgentPanelState();
}

class _ShiftAgentPanelState extends State<_ShiftAgentPanel> {
  StreamSubscription<DatabaseEvent>? _sub;
  List<Map<String, dynamic>> _logs = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseDatabase.instance
        .ref('shift_ai_logs')
        .limitToLast(25)
        .onValue
        .listen((event) {
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
        flat.sort((a, b) =>
            (b['at'] ?? '').toString().compareTo((a['at'] ?? '').toString()));
      }
      if (mounted) setState(() => _logs = flat.take(120).toList());
    }, onError: (e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _bucket(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('assign') || k.contains('transfer')) return 'Assignments';
    if (k.contains('collab')) return 'Collaborations';
    if (k.contains('handover')) return 'Handovers';
    if (k.contains('presence')) return 'Presence checks';
    if (k.contains('block') || k.contains('skip')) return 'Blocked / skipped';
    return 'Other';
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
    final maxBucket =
        buckets.values.isEmpty ? 0 : buckets.values.reduce(math.max);
    final health = widget.health;

    return _AgentScroll(children: [
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
              title: 'COMMAND DECK',
              subtitle:
                  'Every decision the AI commander takes across active shifts — assignments, collaborations, handovers, presence.',
              accent: spec.accent,
              trailing: GlowChip(
                label: 'LLAMA 3.2 · EDGE',
                color: spec.accent,
                icon: Icons.memory,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'Actions · 24h',
                  value: '${last24.length}',
                  icon: Icons.bolt_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Assignments · last cron',
                  value: '${(health?['assignmentsMade'] as num?)?.toInt() ?? 0}',
                  icon: Icons.assignment_turned_in_outlined,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: 'Collabs · last cron',
                  value:
                      '${(health?['collaborationsApproved'] as num?)?.toInt() ?? 0}',
                  icon: Icons.handshake_outlined,
                  color: Sa.blue,
                ),
                SaStatTile(
                  label: 'Handovers · last cron',
                  value:
                      '${(health?['handoversGenerated'] as num?)?.toInt() ?? 0}',
                  icon: Icons.swap_horiz,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Last pulse',
                  value: _agoIso(health?['timestamp']),
                  icon: Icons.monitor_heart_outlined,
                  color: Sa.amber,
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
              icon: Icons.stacked_bar_chart,
              title: 'TASK BREAKDOWN',
              subtitle: 'Distribution of the commander’s recent decisions.',
              accent: spec.accent,
            ),
            const SizedBox(height: 14),
            if (buckets.isEmpty)
              Text('No shift AI activity recorded yet.',
                  style: Sa.body(size: 12, color: Sa.textDim))
            else
              ...buckets.entries.map((e) => _KindBar(
                    label: e.key,
                    count: e.value,
                    max: maxBucket,
                    color: spec.accent,
                  )),
          ],
        ),
      ),
      GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: Icons.receipt_long_outlined,
              title: 'ACTION LOG',
              subtitle:
                  'Tap any entry for the full unredacted reasoning, confidence and gate diagnostics.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              SaEmptyState(
                icon: Icons.lock_outline,
                title: 'Cannot read shift AI logs',
                message: _error!,
                accent: Sa.red,
              )
            else if (_logs.isEmpty)
              SaEmptyState(
                icon: Icons.nights_stay_outlined,
                title: 'No actions yet',
                message:
                    'The commander logs here the moment a shift with AI Commander enabled goes live.',
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
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-02 · BRIEFING OFFICER
// ═══════════════════════════════════════════════════════════════════════════

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
        setState(() => _latest = v is Map ? Map<String, dynamic>.from(v) : null);
      }
    }, onError: (_) {});
  }

  Future<void> _loadFactories() async {
    try {
      final snap =
          await FirebaseDatabase.instance.ref('hierarchy/factories').get();
      if (snap.value is Map && mounted) {
        final names = (snap.value as Map)
            .values
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
      final fact =
          await FirebaseDatabase.instance.ref('ai_briefing/factory').get();
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
          .get(Uri.parse('${AppConfig.briefingEndpoint}?${factoryQuery}force=1'))
          .timeout(const Duration(seconds: 25));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text(
            res.statusCode == 200
                ? 'Briefing regenerated — PM dashboards update live.'
                : 'Briefing endpoint replied ${res.statusCode}.',
            style: Sa.body(size: 12.5),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Regeneration failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
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

    return _AgentScroll(children: [
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
              title: 'BRIEFING DESK',
              subtitle:
                  'Writes the factory-aware morning briefing each Production Manager wakes up to.',
              accent: spec.accent,
              trailing: SaButton(
                label: 'REGENERATE NOW',
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
                  label: 'Briefings archived',
                  value: '$_historyCount',
                  icon: Icons.inventory_2_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Factory scopes',
                  value: '$_factoryCount',
                  icon: Icons.factory_outlined,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Generated total',
                  value: '${(_stats?['generated'] as num?)?.toInt() ?? '—'}',
                  icon: Icons.auto_awesome,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: 'Last generated',
                  value: _agoIso(_stats?['lastGeneratedAt'] ??
                      latest?['generatedAt']),
                  icon: Icons.schedule,
                  color: Sa.amber,
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
              icon: Icons.article_outlined,
              title: 'LATEST DISPATCH',
              subtitle: 'The exact words the PMs are reading right now.',
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
                        color: Sa.muted),
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
                    ? 'No briefing yet today'
                    : 'No briefing yet for $_selectedFactory',
                message:
                    'The officer writes the first dispatch when a PM opens their dashboard (or hit REGENERATE NOW).',
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
                        label: 'MODEL ACCURACY ${latest['accuracyPct']}%',
                        color: Sa.violet),
                  if (latest['topSupervisor'] is Map)
                    GlowChip(
                      label:
                          'TOP: ${((latest['topSupervisor'] as Map)['name'] ?? '—')}'
                          .toUpperCase(),
                      color: Sa.green,
                      icon: Icons.emoji_events_outlined,
                    ),
                  if (latest['predictiveInsight'] is Map &&
                      (latest['predictiveInsight'] as Map)['type'] != null)
                    GlowChip(
                      label:
                          'PREDICTS ${((latest['predictiveInsight'] as Map)['type'] ?? '')}'
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
    ]);
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
            label: 'ALL FACTORIES',
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
              ? LinearGradient(colors: [
                  color.withValues(alpha: 0.32),
                  color.withValues(alpha: 0.14),
                ])
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
            () => _logs = _mapToSortedList(event.snapshot.value, 'at'));
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
      list.sort((a, b) => (b['resolvedAt'] ?? '')
          .toString()
          .compareTo((a['resolvedAt'] ?? '').toString()));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Prompt override deployed — live within 60s.',
              style: Sa.body(size: 12.5)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Save failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
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
    return _AgentScroll(children: [
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
              title: 'CO-PILOT STATUS',
              subtitle:
                  'Serves resolution suggestions to supervisors, grounded in this plant’s real past fixes.',
              accent: spec.accent,
              trailing: GlowChip(
                label: 'LLAMA 3.2 · EDGE',
                color: spec.accent,
                icon: Icons.memory,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'Suggestions served',
                  value: '${(_stats?['served'] as num?)?.toInt() ?? 0}',
                  icon: Icons.tips_and_updates_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Last served',
                  value: _agoIso(_stats?['lastServedAt']),
                  icon: Icons.schedule,
                  color: Sa.amber,
                ),
                SaStatTile(
                  label: 'Knowledge entries',
                  value: '${_knowledge.length}',
                  icon: Icons.school_outlined,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Prompt',
                  value: _overrideActive ? 'CUSTOM' : 'FACTORY DEFAULT',
                  icon: Icons.edit_note,
                  color: _overrideActive ? Sa.green : Sa.muted,
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
              icon: Icons.edit_note,
              title: 'PROMPT LAB',
              subtitle:
                  'The exact instruction sent to Llama on Cloudflare for every suggestion. Edit, deploy, or revert to the factory default.',
              accent: spec.accent,
              trailing: _overrideActive
                  ? GlowChip(
                      label: 'OVERRIDE ACTIVE', color: Sa.green, pulse: true)
                  : GlowChip(label: 'DEFAULT', color: Sa.muted),
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
                      '{type}' => 'Human-readable alert type',
                      '{description}' => 'Supervisor’s sanitized description',
                      '{usine}' => 'Factory name',
                      '{convoyeur}' => 'Conveyor line number',
                      '{poste}' => 'Workstation number',
                      _ => 'Block of past resolutions for this exact location',
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
                  label: 'DEPLOY PROMPT',
                  icon: Icons.rocket_launch_outlined,
                  color: spec.accent,
                  busy: _savingPrompt,
                  onPressed: _savePrompt,
                ),
                const SizedBox(width: 10),
                SaButton(
                  label: 'REVERT TO DEFAULT',
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
              title: 'KNOWLEDGE BASE',
              subtitle:
                  'What the agent learns from: the latest validated resolutions it cites when supervisors ask for help.',
              accent: spec.accent,
              trailing: IconButton(
                tooltip: 'Refresh',
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
                      strokeWidth: 2, color: spec.accent),
                ),
              )
            else if (_knowledge.isEmpty)
              SaEmptyState(
                icon: Icons.menu_book_outlined,
                title: 'No learned fixes yet',
                message:
                    'Resolved alerts with a written resolution become this agent’s study material automatically.',
                accent: spec.accent,
              )
            else
              ..._knowledge.take(20).map((k) => _LogTile(
                    kind: (k['type'] ?? 'fix').toString(),
                    color: spec.accent,
                    title:
                        '${k['usine'] ?? ''} · L${k['convoyeur'] ?? '?'} WS${k['poste'] ?? '?'} — ${k['resolutionReason'] ?? ''}',
                    at: (k['resolvedAt'] ?? '').toString(),
                    details: k,
                  )),
          ],
        ),
      ),
      GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: Icons.receipt_long_outlined,
              title: 'SERVICE LOG',
              subtitle: 'Recent suggestion requests answered at the edge.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if (_logs.isEmpty)
              Text(
                'No requests logged yet — entries appear the moment a supervisor asks for an AI suggestion.',
                style: Sa.body(size: 12, color: Sa.textDim),
              )
            else
              ..._logs.take(30).map((l) => _LogTile(
                    kind: (l['outcome'] ?? 'served').toString(),
                    color: (l['outcome'] ?? '') == 'fallback'
                        ? Sa.amber
                        : spec.accent,
                    title:
                        '${l['type'] ?? ''} @ ${l['usine'] ?? ''} L${l['convoyeur'] ?? '?'} WS${l['poste'] ?? '?'} · ${l['historyUsed'] ?? 0} past fixes cited',
                    at: (l['at'] ?? '').toString(),
                    details: l,
                  )),
          ],
        ),
      ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-04 · SECURITY SENTINEL
// ═══════════════════════════════════════════════════════════════════════════

class _SecurityAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  final Map<String, dynamic>? health;
  const _SecurityAgentPanel(
      {required this.spec, required this.enabled, required this.health});

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
        .listen((event) {
      if (mounted) {
        setState(
            () => _actions = _mapToSortedList(event.snapshot.value, 'at'));
      }
    }, onError: (e) {
      if (mounted) setState(() => _error = '$e');
    });
    _settingsSub = FirebaseDatabase.instance
        .ref('ai_agents/security/settings')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted) {
        setState(() =>
            _settings = v is Map ? Map<String, dynamic>.from(v) : const {});
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text(
            'Defense disabled. The edge worker drops this shield within 60s — re-arm it when done testing.',
            style: Sa.body(size: 12.5, color: Sa.amber),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Update failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
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

    return _AgentScroll(children: [
      if (!widget.enabled) _OfflineBanner(spec: spec),
      GlassPanel(
        accent: spec.accent,
        glow: widget.enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: spec.icon,
              title: 'THREAT CONSOLE',
              subtitle:
                  'Standing guard on every worker endpoint. Blocks are logged with the exact signature that fired.',
              accent: spec.accent,
              trailing: GlowChip(
                label: '$armed/${_defenses.length} DEFENSES ARMED',
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
                  label: 'Blocks · 24h',
                  value: '${recent.length}',
                  icon: Icons.block_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Actions · last cron',
                  value:
                      '${(widget.health?['securityActions'] as num?)?.toInt() ?? 0}',
                  icon: Icons.gpp_maybe_outlined,
                  color: Sa.amber,
                ),
                SaStatTile(
                  label: 'Attack signatures',
                  value: '12',
                  icon: Icons.fingerprint,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Last block',
                  value: _actions.isEmpty ? '—' : _agoIso(_actions.first['at']),
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
              title: 'DEFENSE GRID',
              subtitle:
                  'Arm or stand down individual shields. Changes reach the edge worker within 60 seconds.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            for (final d in _defenses)
              _SettingTile(
                title: d.title,
                description: d.desc,
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
              title: 'THREAT MIX · 24H',
              subtitle: 'What the sentinel has been deflecting.',
              accent: spec.accent,
            ),
            const SizedBox(height: 14),
            if (byKind.isEmpty)
              Text('Clean skies — no blocks in the last 24 hours.',
                  style: Sa.body(size: 12, color: Sa.textDim))
            else
              ...byKind.entries.map((e) => _KindBar(
                    label: e.key,
                    count: e.value,
                    max: maxKind,
                    color: _kindColor(e.key),
                  )),
          ],
        ),
      ),
      GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: Icons.receipt_long_outlined,
              title: 'ENFORCEMENT LOG',
              subtitle:
                  'Every block with endpoint, fingerprint and matched patterns. Tap for the full record.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              SaEmptyState(
                icon: Icons.lock_outline,
                title: 'Cannot read security actions',
                message: _error!,
                accent: Sa.red,
              )
            else if (_actions.isEmpty)
              SaEmptyState(
                icon: Icons.verified_user_outlined,
                title: 'No enforcement actions',
                message: 'The sentinel has not needed to block anything yet.',
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
    ]);
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

  @override
  void initState() {
    super.initState();
    _accSub = FirebaseDatabase.instance
        .ref('ai_forecast/accuracy/latest')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted) {
        setState(() =>
            _accuracy = v is Map ? Map<String, dynamic>.from(v) : null);
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
            (a, b) => (a['day'] ?? '').toString().compareTo((b['day'] ?? '').toString()));
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
        setState(() =>
            _liveForecast = v is Map ? Map<String, dynamic>.from(v) : null);
      }
    }, onError: (_) {});
    _settingsSub = FirebaseDatabase.instance
        .ref('ai_agents/predictive/settings')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted) {
        setState(() =>
            _settings = v is Map ? Map<String, dynamic>.from(v) : const {});
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

    return _AgentScroll(children: [
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
              title: 'MODEL CORE',
              subtitle: deployed
                  ? 'On-device gradient-boosted forecaster, live on every Production Manager dashboard.'
                  : 'No model deployed yet — train one in the AI Training tab.',
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
                    GlowChip(label: 'LEARNING ✓', color: Sa.green),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'Dataset',
                  value: (_modelMeta['datasetName'] ?? '—').toString(),
                  icon: Icons.dataset_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Training samples',
                  value: '${(_modelMeta['sampleCount'] as num?)?.toInt() ?? 0}',
                  icon: Icons.grain,
                  color: Sa.blue,
                ),
                SaStatTile(
                  label: 'Boosted rounds',
                  value:
                      '${(_modelMeta['rounds'] as num?)?.toInt() ?? 0} + $adapted adapted',
                  icon: Icons.forest_outlined,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: 'Val accuracy',
                  value:
                      '${(((_modelMeta['valAccuracy'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%',
                  icon: Icons.verified_outlined,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Machines forecast',
                  value: '$machines',
                  icon: Icons.precision_manufacturing_outlined,
                  color: Sa.amber,
                ),
                SaStatTile(
                  label: 'Trained',
                  value: _agoIso(_modelMeta['trainedAt']),
                  icon: Icons.schedule,
                  color: Sa.muted,
                ),
              ],
            ),
          ],
        ),
      ),
      GlassPanel(
        accent: spec.accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: Icons.psychology_outlined,
              title: 'CONTINUOUS LEARNING',
              subtitle:
                  'The core snapshots tomorrow’s forecast daily, grades itself against the alerts that really happened, and boosts adaptation trees on fresh data.',
              accent: spec.accent,
              trailing: GlowChip(
                label: _accuracy == null
                    ? 'AWAITING FIRST GRADE'
                    : '${(_accuracy?['gradedDays'] as num?)?.toInt() ?? 0} DAYS GRADED',
                color: _accuracy == null ? Sa.muted : Sa.green,
                pulse: _accuracy != null,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (ctx, c) {
              final wide = c.maxWidth >= 760;
              final gauges = Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RingGauge(
                      label: 'PRECISION',
                      value: precision,
                      color: spec.accent),
                  _RingGauge(label: 'RECALL', value: recall, color: Sa.cyan),
                  _RingGauge(
                    label: 'BRIER',
                    value: (1 - brier).clamp(0.0, 1.0),
                    display: brier.toStringAsFixed(3),
                    color: Sa.green,
                  ),
                ],
              );
              final chart = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FORECAST QUALITY TREND · BRIER PER GRADED DAY',
                      style: Sa.mono(size: 8.5, color: Sa.muted)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 110,
                    child: _gradeHistory.isEmpty
                        ? Center(
                            child: Text(
                              'Trend appears after the first graded day.',
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
              return Column(children: [gauges, const SizedBox(height: 16), chart]);
            }),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('DATA ABSORPTION · ADAPTATION BUDGET',
                        style: Sa.mono(size: 8.5, color: Sa.muted)),
                    const Spacer(),
                    Text('$adapted / 60 extra trees per type',
                        style: Sa.mono(size: 9.5, color: spec.accent)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 8,
                    child: Stack(children: [
                      Container(color: Sa.border.withValues(alpha: 0.5)),
                      FractionallySizedBox(
                        widthFactor: (adapted / 60).clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: [spec.accent, Sa.cyan]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Graded $pairs machine-type pairs · $tp confirmed hits · last adapted ${_agoIso(_modelMeta['lastAdaptedAt'])} · a full retrain resets the budget.',
                  style: Sa.body(size: 10.5, color: Sa.textDim),
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
              title: 'LEARNING CONTROLS',
              subtitle:
                  'Pause parts of the learning loop without undeploying the model.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            _SettingTile(
              title: 'Continuous adaptation',
              description:
                  'Boost a few stiffly-regularized trees onto the live ensemble (~daily) from recent production alerts.',
              icon: Icons.auto_mode,
              accent: spec.accent,
              value: _settings['adaptationEnabled'] != false,
              onChanged: (v) => _setSetting('adaptationEnabled', v),
            ),
            _SettingTile(
              title: 'Outcome grading',
              description:
                  'Snapshot tomorrow’s forecast each day and grade it against reality (precision/recall/Brier above).',
              icon: Icons.fact_check_outlined,
              accent: spec.accent,
              value: _settings['outcomeGrading'] != false,
              onChanged: (v) => _setSetting('outcomeGrading', v),
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
              title: 'GRADED DAYS',
              subtitle:
                  'Each elapsed forecast day, scored against the alerts that materialized.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if (_gradeHistory.isEmpty)
              SaEmptyState(
                icon: Icons.pending_actions_outlined,
                title: 'No graded days yet',
                message:
                    'The first grade lands the day after a forecast snapshot — fully automatic, server-side.',
                accent: spec.accent,
              )
            else
              ..._gradeHistory.reversed.take(20).map((g) => _LogTile(
                    kind: 'graded',
                    color: spec.accent,
                    title:
                        '${g['day']} · ${g['pairs'] ?? 0} pairs · ${g['tp'] ?? 0} hits · Brier ${((g['brier'] as num?)?.toDouble() ?? 0).toStringAsFixed(3)}',
                    at: (g['gradedAt'] ?? '').toString(),
                    details: g,
                  )),
          ],
        ),
      ),
    ]);
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
              painter: _RingPainter(
                  value: v, color: color, track: Sa.border),
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
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
        math.pi * 2 * value, false, arc);
    canvas.drawCircle(
        c, r + 4, Paint()..color = color.withValues(alpha: 0.06 * value));
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
      for (final h in history) ((h['brier'] as num?)?.toDouble() ?? 0)
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
  static const _ghUrl = String.fromEnvironment('ALERTSYS_GITHUB_WORKER_URL', defaultValue: '');
  static const _wSecret = String.fromEnvironment('ALERTSYS_WORKER_SHARED_SECRET', defaultValue: '');

  final _cfg = FirebaseDatabase.instance.ref('ai_agents/guardian');
  final _sec = FirebaseDatabase.instance.ref('ai_agent_secrets/guardian');

  static const _gGreen = Color(0xFF3FB950);
  static const _gRed = Color(0xFFF85149);
  static const _gAmber = Color(0xFFD29922);
  static const _gPurple = Color(0xFFA371F7);

  List<Map<String, dynamic>> _ghRuns = [];
  List<Map<String, dynamic>> _ghPulls = [];
  bool _ghLoading = false;
  bool _ghConnected = false;
  Map<dynamic, dynamic> _secrets = {};
  Offset _simOffset = const Offset(10, 96);
  bool _deployAuto = false;
  Timer? _simTimer;

  @override
  void initState() {
    super.initState();
    _sec.get().then((s) {
      if (mounted && s.value is Map) setState(() => _secrets = s.value as Map<dynamic, dynamic>);
    });
    _loadGithub();
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadGithub() async {
    if (_ghUrl.isEmpty) return;
    setState(() => _ghLoading = true);
    final gh = GithubService(baseUrl: _ghUrl, sharedSecret: _wSecret);
    final connected = await gh.connected();
    final runs = connected ? await gh.runs() : <Map<String, dynamic>>[];
    final pulls = connected ? await gh.pulls() : <Map<String, dynamic>>[];
    if (!mounted) return;
    setState(() {
      _ghConnected = connected;
      _ghRuns = runs;
      _ghPulls = pulls;
      _ghLoading = false;
    });
  }

  bool _hasSecret(String k) => (_secrets[k]?.toString() ?? '').isNotEmpty;
  String _ts() => DateTime.now().toIso8601String().substring(11, 19);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: _cfg.onValue,
      builder: (context, snap) {
        final raw = snap.data?.snapshot.value;
        final cfg = (raw is Map) ? raw : const {};
        final settings = (cfg['settings'] is Map) ? cfg['settings'] as Map : const {};
        final enabled = cfg['enabled'] != false;
        final active = (cfg['activeRun'] is Map) ? cfg['activeRun'] as Map : null;
        _deployAuto = (settings['deployMode'] ?? 'human') == 'auto';
        return LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight.isFinite ? c.maxHeight : 1600.0;
            return SizedBox(
              height: h,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(enabled, settings),
                          const SizedBox(height: 14),
                          _pipeline(active),
                          const SizedBox(height: 14),
                          _terminal(active),
                          const SizedBox(height: 14),
                          _aiConfig(settings),
                          const SizedBox(height: 14),
                          _github(cfg),
                          const SizedBox(height: 14),
                          _knowledge(cfg),
                          const SizedBox(height: 14),
                          _githubLive(),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: _simOffset.dx.clamp(0.0, (c.maxWidth - 176).clamp(0.0, double.infinity)),
                    top: _simOffset.dy.clamp(0.0, (h - 120).clamp(0.0, double.infinity)),
                    child: _simToolbar(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── movable simulate toolbar ──
  Widget _simToolbar() {
    final sims = <List<dynamic>>[
      ['Login error', Icons.login, 'high', 'login screen error — users cannot sign in', 'claude-opus-4-8'],
      ['Notifications', Icons.notifications_off, 'high', 'alerts not reaching supervisors', 'claude-opus-4-8'],
      ['Worker fail', Icons.dns, 'high', 'cloudflare worker endpoint failing', 'claude-opus-4-8'],
      ['Version', Icons.sync_problem, 'medium', 'dependency version mismatch breaks build', 'claude-sonnet-4-6'],
      ['Tab broken', Icons.tab_unselected, 'medium', 'supervisor tab blank / not loading', 'claude-sonnet-4-6'],
      ['Test fail', Icons.science, 'low', 'flutter test failing on a widget test', 'claude-haiku-4-5'],
    ];
    return Container(
      width: 166,
      decoration: BoxDecoration(
        color: Sa.panelSolid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.borderBright),
        boxShadow: [BoxShadow(color: Sa.shadow, blurRadius: 20, offset: const Offset(0, 8))],
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(children: [
                Icon(Icons.drag_indicator, size: 15, color: Sa.muted),
                const SizedBox(width: 5),
                Text('SIMULATE', style: Sa.body(size: 10.5, color: Sa.textDim)),
              ]),
            ),
          ),
          for (final s in sims)
            InkWell(
              onTap: () => _simulateIncident(s[0] as String, s[2] as String, s[3] as String, s[4] as String),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(children: [
                  Icon(s[1] as IconData, size: 14,
                      color: s[2] == 'high' ? _gRed : (s[2] == 'medium' ? _gAmber : Sa.muted)),
                  const SizedBox(width: 8),
                  Text(s[0] as String, style: Sa.body(size: 12, color: Sa.text)),
                ]),
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
          SizedBox(width: 40, height: 40, child: _AgentGlyph(spec: widget.spec, size: 40, radius: 11)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GUARDIAN', style: Sa.display(size: 17)),
                Text('autonomous fix pipeline', style: Sa.body(size: 12, color: Sa.muted)),
              ],
            ),
          ),
          _deployToggle('Automatic', _deployAuto, () => _saveSetting('deployMode', 'auto')),
          const SizedBox(width: 6),
          _deployToggle('Human review', !_deployAuto, () => _saveSetting('deployMode', 'human')),
          const SizedBox(width: 12),
          GlowChip(label: enabled ? 'ARMED' : 'OFF', color: enabled ? _gGreen : Sa.muted, pulse: enabled),
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
          color: active ? widget.spec.accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? widget.spec.accent.withValues(alpha: 0.5) : Sa.border),
        ),
        child: Text(label, style: Sa.body(size: 11.5, color: active ? widget.spec.accent : Sa.textDim)),
      ),
    );
  }

  // ── dynamic pipeline ──
  Widget _pipeline(Map? active) {
    if (active == null) {
      return _panel('PIPELINE', Icons.route, Row(children: [
        Icon(Icons.check_circle_outline, color: _gGreen, size: 18),
        const SizedBox(width: 9),
        Expanded(child: Text('No active incident — pipeline idle. Guardian is watching.',
            style: Sa.body(size: 12.5, color: Sa.muted))),
      ]));
    }
    final stages = ['detect', 'context', 'fix', 'review', 'gate', 'deploy'];
    final labels = ['Detect', 'Gather context', 'Fix', 'Review + tests', 'Gate', 'PR / deploy'];
    final cur = stages.indexOf((active['stage'] ?? 'detect').toString());
    final status = (active['status'] ?? 'running').toString();
    final done = status == 'deployed' || status == 'pr_open';
    final failed = status == 'failed';
    final sev = (active['severity'] ?? 'high').toString().toUpperCase();
    return GlassPanel(
      accent: _gRed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GlowChip(label: done ? 'RESOLVED' : 'INCIDENT ACTIVE', color: done ? _gGreen : _gRed, pulse: !done),
            const SizedBox(width: 8),
            GlowChip(label: sev, color: sev == 'HIGH' ? _gRed : (sev == 'MEDIUM' ? _gAmber : Sa.muted)),
            const Spacer(),
            InkWell(onTap: _dismissIncident, child: Icon(Icons.close, size: 16, color: Sa.muted)),
          ]),
          const SizedBox(height: 6),
          Text((active['title'] ?? 'incident').toString(), style: Sa.body(size: 12.5, color: Sa.text)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < stages.length; i++)
              _stageChip(labels[i],
                  done ? 'done' : (i < cur ? 'done' : (i == cur ? (failed ? 'failed' : 'active') : 'pending'))),
          ]),
        ],
      ),
    );
  }

  Widget _stageChip(String label, String state) {
    Color c;
    Widget ic;
    switch (state) {
      case 'done':
        c = _gGreen;
        ic = Icon(Icons.check, size: 13, color: c);
        break;
      case 'active':
        c = _gAmber;
        ic = SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: c));
        break;
      case 'failed':
        c = _gRed;
        ic = Icon(Icons.close, size: 13, color: c);
        break;
      default:
        c = Sa.muted;
        ic = Icon(Icons.circle_outlined, size: 12, color: c);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.45)),
        color: c.withValues(alpha: 0.10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [ic, const SizedBox(width: 6), Text(label, style: Sa.body(size: 11.5, color: c))]),
    );
  }

  // ── terminal ──
  Widget _terminal(Map? active) {
    final logs = (active != null && active['log'] is List)
        ? (active['log'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final running = active != null && (active['status'] ?? '') == 'running';
    return Container(
      decoration: BoxDecoration(color: Sa.termBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: Sa.termBorder)),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.terminal, size: 14, color: Sa.termDim),
            const SizedBox(width: 6),
            Text('GUARDIAN TERMINAL', style: TextStyle(color: Sa.termDim, fontSize: 11, letterSpacing: 0.5, fontFamily: 'monospace')),
            const Spacer(),
            if (running) ...[
              SizedBox(width: 9, height: 9, child: CircularProgressIndicator(strokeWidth: 2, color: _gAmber)),
              const SizedBox(width: 6),
              Text('working', style: TextStyle(color: _gAmber, fontSize: 11, fontFamily: 'monospace')),
            ],
          ]),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            Text('guardian idle \$ watching for incidents…',
                style: TextStyle(color: Sa.termMuted, fontSize: 11.5, fontFamily: 'monospace'))
          else
            for (final l in logs)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(l, style: TextStyle(color: Sa.termText, fontSize: 11.5, height: 1.5, fontFamily: 'monospace')),
              ),
        ],
      ),
    );
  }

  // ── AI config ──
  Widget _aiConfig(Map settings) {
    final auto = settings['autoModelSelect'] != false;
    return _panel('AI CONFIGURATION', Icons.memory, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _aiCard('Fix AI', 'fix', settings, Sa.blue)),
          const SizedBox(width: 10),
          Expanded(child: _aiCard('Review AI', 'review', settings, _gPurple)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text('Auto-select model by severity', style: Sa.body(size: 12, color: Sa.textDim)),
          const Spacer(),
          Switch(value: auto, onChanged: (v) => _saveSetting('autoModelSelect', v)),
        ]),
      ],
    ));
  }

  Widget _aiCard(String title, String role, Map settings, Color accent) {
    final provId = (settings['${role}Provider'] ?? (role == 'fix' ? 'anthropic' : 'openai')).toString();
    final prov = _Providers.list.firstWhere((p) => p.id == provId, orElse: () => _Providers.list.first);
    final model = (settings['${role}Model'] ?? prov.defaultModel).toString();
    final keySet = _hasSecret('${role}ApiKey');
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: Sa.bgRaised, borderRadius: BorderRadius.circular(10), border: Border.all(color: Sa.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Sa.body(size: 12.5, color: accent)),
          const SizedBox(height: 8),
          InkWell(onTap: () => _pickProvider(role, settings), child: _fieldRow(Icons.expand_more, '${prov.name} · $model')),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _setSecret('${role}ApiKey', '$title API key', prov.tokenHint),
            child: _fieldRow(Icons.key, keySet ? '•••••••• set' : 'set API key',
                trailing: keySet ? Icon(Icons.check, size: 14, color: _gGreen) : null),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(IconData ic, String text, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Sa.bg, borderRadius: BorderRadius.circular(7), border: Border.all(color: Sa.border)),
      child: Row(children: [
        Icon(ic, size: 14, color: Sa.muted),
        const SizedBox(width: 7),
        Expanded(child: Text(text, overflow: TextOverflow.ellipsis, style: Sa.body(size: 12, color: Sa.text))),
        if (trailing != null) trailing,
      ]),
    );
  }

  // ── github connection ──
  Widget _github(Map cfg) {
    final repo = (cfg['repo'] ?? '').toString();
    return _panel('GITHUB CONNECTION', Icons.hub_outlined, Row(children: [
      Expanded(child: InkWell(onTap: _setRepo, child: _fieldRow(Icons.account_tree, repo.isEmpty ? 'link repository (owner/name)' : repo))),
      const SizedBox(width: 10),
      Expanded(child: InkWell(
        onTap: () => _setSecret('githubToken', 'GitHub token', 'github_pat_…'),
        child: _fieldRow(Icons.vpn_key, _hasSecret('githubToken') ? '•••••••• set' : 'set token',
            trailing: _ghConnected ? Icon(Icons.check, size: 14, color: _gGreen) : null),
      )),
    ]));
  }

  // ── knowledge ──
  Widget _knowledge(Map cfg) {
    List<String> listOf(String k) {
      final v = cfg[k];
      if (v is List) return v.map((e) => e is Map ? (e['name'] ?? 'file').toString() : e.toString()).toList();
      return const [];
    }
    return _panel('KNOWLEDGE · upload .md', Icons.menu_book_outlined, Row(children: [
      Expanded(child: _mdColumn('Instructions', 'instructions', listOf('instructions'), Sa.blue)),
      const SizedBox(width: 10),
      Expanded(child: _mdColumn('Skills', 'skills', listOf('skills'), _gGreen)),
    ]));
  }

  Widget _mdColumn(String title, String key, List<String> files, Color accent) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: Sa.bgRaised, borderRadius: BorderRadius.circular(10), border: Border.all(color: Sa.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(title, style: Sa.body(size: 12.5, color: accent)),
            const Spacer(),
            Text('${files.length}', style: Sa.body(size: 11, color: Sa.muted)),
          ]),
          const SizedBox(height: 8),
          for (var i = 0; i < files.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Icon(Icons.description_outlined, size: 13, color: Sa.muted),
                const SizedBox(width: 6),
                Expanded(child: Text(files[i], overflow: TextOverflow.ellipsis, style: Sa.body(size: 11.5, color: Sa.textDim))),
                InkWell(
                  onTap: () => _deleteMd(key, i),
                  child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.delete_outline, size: 15, color: _gRed)),
                ),
              ]),
            ),
          const SizedBox(height: 4),
          SaButton(label: 'Upload .md', icon: Icons.upload_file, outlined: true, onPressed: () => _uploadMd(key)),
        ],
      ),
    );
  }

  // ── live github (matches the GitHub screenshots) ──
  Widget _githubLive() {
    return _panel('GITHUB · LIVE', Icons.bolt, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Workflow runs', style: Sa.body(size: 12, color: Sa.textDim)),
          const Spacer(),
          if (_ghLoading)
            SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Sa.cyan))
          else
            InkWell(onTap: _loadGithub, child: Icon(Icons.refresh, size: 17, color: Sa.cyan)),
        ]),
        const SizedBox(height: 4),
        if (!_ghConnected)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Sa.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: Sa.border)),
            child: Row(children: [
              Icon(Icons.link_off, size: 16, color: Sa.muted),
              const SizedBox(width: 9),
              Expanded(child: Text(
                _ghUrl.isEmpty
                    ? 'Set ALERTSYS_GITHUB_WORKER_URL (build define) to stream live Actions + PRs.'
                    : 'Link a repo + GitHub token above to stream live Actions + PRs.',
                style: Sa.body(size: 12, color: Sa.muted))),
            ]),
          )
        else ...[
          for (final r in _ghRuns.take(6)) _ghActionRow(r),
          const SizedBox(height: 12),
          Text('Pull requests', style: Sa.body(size: 12, color: Sa.textDim)),
          const SizedBox(height: 4),
          for (final p in _ghPulls.take(6)) _ghPrRow(p),
        ],
      ],
    ));
  }

  Widget _ghActionRow(Map<String, dynamic> r) {
    final concl = (r['conclusion'] ?? r['status'] ?? '').toString();
    final c = _statusColor(concl);
    final running = concl.contains('progress') || concl.contains('queued') || concl.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Sa.border.withValues(alpha: 0.5)))),
      child: Row(children: [
        running
            ? SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: _gAmber))
            : Icon(_statusIcon(concl), size: 17, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['name'] ?? 'workflow'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Sa.body(size: 13, color: Sa.text)),
            Text('#${r['runNumber'] ?? '?'} · ${r['event'] ?? ''}', style: Sa.body(size: 11, color: Sa.muted)),
          ]),
        ),
        if ((r['branch'] ?? '').toString().isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Sa.blue.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Text(r['branch'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: Sa.body(size: 10.5, color: Sa.blue)),
          ),
        const SizedBox(width: 8),
        Text(_ago(r['createdAt']?.toString()), style: Sa.body(size: 11, color: Sa.muted)),
      ]),
    );
  }

  Widget _ghPrRow(Map<String, dynamic> p) {
    final state = (p['state'] ?? '').toString();
    final c = state == 'merged' ? _gPurple : (state == 'open' ? _gGreen : Sa.muted);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Sa.border.withValues(alpha: 0.5)))),
      child: Row(children: [
        Icon(Icons.call_merge, size: 16, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Sa.body(size: 13, color: Sa.text)),
            Row(children: [
              Text('#${p['number'] ?? '?'} · ${p['user'] ?? ''}', style: Sa.body(size: 11, color: Sa.muted)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Sa.border)),
                child: Text('Bot', style: Sa.body(size: 9, color: Sa.muted)),
              ),
            ]),
          ]),
        ),
        GlowChip(label: state.toUpperCase(), color: c),
      ]),
    );
  }

  // ── helpers ──
  Widget _panel(String label, IconData ic, Widget child) {
    return GlassPanel(
      accent: widget.spec.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(ic, size: 14, color: Sa.muted), const SizedBox(width: 7), Text(label, style: Sa.body(size: 11, color: Sa.muted))]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  String _ago(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  Color _statusColor(String s) {
    s = s.toLowerCase();
    if (s.contains('success') || s.contains('complet')) return _gGreen;
    if (s.contains('fail') || s.contains('cancel')) return _gRed;
    if (s.contains('progress') || s.contains('queued') || s.contains('pending')) return _gAmber;
    return Sa.muted;
  }

  IconData _statusIcon(String s) {
    s = s.toLowerCase();
    if (s.contains('success') || s.contains('complet')) return Icons.check_circle;
    if (s.contains('fail') || s.contains('cancel')) return Icons.cancel;
    return Icons.sync;
  }

  Future<void> _saveSetting(String k, dynamic v) =>
      _cfg.child('settings').update({k: v, 'updatedAt': DateTime.now().toUtc().toIso8601String()});

  Future<void> _dismissIncident() async {
    _simTimer?.cancel();
    await _cfg.child('activeRun').remove();
  }

  Future<void> _simulateIncident(String title, String severity, String description, String model) async {
    _simTimer?.cancel();
    final mode = _deployAuto ? 'automatic' : 'human';
    const target = 'tool/guardian_drill_target.mjs';
    var dispatched = false;
    if (_ghUrl.isNotEmpty) {
      try {
        dispatched = await GithubService(baseUrl: _ghUrl, sharedSecret: _wSecret)
            .dispatchDrill(mode: mode, target: target);
      } catch (_) {}
    }
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
          return _deployAuto ? 'deploy   > merged to main, production live' : 'deploy   > opened PR, awaiting human review';
      }
    }

    final logs = <String>[
      dispatched
          ? '[${_ts()}] dispatch  > guardian-drill triggered on GitHub (mode=$mode)'
          : '[${_ts()}] dispatch  > local preview (link the GitHub worker to go live)',
      '[${_ts()}] incident: $title ($severity)',
      '[${_ts()}] ${line('detect')}',
    ];
    await _cfg.child('activeRun').set({
      'title': title, 'severity': severity, 'description': description, 'model': model,
      'stage': 'detect', 'status': 'running', 'log': logs, 'simulated': true,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    FirebaseDatabase.instance.ref('bugs/client').push().set({
      'area': 'simulation', 'severity': severity, 'message': description,
      'at': DateTime.now().toUtc().toIso8601String(), 'simulated': true,
    });
    var i = 0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 1700), (t) async {
      i++;
      if (i >= stages.length) {
        t.cancel();
        logs.add('[${_ts()}] ${line('deploy')}');
        logs.add('[${_ts()}] ${_deployAuto ? '✔ resolved & deployed' : '✔ PR opened — awaiting review'}');
        await _cfg.child('activeRun').update({'stage': 'deploy', 'status': _deployAuto ? 'deployed' : 'pr_open', 'log': logs});
        return;
      }
      logs.add('[${_ts()}] ${line(stages[i])}');
      await _cfg.child('activeRun').update({'stage': stages[i], 'status': 'running', 'log': logs});
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final p in _Providers.list)
              ListTile(
                leading: Icon(Icons.bolt, color: p.color),
                title: Text(p.name, style: Sa.body(size: 14, color: Sa.text)),
                subtitle: Text(p.defaultModel.isEmpty ? 'custom endpoint' : p.defaultModel, style: Sa.body(size: 11, color: Sa.muted)),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ]),
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
        content: TextField(controller: ctl, obscureText: true,
            style: Sa.body(size: 13, color: Sa.text),
            decoration: InputDecoration(hintText: hint, hintStyle: Sa.body(size: 13, color: Sa.muted), border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text('Save', style: Sa.body(size: 13, color: Sa.cyan))),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      await _sec.update({field: v, 'updatedAt': DateTime.now().toUtc().toIso8601String()});
      final s = await _sec.get();
      if (mounted && s.value is Map) setState(() => _secrets = s.value as Map<dynamic, dynamic>);
    }
  }

  Future<void> _setRepo() async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        title: Text('Link GitHub repository', style: Sa.body(size: 15, color: Sa.text)),
        content: TextField(controller: ctl,
            style: Sa.body(size: 13, color: Sa.text),
            decoration: InputDecoration(hintText: 'owner/repository', hintStyle: Sa.body(size: 13, color: Sa.muted), border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text('Save', style: Sa.body(size: 13, color: Sa.cyan))),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      await _cfg.update({'repo': v});
      _loadGithub();
    }
  }

  Future<void> _uploadMd(String key) async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['md'], withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;
    final content = utf8.decode(bytes, allowMalformed: true);
    final snap = await _cfg.child(key).get();
    final list = (snap.value is List) ? List<dynamic>.from(snap.value as List) : <dynamic>[];
    list.add({'name': f.name, 'content': content, 'at': DateTime.now().toUtc().toIso8601String()});
    await _cfg.child(key).set(list);
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
        ? 'NO CREDENTIAL ON FILE'
        : token.length <= 4
            ? '••••'
            : '${'•' * (token.length - 4).clamp(4, 24)}${token.substring(token.length - 4)}';

    return _AgentScroll(children: [
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
              title: spec.name,
              subtitle: spec.codename,
              accent: spec.accent,
              trailing: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GlowChip(
                    label: 'CUSTOM UNIT',
                    color: spec.accent,
                    icon: Icons.auto_awesome,
                  ),
                  GlowChip(
                    label: widget.enabled ? 'ONLINE' : 'OFFLINE',
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
                  label: 'Provider',
                  value: provider.name,
                  icon: Icons.cloud_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Model',
                  value: (spec.model ?? '').isEmpty ? '—' : spec.model!,
                  icon: Icons.memory,
                  color: Sa.blue,
                ),
                SaStatTile(
                  label: 'Credential',
                  value: token.isEmpty ? 'MISSING' : 'ON FILE',
                  icon: Icons.vpn_key_outlined,
                  color: token.isEmpty ? Sa.amber : Sa.green,
                ),
                SaStatTile(
                  label: 'Deployed',
                  value: _agoIso(spec.createdAt),
                  icon: Icons.schedule,
                  color: Sa.muted,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SaButton(
                  label: 'EDIT AGENT',
                  icon: Icons.tune,
                  color: spec.accent,
                  outlined: true,
                  onPressed: widget.onEdit,
                ),
                const SizedBox(width: 10),
                SaButton(
                  label: 'DELETE',
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
              title: 'PROFILE',
              subtitle: 'Who this agent is and what it stands for.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if ((spec.description ?? '').trim().isEmpty)
              Text('No description provided.',
                  style: Sa.body(size: 12, color: Sa.textDim))
            else
              Text(spec.description!, style: Sa.body(size: 12.5)),
          ],
        ),
      ),
      // ── MISSION / TASKS ───────────────────────────────────────────────
      _CustomDocPanel(
        icon: Icons.assignment_outlined,
        title: 'MISSION BRIEF',
        subtitle: 'The tasks this agent is responsible for.',
        accent: spec.accent,
        body: spec.tasks ?? '',
        fileName: spec.tasksFile,
        emptyMsg: 'No tasks defined yet — edit the agent to brief it.',
      ),
      // ── SKILLS ────────────────────────────────────────────────────────
      _CustomDocPanel(
        icon: Icons.school_outlined,
        title: 'SKILLS & CAPABILITIES',
        subtitle: 'What this agent knows how to do.',
        accent: spec.accent,
        body: spec.skills ?? '',
        fileName: spec.skillsFile,
        emptyMsg: 'No skills listed yet.',
      ),
      // ── CREDENTIALS ───────────────────────────────────────────────────
      GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: Icons.vpn_key_outlined,
              title: 'CREDENTIALS',
              subtitle:
                  'The LLM provider and API token this agent authenticates with.',
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
                        color: provider.color.withValues(alpha: 0.4)),
                  ),
                  child: Center(
                      child: _ProviderLogo(
                          provider: provider, size: 28, color: provider.color)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(provider.name, style: Sa.heading(size: 14)),
                      Text(
                        (spec.model ?? '').isEmpty
                            ? 'Default model'
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      tooltip: _reveal ? 'Hide' : 'Reveal',
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
                      tooltip: 'Copy',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: token));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          backgroundColor: Sa.panelSolid,
                          content: Text('Token copied to clipboard.',
                              style: Sa.body(size: 12.5)),
                        ));
                      },
                      icon: const Icon(Icons.copy_all_outlined,
                          size: 15, color: Sa.termDim),
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
                    'Stored separately in a superadmin-only credential vault. Treat it as a secret — rotate it from EDIT AGENT if it leaks.',
                    style: Sa.body(size: 10.5, color: Sa.muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ]);
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
              child: SelectableText(body,
                  style: Sa.mono(size: 11.5, color: Sa.termText)),
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
        text: (e?.codename ?? '') == 'CUSTOM UNIT' ? '' : (e?.codename ?? ''));
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
      final res =
          await FilePicker.pickFiles(type: FileType.image, withData: true);
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
                gradient: LinearGradient(colors: [
                  accent.withValues(alpha: Sa.isDark ? 0.18 : 0.10),
                  Colors.transparent,
                ]),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        accent.withValues(alpha: 0.3),
                        accent.withValues(alpha: 0.08),
                      ]),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.5)),
                    ),
                    child: logoBytes != null
                        ? Padding(
                            padding: const EdgeInsets.all(5),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(logoBytes,
                                  fit: BoxFit.cover, gaplessPlayback: true),
                            ),
                          )
                        : Icon(_kAgentIcons[_iconKey], color: accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(editing ? 'EDIT AGENT' : 'DEPLOY NEW AGENT',
                            style: Sa.display(size: 16)),
                        Text(
                          'Configure a custom autonomous unit for the fleet',
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
                    _label('IDENTITY', accent),
                    const SizedBox(height: 10),
                    _textField(_name,
                        hint: 'Agent name (e.g. Quality Inspector)',
                        icon: Icons.badge_outlined),
                    const SizedBox(height: 10),
                    _textField(_codename,
                        hint: 'Codename (optional, e.g. UNIT-07 · SENTRY)',
                        icon: Icons.tag),
                    const SizedBox(height: 10),
                    _textField(_description,
                        hint: 'Short description of what this agent is for',
                        icon: Icons.notes_outlined,
                        maxLines: 2),
                    const SizedBox(height: 20),

                    _label('APPEARANCE', accent),
                    const SizedBox(height: 10),
                    _appearanceRow(accent, logoBytes != null),
                    const SizedBox(height: 20),

                    _label('MISSION · TASKS', accent),
                    const SizedBox(height: 6),
                    Text(
                      'Describe the tasks, or attach a brief / spec file.',
                      style: Sa.body(size: 10.5, color: Sa.textDim),
                    ),
                    const SizedBox(height: 10),
                    _textField(_tasks,
                        hint:
                            'e.g. Review incoming quality alerts, draft a containment checklist…',
                        maxLines: 4),
                    const SizedBox(height: 8),
                    _attachRow(
                      fileName: _tasksFile,
                      onAttach: () => _attachText(tasks: true),
                      onClear: () => setState(() => _tasksFile = null),
                      accent: accent,
                    ),
                    const SizedBox(height: 20),

                    _label('SKILLS · CAPABILITIES', accent),
                    const SizedBox(height: 6),
                    Text(
                      'List the skills, or attach a capability sheet.',
                      style: Sa.body(size: 10.5, color: Sa.textDim),
                    ),
                    const SizedBox(height: 10),
                    _textField(_skills,
                        hint:
                            'e.g. Root-cause analysis, ISO 9001 knowledge, French + English…',
                        maxLines: 4),
                    const SizedBox(height: 8),
                    _attachRow(
                      fileName: _skillsFile,
                      onAttach: () => _attachText(tasks: false),
                      onClear: () => setState(() => _skillsFile = null),
                      accent: accent,
                    ),
                    const SizedBox(height: 20),

                    _label('MODEL PROVIDER', accent),
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
                    _textField(_model,
                        hint: 'Model id (e.g. ${_providerHint()})',
                        icon: Icons.memory),
                    const SizedBox(height: 12),
                    _textField(
                      _token,
                      hint: _provider == null
                          ? 'API token / key'
                          : 'API token — ${_Providers.of(_provider).tokenHint}',
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
                              'A name and a model provider are required.',
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
                    label: 'CANCEL',
                    icon: Icons.close,
                    color: Sa.muted,
                    outlined: true,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  SaButton(
                    label: editing ? 'SAVE CHANGES' : 'DEPLOY AGENT',
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
        prefixIcon:
            icon != null ? Icon(icon, size: 17, color: Sa.muted) : null,
        suffixIcon: suffix,
        isDense: true,
        filled: true,
        fillColor: Sa.bgRaised.withValues(alpha: 0.6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
              label: hasLogo ? 'REPLACE LOGO' : 'UPLOAD LOGO',
              icon: Icons.image_outlined,
              color: accent,
              outlined: true,
              busy: _logoBusy,
              onPressed: _attachLogo,
            ),
            const SizedBox(width: 10),
            if (hasLogo)
              SaButton(
                label: 'REMOVE',
                icon: Icons.delete_outline,
                color: Sa.red,
                outlined: true,
                onPressed: () => setState(() => _logoData = null),
              ),
            const Spacer(),
            Text(hasLogo ? 'Custom logo set' : 'No logo · pick an icon',
                style: Sa.mono(size: 9, color: Sa.muted)),
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
                    child: Icon(entry.value,
                        size: 18,
                        color: _iconKey == entry.key ? accent : Sa.textDim),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Text('ACCENT', style: Sa.mono(size: 9, color: Sa.muted)),
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
                                  color: Color(0xFF000000 | rgb)
                                      .withValues(alpha: 0.5),
                                  blurRadius: 8),
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
                Text('ATTACH FILE',
                    style: Sa.mono(
                        size: 9.5, color: accent, weight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        if ((fileName ?? '').isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Sa.bgRaised.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Sa.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined,
                      size: 12, color: Sa.textDim),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(fileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Sa.mono(size: 9.5, color: Sa.textDim)),
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
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
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
                            color: _blood
                                .withValues(alpha: 0.4 + 0.3 * _c.value),
                            blurRadius: 24 + 10 * _c.value,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 38),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'DECOMMISSION AGENT',
                    style: Sa.display(size: 18, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
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
                          weight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'This permanently removes the agent, its mission brief, skills and stored API credential from the fleet registry.\n\nThis action cannot be undone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
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
                                color: Colors.white.withValues(alpha: 0.25)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('CANCEL',
                              style: Sa.heading(
                                  size: 12.5,
                                  color: const Color(0xFFE9C4C8))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: _blood,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.delete_forever,
                                  size: 17, color: Colors.white),
                              const SizedBox(width: 8),
                              Text('DELETE PERMANENTLY',
                                  style: Sa.heading(
                                      size: 12.5, color: Colors.white)),
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
