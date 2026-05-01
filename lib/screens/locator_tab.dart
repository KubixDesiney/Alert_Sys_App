// lib/screens/locator_tab.dart
//
// Supervisor-facing locator. Renders the FactoryMap built by the production
// manager (live, via streamFactoryMap). When the supervisor has claimed an
// alert, an animated blue arrow runs from the factory entrance to that
// station's circle, which pulses blue.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alert_model.dart';
import '../models/factory_map_model.dart';
import '../models/hierarchy_model.dart';
import '../providers/alert_provider.dart';
import '../services/hierarchy_service.dart';
import '../theme.dart';
import '../widgets/locator_painter.dart';
import 'alert_detail_screen.dart';

class LocatorScreen extends StatefulWidget {
  final String supervisorId;
  final String factoryName;

  const LocatorScreen({
    super.key,
    required this.supervisorId,
    required this.factoryName,
  });

  @override
  State<LocatorScreen> createState() => _LocatorScreenState();
}

class _LocatorScreenState extends State<LocatorScreen>
    with SingleTickerProviderStateMixin {
  final HierarchyService _service = HierarchyService();
  late final AnimationController _pulse;
  StreamSubscription<List<Factory>>? _factoriesSub;
  StreamSubscription<FactoryMap>? _mapSub;
  List<Factory> _factories = const [];
  FactoryMap? _map;
  String? _trackedFactoryId;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _factoriesSub = _service.getFactories().listen((list) {
      if (!mounted) return;
      setState(() => _factories = list);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _factoriesSub?.cancel();
    _mapSub?.cancel();
    super.dispose();
  }

  Factory? _resolveFactory(AlertModel? claim) {
    final factories = _factories;
    if (claim != null) {
      for (final f in factories) {
        if (_matches(f, claim.usine)) return f;
      }
    }
    for (final f in factories) {
      if (_matches(f, widget.factoryName)) return f;
    }
    return factories.isEmpty ? null : factories.first;
  }

  bool _matches(Factory f, String value) {
    final n = _normalize(value);
    return n == _normalize(f.id) || n == _normalize(f.name);
  }

  String _normalize(String v) =>
      v.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  void _ensureMapStream(String factoryId) {
    if (_trackedFactoryId == factoryId) return;
    _trackedFactoryId = factoryId;
    _mapSub?.cancel();
    _map = null;
    _mapSub = _service.streamFactoryMap(factoryId).listen((m) {
      if (!mounted) return;
      setState(() => _map = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final alerts = context.watch<AlertProvider>().allAlerts;
    final claim = _activeClaim(alerts, widget.supervisorId);
    final factory = _resolveFactory(claim);

    if (_factories.isEmpty) {
      return Center(child: CircularProgressIndicator(color: t.navy));
    }
    if (factory == null) {
      return _Empty(
        icon: Icons.factory_outlined,
        title: 'No factory',
        message: 'No matching factory for ${widget.factoryName}.',
      );
    }
    _ensureMapStream(factory.id);

    final map = _map;
    if (map == null) {
      return Center(child: CircularProgressIndicator(color: t.navy));
    }

    final factoryAlerts =
        alerts.where((a) => _matches(factory, a.usine)).toList();
    final badges = <String, LocatorNodeBadge>{};
    for (final node in map.nodes) {
      final stationAlerts = factoryAlerts
          .where((a) =>
              a.convoyeur == node.conveyorNumber &&
              a.poste == node.stationNumber)
          .toList()
        ..sort((a, b) =>
            _alertPriority(b).compareTo(_alertPriority(a)));
      if (stationAlerts.isEmpty) continue;
      final top = stationAlerts.first;
      badges[node.key] = LocatorNodeBadge(
        key: node.key,
        status: _statusFor(top),
        alertNumber: top.alertNumber == 0 ? null : top.alertNumber,
      );
    }

    final claimedNode = claim == null
        ? null
        : map.nodeForStation(claim.convoyeur, claim.poste);
    final claimedKey = claimedNode?.key;

    return Container(
      color: t.scaffold,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _LocatorHeader(
              factory: factory,
              mapped: map.nodes.length,
              hasMap: !map.isEmpty,
              hasClaim: claim != null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 880;
                  final canvas = _MapCard(
                    map: map,
                    pulse: _pulse,
                    claimedKey: claimedKey,
                    badges: badges,
                  );
                  final side = _SidePanel(
                    factory: factory,
                    claim: claim,
                    claimedNode: claimedNode,
                    badges: badges,
                    map: map,
                  );
                  return wide
                      ? Row(children: [
                          Expanded(child: canvas),
                          const SizedBox(width: 12),
                          SizedBox(width: 320, child: side),
                        ])
                      : Column(children: [
                          Expanded(child: canvas),
                          const SizedBox(height: 10),
                          SizedBox(height: 200, child: side),
                        ]);
                }),
              ),
            ),
            if (claim == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: t.orangeLt,
                  border: Border(top: BorderSide(color: t.orange)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: t.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No claimed alert. Claim one to see its route on the map.',
                        style: TextStyle(
                          color: t.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

class _LocatorHeader extends StatelessWidget {
  final Factory factory;
  final int mapped;
  final bool hasMap;
  final bool hasClaim;

  const _LocatorHeader({
    required this.factory,
    required this.mapped,
    required this.hasMap,
    required this.hasClaim,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.green, t.blue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.map_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Locator',
                    style: TextStyle(
                      color: t.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    )),
                Text(factory.name,
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              _Pill(
                  icon: Icons.pin_drop_outlined,
                  label: '$mapped mapped',
                  color: mapped > 0 ? t.green : t.muted),
              _Pill(
                  icon: hasMap
                      ? Icons.check_circle_outline_rounded
                      : Icons.dashboard_outlined,
                  label: hasMap ? 'Map ready' : 'No map',
                  color: hasMap ? t.green : t.orange),
              _Pill(
                  icon: hasClaim
                      ? Icons.navigation_rounded
                      : Icons.navigation_outlined,
                  label: hasClaim ? 'Route on' : 'No route',
                  color: hasClaim ? t.blue : t.muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapCard extends StatelessWidget {
  final FactoryMap map;
  final AnimationController pulse;
  final String? claimedKey;
  final Map<String, LocatorNodeBadge> badges;

  const _MapCard({
    required this.map,
    required this.pulse,
    required this.claimedKey,
    required this.badges,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (map.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
        ),
        child: _Empty(
          icon: Icons.dashboard_customize_outlined,
          title: 'Map not configured',
          message:
              'Ask the production manager to build this factory in Hierarchy → Factory Mapping.',
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(alpha: context.isDark ? 0.22 : 0.07),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: InteractiveViewer(
          minScale: 0.6,
          maxScale: 4,
          boundaryMargin: const EdgeInsets.all(120),
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              return CustomPaint(
                size: Size.infinite,
                painter: FactoryMapLocatorPainter(
                  map: map,
                  theme: t,
                  isDark: context.isDark,
                  badges: badges,
                  claimedNodeKey: claimedKey,
                  pulse: pulse.value,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  final Factory factory;
  final AlertModel? claim;
  final MapNode? claimedNode;
  final Map<String, LocatorNodeBadge> badges;
  final FactoryMap map;

  const _SidePanel({
    required this.factory,
    required this.claim,
    required this.claimedNode,
    required this.badges,
    required this.map,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (claim == null)
            _InfoBlock(
              icon: Icons.map_outlined,
              color: t.orange,
              title: 'No active claim',
              message: 'Claim an alert to view its blue route.',
            )
          else if (claimedNode == null)
            _InfoBlock(
              icon: Icons.report_gmailerrorred_outlined,
              color: t.red,
              title: 'Station not on map',
              message:
                  'C${claim!.convoyeur}S${claim!.poste} has not been placed yet.',
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AlertDetailScreen(alertId: claim!.id)),
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.blueLt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.blue.withValues(alpha: 0.28)),
                ),
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.navigation_rounded,
                        color: t.blue, size: 26),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(claimedNode!.label,
                            style: TextStyle(
                              color: t.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            )),
                        Text(_typeLabel(claim!.type),
                            style: TextStyle(color: t.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: t.muted),
                ]),
              ),
            ),
          const SizedBox(height: 14),
          Text('Live station status',
              style: TextStyle(
                color: t.text,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 8),
          Expanded(
            child: badges.isEmpty
                ? Center(
                    child: Text('All mapped stations idle',
                        style: TextStyle(color: t.muted)))
                : ListView(
                    children: badges.entries.map((e) {
                      final node = map.nodeByKey(e.key);
                      if (node == null) return const SizedBox.shrink();
                      final color = _badgeColor(e.value.status, t);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              node.label,
                              style: TextStyle(
                                  color: t.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                          if (e.value.alertNumber != null)
                            Text('#${e.value.alertNumber}',
                                style: TextStyle(
                                    color: t.muted, fontSize: 11)),
                        ]),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _InfoBlock({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: t.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 13)),
              Text(message, style: TextStyle(color: t.muted, fontSize: 12)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: t.text, fontSize: 11, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _Empty(
      {required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
                color: t.navyLt, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: t.navy, size: 28),
          ),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: t.text, fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

AlertModel? _activeClaim(List<AlertModel> alerts, String supervisorId) {
  final claims = alerts
      .where((a) =>
          a.status == 'en_cours' && a.superviseurId == supervisorId)
      .toList()
    ..sort((a, b) {
      final at = a.takenAtTimestamp ?? a.timestamp;
      final bt = b.takenAtTimestamp ?? b.timestamp;
      return bt.compareTo(at);
    });
  return claims.isEmpty ? null : claims.first;
}

int _alertPriority(AlertModel a) {
  if (a.isCritical && a.status != 'validee') return 50;
  return switch (a.status) {
    'disponible' => 40,
    'en_cours' => 30,
    'validee' => 20,
    _ => 0,
  };
}

LocatorNodeStatus _statusFor(AlertModel a) {
  if (a.isCritical && a.status != 'validee') return LocatorNodeStatus.critical;
  return switch (a.status) {
    'disponible' => LocatorNodeStatus.available,
    'en_cours' => LocatorNodeStatus.inProgress,
    'validee' => LocatorNodeStatus.resolved,
    _ => LocatorNodeStatus.idle,
  };
}

Color _badgeColor(LocatorNodeStatus s, AppTheme t) => switch (s) {
      LocatorNodeStatus.critical => t.red,
      LocatorNodeStatus.available => t.orange,
      LocatorNodeStatus.inProgress => t.blue,
      LocatorNodeStatus.resolved => t.green,
      LocatorNodeStatus.idle => t.mutedDk,
    };

String _typeLabel(String type) => switch (type) {
      'qualite' => 'Quality',
      'maintenance' => 'Maintenance',
      'defaut_produit' => 'Damaged product',
      'manque_ressource' => 'Resource shortage',
      _ => type,
    };
