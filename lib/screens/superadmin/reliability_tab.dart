import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';

import '../../services/monitoring_config_service.dart';
import '../../services/telemetry_service.dart';
import 'superadmin_theme.dart';

/// SuperAdmin -> Reliability.
///
/// Live backup + system-monitor status, which checks the deadman switch runs,
/// and a configurable alert webhook (Discord / Slack / Teams / ...). The config
/// is saved to `monitoring_config`, which the monitor worker reads live — so a
/// new webhook takes effect on the next 5-minute run, no redeploy.
class ReliabilityTab extends StatefulWidget {
  const ReliabilityTab({super.key});

  @override
  State<ReliabilityTab> createState() => _ReliabilityTabState();
}

class _ReliabilityTabState extends State<ReliabilityTab> {
  final _service = MonitoringConfigService();
  final _url = TextEditingController();
  final _chatId = TextEditingController();

  MonitoringConfig _cfg = const MonitoringConfig();
  bool _loaded = false;
  bool _saving = false;
  bool _testing = false;
  String? _status;
  bool _ok = false;

  Map<String, dynamic>? _backup;
  Map<String, dynamic>? _monitor;

  @override
  void initState() {
    super.initState();
    _service.load().then((c) {
      if (!mounted) return;
      setState(() {
        _cfg = c;
        _url.text = c.url;
        _chatId.text = c.chatId;
        _loaded = true;
      });
    });
    _service.healthStream('backup').listen((m) {
      if (mounted) setState(() => _backup = m);
    });
    _service.healthStream('monitor').listen((m) {
      if (mounted) setState(() => _monitor = m);
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _chatId.dispose();
    super.dispose();
  }

  String _ago(String? iso) {
    if (iso == null) return 'never';
    final t = DateTime.tryParse(iso);
    if (t == null) return '—';
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 48) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _status = null;
    });
    final cfg = _cfg.copyWith(url: _url.text.trim(), chatId: _chatId.text.trim());
    if (cfg.webhookEnabled && cfg.url.isEmpty) {
      setState(() {
        _saving = false;
        _ok = false;
        _status = 'Enter the webhook URL before enabling alerts.';
      });
      return;
    }
    try {
      await _service.save(cfg);
      if (mounted) {
        setState(() {
          _cfg = cfg;
          _saving = false;
          _ok = true;
          _status = 'Saved. The monitor uses it on its next run (within 5 min).';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _ok = false;
          _status = 'Save failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Center(child: CircularProgressIndicator(color: Sa.cyan));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusRow(),
            const SizedBox(height: 16),
            _apmPanel(),
            const SizedBox(height: 16),
            _alertsPanel(),
            const SizedBox(height: 16),
            _checksPanel(),
          ],
        ),
      ),
    );
  }

  Widget _statusRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _backupPanel()),
        const SizedBox(width: 16),
        Expanded(child: _monitorPanel()),
      ],
    );
  }

  Widget _backupPanel() {
    final b = _backup;
    final ok = b != null && b['ok'] != false;
    final color = b == null ? Sa.muted : (ok ? Sa.green : Sa.red);
    final label = b == null ? 'NO DATA' : (ok ? 'HEALTHY' : 'FAILED');
    final bytes = b != null && b['bytes'] is num ? (b['bytes'] as num).toInt() : null;
    return GlassPanel(
      accent: Sa.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.cloud_done_outlined,
            title: 'Backups',
            subtitle: 'Nightly snapshot to Cloudflare R2',
            accent: Sa.cyan,
            trailing: GlowChip(label: label, color: color, pulse: ok),
          ),
          const SizedBox(height: 16),
          _kv('Last backup', _ago(b?['at']?.toString())),
          if (bytes != null) _kv('Size', '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB'),
          if (b != null && b['ok'] == false)
            _kv('Error', (b['error'] ?? '').toString(), color: Sa.red),
          const SizedBox(height: 6),
          Text(
            'Storage and retention are managed in Cloudflare (alertsys-backups, '
            'last 30 nightly). See DISASTER_RECOVERY.md.',
            style: Sa.body(size: 11.5, color: Sa.muted),
          ),
        ],
      ),
    );
  }

  Widget _monitorPanel() {
    final m = _monitor;
    final state = (m?['state'] ?? '').toString();
    final degraded = state == 'degraded';
    final color = m == null ? Sa.muted : (degraded ? Sa.red : Sa.green);
    final label = m == null ? 'PROBING' : (degraded ? 'DEGRADED' : 'NOMINAL');
    final problems = (m?['problems'] is List) ? (m!['problems'] as List) : const [];
    return GlassPanel(
      accent: degraded ? Sa.red : Sa.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.radar_outlined,
            title: 'System monitor',
            subtitle: 'Deadman switch · every 5 min',
            accent: degraded ? Sa.red : Sa.green,
            trailing: GlowChip(label: label, color: color, pulse: !degraded && m != null),
          ),
          const SizedBox(height: 16),
          _kv('Last check', _ago(m?['at']?.toString())),
          const SizedBox(height: 8),
          if (problems.isEmpty)
            Text('All checks passing.', style: Sa.body(size: 12.5, color: Sa.green))
          else
            ...problems.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, size: 14, color: Sa.red),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p.toString(), style: Sa.body(size: 12, color: Sa.textDim))),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _alertsPanel() {
    final selected = providerById(_cfg.provider);
    return GlassPanel(
      accent: Sa.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.notifications_active_outlined,
            title: 'Alert destination',
            subtitle: 'Get pinged the moment the system degrades',
            accent: Sa.violet,
            trailing: GlowChip(
              label: _cfg.webhookEnabled ? 'ON' : 'OFF',
              color: _cfg.webhookEnabled ? Sa.green : Sa.muted,
              pulse: _cfg.webhookEnabled,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Enable alerts', style: Sa.heading(size: 14)),
                    Text('Post to your chat tool on every state change',
                        style: Sa.body(size: 12, color: Sa.muted)),
                  ],
                ),
              ),
              Switch(
                value: _cfg.webhookEnabled,
                activeColor: Sa.cyan,
                onChanged: (v) => setState(() => _cfg = _cfg.copyWith(webhookEnabled: v)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('PROVIDER', style: Sa.mono(size: 10, color: Sa.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: kWebhookProviders.map(_providerTile).toList(),
          ),
          const SizedBox(height: 18),
          Text('WEBHOOK URL', style: Sa.mono(size: 10, color: Sa.muted)),
          const SizedBox(height: 6),
          TextField(
            controller: _url,
            style: Sa.body(size: 13, color: Sa.text),
            decoration: _decoration(hint: 'https://...'),
          ),
          if (selected.hint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(selected.hint, style: Sa.body(size: 11, color: Sa.muted)),
          ],
          if (selected.needsChatId) ...[
            const SizedBox(height: 14),
            Text('TELEGRAM CHAT ID', style: Sa.mono(size: 10, color: Sa.muted)),
            const SizedBox(height: 6),
            TextField(
              controller: _chatId,
              style: Sa.body(size: 13, color: Sa.text),
              decoration: _decoration(hint: 'e.g. -1001234567890'),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _saveButton()),
              const SizedBox(width: 10),
              _testButton(),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, style: Sa.body(size: 12, color: _ok ? Sa.green : Sa.red)),
          ],
        ],
      ),
    );
  }

  IconData _providerIcon(String id) {
    switch (id) {
      case 'discord':
        return FontAwesomeIcons.discord;
      case 'slack':
        return FontAwesomeIcons.slack;
      case 'teams':
        return FontAwesomeIcons.microsoft;
      case 'google_chat':
        return FontAwesomeIcons.google;
      case 'mattermost':
        return FontAwesomeIcons.comments;
      case 'rocketchat':
        return FontAwesomeIcons.rocketchat;
      case 'telegram':
        return FontAwesomeIcons.telegram;
      case 'pagerduty':
        return FontAwesomeIcons.bell;
      default:
        return FontAwesomeIcons.bolt;
    }
  }

  Widget _providerTile(WebhookProvider p) {
    final selected = _cfg.provider == p.id;
    final brand = Color(p.color);
    return InkWell(
      onTap: () => setState(() => _cfg = _cfg.copyWith(provider: p.id)),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? brand.withValues(alpha: 0.14) : Sa.bgRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? brand : Sa.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(_providerIcon(p.id), size: 18, color: brand),
            const SizedBox(width: 10),
            Text(p.name,
                style: Sa.heading(size: 12.5, color: selected ? Sa.text : Sa.textDim)),
          ],
        ),
      ),
    );
  }

  Widget _apmPanel() {
    final slo = _cfg.crashFreeSlo;
    return GlassPanel(
      accent: Sa.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.monitor_heart_outlined,
            title: 'App health (today)',
            subtitle: 'Crash-free sessions & error rate — SLA alert below $slo%',
            accent: Sa.green,
          ),
          const SizedBox(height: 12),
          StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance
                .ref('telemetry/daily/${TelemetryService.todayKey()}')
                .onValue,
            builder: (context, snap) {
              final m = (snap.data?.snapshot.value as Map?) ?? const {};
              int n(String k) => (m[k] is num) ? (m[k] as num).toInt() : 0;
              final sessions = n('sessions');
              final crashed = n('errorSessions');
              final errors = n('errors');
              final pct = TelemetryService.crashFreeRate(
                      sessions: sessions, errorSessions: crashed) *
                  100;
              final enough = sessions >= 20;
              final breaching = enough && pct < slo;
              final cfColor = !enough ? Sa.muted : (breaching ? Sa.red : Sa.green);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: _metric('Crash-free', sessions == 0 ? '—' : '${pct.toStringAsFixed(1)}%', cfColor)),
                    Expanded(child: _metric('Sessions', '$sessions', Sa.cyan)),
                    Expanded(child: _metric('Crashed', '$crashed', crashed > 0 ? Sa.amber : Sa.muted)),
                    Expanded(child: _metric('Errors', '$errors', errors > 0 ? Sa.amber : Sa.muted)),
                  ]),
                  if (sessions > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      breaching
                          ? 'Below SLO — the monitor will alert your webhook.'
                          : enough
                              ? 'Meeting the $slo% crash-free SLO.'
                              : 'Collecting data ($sessions/20 sessions before SLO alerting).',
                      style: Sa.body(size: 11.5, color: breaching ? Sa.red : Sa.muted),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Sa.display(size: 22, color: color)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: Sa.mono(size: 9, color: Sa.muted)),
        ],
      );

  Widget _checksPanel() {
    final c = _cfg.checks;
    final items = <(String, String, bool, MonitorChecks Function(bool))>[
      ('AI worker', 'Assignment / escalation / predictions edge', c.aiWorker, (v) => c.copyWith(aiWorker: v)),
      ('Notification worker', 'Push fan-out edge', c.notifyWorker, (v) => c.copyWith(notifyWorker: v)),
      ('Cron freshness', 'The every-minute engine is alive', c.cron, (v) => c.copyWith(cron: v)),
      ('Backups', 'Nightly snapshot ran and succeeded', c.backup, (v) => c.copyWith(backup: v)),
      ('Error spike', 'Surge of client errors in the last hour', c.errorSpike, (v) => c.copyWith(errorSpike: v)),
      ('Notification backlog', 'Notify worker keeping up', c.notificationBacklog, (v) => c.copyWith(notificationBacklog: v)),
      ('App error budget', 'Crash-free below the ${_cfg.crashFreeSlo}% SLO', c.appErrorBudget, (v) => c.copyWith(appErrorBudget: v)),
      ('AI model drift', 'A deployed agent model regressed in quality', c.modelDrift, (v) => c.copyWith(modelDrift: v)),
    ];
    return GlassPanel(
      accent: Sa.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.checklist_outlined,
            title: 'What gets monitored',
            subtitle: 'Toggle the checks the deadman switch runs',
            accent: Sa.blue,
          ),
          const SizedBox(height: 8),
          ...items.map((it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.$1, style: Sa.heading(size: 13)),
                          Text(it.$2, style: Sa.body(size: 11.5, color: Sa.muted)),
                        ],
                      ),
                    ),
                    Switch(
                      value: it.$3,
                      activeColor: Sa.cyan,
                      onChanged: (v) => setState(() => _cfg = _cfg.copyWith(checks: it.$4(v))),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          Text('Saved with the Save button above; applied on the next monitor run.',
              style: Sa.body(size: 11.5, color: Sa.muted)),
        ],
      ),
    );
  }

  Future<void> _sendTest() async {
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() {
        _ok = false;
        _status = 'Enter the webhook URL first.';
      });
      return;
    }
    setState(() {
      _testing = true;
      _status = null;
    });
    final format = providerById(_cfg.provider).format;
    const msg =
        'Test alert from Smart Industrial Alert — your monitoring webhook works.';
    Map<String, dynamic> body;
    if (format == 'discord') {
      body = {'content': msg};
    } else if (format == 'telegram') {
      body = {'chat_id': _chatId.text.trim(), 'text': msg};
    } else if (format == 'generic') {
      body = {'text': msg, 'state': 'test', 'problems': <String>[]};
    } else {
      body = {'text': msg};
    }
    try {
      final res = await http
          .post(Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      final okCode = res.statusCode >= 200 && res.statusCode < 300;
      setState(() {
        _testing = false;
        _ok = okCode;
        _status = okCode
            ? 'Test sent — check ${providerById(_cfg.provider).name}.'
            : 'Webhook returned ${res.statusCode}. Double-check the URL.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _ok = false;
        _status = 'Could not reach the webhook. On the web console this can be a '
            'CORS block — the live server-side monitor still delivers fine.';
      });
    }
  }

  Widget _testButton() {
    return OutlinedButton.icon(
      onPressed: _testing ? null : _sendTest,
      icon: _testing
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.send_outlined, size: 18),
      label: Text(_testing ? 'Sending…' : 'Send test'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Sa.cyan,
        side: BorderSide(color: Sa.cyan.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _saveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save_outlined, size: 18),
        label: Text(_saving ? 'Saving…' : 'Save monitoring settings'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Sa.cyan,
          foregroundColor: Sa.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(k, style: Sa.mono(size: 10.5, color: Sa.muted))),
          Expanded(child: Text(v, style: Sa.body(size: 12.5, color: color ?? Sa.text))),
        ],
      ),
    );
  }

  InputDecoration _decoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: Sa.body(size: 12, color: Sa.muted),
        filled: true,
        fillColor: Sa.bgRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Sa.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Sa.cyan),
        ),
      );
}
