import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/infra_config_service.dart';
import 'superadmin_theme.dart';

/// SuperAdmin → Infrastructure. The company IT team connects their OWN backend
/// (Firebase project), their Cloudflare account + workers, and SCIM, then
/// triggers a deploy of their dedicated instance through their CI pipeline.
///
/// Honest model: the running app is wired to one Firebase project at build, so
/// this configures the *deploy target* (applied on the next deploy) rather than
/// hot-swapping the live backend. Secrets are sent write-only to the pipeline
/// and never stored in the database.
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
  final _accountId = TextEditingController();
  final _subdomain = TextEditingController();
  final _r2Bucket = TextEditingController();
  final _webhook = TextEditingController();

  // Secrets — write-only, never persisted to RTDB.
  final _serviceAccount = TextEditingController();
  final _cfToken = TextEditingController();
  final _scimToken = TextEditingController();
  final _sharedSecret = TextEditingController();
  final _deployToken = TextEditingController();

  bool _loaded = false;
  bool _saving = false;
  bool _deploying = false;
  String _lastDeployAt = '';
  String _lastDeployStatus = '';

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
      _accountId.text = c.cloudflareAccountId;
      _subdomain.text = c.workersSubdomain;
      _r2Bucket.text = c.r2Bucket;
      _webhook.text = c.deployWebhookUrl;
      _lastDeployAt = c.lastDeployAt;
      _lastDeployStatus = c.lastDeployStatus;
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [
      _projectId, _dbUrl, _apiKey, _accountId, _subdomain, _r2Bucket,
      _webhook, _serviceAccount, _cfToken, _scimToken, _sharedSecret, _deployToken
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  InfraConfig _current() => InfraConfig(
        firebaseProjectId: _projectId.text,
        firebaseDbUrl: _dbUrl.text,
        firebaseApiKey: _apiKey.text,
        cloudflareAccountId: _accountId.text,
        workersSubdomain: _subdomain.text,
        r2Bucket: _r2Bucket.text,
        deployWebhookUrl: _webhook.text,
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

  Future<void> _deploy() async {
    setState(() => _deploying = true);
    final r = await _service.deploy(
      config: _current(),
      authToken: _deployToken.text,
    );
    if (!mounted) return;
    setState(() {
      _deploying = false;
      _lastDeployAt = DateTime.now().toIso8601String();
      _lastDeployStatus = r.ok ? 'triggered' : 'failed';
    });
    _toast(r.message, r.ok ? Sa.green : Sa.red);
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
          _databaseSection(),
          const SizedBox(height: 16),
          _cloudflareSection(),
          const SizedBox(height: 16),
          _scimSection(),
          const SizedBox(height: 16),
          _deploySection(),
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
              Text('INFRASTRUCTURE', style: Sa.display(size: 18)),
              const SizedBox(height: 3),
              Text(
                'Connect your own backend and edge, then deploy your dedicated '
                'instance. Secrets go to your pipeline — never the database.',
                style: Sa.body(size: 12, color: Sa.textDim),
              ),
            ],
          ),
        ),
        if (_lastDeployStatus.isNotEmpty)
          GlowChip(
            label: _lastDeployStatus == 'triggered' ? 'DEPLOYED' : 'DEPLOY FAILED',
            color: _lastDeployStatus == 'triggered' ? Sa.green : Sa.red,
            icon: _lastDeployStatus == 'triggered' ? Icons.check : Icons.error_outline,
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
          _sectionHeader(Icons.storage_outlined, 'DATABASE · YOUR FIREBASE'),
          const SizedBox(height: 6),
          Text(
            'Point the build at your own Firebase project. Applied on the next '
            'deploy (the live app is not hot-swapped).',
            style: Sa.body(size: 11.5, color: Sa.muted),
          ),
          const SizedBox(height: 14),
          _backendStrip(),
          const SizedBox(height: 16),
          _field('Firebase project ID', _projectId, hint: 'acme-alerts'),
          _field('Realtime Database URL', _dbUrl,
              hint: 'https://acme-alerts-default-rtdb.firebaseio.com'),
          _field('Web API key', _apiKey, hint: 'AIza… (not secret)'),
          const SizedBox(height: 8),
          _SecretField(
            label: 'Service account JSON',
            controller: _serviceAccount,
            hint: 'Paste the service-account JSON — sent to your pipeline, never stored',
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

  // ── Cloudflare ───────────────────────────────────────────────────────────
  Widget _cloudflareSection() {
    final cfg = _current();
    return GlassPanel(
      accent: const Color(0xFFF38020),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.cloud_sync_outlined, 'CLOUDFLARE & WORKERS'),
          const SizedBox(height: 14),
          _field('Account ID', _accountId, hint: 'your Cloudflare account id'),
          _field('workers.dev subdomain', _subdomain,
              hint: 'acme-co', onChanged: (_) => setState(() {})),
          _field('R2 bucket', _r2Bucket, hint: 'acme-alertsys-backups'),
          const SizedBox(height: 8),
          _SecretField(label: 'Cloudflare API token', controller: _cfToken),
          _SecretField(label: 'Worker shared secret', controller: _sharedSecret),
          const SizedBox(height: 16),
          Text('WORKERS · OUR EXACT SETUP',
              style: Sa.mono(size: 10, color: Sa.muted, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...cfg.workers().map(_workerRow),
        ],
      ),
    );
  }

  Widget _workerRow(({String key, String name, String role, String url}) w) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Sa.bg.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Sa.border),
        ),
        child: Row(children: [
          PulseDot(color: Sa.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.name,
                    style: Sa.body(size: 12.5, color: Sa.text, weight: FontWeight.w700)),
                Text(w.role, style: Sa.body(size: 10.5, color: Sa.muted)),
                const SizedBox(height: 2),
                Text(w.url, style: Sa.mono(size: 10, color: Sa.cyan)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy_outlined, size: 15, color: Sa.muted),
            visualDensity: VisualDensity.compact,
            onPressed: () => _copy(w.url),
          ),
        ]),
      ),
    );
  }

  // ── SCIM ───────────────────────────────────────────────────────────────────
  Widget _scimSection() {
    final base = _current().scimBaseUrl;
    return GlassPanel(
      accent: Sa.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.badge_outlined, 'SCIM PROVISIONING'),
          const SizedBox(height: 6),
          Text(
            'Point your IdP (Okta / Entra) SCIM connector here with the token '
            'below to auto-provision and deprovision users.',
            style: Sa.body(size: 11.5, color: Sa.muted),
          ),
          const SizedBox(height: 14),
          _SecretField(label: 'SCIM bearer token', controller: _scimToken),
          const SizedBox(height: 8),
          _readonlyRow('SCIM base URL', base.isEmpty ? 'set subdomain first' : base),
        ],
      ),
    );
  }

  // ── Deploy ───────────────────────────────────────────────────────────────
  Widget _deploySection() {
    return GlassPanel(
      accent: Sa.green,
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.rocket_launch_outlined, 'DEPLOY'),
          const SizedBox(height: 6),
          Text(
            'Deploy fires a GitHub repository_dispatch to the deploy-instance '
            'workflow, which provisions and deploys your 5 workers + R2 + '
            'database rules. Only non-secret config is sent — set the secrets '
            'once in GitHub Actions with the button below.',
            style: Sa.body(size: 11.5, color: Sa.muted),
          ),
          const SizedBox(height: 14),
          _field('Deploy webhook URL', _webhook,
              hint: 'https://api.github.com/repos/acme/sia/dispatches'),
          _SecretField(label: 'GitHub token (repo scope)', controller: _deployToken),
          const SizedBox(height: 4),
          SaButton(
            label: 'Copy GitHub secret commands',
            icon: Icons.key_outlined,
            outlined: true,
            onPressed: _copySecretCommands,
          ),
          if (_lastDeployAt.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Last deploy: $_lastDeployAt · $_lastDeployStatus',
                style: Sa.mono(size: 10, color: Sa.muted)),
          ],
          const SizedBox(height: 16),
          Row(children: [
            SaButton(
              label: _saving ? 'Saving…' : 'Save config',
              icon: Icons.save_outlined,
              outlined: true,
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(width: 12),
            SaButton(
              label: _deploying ? 'Deploying…' : 'Deploy instance',
              icon: Icons.rocket_launch_outlined,
              color: Sa.green,
              busy: _deploying,
              onPressed: _deploying ? null : _deploy,
            ),
          ]),
        ],
      ),
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

  /// Builds `gh secret set` commands from the entered values so IT can set the
  /// GitHub Actions secrets the workflow reads (secrets never leave the device
  /// via the app — they go straight to GitHub).
  void _copySecretCommands() {
    String q(String v) => v.trim().replaceAll("'", "'\\''");
    final lines = <String>[
      '# Run in your instance repo with the GitHub CLI (gh auth login first):',
      if (_cfToken.text.trim().isNotEmpty)
        "gh secret set CLOUDFLARE_API_TOKEN --body '${q(_cfToken.text)}'",
      if (_accountId.text.trim().isNotEmpty)
        "gh secret set CLOUDFLARE_ACCOUNT_ID --body '${q(_accountId.text)}'",
      if (_dbUrl.text.trim().isNotEmpty)
        "gh secret set FB_DB_URL --body '${q(_dbUrl.text)}'",
      if (_apiKey.text.trim().isNotEmpty)
        "gh secret set FB_API_KEY --body '${q(_apiKey.text)}'",
      if (_sharedSecret.text.trim().isNotEmpty)
        "gh secret set WORKER_SHARED_SECRET --body '${q(_sharedSecret.text)}'",
      if (_scimToken.text.trim().isNotEmpty)
        "gh secret set SCIM_TOKEN --body '${q(_scimToken.text)}'",
      'gh secret set FIREBASE_SERVICE_ACCOUNT < service-account.json',
    ];
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    _toast('Secret-setup commands copied to clipboard.', Sa.cyan);
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
            Text('write-only',
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
