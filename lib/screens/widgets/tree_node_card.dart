import 'package:flutter/material.dart';

import '../../theme.dart';

/// Visual density for tree nodes — controlled by user toggle in the filter bar.
enum TreeNodeDensity { compact, comfortable, detailed }

extension TreeNodeDensityX on TreeNodeDensity {
  double get iconBoxSize => switch (this) {
        TreeNodeDensity.compact => 32,
        TreeNodeDensity.comfortable => 40,
        TreeNodeDensity.detailed => 48,
      };
  double get cardWidth => switch (this) {
        TreeNodeDensity.compact => 130,
        TreeNodeDensity.comfortable => 168,
        TreeNodeDensity.detailed => 200,
      };
  double get cardHeight => switch (this) {
        TreeNodeDensity.compact => 66,
        TreeNodeDensity.comfortable => 98,
        TreeNodeDensity.detailed => 118,
      };
  double get titleSize => switch (this) {
        TreeNodeDensity.compact => 12,
        TreeNodeDensity.comfortable => 13,
        TreeNodeDensity.detailed => 14,
      };
  bool get showSubtitle =>
      this == TreeNodeDensity.comfortable || this == TreeNodeDensity.detailed;
  bool get showBadges => this != TreeNodeDensity.compact;
}

/// Modern card-style tree node used at every level (factory / conveyor /
/// workstation). Replaces the bespoke node widgets in the legacy tree.
class TreeNodeCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final int activeCount;
  final int inProgressCount;
  final int resolvedCount;
  final bool hasError;
  final bool isCritical;
  final bool isSelected;
  final bool isDimmed;
  final bool ripple; // play one-shot ripple animation
  final Color accent; // top stripe + selection ring
  final TreeNodeDensity density;
  final VoidCallback onTap;

  const TreeNodeCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.activeCount = 0,
    this.inProgressCount = 0,
    this.resolvedCount = 0,
    this.hasError = false,
    this.isCritical = false,
    this.isSelected = false,
    this.isDimmed = false,
    this.ripple = false,
    required this.accent,
    this.density = TreeNodeDensity.comfortable,
    required this.onTap,
  });

  @override
  State<TreeNodeCard> createState() => _TreeNodeCardState();
}

class _TreeNodeCardState extends State<TreeNodeCard>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _ripple;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didUpdateWidget(covariant TreeNodeCard old) {
    super.didUpdateWidget(old);
    if (widget.ripple && !old.ripple) {
      _ripple.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final d = widget.density;

    return Opacity(
      opacity: widget.isDimmed ? 0.32 : 1.0,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (widget.ripple) _buildRipple(t),
              Container(
                width: d.cardWidth,
                height: d.cardHeight,
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: widget.isSelected
                        ? widget.accent
                        : (widget.hasError
                            ? widget.accent.withValues(alpha: 0.45)
                            : t.border),
                    width: widget.isSelected ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.isSelected
                          ? widget.accent.withValues(alpha: 0.18)
                          : Colors.black
                              .withValues(alpha: context.isDark ? 0.28 : 0.05),
                      blurRadius: widget.isSelected ? 14 : 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(height: 3, color: widget.accent),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _topRow(t, d),
                          if (widget.subtitle != null && d.showSubtitle) ...[
                            const SizedBox(height: 2),
                            Padding(
                              padding: EdgeInsets.only(left: d.iconBoxSize + 8),
                              child: Text(
                                widget.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: t.muted,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                          if (d.showBadges &&
                              (widget.activeCount > 0 ||
                                  widget.inProgressCount > 0 ||
                                  widget.resolvedCount > 0)) ...[
                            const SizedBox(height: 8),
                            _badgeRow(t),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.hasError)
                Positioned(
                  top: 5,
                  right: 5,
                  child: _errorPulse(t),
                ),
              if (widget.isCritical)
                Positioned(
                  top: 5,
                  left: 5,
                  child: _criticalBadge(t),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topRow(AppTheme t, TreeNodeDensity d) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: d.iconBoxSize,
          height: d.iconBoxSize,
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(widget.icon,
              color: widget.accent, size: d.iconBoxSize * 0.5),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.text,
              fontSize: d.titleSize,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _badgeRow(AppTheme t) {
    final children = <Widget>[];
    final unclaimedCount = (widget.activeCount - widget.inProgressCount)
        .clamp(0, widget.activeCount);
    if (unclaimedCount > 0) {
      children.add(_badge(
        icon: Icons.notifications_active_outlined,
        label: '$unclaimedCount',
        color: t.red,
        bg: t.redLt,
      ));
    }
    if (widget.inProgressCount > 0) {
      children.add(_badge(
        icon: Icons.autorenew,
        label: '${widget.inProgressCount}',
        color: t.yellow,
        bg: t.yellowLt,
      ));
    }
    if (widget.density == TreeNodeDensity.detailed &&
        widget.resolvedCount > 0) {
      children.add(_badge(
        icon: Icons.verified,
        label: '${widget.resolvedCount}',
        color: t.green,
        bg: t.greenLt,
      ));
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: children,
    );
  }

  Widget _badge({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorPulse(AppTheme t) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final v = _pulse.value;
        return Container(
          width: 12 + v * 3,
          height: 12 + v * 3,
          decoration: BoxDecoration(
            color: widget.accent,
            shape: BoxShape.circle,
            border: Border.all(color: t.card, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: 0.45 + v * 0.25),
                blurRadius: 8 + v * 4,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _criticalBadge(AppTheme t) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.red,
        shape: BoxShape.circle,
        border: Border.all(color: t.card, width: 2),
      ),
      child: const Icon(
        Icons.local_fire_department,
        size: 10,
        color: Colors.white,
      ),
    );
  }

  Widget _buildRipple(AppTheme t) {
    return AnimatedBuilder(
      animation: _ripple,
      builder: (_, __) {
        final v = _ripple.value;
        if (v == 0) return const SizedBox.shrink();
        final size = widget.density.cardWidth * (1 + v * 0.6);
        return IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.accent.withValues(alpha: (1 - v).clamp(0, 1)),
                width: 3,
              ),
            ),
          ),
        );
      },
    );
  }
}
