import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../utils/alert_meta.dart';
import 'tree_node_card.dart';

/// User-controlled filter & view state for the tree.
class TreeFilterState {
  final String search;
  final Set<String> types;
  final Set<String> statuses;
  final bool criticalOnly;
  final TreeNodeDensity density;
  final bool heatmap;

  const TreeFilterState({
    this.search = '',
    this.types = const {},
    this.statuses = const {},
    this.criticalOnly = false,
    this.density = TreeNodeDensity.comfortable,
    this.heatmap = false,
  });

  TreeFilterState copyWith({
    String? search,
    Set<String>? types,
    Set<String>? statuses,
    bool? criticalOnly,
    TreeNodeDensity? density,
    bool? heatmap,
  }) =>
      TreeFilterState(
        search: search ?? this.search,
        types: types ?? this.types,
        statuses: statuses ?? this.statuses,
        criticalOnly: criticalOnly ?? this.criticalOnly,
        density: density ?? this.density,
        heatmap: heatmap ?? this.heatmap,
      );

  bool get hasFilters =>
      search.isNotEmpty ||
      types.isNotEmpty ||
      statuses.isNotEmpty ||
      criticalOnly;

  int get filterCount =>
      (search.isNotEmpty ? 1 : 0) +
      types.length +
      statuses.length +
      (criticalOnly ? 1 : 0);
}

class TreeFilterBar extends StatefulWidget {
  final TreeFilterState state;
  final ValueChanged<TreeFilterState> onChanged;

  const TreeFilterBar({
    super.key,
    required this.state,
    required this.onChanged,
  });

  @override
  State<TreeFilterBar> createState() => _TreeFilterBarState();
}

class _TreeFilterBarState extends State<TreeFilterBar> {
  late final TextEditingController _searchCtrl =
      TextEditingController(text: widget.state.search);
  bool _expanded = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TreeFilterBar old) {
    super.didUpdateWidget(old);
    if (widget.state.search != _searchCtrl.text) {
      _searchCtrl.text = widget.state.search;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _searchField(t)),
              const SizedBox(width: 8),
              _viewToggle(t),
              const SizedBox(width: 8),
              _expandButton(t),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _filtersPanel(t),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _searchField(AppTheme t) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) =>
            widget.onChanged(widget.state.copyWith(search: v.trim())),
        style: TextStyle(color: t.text, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          prefixIcon: Icon(Icons.search, size: 18, color: t.muted),
          suffixIcon: widget.state.search.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, size: 16, color: t.muted),
                  onPressed: () {
                    _searchCtrl.clear();
                    widget.onChanged(widget.state.copyWith(search: ''));
                  },
                )
              : null,
          hintText: 'Search factory, conveyor, station…',
          hintStyle: TextStyle(color: t.muted, fontSize: 13),
          filled: true,
          fillColor: t.scaffold,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.navy, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _viewToggle(AppTheme t) {
    return Container(
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewOption(
            t,
            icon: Icons.account_tree,
            tooltip: 'Tree view',
            selected: !widget.state.heatmap,
            onTap: () =>
                widget.onChanged(widget.state.copyWith(heatmap: false)),
          ),
          _viewOption(
            t,
            icon: Icons.grid_view_rounded,
            tooltip: 'Heatmap view',
            selected: widget.state.heatmap,
            onTap: () =>
                widget.onChanged(widget.state.copyWith(heatmap: true)),
          ),
        ],
      ),
    );
  }

  Widget _viewOption(
    AppTheme t, {
    required IconData icon,
    required String tooltip,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? t.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: selected ? Colors.white : t.muted,
          ),
        ),
      ),
    );
  }

  Widget _expandButton(AppTheme t) {
    final count = widget.state.filterCount;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _expanded || count > 0 ? t.navyLt : t.scaffold,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _expanded || count > 0 ? t.navy : t.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 16, color: t.navy),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: t.navy,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filtersPanel(AppTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(t, 'Type'),
        const SizedBox(height: 4),
        _typeChips(t),
        const SizedBox(height: 10),
        _label(t, 'Status'),
        const SizedBox(height: 4),
        _statusChips(t),
        const SizedBox(height: 10),
        Row(
          children: [
            _criticalToggle(t),
            const SizedBox(width: 8),
            _densityToggle(t),
            const Spacer(),
            if (widget.state.hasFilters)
              TextButton.icon(
                onPressed: () =>
                    widget.onChanged(const TreeFilterState()),
                icon: Icon(Icons.clear_all, size: 14, color: t.muted),
                label: Text('Clear',
                    style: TextStyle(color: t.muted, fontSize: 12)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _label(AppTheme t, String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: t.muted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      );

  Widget _typeChips(AppTheme t) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: kAllAlertTypes.map((type) {
        final m = typeMeta(type, t);
        final on = widget.state.types.contains(type);
        return _filterChip(
          icon: m.icon,
          label: m.label,
          color: m.color,
          bg: m.bg,
          selected: on,
          onTap: () {
            final next = Set<String>.from(widget.state.types);
            on ? next.remove(type) : next.add(type);
            widget.onChanged(widget.state.copyWith(types: next));
          },
        );
      }).toList(),
    );
  }

  Widget _statusChips(AppTheme t) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: kAllAlertStatuses.map((status) {
        final m = statusMeta(status, t);
        final on = widget.state.statuses.contains(status);
        return _filterChip(
          icon: m.icon,
          label: m.label,
          color: m.color,
          bg: m.bg,
          selected: on,
          onTap: () {
            final next = Set<String>.from(widget.state.statuses);
            on ? next.remove(status) : next.add(status);
            widget.onChanged(widget.state.copyWith(statuses: next));
          },
        );
      }).toList(),
    );
  }

  Widget _filterChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: color.withValues(alpha: selected ? 1 : 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 12, color: selected ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : color,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _criticalToggle(AppTheme t) {
    final on = widget.state.criticalOnly;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () =>
          widget.onChanged(widget.state.copyWith(criticalOnly: !on)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? t.red : t.scaffold,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? t.red : t.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department,
                size: 12, color: on ? Colors.white : t.red),
            const SizedBox(width: 4),
            Text(
              'Critical only',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : t.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _densityToggle(AppTheme t) {
    return Container(
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: TreeNodeDensity.values.map((d) {
          final selected = widget.state.density == d;
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () =>
                widget.onChanged(widget.state.copyWith(density: d)),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? t.navy : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                _densityIcon(d),
                size: 14,
                color: selected ? Colors.white : t.muted,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _densityIcon(TreeNodeDensity d) => switch (d) {
        TreeNodeDensity.compact => Icons.density_small,
        TreeNodeDensity.comfortable => Icons.density_medium,
        TreeNodeDensity.detailed => Icons.density_large,
      };
}
