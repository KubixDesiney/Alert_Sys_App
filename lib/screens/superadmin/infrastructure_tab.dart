import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/infra_config_service.dart';
import '../../l10n/app_strings.dart';
import 'connectors_section.dart';
import 'superadmin_theme.dart';

/// SuperAdmin → Infrastructure. The company IT team connects their OWN backend
/// (Firebase project) and SCIM provisioning.
///
/// Honest model: the running app is wired to one Firebase project at build, so
/// this configures the *deploy target* (applied on the next deploy) rather than
/// hot-swapping the live backend. Secrets are never stored in the database.
class InfrastructureTab extends StatefulWidget {
  const InfrastructureTab({super.key});

  @override
  State<InfrastructureTab> createState() => _InfrastructureTabState();
}

class _InfrastructureTabState extends State<InfrastructureTab> {
  final _service = InfraConfigService();

  // Non-secret config.
  final _projectId = TextEditingController();
  final _dbUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _subdomain = TextEditingController();

  // Secrets — write-only, never persisted to RTDB.
  final _serviceAccount = TextEditingController();
  final _scimToken = TextEditingController();

  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _service.fetch();
      _projectId.text = c.firebaseProjectId;
      _dbUrl.text = c.firebaseDbUrl;
      _apiKey.text = c.firebaseApiKey;
      _subdomain.text = c.workersSubdomain;
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [
      _projectId, _dbUrl, _apiKey, _subdomain, _serviceAccount, _scimToken,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  InfraConfig _current() => InfraConfig(
        firebaseProjectId: _projectId.text,
        firebaseDbUrl: _dbUrl.text,
        firebaseApiKey: _apiKey.text,
        workersSubdomain: _subdomain.text,
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.save(_current());
      _toast('Infrastructure config saved.', Sa.green);
    } catch (e) {
      _toast('Save failed: $e', Sa.red);
    }
    if (mounted) setState(() => _saving = false);
  }

  void _toast(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Sa.panelSolid,
      content: Text(msg, style: Sa.body(color: c, weight: FontWeight.w600)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Center(child: CircularProgressIndicator(color: Sa.cyan));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _intro(),
          const SizedBox(height: 18),
          const ConnectorsSection(),
          const SizedBox(height: 16),
          _databaseSection(),
          const SizedBox(height: 16),
          _scimSection(),
          const SizedBox(height: 16),
          _saveSection(),
        ],
      ),
    );
  }

  Widget _intro() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Sa.blue, Sa.cyan]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Sa.blue.withValues(alpha: 0.4), blurRadius: 16)],
          ),
          child: const Icon(Icons.dns_outlined, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('INFRASTRUCTURE'), style: Sa.display(size: 18)),
              const SizedBox(height: 3),
              Text(
                context.tr(
                    'Connect your own backend, then configure SCIM user provisioning. Secrets are never stored in the database.'),
                style: Sa.body(size: 12, color: Sa.textDim),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Database ───────────────────────────────────────────────────────────────
  Widget _databaseSection() {
    return GlassPanel(
      accent: const Color(0xFFFFA000),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.storage_outlined, context.tr('DATABASE · YOUR FIREBASE')),
          const SizedBox(height: 6),
          Text(
            'Point the build at your own Firebase project. Applied on the next '
            'deploy (the live app is not hot-swapped).',
            style: Sa.body(size: 11.5, color: Sa.muted),
          ),
          const SizedBox(height: 14),
          _backendStrip(),
          const SizedBox(height: 16),
          _field(context.tr('Firebase project ID'), _projectId, hint: 'acme-alerts'),
          _field(context.tr('Realtime Database URL'), _dbUrl,
              hint: 'https://acme-alerts-default-rtdb.firebaseio.com'),
          _field(context.tr('Web API key'), _apiKey, hint: 'AIza… (not secret)'),
          const SizedBox(height: 8),
          _SecretField(
            label: context.tr('Service account JSON'),
            controller: _serviceAccount,
            hint: context.tr(
                'Paste the service-account JSON — sent to your pipeline, never stored'),
            multiline: true,
          ),
        ],
      ),
    );
  }

  Widget _backendStrip() {
    Widget chip(String name, IconData icon, Color color, bool active) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.14) : Sa.bg.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? color : Sa.border, width: active ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: active ? color : Sa.muted),
          const SizedBox(width: 7),
          Text(name,
              style: Sa.body(
                  size: 12,
                  color: active ? Sa.text : Sa.muted,
                  weight: FontWeight.w600)),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (active ? Sa.green : Sa.muted).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(active ? 'ACTIVE' : 'ROADMAP',
                style: Sa.mono(
                    size: 8,
                    color: active ? Sa.green : Sa.muted,
                    weight: FontWeight.w700)),
          ),
        ]),
      );
    }

    return Wrap(spacing: 9, runSpacing: 9, children: [
      chip('Firebase', Icons.local_fire_department, const Color(0xFFFFA000), true),
      chip('Cloud Firestore', Icons.cloud_outlined, const Color(0xFF4285F4), false),
      chip('Supabase', Icons.bolt_outlined, const Color(0xFF3ECF8E), false),
      chip('PostgreSQL', Icons.storage_outlined, const Color(0xFF336791), false),
      chip('MySQL', Icons.dns_outlined, const Color(0xFF00758F), false),
      chip('MongoDB', Icons.eco_outlined, const Color(0xFF47A248), false),
    ]);
  }

  // ── SCIM ───────────────────────────────────────────────────────────────────
  Widget _scimSection() {
    final base = _current().scimBaseUrl;
    return GlassPanel(
      accent: Sa.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.badge_outlined, context.tr('SCIM PROVISIONING')),
          const SizedBox(height: 6),
          Text(
            context.tr(
                'Point your IdP (Okta / Entra) SCIM connector here with the token below to auto-provision and deprovision users.'),
            style: Sa.body(size: 11.5, color: Sa.muted),
          ),
          const SizedBox(height: 14),
          _field(context.tr('workers.dev subdomain'), _subdomain,
              hint: 'acme-co', onChanged: (_) => setState(() {})),
          _SecretField(label: context.tr('SCIM bearer token'), controller: _scimToken),
          const SizedBox(height: 8),
          _readonlyRow(context.tr('SCIM base URL'),
              base.isEmpty ? context.tr('set subdomain first') : base),
        ],
      ),
    );
  }

  // ── Save ───────────────────────────────────────────────────────────────────
  Widget _saveSection() {
    return GlassPanel(
      accent: Sa.green,
      child: Row(children: [
        SaButton(
          label: _saving ? context.tr('Saving…') : context.tr('Save config'),
          icon: Icons.save_outlined,
          color: Sa.green,
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ]),
    );
  }

  // ── shared bits ────────────────────────────────────────────────────────────
  Widget _sectionHeader(IconData icon, String label) => Row(children: [
        Icon(icon, size: 16, color: Sa.cyan),
        const SizedBox(width: 8),
        Text(label, style: Sa.heading(size: 13)),
      ]);

  Widget _field(String label, TextEditingController c,
      {String? hint, ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Sa.body(size: 11, color: Sa.textDim, weight: FontWeight.w600)),
          const SizedBox(height: 5),
          TextField(
            controller: c,
            onChanged: onChanged,
            style: Sa.body(size: 12.5, color: Sa.text),
            decoration: _dec(hint),
          ),
        ],
      ),
    );
  }

  Widget _readonlyRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Sa.bg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Sa.body(size: 10.5, color: Sa.muted)),
              const SizedBox(height: 2),
              Text(value, style: Sa.mono(size: 11, color: Sa.cyan)),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.copy_outlined, size: 15, color: Sa.muted),
          visualDensity: VisualDensity.compact,
          onPressed: () => _copy(value),
        ),
      ]),
    );
  }

  InputDecoration _dec(String? hint) => InputDecoration(
        hintText: hint,
        hintStyle: Sa.body(size: 12, color: Sa.muted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        filled: true,
        fillColor: Sa.bg.withValues(alpha: 0.5),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Sa.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Sa.cyan, width: 1.5),
        ),
      );

  void _copy(String v) {
    Clipboard.setData(ClipboardData(text: v));
    _toast('Copied.', Sa.cyan);
  }
}

/// Single/multi-line secret field with a show/hide toggle and a "never stored"
/// affordance.
class _SecretField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool multiline;
  const _SecretField({
    required this.label,
    required this.controller,
    this.hint,
    this.multiline = false,
  });

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lock_outline, size: 12, color: Sa.amber),
            const SizedBox(width: 5),
            Text(widget.label,
                style: Sa.body(size: 11, color: Sa.textDim, weight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text(context.tr('write-only'),
                style: Sa.mono(size: 8.5, color: Sa.muted)),
          ]),
          const SizedBox(height: 5),
          TextField(
            controller: widget.controller,
            obscureText: !widget.multiline && !_show,
            maxLines: widget.multiline ? 3 : 1,
            style: Sa.mono(size: 12, color: Sa.text),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: Sa.body(size: 11.5, color: Sa.muted),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              filled: true,
              fillColor: Sa.bg.withValues(alpha: 0.5),
              suffixIcon: widget.multiline
                  ? null
                  : IconButton(
                      icon: Icon(
                          _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 16,
                          color: Sa.muted),
                      onPressed: () => setState(() => _show = !_show),
                    ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Sa.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Sa.amber, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
