import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../services/connector_service.dart';
import 'superadmin_theme.dart';

/// SuperAdmin → Infrastructure → Industrial Connectors.
///
/// The IT team wires SIAS on top of an existing automation estate — SCADA, PLC,
/// historian, MQTT broker, or any REST source — then hits "Verify link test" and
/// goes live. Flow: pick a connector → enter endpoint + token → Verify → done.
class ConnectorsSection extends StatefulWidget {
  const ConnectorsSection({super.key});

  @override
  State<ConnectorsSection> createState() => _ConnectorsSectionState();
}

class _CatalogEntry {
  final ConnectorKind kind;
  final IconData icon;
  final Color color;
  final String blurb;
  const _CatalogEntry(this.kind, this.icon, this.color, this.blurb);
}

const _catalog = <_CatalogEntry>[
  _CatalogEntry(ConnectorKind.opcua, Icons.account_tree_outlined, Color(0xFF5B8DEF),
      'Subscribe to OPC-UA nodes via an edge bridge. The SCADA / DCS standard.'),
  _CatalogEntry(ConnectorKind.modbus, Icons.memory_outlined, Color(0xFF26A69A),
      'Poll Modbus TCP registers from a gateway near the PLC.'),
  _CatalogEntry(ConnectorKind.mqtt, Icons.sensors_outlined, Color(0xFFAB47BC),
      'MQTT / Sparkplug B broker. Live CONNACK handshake verify.'),
  _CatalogEntry(ConnectorKind.historianPi, Icons.timeline_outlined, Color(0xFFEF6C00),
      'OSIsoft / AVEVA PI Web API. Cloud-pulled on a schedule.'),
  _CatalogEntry(ConnectorKind.historianIgnition, Icons.show_chart_outlined, Color(0xFFD4A017),
      'Ignition (Inductive Automation) HTTP / WebDev tag reads.'),
  _CatalogEntry(ConnectorKind.rest, Icons.api_outlined, Color(0xFF42A5F5),
      'Any MES / CMMS / quality system with an HTTPS endpoint.'),
  _CatalogEntry(ConnectorKind.microcontroller, Icons.developer_board_outlined, Color(0xFF66BB6A),
      'ESP32 / Arduino + buttons POSTing structured telemetry.'),
  _CatalogEntry(ConnectorKind.custom, Icons.extension_outlined, Color(0xFF8D9199),
      'Anything else that can POST JSON or expose a value.'),
];

_CatalogEntry _entryFor(ConnectorKind k) =>
    _catalog.firstWhere((e) => e.kind == k, orElse: () => _catalog.last);

class _ConnectorsSectionState extends State<ConnectorsSection> {
  final _svc = ConnectorService();

  void _openEditor({ConnectorKind? kind, IndustrialConnector? existing}) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => _ConnectorEditorDialog(
        svc: _svc,
        kind: kind ?? existing?.kind ?? ConnectorKind.rest,
        existing: existing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      accent: Sa.cyan,
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.hub_outlined,
            title: context.tr('INDUSTRIAL CONNECTORS'),
            subtitle: context.tr(
                'Feed alerts from SCADA · PLC · Historian · MQTT · REST — on top of what the plant already runs'),
            accent: Sa.cyan,
            trailing: StreamBuilder<List<IndustrialConnector>>(
              stream: _svc.stream(),
              builder: (_, snap) {
                final list = snap.data ?? const <IndustrialConnector>[];
                final linked =
                    list.where((c) => c.runtime.status == 'linked').length;
                if (list.isEmpty) return const SizedBox.shrink();
                return GlowChip(
                  label: '$linked/${list.length} ${context.tr('LINKED')}',
                  color: linked > 0 ? Sa.green : Sa.muted,
                  pulse: linked > 0,
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.tr(
                'Add a connector, enter its endpoint and credentials, then run the Verify link test — the link reads LINKED only when real data is genuinely flowing.'),
            style: Sa.body(size: 11.5, color: Sa.muted),
          ),
          const SizedBox(height: 16),
          _CatalogGrid(onPick: (k) => _openEditor(kind: k)),
          const SizedBox(height: 20),
          Row(children: [
            Text(context.tr('CONFIGURED CONNECTORS'),
                style: Sa.mono(size: 10, color: Sa.muted, weight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: Sa.border)),
          ]),
          const SizedBox(height: 12),
          StreamBuilder<List<IndustrialConnector>>(
            stream: _svc.stream(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Sa.cyan))),
                );
              }
              final list = snap.data ?? const <IndustrialConnector>[];
              if (list.isEmpty) return _emptyState();
              return Column(
                children: [
                  for (final c in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ConnectorCard(
                        connector: c,
                        svc: _svc,
                        onEdit: () => _openEditor(existing: c),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        color: Sa.bg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        children: [
          Icon(Icons.lan_outlined, color: Sa.muted, size: 26),
          const SizedBox(height: 8),
          Text(context.tr('No connectors yet'),
              style: Sa.body(size: 12.5, color: Sa.textDim, weight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(
            context.tr('Pick a system above to wire your first live data source.'),
            style: Sa.body(size: 11, color: Sa.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Catalog grid ─────────────────────────────────────────────────────────────
class _CatalogGrid extends StatelessWidget {
  final ValueChanged<ConnectorKind> onPick;
  const _CatalogGrid({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 720 ? 4 : (c.maxWidth > 480 ? 3 : 2);
      const gap = 10.0;
      final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final e in _catalog)
            SizedBox(width: tileW, child: _CatalogTile(entry: e, onTap: () => onPick(e.kind))),
        ],
      );
    });
  }
}

class _CatalogTile extends StatefulWidget {
  final _CatalogEntry entry;
  final VoidCallback onTap;
  const _CatalogTile({required this.entry, required this.onTap});

  @override
  State<_CatalogTile> createState() => _CatalogTileState();
}

class _CatalogTileState extends State<_CatalogTile> {
  bool _hover = false;

  String _modeBadge(BuildContext context) {
    switch (widget.entry.kind.mode) {
      case ConnectorMode.pull:
        return context.tr('CLOUD-PULL');
      case ConnectorMode.push:
        return context.tr('EDGE-PUSH');
      case ConnectorMode.mqtt:
        return context.tr('BROKER');
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hover ? e.color.withValues(alpha: 0.12) : Sa.bg.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _hover ? e.color.withValues(alpha: 0.7) : Sa.border,
                width: _hover ? 1.4 : 1),
            boxShadow: _hover
                ? [BoxShadow(color: e.color.withValues(alpha: 0.25), blurRadius: 16)]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: e.color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(e.icon, size: 17, color: e.color),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: e.color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(_modeBadge(context),
                      style: Sa.mono(size: 7.5, color: e.color, weight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 9),
              Text(e.kind.label,
                  style: Sa.body(size: 12, color: Sa.text, weight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(context.tr(e.blurb),
                  style: Sa.body(size: 10, color: Sa.muted),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.add_circle_outline, size: 13, color: _hover ? e.color : Sa.muted),
                const SizedBox(width: 5),
                Text(context.tr('Add'),
                    style: Sa.mono(
                        size: 10,
                        color: _hover ? e.color : Sa.muted,
                        weight: FontWeight.w700)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Configured connector card ────────────────────────────────────────────────
({Color color, String label, IconData icon}) _statusStyle(String s, BuildContext ctx) {
  switch (s) {
    case 'linked':
      return (color: Sa.green, label: ctx.tr('LINKED'), icon: Icons.check_circle_outline);
    case 'waiting':
      return (color: Sa.amber, label: ctx.tr('WAITING'), icon: Icons.hourglass_top_outlined);
    case 'error':
      return (color: Sa.red, label: ctx.tr('ERROR'), icon: Icons.error_outline);
    default:
      return (color: Sa.muted, label: ctx.tr('NOT VERIFIED'), icon: Icons.radio_button_unchecked);
  }
}

String _relative(String iso, BuildContext ctx) {
  if (iso.isEmpty) return ctx.tr('never');
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return ctx.tr('just now');
  if (d.inMinutes < 60) return '${d.inMinutes}m ${ctx.tr('ago')}';
  if (d.inHours < 24) return '${d.inHours}h ${ctx.tr('ago')}';
  return '${d.inDays}d ${ctx.tr('ago')}';
}

class _ConnectorCard extends StatefulWidget {
  final IndustrialConnector connector;
  final ConnectorService svc;
  final VoidCallback onEdit;
  const _ConnectorCard({required this.connector, required this.svc, required this.onEdit});

  @override
  State<_ConnectorCard> createState() => _ConnectorCardState();
}

class _ConnectorCardState extends State<_ConnectorCard> {
  bool _verifying = false;
  bool _polling = false;
  bool _showEndpoint = false;
  String? _ingestKey;

  Future<void> _verify() async {
    setState(() => _verifying = true);
    final r = await widget.svc.verify(widget.connector.id);
    if (!mounted) return;
    setState(() => _verifying = false);
    _toast(r.message, _statusStyle(r.status, context).color);
  }

  Future<void> _pollNow() async {
    setState(() => _polling = true);
    final r = await widget.svc.pollNow(widget.connector.id);
    if (!mounted) return;
    setState(() => _polling = false);
    _toast(r.message, r.ok ? Sa.green : Sa.red);
  }

  Future<void> _toggleEndpoint() async {
    final next = !_showEndpoint;
    setState(() => _showEndpoint = next);
    if (next && _ingestKey == null) {
      final k = await widget.svc.fetchIngestKey(widget.connector.id);
      if (mounted) setState(() => _ingestKey = k ?? '');
    }
  }

  void _toast(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Sa.panelSolid,
      duration: const Duration(seconds: 4),
      content: Text(msg, style: Sa.body(color: c, weight: FontWeight.w600)),
    ));
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        title: Text(context.tr('Remove connector?'), style: Sa.heading(size: 14)),
        content: Text(
          context.tr('“{name}” will stop feeding alerts. This cannot be undone.',
              {'name': widget.connector.name}),
          style: Sa.body(size: 12, color: Sa.textDim),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Cancel'), style: Sa.body(color: Sa.muted))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Remove'), style: Sa.body(color: Sa.red, weight: FontWeight.w700))),
        ],
      ),
    );
    if (ok == true) await widget.svc.delete(widget.connector.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.connector;
    final e = _entryFor(c.kind);
    final st = _statusStyle(c.runtime.status, context);
    final isPull = c.kind.isPull;
    final isEdge = c.kind.isPush || c.kind.isMqtt;

    return Container(
      decoration: BoxDecoration(
        color: Sa.bg.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.enabled ? st.color.withValues(alpha: 0.4) : Sa.border),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: e.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(e.icon, size: 18, color: e.color),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name.isEmpty ? c.kind.label : c.name,
                      style: Sa.body(size: 13.5, color: Sa.text, weight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(c.kind.label, style: Sa.body(size: 10.5, color: Sa.muted)),
                ],
              ),
            ),
            _statusChip(st),
            const SizedBox(width: 8),
            Switch(
              value: c.enabled,
              activeColor: Sa.green,
              onChanged: (v) => widget.svc.setEnabled(c.id, v),
            ),
          ]),
          const SizedBox(height: 10),
          _metaRow(c),
          if (c.runtime.lastVerifyMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: st.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: st.color.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(st.icon, size: 13, color: st.color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(c.runtime.lastVerifyMessage,
                      style: Sa.body(size: 10.5, color: Sa.textDim)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 11),
          Wrap(spacing: 8, runSpacing: 8, children: [
            SaButton(
              label: _verifying ? context.tr('Verifying…') : context.tr('Verify link test'),
              icon: Icons.cable_outlined,
              color: Sa.cyan,
              busy: _verifying,
              onPressed: _verifying ? null : _verify,
            ),
            if (isPull)
              SaButton(
                label: _polling ? context.tr('Polling…') : context.tr('Poll now'),
                icon: Icons.download_outlined,
                outlined: true,
                busy: _polling,
                onPressed: _polling ? null : _pollNow,
              ),
            if (isEdge)
              SaButton(
                label: context.tr('Endpoint & key'),
                icon: _showEndpoint ? Icons.expand_less : Icons.vpn_key_outlined,
                outlined: true,
                onPressed: _toggleEndpoint,
              ),
            SaButton(
              label: context.tr('Edit'),
              icon: Icons.tune_outlined,
              outlined: true,
              onPressed: widget.onEdit,
            ),
            SaButton(
              label: context.tr('Remove'),
              icon: Icons.delete_outline,
              color: Sa.red,
              outlined: true,
              onPressed: _confirmDelete,
            ),
          ]),
          if (isEdge && _showEndpoint) ...[
            const SizedBox(height: 12),
            _endpointPanel(c),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(({Color color, String label, IconData icon}) st) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: st.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: st.color.withValues(alpha: 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (widget.connector.runtime.status == 'linked')
          PulseDot(color: st.color)
        else
          Icon(st.icon, size: 11, color: st.color),
        const SizedBox(width: 6),
        Text(st.label, style: Sa.mono(size: 9.5, color: st.color, weight: FontWeight.w700)),
      ]),
    );
  }

  Widget _metaRow(IndustrialConnector c) {
    final bits = <({IconData icon, String label})>[
      (icon: Icons.factory_outlined, label: [c.factory, c.line, c.station].where((s) => s.isNotEmpty).join(' / ')),
      (icon: Icons.bolt_outlined, label: '${c.runtime.eventsIngested} ${context.tr('events')}'),
      if (c.runtime.lastValue != null)
        (icon: Icons.speed_outlined, label: '${context.tr('last')} ${c.runtime.lastValue}'),
      (icon: Icons.schedule_outlined, label: '${context.tr('seen')} ${_relative(c.runtime.lastIngestAt, context)}'),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final b in bits)
          if (b.label.trim().isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(b.icon, size: 12, color: Sa.muted),
              const SizedBox(width: 5),
              Text(b.label, style: Sa.body(size: 10.5, color: Sa.textDim)),
            ]),
      ],
    );
  }

  Widget _endpointPanel(IndustrialConnector c) {
    final url = widget.svc.ingestUrl(c.id);
    final key = _ingestKey ?? '…';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Sa.bg.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Point your gateway here'),
              style: Sa.mono(size: 9.5, color: Sa.muted, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          _copyRow(context.tr('Ingest URL'), url),
          const SizedBox(height: 6),
          _copyRow(context.tr('Ingest key (x-alertsys-ingest header)'), key),
          const SizedBox(height: 10),
          Row(children: [
            Text(context.tr('READY-TO-RUN GATEWAY'),
                style: Sa.mono(size: 9, color: Sa.muted, weight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.copy_all_outlined, size: 15, color: Sa.cyan),
              visualDensity: VisualDensity.compact,
              tooltip: context.tr('Copy snippet'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _gatewaySnippet(c, url, key)));
                _toast(context.tr('Gateway snippet copied.'), Sa.cyan);
              },
            ),
          ]),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Sa.border),
            ),
            child: SelectableText(
              _gatewaySnippet(c, url, key),
              style: Sa.mono(size: 9.5, color: const Color(0xFF9FE7C7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _copyRow(String label, String value) {
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Sa.body(size: 10, color: Sa.muted)),
            const SizedBox(height: 2),
            SelectableText(value, style: Sa.mono(size: 10.5, color: Sa.cyan)),
          ],
        ),
      ),
      IconButton(
        icon: Icon(Icons.copy_outlined, size: 14, color: Sa.muted),
        visualDensity: VisualDensity.compact,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: value));
          _toast(context.tr('Copied.'), Sa.cyan);
        },
      ),
    ]);
  }
}

/// A ready-to-run edge gateway snippet for push-mode connectors.
String _gatewaySnippet(IndustrialConnector c, String url, String key) {
  final fac = c.factory.isEmpty ? 'Plant 1' : c.factory;
  final line = c.line.isEmpty ? 'Line 1' : c.line;
  final station = c.station.isEmpty ? 'S1' : c.station;
  switch (c.kind) {
    case ConnectorKind.opcua:
      return '''// OPC-UA → SIAS bridge (Node.js, node-opcua)
// npm i node-opcua node-fetch
const { OPCUAClient, AttributeIds } = require("node-opcua");
const fetch = require("node-fetch");
const SIAS_URL = "$url";
const KEY = "$key";
(async () => {
  const client = OPCUAClient.create({ endpointMustExist: false });
  await client.connect("opc.tcp://YOUR-PLC:4840");
  const session = await client.createSession();
  setInterval(async () => {
    const dv = await session.read({ nodeId: "ns=2;s=Bearing.Temp", attributeId: AttributeIds.Value });
    await fetch(SIAS_URL, { method: "POST",
      headers: { "content-type": "application/json", "x-alertsys-ingest": KEY },
      body: JSON.stringify({ factory: "$fac", line: "$line", station: "$station",
        metric: "bearing_temp", value: dv.value.value, unit: "C",
        thresholds: { warn: 70, critical: 90 } }) });
  }, 5000);
})();''';
    case ConnectorKind.modbus:
      return '''// Modbus TCP → SIAS poller (Node.js, modbus-serial)
// npm i modbus-serial node-fetch
const ModbusRTU = require("modbus-serial");
const fetch = require("node-fetch");
const SIAS_URL = "$url"; const KEY = "$key";
const client = new ModbusRTU();
(async () => {
  await client.connectTCP("YOUR-PLC", { port: 502 });
  client.setID(1);
  setInterval(async () => {
    const { data } = await client.readHoldingRegisters(0, 1); // register 40001
    await fetch(SIAS_URL, { method: "POST",
      headers: { "content-type": "application/json", "x-alertsys-ingest": KEY },
      body: JSON.stringify({ factory: "$fac", line: "$line", station: "$station",
        metric: "pressure", value: data[0], unit: "bar",
        thresholds: { warn: 8, critical: 10 } }) });
  }, 5000);
})();''';
    case ConnectorKind.mqtt:
      return '''# MQTT → SIAS bridge (broker rule, or mosquitto_sub + curl)
# The broker pushes; "Verify link test" proves the broker link with a real
# MQTT CONNACK. Steady-state, forward matching topics to the ingest URL:
mosquitto_sub -h YOUR-BROKER -t 'plant/#' | while read -r MSG; do
  curl -sS "$url" \\
    -H 'content-type: application/json' \\
    -H 'x-alertsys-ingest: $key' \\
    -d "{\\"factory\\":\\"$fac\\",\\"line\\":\\"$line\\",\\"station\\":\\"$station\\",\\"metric\\":\\"vibration\\",\\"value\\":\${MSG},\\"thresholds\\":{\\"warn\\":4,\\"critical\\":7}}"
done''';
    case ConnectorKind.microcontroller:
      return '''// ESP32 / Arduino → SIAS (HTTPS POST)
#include <WiFi.h>
#include <HTTPClient.h>
const char* SIAS_URL = "$url";
const char* KEY = "$key";
void sendReading(float value) {
  HTTPClient http; http.begin(SIAS_URL);
  http.addHeader("content-type", "application/json");
  http.addHeader("x-alertsys-ingest", KEY);
  String body = String("{\\"factory\\":\\"$fac\\",\\"line\\":\\"$line\\",")
    + "\\"station\\":\\"$station\\",\\"metric\\":\\"temp\\",\\"value\\":" + value
    + ",\\"thresholds\\":{\\"warn\\":70,\\"critical\\":90}}";
  http.POST(body); http.end();
}''';
    default:
      return '''# Any system → SIAS (HTTPS POST)
curl -sS "$url" \\
  -H 'content-type: application/json' \\
  -H 'x-alertsys-ingest: $key' \\
  -d '{"factory":"$fac","line":"$line","station":"$station",
       "metric":"bearing_temp","value":95,"unit":"C",
       "thresholds":{"warn":70,"critical":90}}'

# Normal readings raise nothing; an alert is created only when a threshold is
# crossed (or send "alert": true / a canonical "type" to force one).''';
  }
}

// ── Add / edit wizard ────────────────────────────────────────────────────────
class _TagDraft {
  final tag = TextEditingController();
  final metric = TextEditingController();
  final unit = TextEditingController();
  final valuePath = TextEditingController();
  final webId = TextEditingController();
  final warn = TextEditingController();
  final critical = TextEditingController();
  String direction = 'high';
  String type = '';

  _TagDraft();

  factory _TagDraft.from(ConnectorTag t) {
    final d = _TagDraft();
    d.tag.text = t.tag;
    d.metric.text = t.metric;
    d.unit.text = t.unit ?? '';
    d.valuePath.text = t.valuePath ?? '';
    d.webId.text = t.webId ?? '';
    d.warn.text = t.thresholds.warn?.toString() ?? '';
    d.critical.text = t.thresholds.critical?.toString() ?? '';
    d.direction = t.thresholds.direction;
    d.type = t.type ?? '';
    return d;
  }

  ConnectorTag toTag() => ConnectorTag(
        tag: tag.text.trim(),
        metric: metric.text.trim(),
        type: type.isEmpty ? null : type,
        unit: unit.text.trim().isEmpty ? null : unit.text.trim(),
        valuePath: valuePath.text.trim().isEmpty ? null : valuePath.text.trim(),
        webId: webId.text.trim().isEmpty ? null : webId.text.trim(),
        thresholds: ConnectorThresholds(
          warn: num.tryParse(warn.text.trim()),
          critical: num.tryParse(critical.text.trim()),
          direction: direction,
        ),
      );

  bool get isEmpty => tag.text.trim().isEmpty && metric.text.trim().isEmpty;

  void dispose() {
    for (final c in [tag, metric, unit, valuePath, webId, warn, critical]) {
      c.dispose();
    }
  }
}

class _ConnectorEditorDialog extends StatefulWidget {
  final ConnectorService svc;
  final ConnectorKind kind;
  final IndustrialConnector? existing;
  const _ConnectorEditorDialog({required this.svc, required this.kind, this.existing});

  @override
  State<_ConnectorEditorDialog> createState() => _ConnectorEditorDialogState();
}

class _ConnectorEditorDialogState extends State<_ConnectorEditorDialog> {
  late final String _id;
  final _name = TextEditingController();
  final _factory = TextEditingController();
  final _line = TextEditingController();
  final _station = TextEditingController();
  final _endpoint = TextEditingController();
  final _poll = TextEditingController(text: '60');
  final _headerName = TextEditingController(text: 'X-API-Key');
  final _queryParam = TextEditingController(text: 'api_key');
  final _username = TextEditingController();
  final _mqttTopic = TextEditingController();
  final _mqttClientId = TextEditingController();
  // secrets (write-only)
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _ingestKey = TextEditingController();

  String _authScheme = 'none';
  final List<_TagDraft> _tags = [];

  bool _saving = false;
  bool _verifying = false;
  VerifyResult? _result;

  ConnectorKind get _kind => widget.existing?.kind ?? widget.kind;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _id = ex?.id ?? widget.svc.newId();
    if (ex != null) {
      _name.text = ex.name;
      _factory.text = ex.factory;
      _line.text = ex.line;
      _station.text = ex.station;
      _endpoint.text = ex.endpoint;
      _poll.text = ex.pollIntervalSec.toString();
      _authScheme = ex.auth.scheme;
      if (ex.auth.headerName != null) _headerName.text = ex.auth.headerName!;
      if (ex.auth.queryParam != null) _queryParam.text = ex.auth.queryParam!;
      if (ex.auth.username != null) _username.text = ex.auth.username!;
      _mqttTopic.text = ex.mqttTopic;
      _mqttClientId.text = ex.mqttClientId;
      for (final t in ex.tags) {
        _tags.add(_TagDraft.from(t));
      }
    } else {
      _name.text = _kind.label;
      if (_kind == ConnectorKind.historianPi) _authScheme = 'basic';
      if (_kind == ConnectorKind.rest || _kind == ConnectorKind.historianIgnition) {
        _authScheme = 'bearer';
      }
    }
    if (_tags.isEmpty && (_kind.isPull)) _tags.add(_TagDraft());
    if (_kind.isPush) {
      // Pre-fill / generate the per-connector ingest key for the gateway.
      if (ex != null) {
        widget.svc.fetchIngestKey(_id).then((k) {
          if (mounted) setState(() => _ingestKey.text = k ?? widget.svc.generateIngestKey());
        });
      } else {
        _ingestKey.text = widget.svc.generateIngestKey();
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name, _factory, _line, _station, _endpoint, _poll, _headerName,
      _queryParam, _username, _mqttTopic, _mqttClientId, _token, _password, _ingestKey
    ]) {
      c.dispose();
    }
    for (final t in _tags) {
      t.dispose();
    }
    super.dispose();
  }

  IndustrialConnector _build() {
    return IndustrialConnector(
      id: _id,
      name: _name.text.trim().isEmpty ? _kind.label : _name.text.trim(),
      kind: _kind,
      enabled: widget.existing?.enabled ?? true,
      factory: _factory.text.trim(),
      line: _line.text.trim(),
      station: _station.text.trim(),
      endpoint: _endpoint.text.trim(),
      pollIntervalSec: int.tryParse(_poll.text.trim()) ?? 60,
      auth: ConnectorAuth(
        scheme: _kind.isMqtt ? (_username.text.trim().isEmpty ? 'none' : 'basic') : _authScheme,
        headerName: _headerName.text.trim(),
        queryParam: _queryParam.text.trim(),
        username: _username.text.trim(),
      ),
      tags: _tags.where((t) => !t.isEmpty).map((t) => t.toTag()).toList(),
      mqttTopic: _mqttTopic.text.trim(),
      mqttClientId: _mqttClientId.text.trim(),
      createdAt: widget.existing?.createdAt ?? '',
    );
  }

  Future<bool> _persist() async {
    await widget.svc.save(_build());
    await widget.svc.saveSecret(
      _id,
      ConnectorSecret(
        token: _token.text,
        password: _password.text,
        ingestKey: _kind.isPush ? _ingestKey.text : null,
      ),
    );
    return true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _persist();
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _result = null;
    });
    await _persist();
    final r = await widget.svc.verify(_id);
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _result = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = _entryFor(_kind);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: GlassPanel(
          accent: e.color,
          glow: true,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(e),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(context.tr('Connector name'), _name, hint: e.kind.label),
                      Row(children: [
                        Expanded(child: _field(context.tr('Factory'), _factory, hint: 'Plant 1')),
                        const SizedBox(width: 10),
                        Expanded(child: _field(context.tr('Line'), _line, hint: 'Line 2')),
                        const SizedBox(width: 10),
                        Expanded(child: _field(context.tr('Station'), _station, hint: 'S3')),
                      ]),
                      if (_kind.isPull) ..._pullFields(),
                      if (_kind.isMqtt) ..._mqttFields(),
                      if (_kind.isPush) ..._pushFields(),
                      if (_result != null) ...[
                        const SizedBox(height: 14),
                        _resultBanner(_result!),
                      ],
                    ],
                  ),
                ),
              ),
              _footer(e),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(_CatalogEntry e) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [e.color.withValues(alpha: 0.3), e.color.withValues(alpha: 0.08)]),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: e.color.withValues(alpha: 0.5)),
          ),
          child: Icon(e.icon, size: 19, color: e.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? context.tr('New connector') : context.tr('Edit connector'),
                  style: Sa.display(size: 15)),
              Text(e.kind.label, style: Sa.body(size: 11, color: Sa.muted)),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.close, size: 18, color: Sa.muted),
          onPressed: () => Navigator.pop(context),
        ),
      ]),
    );
  }

  List<Widget> _pullFields() {
    return [
      const SizedBox(height: 4),
      _field(context.tr('Endpoint URL'), _endpoint,
          hint: _kind == ConnectorKind.historianPi
              ? 'https://pi-server/piwebapi'
              : 'https://host/api'),
      _authBlock(),
      _field(context.tr('Poll interval (seconds)'), _poll, hint: '60', number: true),
      const SizedBox(height: 8),
      _tagsEditor(pull: true),
    ];
  }

  List<Widget> _mqttFields() {
    return [
      const SizedBox(height: 4),
      _field(context.tr('Broker URL (MQTT over WebSocket)'), _endpoint,
          hint: 'wss://broker:8084/mqtt'),
      Row(children: [
        Expanded(child: _field(context.tr('Topic'), _mqttTopic, hint: 'plant/#')),
        const SizedBox(width: 10),
        Expanded(child: _field(context.tr('Client ID'), _mqttClientId, hint: 'sia-bridge')),
      ]),
      Row(children: [
        Expanded(child: _field(context.tr('Username'), _username, hint: context.tr('optional'))),
        const SizedBox(width: 10),
        Expanded(
            child: _secretField(context.tr('Password'), _password,
                hint: context.tr('optional'))),
      ]),
      const SizedBox(height: 6),
      _hint(context.tr(
          'Verify opens a real MQTT connection and waits for the broker CONNACK. For steady-state, forward matching topics to the ingest URL (shown after Save).')),
      const SizedBox(height: 8),
      _tagsEditor(pull: false),
    ];
  }

  List<Widget> _pushFields() {
    return [
      const SizedBox(height: 8),
      _hint(context.tr(
          'Edge-push connector. After Save you get a dedicated ingest URL + key and a ready-to-run gateway snippet. Verify reads LINKED once your gateway sends its first packet.')),
      const SizedBox(height: 10),
      Text(context.tr('Per-connector ingest key'),
          style: Sa.body(size: 11, color: Sa.textDim, weight: FontWeight.w600)),
      const SizedBox(height: 5),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _ingestKey,
            readOnly: true,
            style: Sa.mono(size: 11.5, color: Sa.cyan),
            decoration: _dec(null),
          ),
        ),
        IconButton(
          tooltip: context.tr('Regenerate'),
          icon: Icon(Icons.autorenew, size: 17, color: Sa.amber),
          onPressed: () => setState(() => _ingestKey.text = widget.svc.generateIngestKey()),
        ),
      ]),
      const SizedBox(height: 10),
      Text(context.tr('Optional tag mapping (metric · thresholds for incoming readings)'),
          style: Sa.mono(size: 9.5, color: Sa.muted, weight: FontWeight.w700)),
      const SizedBox(height: 6),
      _tagsEditor(pull: false),
    ];
  }

  Widget _authBlock() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Authentication'),
              style: Sa.body(size: 11, color: Sa.textDim, weight: FontWeight.w600)),
          const SizedBox(height: 5),
          _dropdown(_authScheme, const {
            'none': 'None',
            'bearer': 'Bearer token',
            'basic': 'Basic (user + password)',
            'header': 'API key header',
            'query': 'API key query param',
          }, (v) => setState(() => _authScheme = v)),
          if (_authScheme == 'bearer' || _authScheme == 'header' || _authScheme == 'query') ...[
            if (_authScheme == 'header')
              _field(context.tr('Header name'), _headerName, hint: 'X-API-Key'),
            if (_authScheme == 'query')
              _field(context.tr('Query parameter'), _queryParam, hint: 'api_key'),
            _secretField(context.tr('Token / API key'), _token,
                hint: widget.existing != null ? context.tr('leave blank to keep current') : null),
          ],
          if (_authScheme == 'basic') ...[
            _field(context.tr('Username'), _username, hint: 'user'),
            _secretField(context.tr('Password'), _password,
                hint: widget.existing != null ? context.tr('leave blank to keep current') : null),
          ],
        ],
      ),
    );
  }

  Widget _tagsEditor({required bool pull}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(pull ? context.tr('Tags to read') : context.tr('Tag mappings'),
              style: Sa.mono(size: 9.5, color: Sa.muted, weight: FontWeight.w700)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _tags.add(_TagDraft())),
            icon: Icon(Icons.add, size: 15, color: Sa.cyan),
            label: Text(context.tr('Add'), style: Sa.body(size: 11, color: Sa.cyan)),
          ),
        ]),
        for (int i = 0; i < _tags.length; i++) _tagRow(i, pull),
      ],
    );
  }

  Widget _tagRow(int i, bool pull) {
    final t = _tags[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Sa.bg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        children: [
          Row(children: [
            Expanded(
                child: _miniField(
                    pull ? context.tr('Tag / node / register') : context.tr('Incoming tag'),
                    t.tag)),
            const SizedBox(width: 8),
            Expanded(child: _miniField(context.tr('Metric'), t.metric, hint: 'bearing_temp')),
            IconButton(
              icon: Icon(Icons.remove_circle_outline, size: 17, color: Sa.red),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                _tags.removeAt(i).dispose();
              }),
            ),
          ]),
          if (pull && _kind == ConnectorKind.historianPi)
            _miniField(context.tr('PI WebId'), t.webId, hint: 'F1AbEf…'),
          if (pull && _kind != ConnectorKind.historianPi)
            _miniField(context.tr('Value JSON path'), t.valuePath, hint: 'value'),
          Row(children: [
            Expanded(child: _miniField(context.tr('Unit'), t.unit, hint: 'C')),
            const SizedBox(width: 8),
            Expanded(child: _miniField(context.tr('Warn ≥'), t.warn, number: true)),
            const SizedBox(width: 8),
            Expanded(child: _miniField(context.tr('Critical ≥'), t.critical, number: true)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: _dropdown(t.direction, const {
                'high': 'Higher is worse',
                'low': 'Lower is worse',
              }, (v) => setState(() => t.direction = v)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dropdown(t.type.isEmpty ? 'auto' : t.type, const {
                'auto': 'Type: auto',
                'Mechanical': 'Mechanical',
                'Electrical': 'Electrical',
                'Quality': 'Quality',
                'Safety': 'Safety',
              }, (v) => setState(() => t.type = v == 'auto' ? '' : v)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _resultBanner(VerifyResult r) {
    final st = _statusStyle(r.status, context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: st.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: st.color.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(st.icon, color: st.color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(st.label,
                  style: Sa.body(size: 12.5, color: st.color, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(r.message, style: Sa.body(size: 11, color: Sa.textDim)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _footer(_CatalogEntry e) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Sa.border)),
      ),
      child: Row(children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel'), style: Sa.body(color: Sa.muted)),
        ),
        const Spacer(),
        SaButton(
          label: _saving ? context.tr('Saving…') : context.tr('Save'),
          icon: Icons.save_outlined,
          outlined: true,
          busy: _saving,
          onPressed: (_saving || _verifying) ? null : _save,
        ),
        const SizedBox(width: 10),
        SaButton(
          label: _verifying ? context.tr('Verifying…') : context.tr('Verify link test'),
          icon: Icons.cable_outlined,
          color: e.color,
          busy: _verifying,
          onPressed: (_saving || _verifying) ? null : _verify,
        ),
      ]),
    );
  }

  // ── small field helpers ────────────────────────────────────────────────────
  Widget _field(String label, TextEditingController c,
      {String? hint, bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Sa.body(size: 11, color: Sa.textDim, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: c,
            keyboardType: number ? TextInputType.number : null,
            style: Sa.body(size: 12.5, color: Sa.text),
            decoration: _dec(hint),
          ),
        ],
      ),
    );
  }

  Widget _miniField(String label, TextEditingController c, {String? hint, bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : null,
        style: Sa.body(size: 11.5, color: Sa.text),
        decoration: _dec(hint).copyWith(
          labelText: label,
          labelStyle: Sa.body(size: 10.5, color: Sa.muted),
        ),
      ),
    );
  }

  Widget _secretField(String label, TextEditingController c, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lock_outline, size: 12, color: Sa.amber),
            const SizedBox(width: 5),
            Text(label, style: Sa.body(size: 11, color: Sa.textDim, weight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text(context.tr('write-only'), style: Sa.mono(size: 8.5, color: Sa.muted)),
          ]),
          const SizedBox(height: 4),
          TextField(
            controller: c,
            obscureText: true,
            style: Sa.mono(size: 12, color: Sa.text),
            decoration: _dec(hint),
          ),
        ],
      ),
    );
  }

  Widget _hint(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Sa.cyan.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Sa.cyan.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 13, color: Sa.cyan),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Sa.body(size: 10.5, color: Sa.textDim))),
      ]),
    );
  }

  Widget _dropdown(String value, Map<String, String> options, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Sa.bg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.containsKey(value) ? value : options.keys.first,
          isExpanded: true,
          dropdownColor: Sa.panelSolid,
          style: Sa.body(size: 12.5, color: Sa.text),
          icon: Icon(Icons.expand_more, color: Sa.muted, size: 18),
          items: [
            for (final entry in options.entries)
              DropdownMenuItem(value: entry.key, child: Text(context.tr(entry.value))),
          ],
          onChanged: (v) => onChanged(v ?? value),
        ),
      ),
    );
  }

  InputDecoration _dec(String? hint) => InputDecoration(
        hintText: hint,
        hintStyle: Sa.body(size: 11.5, color: Sa.muted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: Sa.bg.withValues(alpha: 0.5),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Sa.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Sa.cyan, width: 1.4),
        ),
      );
}
