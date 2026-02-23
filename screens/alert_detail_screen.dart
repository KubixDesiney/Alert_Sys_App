import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/alert_model.dart';
import '../providers/alert_provider.dart';

class AlertDetailScreen extends StatefulWidget {
  final AlertModel alert;
  const AlertDetailScreen({super.key, required this.alert});

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  final _commentController = TextEditingController();
  final _resolveController = TextEditingController();

  static const accent = Color(0xFFE85D26);
  static const surface = Color(0xFF161920);
  static const card = Color(0xFF1C2130);
  static const border = Color(0xFF252D3D);
  static const muted = Color(0xFF6B7A96);
  static const danger = Color(0xFFEF4444);
  static const success = Color(0xFF22C55E);

  Color get _sevColor => switch (widget.alert.severity) {
    'critical' => danger, 'high' => accent,
    'medium' => Colors.amber, _ => Colors.blue,
  };

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AlertProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: border)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.alert.id,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: muted)),
          Text('${widget.alert.type} — ${widget.alert.machine}',
            style: const TextStyle(fontFamily: 'Barlow Condensed',
                fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Severity banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _sevColor.withOpacity(0.1),
              border: Border.all(color: _sevColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.alert.message,
                style: TextStyle(fontFamily: 'Barlow Condensed',
                    fontSize: 20, fontWeight: FontWeight.w800, color: _sevColor)),
              const SizedBox(height: 4),
              Text('${widget.alert.plant} · ${widget.alert.sector}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: muted)),
            ]),
          ),
          const SizedBox(height: 16),

          // Metadata grid
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.5,
            children: [
              _metaCard('Machine', widget.alert.machine),
              _metaCard('Usine', widget.alert.plant),
              _metaCard('Valeur', widget.alert.value ?? '-'),
              _metaCard('Seuil', widget.alert.threshold ?? '-'),
            ],
          ),
          const SizedBox(height: 16),

          // Recommended action
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.08),
              border: Border.all(color: Colors.blue),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('💡 ACTION RECOMMANDÉE',
                style: TextStyle(fontSize: 10, color: Colors.blue,
                    fontWeight: FontWeight.w700, letterSpacing: 2)),
              const SizedBox(height: 8),
              Text(widget.alert.recommendedAction,
                style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 20),

          // Action buttons (only if not resolved)
          if (widget.alert.status != 'resolved') ...[
            const Text('ACTIONS', style: TextStyle(fontSize: 10, color: muted,
                fontWeight: FontWeight.w700, letterSpacing: 2)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              if (!widget.alert.acknowledged)
                _actionBtn('✋ Prendre en Charge', Colors.amber, () async {
                  await provider.acknowledge(widget.alert.id, 'superviseur');
                  _showSnack('Alerte prise en charge ✋');
                }),
              _actionBtn('✅ Résoudre', success, () => _showResolveSheet(provider)),
              if (!widget.alert.escalated)
                _actionBtn('⬆️ Escalader', danger, () => _showEscalateSheet(provider)),
              _actionBtn('🔗 Se Détacher', muted, () async {
                await provider.detach(widget.alert.id);
                _showSnack('Détaché de l\'alerte');
              }),
            ]),
            const SizedBox(height: 20),
          ],

          // Status badges
          if (widget.alert.acknowledged)
            _statusBadge('✓ Pris en charge par ${widget.alert.acknowledgedBy}', Colors.amber),
          if (widget.alert.escalated)
            _statusBadge('⬆️ Escaladé → ${widget.alert.escalatedTo}', Colors.blue),
          if (widget.alert.status == 'resolved')
            _statusBadge('✅ Résolu', success),
          if (widget.alert.resolvedNote != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: success.withOpacity(0.08),
                border: Border.all(color: success),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('NOTE DE RÉSOLUTION',
                  style: TextStyle(fontSize: 10, color: success, fontWeight: FontWeight.w700, letterSpacing: 2)),
                const SizedBox(height: 6),
                Text(widget.alert.resolvedNote!, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ]),
            ),
          ],
          const SizedBox(height: 20),

          // Comment log
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: card, border: Border.all(color: border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('💬 JOURNAL D\'ACTIONS',
                style: TextStyle(fontFamily: 'Barlow Condensed',
                    fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (widget.alert.comments.isEmpty)
                const Text('Aucun commentaire.', style: TextStyle(color: muted, fontStyle: FontStyle.italic)),
              ...widget.alert.comments.map((c) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: surface,
                  border: Border(left: BorderSide(color: border, width: 2)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(c, style: const TextStyle(fontSize: 13, color: Colors.white)),
              )),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Ajouter une note…',
                      hintStyle: const TextStyle(color: muted),
                      filled: true, fillColor: surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: accent)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (_commentController.text.trim().isEmpty) return;
                    await provider.addComment(widget.alert.id, _commentController.text.trim());
                    _commentController.clear();
                    _showSnack('Note ajoutée');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF252D3D),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  ),
                  child: const Text('Envoyer', style: TextStyle(fontSize: 13)),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _metaCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: card, border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 9, color: muted,
            fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white)),
      ]),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'Barlow Condensed',
            fontSize: 14, fontWeight: FontWeight.w700, color: color, letterSpacing: 1)),
      ),
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF22C55E)));
  }

  void _showResolveSheet(AlertProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161920),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('✅ Marquer comme Résolu',
            style: TextStyle(fontFamily: 'Barlow Condensed',
                fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 16),
          TextField(
            controller: _resolveController,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Note de résolution (facultatif)…',
              hintStyle: const TextStyle(color: muted),
              filled: true, fillColor: const Color(0xFF0D0F14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: border)),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () async {
                  await provider.resolve(widget.alert.id, _resolveController.text.trim());
                  if (mounted) {
                    Navigator.pop(context); // close sheet
                    Navigator.pop(context); // go back to list
                    _showSnack('Alerte résolue ✅');
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: success),
                child: const Text('Confirmer'),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler', style: TextStyle(color: muted)),
            ),
          ]),
        ]),
      ),
    );
  }

  void _showEscalateSheet(AlertProvider provider) {
    String selectedTarget = 'Admin';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161920),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('⬆️ Escalader l\'Alerte',
              style: TextStyle(fontFamily: 'Barlow Condensed',
                  fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedTarget,
              dropdownColor: const Color(0xFF1C2130),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Escalader vers',
                labelStyle: const TextStyle(color: muted),
                filled: true, fillColor: const Color(0xFF0D0F14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: border)),
              ),
              items: ['Admin', 'Directeur Usine', 'Superviseur Senior', 'Responsable Maintenance']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setSheetState(() => selectedTarget = v!),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: danger.withOpacity(0.08), border: Border.all(color: danger),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '⚠️ Une notification sera envoyée à $selectedTarget.',
                style: const TextStyle(color: danger, fontSize: 13)),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    await provider.escalate(widget.alert.id, selectedTarget);
                    if (mounted) {
                      Navigator.pop(context);
                      _showSnack('Alerte escaladée ⬆️');
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: danger),
                  child: const Text('Confirmer'),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler', style: TextStyle(color: muted)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}