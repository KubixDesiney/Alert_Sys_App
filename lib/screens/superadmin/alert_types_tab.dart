import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/alert_type.dart';
import '../../services/alert_type_registry.dart';
import '../../services/forecast/forecast_model_store.dart';
import 'superadmin_theme.dart';

/// SuperAdmin tab: manage the deployment's configurable alert-type vocabulary.
///
/// CRUD + reorder over `app_config/alertTypes`. Changing the set invalidates a
/// trained forecaster (its per-type ensembles no longer match), so this tab
/// surfaces a stale-model banner and prompts a retrain whenever the deployed
/// model's type list drifts from the configured set.
class AlertTypesTab extends StatefulWidget {
  const AlertTypesTab({super.key});

  @override
  State<AlertTypesTab> createState() => _AlertTypesTabState();
}

class _AlertTypesTabState extends State<AlertTypesTab> {
  final _store = ForecastModelStore();
  StreamSubscription? _modelSub;

  List<AlertTypeDef> _working = [];
  bool _dirty = false;
  bool _saving = false;
  String? _message;

  List<String>? _deployedTypes; // null = no model deployed

  @override
  void initState() {
    super.initState();
    _working = AlertTypeRegistry.instance.types
        .map((d) => d.copyWith())
        .toList();
    AlertTypeRegistry.instance.addListener(_onRegistry);
    _modelSub = _store.modelStream().listen((m) {
      if (mounted) setState(() => _deployedTypes = m?.types);
    }, onError: (_) {});
  }

  void _onRegistry() {
    // Keep the working copy in sync while there are no local edits.
    if (_dirty || !mounted) return;
    setState(() {
      _working =
          AlertTypeRegistry.instance.types.map((d) => d.copyWith()).toList();
    });
  }

  @override
  void dispose() {
    AlertTypeRegistry.instance.removeListener(_onRegistry);
    _modelSub?.cancel();
    super.dispose();
  }

  List<String> get _workingCodes => [for (final d in _working) d.code];

  /// The deployed model is stale when its learned types differ from the saved
  /// registry (not the unsaved working copy).
  bool get _modelStale {
    final deployed = _deployedTypes;
    if (deployed == null) return false;
    final saved = AlertTypeRegistry.instance.codes;
    if (deployed.length != saved.length) return true;
    for (var i = 0; i < deployed.length; i++) {
      if (deployed[i] != saved[i]) return true;
    }
    return false;
  }

  void _markDirty() => setState(() {
        _dirty = true;
        _message = null;
      });

  Future<void> _save() async {
    if (_saving) return;
    if (_working.isEmpty) {
      setState(() => _message = context.tr(
          'Keep at least one alert type — the app and forecaster need one.'));
      return;
    }
    // Re-number order to match the current arrangement.
    for (var i = 0; i < _working.length; i++) {
      _working[i] = _working[i].copyWith(order: i);
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await AlertTypeRegistry.instance.saveAll(_working);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _message = context.tr('Alert types saved.');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = context.tr('Save failed: {error}', {'error': '$e'});
      });
    }
  }

  void _revert() {
    setState(() {
      _working =
          AlertTypeRegistry.instance.types.map((d) => d.copyWith()).toList();
      _dirty = false;
      _message = null;
    });
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _working.length) return;
    final item = _working.removeAt(index);
    _working.insert(target, item);
    _markDirty();
  }

  void _delete(int index) {
    _working.removeAt(index);
    _markDirty();
  }

  Future<void> _edit({int? index}) async {
    final existing = index == null ? null : _working[index];
    final result = await showDialog<AlertTypeDef>(
      context: context,
      builder: (_) => _AlertTypeEditorDialog(
        existing: existing,
        existingCodes: _workingCodes,
      ),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _working.add(result.copyWith(order: _working.length));
      } else {
        _working[index] = result;
      }
      _dirty = true;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassPanel(
            accent: Sa.violet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: Icons.label_outline,
                  accent: Sa.violet,
                  title: context.tr('Alert Types'),
                  subtitle: context.tr(
                      'Define this deployment’s alert-type vocabulary — '
                      'labels, colours, icons, parser synonyms and default '
                      'severity. Everything (alerts, filters, the AI forecaster) '
                      'adapts to this set.'),
                  trailing: SaButton(
                    label: context.tr('Add type'),
                    icon: Icons.add,
                    color: Sa.violet,
                    onPressed: () => _edit(),
                  ),
                ),
                if (_modelStale) ...[
                  const SizedBox(height: 14),
                  _StaleBanner(),
                ],
                if (_dirty) ...[
                  const SizedBox(height: 14),
                  _DirtyBanner(),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, style: Sa.body(size: 12, color: Sa.textDim)),
                ],
                const SizedBox(height: 16),
                ..._working.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TypeRow(
                        def: e.value,
                        first: e.key == 0,
                        last: e.key == _working.length - 1,
                        onUp: () => _move(e.key, -1),
                        onDown: () => _move(e.key, 1),
                        onEdit: () => _edit(index: e.key),
                        onDelete: _working.length <= 1
                            ? null
                            : () => _delete(e.key),
                      ),
                    )),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SaButton(
                      label: context.tr('Save changes'),
                      icon: Icons.save_outlined,
                      color: Sa.green,
                      busy: _saving,
                      onPressed: _dirty ? _save : null,
                    ),
                    const SizedBox(width: 10),
                    SaButton(
                      label: context.tr('Revert'),
                      icon: Icons.undo,
                      outlined: true,
                      onPressed: _dirty ? _revert : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Sa.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.amber.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Sa.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(
                  'The deployed forecaster was trained on a different alert-type '
                  'set. It is running in fallback mode (statistical model) and '
                  'won’t forecast the new types until you retrain it in the '
                  'AI Training tab.'),
              style: Sa.body(size: 12, color: Sa.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirtyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Sa.cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.cyan.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Sa.cyan, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(
                  'Unsaved changes. Save to apply across the app, then retrain '
                  'the forecaster so it learns the updated type set.'),
              style: Sa.body(size: 12, color: Sa.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  final AlertTypeDef def;
  final bool first;
  final bool last;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _TypeRow({
    required this.def,
    required this.first,
    required this.last,
    required this.onUp,
    required this.onDown,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = def.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Sa.bgRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.55)),
            ),
            child: Icon(alertTypeIcon(def.icon), color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(def.label), style: Sa.heading(size: 13.5)),
                const SizedBox(height: 2),
                Text(def.code, style: Sa.mono(size: 10.5, color: Sa.muted)),
              ],
            ),
          ),
          if (def.criticalByDefault)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GlowChip(
                label: context.tr('CRITICAL'),
                color: Sa.red,
              ),
            ),
          if (def.synonyms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                context.tr('{n} synonyms', {'n': '${def.synonyms.length}'}),
                style: Sa.mono(size: 10, color: Sa.textDim),
              ),
            ),
          _IconBtn(icon: Icons.arrow_upward, onTap: first ? null : onUp),
          _IconBtn(icon: Icons.arrow_downward, onTap: last ? null : onDown),
          _IconBtn(icon: Icons.edit_outlined, onTap: onEdit, color: Sa.cyan),
          _IconBtn(
              icon: Icons.delete_outline, onTap: onDelete, color: Sa.red),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  const _IconBtn({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = onTap == null ? Sa.muted.withValues(alpha: 0.4) : (color ?? Sa.textDim);
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: c),
      splashRadius: 18,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
    );
  }
}

/// Add/edit dialog for a single alert type.
class _AlertTypeEditorDialog extends StatefulWidget {
  final AlertTypeDef? existing;
  final List<String> existingCodes;
  const _AlertTypeEditorDialog({
    required this.existing,
    required this.existingCodes,
  });

  @override
  State<_AlertTypeEditorDialog> createState() => _AlertTypeEditorDialogState();
}

class _AlertTypeEditorDialogState extends State<_AlertTypeEditorDialog> {
  late final TextEditingController _code;
  late final TextEditingController _label;
  late final TextEditingController _synonyms;
  late String _icon;
  late String _colorHex;
  late bool _critical;
  String? _error;

  static const _palette = [
    '#DC2626', '#EA580C', '#D97706', '#FBBF24', '#16A34A', '#059669',
    '#0891B2', '#2563EB', '#4F46E5', '#7C3AED', '#DB2777', '#64748B',
  ];

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _code = TextEditingController(text: e?.code ?? '');
    _label = TextEditingController(text: e?.label ?? '');
    _synonyms = TextEditingController(text: e?.synonyms.join(', ') ?? '');
    _icon = e?.icon ?? 'warning';
    _colorHex = e?.colorHex ?? _palette.first;
    _critical = e?.criticalByDefault ?? false;
  }

  @override
  void dispose() {
    _code.dispose();
    _label.dispose();
    _synonyms.dispose();
    super.dispose();
  }

  String _slug(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  void _submit() {
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = context.tr('Enter a label.'));
      return;
    }
    final code = _isNew
        ? _slug(_code.text.isEmpty ? label : _code.text)
        : widget.existing!.code;
    if (code.isEmpty) {
      setState(() => _error = context.tr('Enter a valid code.'));
      return;
    }
    if (_isNew && widget.existingCodes.contains(code)) {
      setState(() => _error =
          context.tr('The code "{code}" already exists.', {'code': code}));
      return;
    }
    final syn = _synonyms.text
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
    Navigator.pop(
      context,
      AlertTypeDef(
        code: code,
        label: label,
        colorHex: _colorHex,
        icon: _icon,
        synonyms: syn,
        severityDefault: _critical ? 'critical' : 'normal',
        order: widget.existing?.order ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: GlassPanel(
          accent: Sa.violet,
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isNew
                      ? context.tr('New alert type')
                      : context.tr('Edit alert type'),
                  style: Sa.display(size: 17),
                ),
                const SizedBox(height: 16),
                SaTextField(
                  controller: _label,
                  label: context.tr('Label'),
                  hint: context.tr('e.g. Overheating'),
                ),
                const SizedBox(height: 12),
                SaTextField(
                  controller: _code,
                  label: _isNew
                      ? context.tr('Code (identifier)')
                      : context.tr('Code (locked)'),
                  hint: 'overheating',
                ),
                if (!_isNew)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.tr(
                          'The code is locked after creation so existing alerts '
                          'and the trained model keep matching.'),
                      style: Sa.body(size: 10.5, color: Sa.muted),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(context.tr('Colour'),
                    style: Sa.heading(size: 12, color: Sa.textDim)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final hex in _palette)
                      GestureDetector(
                        onTap: () => setState(() => _colorHex = hex),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: parseHexColor(hex),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _colorHex == hex ? Sa.text : Sa.border,
                              width: _colorHex == hex ? 2.5 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(context.tr('Icon'),
                    style: Sa.heading(size: 12, color: Sa.textDim)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final key in kAlertTypeIconKeys)
                      GestureDetector(
                        onTap: () => setState(() => _icon = key),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _icon == key
                                ? parseHexColor(_colorHex).withValues(alpha: 0.18)
                                : Sa.bgRaised,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: _icon == key
                                  ? parseHexColor(_colorHex)
                                  : Sa.border,
                              width: _icon == key ? 2 : 1,
                            ),
                          ),
                          child: Icon(alertTypeIcon(key),
                              size: 18,
                              color: _icon == key
                                  ? parseHexColor(_colorHex)
                                  : Sa.textDim),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SaTextField(
                  controller: _synonyms,
                  label: context.tr('Parser synonyms (comma-separated)'),
                  hint: context.tr('overheat, temperature, hot'),
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr(
                      'Substrings used to map free-text types (uploaded '
                      'history, SCADA payloads) onto this type.'),
                  style: Sa.body(size: 10.5, color: Sa.muted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Switch(
                      value: _critical,
                      activeThumbColor: Sa.red,
                      onChanged: (v) => setState(() => _critical = v),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.tr('New alerts of this type default to critical'),
                        style: Sa.body(size: 12, color: Sa.text),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: Sa.body(size: 12, color: Sa.red)),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SaButton(
                      label: context.tr('Cancel'),
                      icon: Icons.close,
                      outlined: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                    SaButton(
                      label: context.tr('Done'),
                      icon: Icons.check,
                      color: Sa.violet,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
