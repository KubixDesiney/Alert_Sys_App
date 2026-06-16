part of 'admin_escalation_screen.dart';

class CollaborationsTab extends StatelessWidget {
  const CollaborationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CollaborationService();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pending section header
          Row(
            children: [
              Icon(Icons.pending_actions, color: _orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Pending Collaboration Requests',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Approve or reject collaboration requests from supervisors',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 16),

          // Pending requests stream
          StreamBuilder<List<CollaborationRequest>>(
            stream: service.getPendingCollaborationRequests(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoadingIndicator();
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 48,
                        color: _green.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No pending collaboration requests',
                        style: TextStyle(fontSize: 13, color: _muted),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: snapshot.data!
                    .map(
                      (request) => _CollaborationRequestCard(request: request),
                    )
                    .toList(),
              );
            },
          ),

          const SizedBox(height: 32),

          // History section header
          Row(
            children: [
              Icon(Icons.history, color: _navy, size: 20),
              const SizedBox(width: 8),
              Text(
                'Request History',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Recently processed collaboration requests',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 16),

          // History requests stream
          StreamBuilder<List<CollaborationRequest>>(
            stream: service.getAllCollaborationRequests(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoadingIndicator();
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  child: Text(
                    'No request history',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
                );
              }
              final history = snapshot.data!
                  .where((r) => r.status != 'pending')
                  .toList();
              if (history.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  child: Text(
                    'No request history',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
                );
              }
              return Column(
                children: history
                    .map((request) => _HistoryRequestCard(request: request))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CollaborationRequestCard extends StatefulWidget {
  final CollaborationRequest request;
  const _CollaborationRequestCard({required this.request});

  @override
  State<_CollaborationRequestCard> createState() =>
      _CollaborationRequestCardState();
}

class _CollaborationRequestCardState extends State<_CollaborationRequestCard> {
  final Set<String> _removing = {};
  bool _isApproving = false;

  Future<void> _openAddCollaborators() async {
    final added = await _AddCollaboratorsDialog.show(
      context,
      request: widget.request,
    );
    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Collaborators added to the request'),
          backgroundColor: _green,
        ),
      );
    }
  }

  Future<void> _removeAssistant(
    String assistantId,
    String assistantName,
  ) async {
    if (_removing.contains(assistantId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Assistant?'),
        content: Text('Remove @$assistantName from this collaboration?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing.add(assistantId));
    try {
      final pmName =
          FirebaseAuth.instance.currentUser?.email?.split('@').first ?? 'PM';
      await CollaborationService().removeAssistantFromRequest(
        requestId: widget.request.id,
        assistantId: assistantId,
        assistantName: assistantName,
        removedByName: pmName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFriendlyError.message(e)),
          backgroundColor: context.appTheme.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _removing.remove(assistantId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final r = widget.request;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final activeCollaboratorCount = r.targetSupervisorIds.where((id) {
      return (r.assistantDecisions[id] ?? 'pending') != 'refused';
    }).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.shield, color: _purple, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.requesterName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: t.navy,
                  ),
                ),
              ),
              Text(
                'Alert #${r.alertId.substring(0, 8)}',
                style: TextStyle(
                  fontSize: 11,
                  color: t.muted,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Pending PM',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.access_time, size: 12, color: t.muted),
              const SizedBox(width: 4),
              Text(
                _formatTime(r.timestamp),
                style: TextStyle(fontSize: 11, color: t.muted),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Assistants with optional remove buttons
          Text(
            'Requesting collaboration with:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: t.muted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...List.generate(r.targetSupervisorIds.length, (i) {
                final id = r.targetSupervisorIds[i];
                final name = r.targetSupervisorNames[i];
                final decision = r.assistantDecisions[id] ?? 'pending';
                final isRemoving = _removing.contains(id);

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: decision == 'accepted'
                        ? _green.withValues(alpha: 0.12)
                        : decision == 'refused'
                        ? _red.withValues(alpha: 0.1)
                        : _purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: decision == 'accepted'
                          ? _green.withValues(alpha: 0.4)
                          : decision == 'refused'
                          ? _red.withValues(alpha: 0.4)
                          : _purple.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        decision == 'accepted'
                            ? Icons.check_circle
                            : decision == 'refused'
                            ? Icons.cancel
                            : Icons.pending,
                        size: 13,
                        color: decision == 'accepted'
                            ? _green
                            : decision == 'refused'
                            ? _red
                            : _purple,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '@$name',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: decision == 'accepted'
                              ? _green
                              : decision == 'refused'
                              ? _red
                              : _purple,
                        ),
                      ),
                      // PM remove button — only if multiple assistants
                      if (activeCollaboratorCount > 1 &&
                          decision != 'refused') ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Remove collaborator',
                          child: GestureDetector(
                            onTap: isRemoving
                                ? null
                                : () => _removeAssistant(id, name),
                            child: isRemoving
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.red,
                                    ),
                                  )
                                : const Icon(
                                    Icons.close,
                                    size: 13,
                                    color: Colors.red,
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
              Tooltip(
                message: 'Add collaborators',
                child: InkWell(
                  onTap: _openAddCollaborators,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: t.navyLt,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: t.navy.withValues(alpha: 0.22)),
                    ),
                    child: Icon(Icons.add, size: 16, color: t.navy),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Message + description
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.scaffold,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.message, style: TextStyle(fontSize: 12, color: t.navy)),
                if (r.alertDescription?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Issue: ${r.alertDescription}',
                    style: TextStyle(
                      fontSize: 11,
                      color: t.muted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // PM Approve / Reject buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isApproving
                      ? null
                      : () => _handleApprove(context, r),
                  icon: _isApproving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle, size: 16),
                  label: Text(
                    _isApproving ? 'Approving…' : 'Approve',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await CollaborationService().rejectCollaborationRequest(
                      r.id,
                      currentUserId,
                      '',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Collaboration rejected'),
                          backgroundColor: _red,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.cancel, size: 16),
                  label: const Text(
                    'Reject',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: const BorderSide(color: _red),
                    backgroundColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleApprove(
    BuildContext context,
    CollaborationRequest request,
  ) async {
    if (_isApproving) return;
    setState(() => _isApproving = true);
    try {
      await _doHandleApprove(context, request);
    } finally {
      if (mounted) setState(() => _isApproving = false);
    }
  }

  Future<void> _doHandleApprove(
    BuildContext context,
    CollaborationRequest request,
  ) async {
    final service = CollaborationService();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final pmName =
        FirebaseAuth.instance.currentUser?.email?.split('@').first ?? 'PM';

    // Build approval plan and delegate dialogs/decisions to the service.
    final plan = await service.buildApprovalPlanForRequest(request);

    final alertSnapshot = await FirebaseDatabase.instance
        .ref('alerts/${request.alertId}')
        .get();
    final alertUsine = alertSnapshot.exists
        ? (alertSnapshot.child('usine').value as String? ?? '')
        : '';

    if (!context.mounted) return;
    final decision = await service.requestApprovalDecision(
      context: context,
      plan: plan,
      targetUsine: alertUsine,
    );
    if (decision == null) return;

    try {
      await service.approveCollaborationRequestWithDetails(
        requestId: request.id,
        approverId: currentUserId,
        approverName: pmName,
        isPMApproval: true,
        confirmTransfer: decision.confirmTransfer,
        confirmCancelOriginal: decision.confirmCancelOriginal,
        cancelExistingAlertIds: decision.cancelExistingAlertIds.isNotEmpty
            ? decision.cancelExistingAlertIds
            : null,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Collaboration approved successfully'),
            backgroundColor: _green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFriendlyError.message(e)),
            backgroundColor: _red,
          ),
        );
      }
    }
  }

  // Dialog methods moved to CollaborationService

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
  }
}

class _AddCollaboratorsDialog extends StatefulWidget {
  final CollaborationRequest request;

  const _AddCollaboratorsDialog({required this.request});

  static Future<bool?> show(
    BuildContext context, {
    required CollaborationRequest request,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (_) => _AddCollaboratorsDialog(request: request),
    );
  }

  @override
  State<_AddCollaboratorsDialog> createState() =>
      _AddCollaboratorsDialogState();
}

class _AddCollaboratorsDialogState extends State<_AddCollaboratorsDialog> {
  final CollaborationService _service = CollaborationService();
  final ShiftService _shiftService = ServiceLocator.instance.shiftService;
  final Set<String> _selectedIds = <String>{};

  List<UserModel> _supervisors = const [];
  ShiftModel? _activeShift;
  String _query = '';
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final supervisors = await AuthService().fetchSupervisors();
      final shifts = await _shiftService.fetchShiftsOnce();
      if (!mounted) return;
      setState(() {
        _supervisors = supervisors;
        _activeShift = ShiftService.activeShift(shifts, DateTime.now());
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load supervisors';
        _loading = false;
      });
    }
  }

  bool _isWorkingNow(UserModel user) {
    final active = _activeShift;
    if (active == null) return false;
    return active.supervisors.any((s) => s.id == user.id);
  }

  List<UserModel> get _filtered {
    final existing = <String>{
      widget.request.requesterId,
      ...widget.request.targetSupervisorIds,
    };
    final q = _query.trim().toLowerCase();
    final list = _supervisors.where((u) {
      if (u.role != 'supervisor' || existing.contains(u.id)) return false;
      if (q.isEmpty) return true;
      return u.fullName.toLowerCase().contains(q) ||
          u.usine.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          u.phone.toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) {
      final shiftRank = (_isWorkingNow(b) ? 1 : 0) - (_isWorkingNow(a) ? 1 : 0);
      if (shiftRank != 0) return shiftRank;
      final activeRank = (b.isActive ? 1 : 0) - (a.isActive ? 1 : 0);
      if (activeRank != 0) return activeRank;
      return a.fullName.compareTo(b.fullName);
    });
    return list;
  }

  Future<void> _toggle(UserModel user) async {
    if (_saving) return;
    if (_selectedIds.contains(user.id)) {
      setState(() => _selectedIds.remove(user.id));
      return;
    }
    if (!_isWorkingNow(user)) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => _ShiftMembershipRequiredDialog(
          user: user,
          activeShift: _activeShift,
          affectedFactory: _affectedFactory,
        ),
      );
      return;
    }
    setState(() => _selectedIds.add(user.id));
  }

  String get _affectedFactory {
    final usine = widget.request.usine?.trim();
    if (usine != null && usine.isNotEmpty) return usine;
    return 'Alert factory';
  }

  Future<String> _resolveAlertUsine() async {
    final usine = widget.request.usine?.trim();
    if (usine != null && usine.isNotEmpty) return usine;
    final snap = await FirebaseDatabase.instance
        .ref('alerts/${widget.request.alertId}')
        .get();
    if (!snap.exists) return '';
    return snap.child('usine').value as String? ?? '';
  }

  Future<void> _save() async {
    if (_selectedIds.isEmpty || _saving) return;
    final selected = _supervisors
        .where((u) => _selectedIds.contains(u.id))
        .toList();
    final ids = selected.map((u) => u.id).toList();
    final names = selected.map((u) => u.fullName).toList();
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final plan = await _service.buildApprovalPlanForSupervisorIds(
        alertId: widget.request.alertId,
        supervisorIds: ids,
        supervisorNames: names,
      );
      final targetUsine = await _resolveAlertUsine();
      if (!mounted) return;
      final decision = await _service.requestApprovalDecision(
        context: context,
        plan: plan,
        targetUsine: targetUsine,
      );
      if (decision == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      final pmName =
          FirebaseAuth.instance.currentUser?.email?.split('@').first ?? 'PM';
      await _service.addSupervisorsToRequest(
        requestId: widget.request.id,
        supervisorIds: ids,
        supervisorNames: names,
        addedByName: pmName,
        confirmCancelOriginal: decision.confirmCancelOriginal,
        cancelExistingAlertIds: decision.cancelExistingAlertIds.isEmpty
            ? null
            : decision.cancelExistingAlertIds,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = UserFriendlyError.message(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final media = MediaQuery.of(context);
    final filtered = _filtered;
    return Dialog(
      backgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: media.size.height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: t.navyLt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.navy.withValues(alpha: 0.18)),
                    ),
                    child: Icon(
                      Icons.group_add_outlined,
                      color: t.navy,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Collaborators',
                          style: TextStyle(
                            color: t.text,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select supervisors currently assigned to the active shift.',
                          style: TextStyle(color: t.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close, color: t.muted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _ActiveShiftBanner(
                    shift: _activeShift,
                    affectedFactory: _affectedFactory,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    enabled: !_saving,
                    style: TextStyle(color: t.text),
                    decoration: InputDecoration(
                      hintText: 'Search by name, factory, email, or phone',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: t.scaffold,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: t.border),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _loading
                    ? const Center(child: AppLoadingIndicator())
                    : filtered.isEmpty
                    ? _DialogEmptyState(query: _query)
                    : Container(
                        decoration: BoxDecoration(
                          color: t.scaffold,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: t.border),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: t.border.withValues(alpha: 0.72),
                          ),
                          itemBuilder: (context, index) {
                            final user = filtered[index];
                            return _CollaboratorCandidateTile(
                              user: user,
                              selected: _selectedIds.contains(user.id),
                              workingNow: _isWorkingNow(user),
                              activeShift: _activeShift,
                              affectedFactory: _affectedFactory,
                              onTap: () => _toggle(user),
                            );
                          },
                        ),
                      ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: t.redLt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.red),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: t.red, fontSize: 12),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.border)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _selectedIds.isEmpty ? t.scaffold : t.greenLt,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _selectedIds.isEmpty ? t.border : t.green,
                      ),
                    ),
                    child: Text(
                      '${_selectedIds.length} selected',
                      style: TextStyle(
                        color: _selectedIds.isEmpty ? t.muted : t.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _selectedIds.isEmpty || _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add, size: 16),
                    label: Text(_saving ? 'Adding...' : 'Add Selected'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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

class _ActiveShiftBanner extends StatelessWidget {
  final ShiftModel? shift;
  final String affectedFactory;

  const _ActiveShiftBanner({
    required this.shift,
    required this.affectedFactory,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final hasShift = shift != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasShift ? t.navyLt : t.orangeLt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasShift
              ? t.navy.withValues(alpha: 0.22)
              : t.orange.withValues(alpha: 0.36),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasShift ? Icons.schedule : Icons.warning_amber_rounded,
            color: hasShift ? t.navy : t.orange,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasShift
                  ? '${shift!.name} active now - affected factory: $affectedFactory'
                  : 'No active shift right now - collaborators must belong to the running shift.',
              style: TextStyle(
                color: hasShift ? t.navy : t.orange,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollaboratorCandidateTile extends StatelessWidget {
  final UserModel user;
  final bool selected;
  final bool workingNow;
  final ShiftModel? activeShift;
  final String affectedFactory;
  final VoidCallback onTap;

  const _CollaboratorCandidateTile({
    required this.user,
    required this.selected,
    required this.workingNow,
    required this.activeShift,
    required this.affectedFactory,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final initials = _userInitials(user);
    return InkWell(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: workingNow ? 1 : 0.62,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected ? t.green : t.navyLt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? t.green : t.navy.withValues(alpha: 0.16),
                  ),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: selected ? Colors.white : t.navy,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.fullName,
                            style: TextStyle(
                              color: t.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _SupervisorAvailabilityTag(active: user.isActive),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Supervisor - ${user.email.isEmpty ? user.phone : user.email}',
                      style: TextStyle(color: t.muted, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _TinyInfoPill(
                          icon: Icons.factory_outlined,
                          label: 'Assigned: ${user.usine}',
                          color: t.navy,
                        ),
                        _TinyInfoPill(
                          icon: Icons.crisis_alert_outlined,
                          label: 'Affected: $affectedFactory',
                          color: t.orange,
                        ),
                        _TinyInfoPill(
                          icon: workingNow
                              ? Icons.play_circle_outline
                              : Icons.lock_clock,
                          label: workingNow
                              ? 'On ${activeShift?.name ?? "active shift"}'
                              : 'Not on active shift',
                          color: workingNow ? t.green : t.red,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? t.green : t.card,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? t.green : t.border,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 17)
                    : Icon(
                        workingNow ? Icons.add : Icons.lock_outline,
                        color: workingNow ? t.navy : t.muted,
                        size: 16,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupervisorAvailabilityTag extends StatelessWidget {
  final bool active;

  const _SupervisorAvailabilityTag({required this.active});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final color = active ? t.green : t.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        active ? 'Active' : 'Absent',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TinyInfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _TinyInfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogEmptyState extends StatelessWidget {
  final String query;

  const _DialogEmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_outlined, size: 44, color: t.muted),
            const SizedBox(height: 10),
            Text(
              query.trim().isEmpty
                  ? 'No available supervisors'
                  : 'No supervisors match this search',
              style: TextStyle(
                color: t.text,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Existing collaborators and the requester are excluded.',
              style: TextStyle(color: t.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftMembershipRequiredDialog extends StatelessWidget {
  final UserModel user;
  final ShiftModel? activeShift;
  final String affectedFactory;

  const _ShiftMembershipRequiredDialog({
    required this.user,
    required this.activeShift,
    required this.affectedFactory,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final shift = activeShift;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: t.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.block_flipped, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Shift Assignment Required',
                  style: TextStyle(
                    color: t.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${user.fullName} is not working this shift',
                  style: TextStyle(
                    color: t.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Only supervisors assigned to the currently running shift can be added to this collaboration.',
              style: TextStyle(color: t.text, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.scaffold,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: shift == null
                  ? Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: t.orange,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No shift is active right now.',
                            style: TextStyle(
                              color: t.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _shiftIcon(shift.kind),
                              size: 16,
                              color: t.navy,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                shift.name,
                                style: TextStyle(
                                  color: t.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${shift.timeRangeLabel} - affected factory: $affectedFactory',
                          style: TextStyle(
                            color: t.muted,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              'Add ${user.firstName.isEmpty ? user.fullName : user.firstName} to the active shift first, then return to this request.',
              style: TextStyle(
                color: t.muted,
                fontSize: 12,
                height: 1.45,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Understood',
            style: TextStyle(color: t.navy, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  IconData _shiftIcon(ShiftKind kind) => switch (kind) {
    ShiftKind.morning => Icons.wb_sunny,
    ShiftKind.afternoon => Icons.wb_twilight,
    ShiftKind.night => Icons.nights_stay,
  };
}

String _userInitials(UserModel user) {
  final first = user.firstName.trim();
  final last = user.lastName.trim();
  final letters = [
    if (first.isNotEmpty) first[0],
    if (last.isNotEmpty) last[0],
  ].join();
  if (letters.isNotEmpty) return letters.toUpperCase();
  final name = user.fullName.trim();
  return name.isEmpty ? 'S' : name[0].toUpperCase();
}

class _HistoryRequestCard extends StatelessWidget {
  final CollaborationRequest request;

  const _HistoryRequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar / icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: request.status == 'approved' ? _greenLt : _redLt,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              request.status == 'approved' ? Icons.check_circle : Icons.cancel,
              color: request.status == 'approved' ? _green : _red,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.requesterName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Requested: ${request.targetSupervisorNames.join(", ")}',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 12, color: _muted),
                    const SizedBox(width: 4),
                    Text(
                      _formatRelativeTime(request.timestamp),
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: request.status == 'approved' ? _greenLt : _redLt,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        request.status == 'approved' ? 'Approved' : 'Rejected',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: request.status == 'approved' ? _green : _red,
                        ),
                      ),
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

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
  }
}

// ============================================================================
// SETTINGS TAB (Theme‑aware & dark‑mode creativity)
// ============================================================================
