import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../superadmin_theme.dart';
import 'hw_models.dart';
import 'hw_runtime.dart';

/// ESP32 → Firebase connectivity test.
///
/// This is real, not a mock: the simulated controller's `Firebase.setFloat()` /
/// `getFloat()` calls are bridged straight to the live Realtime Database under
/// `hardware_lab/telemetry/{deviceId}`, and the handshake test writes a nonce
/// and reads it back to measure the true round-trip latency to production.
/// The operator sees the backend layer answer the hardware layer.

String hwSanitizeId(String raw) {
  final s = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
  final t = s.replaceAll(RegExp(r'^-+|-+$'), '');
  return t.isEmpty ? 'device' : t;
}

class HwLinkEvent {
  final DateTime at;
  final String dir; // tx / rx / ok / err
  final String label;
  const HwLinkEvent(this.at, this.dir, this.label);
}

class HwConnectivityPanel extends StatefulWidget {
  final HwSimulator sim;
  final String deviceId;
  final String deviceLabel;

  const HwConnectivityPanel({
    super.key,
    required this.sim,
    required this.deviceId,
    required this.deviceLabel,
  });

  @override
  State<HwConnectivityPanel> createState() => _HwConnectivityPanelState();
}

class _HwConnectivityPanelState extends State<HwConnectivityPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow;
  final List<HwLinkEvent> _events = [];
  Map<String, Object?> _cloud = {};
  StreamSubscription<DatabaseEvent>? _cloudSub;

  bool _testing = false;
  bool? _linkUp;
  int? _rttMs;
  bool _bridgeActive = false;
  int _txCount = 0; // real telemetry writes the running sketch produced
  int _rxCount = 0;
  bool _lastRunning = false;

  DatabaseReference get _root =>
      FirebaseDatabase.instance.ref('hardware_lab/telemetry/${widget.deviceId}');

  HwCircuit get _circuit => widget.sim.circuit;
  String get _sketch => _circuit.sketch;
  bool get _hasController => _circuit.controller != null;

  /// The firmware actually talks to the cloud (our interpreter binds
  /// `Firebase.set*/get*` and `Cloud.*`).
  bool get _firmwareUsesCloud =>
      RegExp(r'(Firebase|Cloud)\s*\.\s*(set|get|push|update)', caseSensitive: false)
          .hasMatch(_sketch);

  bool get _firmwareUsesWifi =>
      RegExp(r'WiFi|#include\s*<.*WiFi', caseSensitive: false).hasMatch(_sketch);

  /// Overall verdict: null = not ready to judge, true = online, false = down.
  bool? get _overall {
    if (!_hasController || !_firmwareUsesCloud) return null;
    return _linkUp;
  }

  @override
  void initState() {
    super.initState();
    _flow = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
    _wireBridge();
    _listenCloud();
    _lastRunning = widget.sim.isRunning;
    widget.sim.addListener(_onSim);
  }

  void _onSim() {
    if (!mounted) return;
    // Only rebuild when the run-state flips; telemetry rebuilds via _bridgeSet.
    if (widget.sim.isRunning != _lastRunning) {
      _lastRunning = widget.sim.isRunning;
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant HwConnectivityPanel old) {
    super.didUpdateWidget(old);
    if (old.deviceId != widget.deviceId) {
      _cloudSub?.cancel();
      _listenCloud();
      _wireBridge();
      // A different device → its link verdict and telemetry start fresh.
      setState(() {
        _linkUp = null;
        _rttMs = null;
        _txCount = 0;
        _rxCount = 0;
        _events.clear();
        _cloud = {};
      });
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    _cloudSub?.cancel();
    widget.sim.removeListener(_onSim);
    // Detach the bridge so a disposed panel never writes to RTDB.
    if (identical(widget.sim.onFirebaseSet, _bridgeSet)) {
      widget.sim.onFirebaseSet = null;
    }
    if (identical(widget.sim.onFirebaseGet, _bridgeGet)) {
      widget.sim.onFirebaseGet = null;
    }
    super.dispose();
  }

  void _wireBridge() {
    widget.sim.onFirebaseSet = _bridgeSet;
    widget.sim.onFirebaseGet = _bridgeGet;
    _bridgeActive = true;
  }

  Future<void> _bridgeSet(String path, Object? value) async {
    final clean = hwSanitizeId(path.isEmpty ? 'value' : path);
    _txCount++;
    _log('tx', 'setFloat("$path") → $value');
    await _root.child('data/$clean').set({
      'value': value is num ? value : '$value',
      'at': ServerValue.timestamp,
    });
    _log('ok', 'cloud ACK · $clean');
  }

  Future<num> _bridgeGet(String path) async {
    final clean = hwSanitizeId(path.isEmpty ? 'value' : path);
    final snap = await _root.child('data/$clean/value').get();
    final v = snap.value;
    _rxCount++;
    _log('rx', 'getFloat("$path") ← ${v ?? 0}');
    return (v is num) ? v : num.tryParse('$v') ?? 0;
  }

  void _listenCloud() {
    _cloudSub = _root.child('data').onValue.listen((event) {
      final v = event.snapshot.value;
      if (!mounted) return;
      setState(() {
        _cloud = (v is Map) ? Map<String, Object?>.from(v) : {};
      });
    }, onError: (_) {});
  }

  void _log(String dir, String label) {
    if (!mounted) return;
    setState(() {
      _events.insert(0, HwLinkEvent(DateTime.now(), dir, label));
      if (_events.length > 60) _events.removeLast();
    });
  }

  Future<void> _runHandshake() async {
    setState(() {
      _testing = true;
      _linkUp = null;
      _rttMs = null;
    });
    final nonce = math.Random().nextInt(0x7fffffff);
    final ref = _root.child('handshake');
    try {
      _log('tx', 'ESP32 boot · acquiring Wi-Fi…');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      _log('tx', 'TX  nonce=$nonce → Firebase');
      final t0 = DateTime.now().millisecondsSinceEpoch;
      await ref.set({'nonce': nonce, 'sentAt': ServerValue.timestamp});
      _log('ok', 'cloud write committed');
      final snap = await ref.child('nonce').get();
      final t1 = DateTime.now().millisecondsSinceEpoch;
      final got = snap.value;
      final ok = (got is num ? got.toInt() : int.tryParse('$got')) == nonce;
      if (!mounted) return;
      setState(() {
        _linkUp = ok;
        _rttMs = t1 - t0;
        _testing = false;
      });
      _log(ok ? 'ok' : 'err',
          ok ? 'RX  echo verified · RTT ${t1 - t0} ms' : 'echo mismatch');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _linkUp = false;
        _testing = false;
      });
      _log('err', _reason(e));
    }
  }

  String _reason(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('permission')) {
      return 'permission denied — deploy database rules (hardware_lab)';
    }
    if (s.contains('network') || s.contains('offline')) {
      return 'network unreachable — device is offline';
    }
    return 'link error: $e';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _linkDiagram(),
          const SizedBox(height: 14),
          _readinessCard(),
          const SizedBox(height: 14),
          _controls(),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _cloudMonitor()),
              const SizedBox(width: 12),
              Expanded(child: _packetLog()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linkDiagram() {
    final up = _overall;
    final color = up == null ? Sa.muted : (up ? Sa.green : Sa.red);
    return GlassPanel(
      accent: color,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: AnimatedBuilder(
              animation: _flow,
              builder: (_, __) => CustomPaint(
                size: Size.infinite,
                painter: _LinkPainter(
                  t: _flow.value,
                  active: widget.sim.isRunning || _testing,
                  up: up,
                  deviceLabel: widget.deviceLabel,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              GlowChip(
                label: up == null
                    ? 'LINK · STANDBY'
                    : up
                        ? 'LINK · ONLINE'
                        : 'LINK · DOWN',
                color: color,
                pulse: up == true,
              ),
              if (_rttMs != null) GlowChip(label: 'RTT ${_rttMs}ms', color: Sa.cyan),
              if (_txCount > 0)
                GlowChip(label: 'TELEMETRY · $_txCount TX', color: Sa.green),
              if (_rxCount > 0)
                GlowChip(label: '$_rxCount RX', color: Sa.cyan),
              if (_bridgeActive)
                GlowChip(label: 'FIREBASE BRIDGE ARMED', color: Sa.violet),
            ],
          ),
        ],
      ),
    );
  }

  /// Real, sketch-aware readiness — this is what makes the link verdict honest
  /// instead of "connected" the moment a raw RTDB write succeeds.
  Widget _readinessCard() {
    final board = _circuit.controller;
    final running = widget.sim.isRunning;
    return GlassPanel(
      accent: Sa.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SaSectionHeader(
            icon: Icons.fact_check,
            title: 'Firmware Readiness',
            subtitle: 'What actually has to be true for the device to talk to the cloud',
          ),
          const SizedBox(height: 12),
          _ReadyRow(
            ok: _hasController,
            label: 'Controller on the bench',
            detail: board == null
                ? 'Drop an ESP32 / ESP8266 / Pico onto the canvas — a plain Arduino UNO has no WiFi.'
                : '${board.def.name} detected',
          ),
          _ReadyRow(
            ok: _firmwareUsesWifi,
            warn: true,
            label: 'Wi-Fi in firmware',
            detail: _firmwareUsesWifi
                ? 'WiFi.begin(...) found in the sketch'
                : 'No WiFi.begin() — add it so the real device can associate (the simulator still bridges).',
          ),
          _ReadyRow(
            ok: _firmwareUsesCloud,
            label: 'Firebase calls in firmware',
            detail: _firmwareUsesCloud
                ? 'Firebase.set/get found — telemetry will flow when you run'
                : 'Add e.g. Firebase.setFloat("machines/MACH-001/temp", t); — without it nothing is sent.',
          ),
          _ReadyRow(
            ok: _linkUp == true,
            warn: _linkUp == null,
            label: 'Cloud reachable',
            detail: _linkUp == null
                ? 'Not measured yet — run the handshake below.'
                : _linkUp == true
                    ? 'RTDB round-trip verified${_rttMs != null ? ' · ${_rttMs}ms' : ''}'
                    : 'Handshake failed — check rules / network.',
          ),
          _ReadyRow(
            ok: _txCount > 0,
            warn: !running,
            label: 'Live telemetry observed',
            detail: _txCount > 0
                ? '$_txCount value(s) pushed by the running sketch'
                : running
                    ? 'Running, but the sketch has not called Firebase yet.'
                    : 'Press UPLOAD ▶ in DESIGN and your Firebase writes will land here for real.',
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SaSectionHeader(
            icon: Icons.cell_tower,
            title: 'Backend Connectivity',
            subtitle: 'Prove the hardware layer reaches the cloud',
          ),
          const SizedBox(height: 12),
          Text(
            'The handshake writes a nonce to '
            'hardware_lab/telemetry/${widget.deviceId} and reads it back to '
            'measure the live round-trip — that only proves the cloud is '
            'reachable. The link reads ONLINE only once your firmware actually '
            'uses Firebase and the running sketch pushes telemetry.',
            style: Sa.body(size: 12, color: Sa.textDim),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SaButton(
                label: 'RUN HANDSHAKE',
                icon: Icons.wifi_tethering,
                color: Sa.green,
                busy: _testing,
                onPressed: (_testing || !_hasController) ? null : _runHandshake,
              ),
              const SizedBox(width: 10),
              SaButton(
                label: 'CLEAR',
                icon: Icons.clear_all,
                color: Sa.muted,
                outlined: true,
                onPressed: () => setState(() {
                  _events.clear();
                  _txCount = 0;
                  _rxCount = 0;
                }),
              ),
            ],
          ),
          if (!_hasController) ...[
            const SizedBox(height: 10),
            Text('Add a controller board on the DESIGN canvas first.',
                style: Sa.body(size: 11, color: Sa.amber)),
          ],
        ],
      ),
    );
  }

  Widget _cloudMonitor() {
    final keys = _cloud.keys.toList()..sort();
    return GlassPanel(
      accent: Sa.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done, size: 15, color: Sa.violet),
              const SizedBox(width: 8),
              Text('CLOUD STATE', style: Sa.mono(size: 10, color: Sa.violet)),
              const Spacer(),
              Text('hardware_lab/telemetry',
                  style: Sa.mono(size: 8, color: Sa.muted)),
            ],
          ),
          const SizedBox(height: 10),
          if (keys.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('No telemetry yet. Run the sketch with Firebase.setFloat().',
                  style: Sa.body(size: 11.5, color: Sa.muted)),
            )
          else
            ...keys.map((k) {
              final entry = _cloud[k];
              final value = (entry is Map) ? entry['value'] : entry;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Sa.bgRaised.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Sa.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(k,
                          style: Sa.mono(size: 11, color: Sa.text)),
                    ),
                    Text('$value',
                        style: Sa.mono(
                            size: 12, color: Sa.green, weight: FontWeight.w700)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _packetLog() {
    return GlassPanel(
      accent: Sa.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_vert, size: 15, color: Sa.cyan),
              const SizedBox(width: 8),
              Text('PACKET LOG', style: Sa.mono(size: 10, color: Sa.cyan)),
            ],
          ),
          const SizedBox(height: 10),
          if (_events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('Idle. Run a handshake or start the simulation.',
                  style: Sa.body(size: 11.5, color: Sa.muted)),
            )
          else
            SizedBox(
              height: 180,
              child: ListView.builder(
                itemCount: _events.length,
                itemBuilder: (_, i) {
                  final e = _events[i];
                  final c = switch (e.dir) {
                    'tx' => Sa.cyan,
                    'rx' => Sa.violet,
                    'ok' => Sa.green,
                    _ => Sa.red,
                  };
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.dir.toUpperCase().padRight(3),
                            style: Sa.mono(
                                size: 9, color: c, weight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(e.label,
                              style: Sa.mono(size: 10, color: Sa.termText)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadyRow extends StatelessWidget {
  final bool ok;
  final bool warn;
  final String label;
  final String detail;
  const _ReadyRow({
    required this.ok,
    required this.label,
    required this.detail,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = ok ? Sa.green : (warn ? Sa.amber : Sa.red);
    final icon = ok
        ? Icons.check_circle
        : (warn ? Icons.radio_button_unchecked : Icons.cancel);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Sa.body(size: 12.5, weight: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(detail, style: Sa.body(size: 10.5, color: Sa.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkPainter extends CustomPainter {
  final double t;
  final bool active;
  final bool? up;
  final String deviceLabel;
  _LinkPainter({
    required this.t,
    required this.active,
    required this.up,
    required this.deviceLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final left = Offset(56, size.height / 2);
    final right = Offset(size.width - 56, size.height / 2);
    final color = up == null
        ? const Color(0xFF22D3EE)
        : (up! ? const Color(0xFF34D399) : const Color(0xFFF87171));

    // Link line.
    canvas.drawLine(
        left,
        right,
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..strokeWidth = 2);

    // Travelling packets.
    if (active && up != false) {
      for (var i = 0; i < 4; i++) {
        final p = (t + i / 4) % 1.0;
        final pos = Offset.lerp(left, right, p)!;
        canvas.drawCircle(pos, 3.5,
            Paint()..color = color.withValues(alpha: 0.9));
        canvas.drawCircle(pos, 7,
            Paint()..color = color.withValues(alpha: 0.25));
      }
    }

    // ESP32 chip node.
    _node(canvas, left, const Color(0xFF111C33), const Color(0xFF22D3EE),
        Icons.memory, deviceLabel);
    // Cloud node.
    _node(canvas, right, const Color(0xFF1A1330), const Color(0xFFA78BFA),
        Icons.cloud, 'Firebase');
  }

  void _node(Canvas canvas, Offset c, Color fill, Color border, IconData icon,
      String label) {
    final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 84, height: 56),
        const Radius.circular(12));
    canvas.drawRRect(rect, Paint()..color = fill);
    canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = border);
    final ip = TextPainter(
      text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
              fontSize: 22,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              color: border)),
      textDirection: TextDirection.ltr,
    )..layout();
    ip.paint(canvas, c - Offset(ip.width / 2, ip.height / 2 + 8));
    final lp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              fontSize: 9, color: border, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 80);
    lp.paint(canvas, c - Offset(lp.width / 2, -10));
  }

  @override
  bool shouldRepaint(covariant _LinkPainter old) =>
      old.t != t || old.up != up || old.active != active;
}
