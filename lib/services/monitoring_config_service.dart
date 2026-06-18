import 'package:firebase_database/firebase_database.dart';

/// A supported alert destination. `format` tells the monitor worker how to shape
/// the payload: `slack` ({text}), `discord` ({content}), `telegram` ({chat_id,text}),
/// or `generic` (raw {text,state,problems}).
class WebhookProvider {
  final String id;
  final String name;
  final String format;
  final int color; // brand colour (ARGB)
  final bool needsChatId;
  final String hint;
  const WebhookProvider(
    this.id,
    this.name,
    this.format,
    this.color, {
    this.needsChatId = false,
    this.hint = '',
  });
}

/// As many destinations as cleanly support an incoming-webhook URL.
const List<WebhookProvider> kWebhookProviders = [
  WebhookProvider('discord', 'Discord', 'discord', 0xFF5865F2,
      hint: 'Channel → Integrations → Webhooks → New Webhook → Copy URL'),
  WebhookProvider('slack', 'Slack', 'slack', 0xFF611F69,
      hint: 'api.slack.com/apps → Incoming Webhooks → Add to Workspace'),
  WebhookProvider('teams', 'Microsoft Teams', 'slack', 0xFF6264A7,
      hint: 'Channel → Connectors → Incoming Webhook'),
  WebhookProvider('google_chat', 'Google Chat', 'slack', 0xFF1A73E8,
      hint: 'Space → Apps & integrations → Webhooks'),
  WebhookProvider('mattermost', 'Mattermost', 'slack', 0xFF0058CC,
      hint: 'Integrations → Incoming Webhooks'),
  WebhookProvider('rocketchat', 'Rocket.Chat', 'slack', 0xFFF5455C,
      hint: 'Administration → Integrations → New Incoming Webhook'),
  WebhookProvider('telegram', 'Telegram', 'telegram', 0xFF229ED9,
      needsChatId: true,
      hint: 'Bot API URL https://api.telegram.org/bot<token>/sendMessage + chat id'),
  WebhookProvider('pagerduty', 'PagerDuty (via webhook)', 'generic', 0xFF06AC38,
      hint: 'Use a Slack/Teams relay or a generic events endpoint'),
  WebhookProvider('webhook', 'Generic / Custom JSON', 'generic', 0xFF888780,
      hint: 'Any endpoint — receives {text, state, problems}. Works with Zapier, Make, n8n.'),
];

WebhookProvider providerById(String id) =>
    kWebhookProviders.firstWhere((p) => p.id == id, orElse: () => kWebhookProviders.last);

/// What the monitor worker watches. Each can be toggled by IT.
class MonitorChecks {
  final bool aiWorker;
  final bool notifyWorker;
  final bool cron;
  final bool backup;
  final bool errorSpike;
  final bool notificationBacklog;
  final bool appErrorBudget;
  final bool modelDrift;

  const MonitorChecks({
    this.aiWorker = true,
    this.notifyWorker = true,
    this.cron = true,
    this.backup = true,
    this.errorSpike = true,
    this.notificationBacklog = true,
    this.appErrorBudget = true,
    this.modelDrift = true,
  });

  factory MonitorChecks.fromMap(Map? m) {
    final map = m ?? const {};
    bool v(String k, bool d) => map[k] is bool ? map[k] as bool : d;
    return MonitorChecks(
      aiWorker: v('aiWorker', true),
      notifyWorker: v('notifyWorker', true),
      cron: v('cron', true),
      backup: v('backup', true),
      errorSpike: v('errorSpike', true),
      notificationBacklog: v('notificationBacklog', true),
      appErrorBudget: v('appErrorBudget', true),
      modelDrift: v('modelDrift', true),
    );
  }

  Map<String, dynamic> toMap() => {
        'aiWorker': aiWorker,
        'notifyWorker': notifyWorker,
        'cron': cron,
        'backup': backup,
        'errorSpike': errorSpike,
        'notificationBacklog': notificationBacklog,
        'appErrorBudget': appErrorBudget,
        'modelDrift': modelDrift,
      };

  MonitorChecks copyWith({
    bool? aiWorker,
    bool? notifyWorker,
    bool? cron,
    bool? backup,
    bool? errorSpike,
    bool? notificationBacklog,
    bool? appErrorBudget,
    bool? modelDrift,
  }) =>
      MonitorChecks(
        aiWorker: aiWorker ?? this.aiWorker,
        notifyWorker: notifyWorker ?? this.notifyWorker,
        cron: cron ?? this.cron,
        backup: backup ?? this.backup,
        errorSpike: errorSpike ?? this.errorSpike,
        notificationBacklog: notificationBacklog ?? this.notificationBacklog,
        appErrorBudget: appErrorBudget ?? this.appErrorBudget,
        modelDrift: modelDrift ?? this.modelDrift,
      );
}

/// Runtime monitoring/alerting config owned by IT in SuperAdmin → Reliability.
/// Stored at `monitoring_config`. The monitor worker reads this live (no
/// redeploy), so changing the webhook here takes effect on the next cron run.
class MonitoringConfig {
  final bool webhookEnabled;
  final String provider; // WebhookProvider.id
  final String url;
  final String chatId; // Telegram
  final MonitorChecks checks;
  final int crashFreeSlo; // % crash-free SLO for the app error budget

  const MonitoringConfig({
    this.webhookEnabled = false,
    this.provider = 'discord',
    this.url = '',
    this.chatId = '',
    this.checks = const MonitorChecks(),
    this.crashFreeSlo = 99,
  });

  factory MonitoringConfig.fromMap(Map? m) {
    final map = m ?? const {};
    final w = map['webhook'] is Map ? map['webhook'] as Map : const {};
    return MonitoringConfig(
      webhookEnabled: w['enabled'] == true,
      provider: (w['provider'] ?? 'discord').toString(),
      url: (w['url'] ?? '').toString(),
      chatId: (w['chatId'] ?? '').toString(),
      checks: MonitorChecks.fromMap(map['checks'] is Map ? map['checks'] as Map : null),
      crashFreeSlo:
          map['crashFreeSlo'] is num ? (map['crashFreeSlo'] as num).toInt() : 99,
    );
  }

  Map<String, dynamic> toMap() => {
        'webhook': {
          'enabled': webhookEnabled,
          'provider': provider,
          'format': providerById(provider).format,
          'url': url.trim(),
          'chatId': chatId.trim(),
        },
        'checks': checks.toMap(),
        'crashFreeSlo': crashFreeSlo,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  MonitoringConfig copyWith({
    bool? webhookEnabled,
    String? provider,
    String? url,
    String? chatId,
    MonitorChecks? checks,
    int? crashFreeSlo,
  }) =>
      MonitoringConfig(
        webhookEnabled: webhookEnabled ?? this.webhookEnabled,
        provider: provider ?? this.provider,
        url: url ?? this.url,
        chatId: chatId ?? this.chatId,
        checks: checks ?? this.checks,
        crashFreeSlo: crashFreeSlo ?? this.crashFreeSlo,
      );
}

class MonitoringConfigService {
  MonitoringConfigService({DatabaseReference? database})
      : _ref = (database ?? FirebaseDatabase.instance.ref())
            .child('monitoring_config');

  final DatabaseReference _ref;

  Future<MonitoringConfig> load() async {
    try {
      final snap = await _ref.get();
      return MonitoringConfig.fromMap(snap.value is Map ? snap.value as Map : null);
    } catch (_) {
      return const MonitoringConfig();
    }
  }

  Future<void> save(MonitoringConfig config) => _ref.set(config.toMap());

  /// Live stream of a worker health beacon (e.g. `workers/health/backup`).
  Stream<Map<String, dynamic>?> healthStream(String node) {
    return (_ref.root.child('workers/health/$node')).onValue.map((e) {
      final v = e.snapshot.value;
      return v is Map ? Map<String, dynamic>.from(v) : null;
    });
  }
}
