/// Customer-facing roles for on-prem SIAS deployments (PocketBase backend).
///
/// These are DISTINCT from the internal platform `superadmin`: that account
/// belongs to the vendor's cloud console and never exists inside a customer's
/// PocketBase. On-prem, platform-level maintenance uses PocketBase's own
/// `_superusers` admin (held by the customer's IT), not a SIAS role.
enum OnPremRole {
  /// Owns the deployment: branding, user accounts, industrial connectors.
  companyOwner('company_owner'),

  /// Runs factory operations: alerts, shifts, escalation policy, hierarchy.
  productionManager('production_manager'),

  /// Handles alerts, restricted to the factories they are assigned to.
  supervisor('supervisor'),

  /// Vendor diagnostics account: disabled by default, time-boxed, read-only,
  /// every session audited. Never a shared credential — one named account per
  /// vendor engineer.
  vendorSupport('vendor_support');

  const OnPremRole(this.wire);

  /// The value stored in PocketBase `users.role`.
  final String wire;

  static OnPremRole? parse(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    for (final r in OnPremRole.values) {
      if (r.wire == v) return r;
    }
    // Compatibility: early scaffolds stored 'admin' for factory managers.
    if (v == 'admin') return OnPremRole.productionManager;
    return null;
  }
}

/// Pure, table-driven permission matrix. The PocketBase API rules in
/// `deploy/onprem/pocketbase/pb_schema.json` are the enforcement layer; this
/// class exists so the Flutter UI shows/hides capabilities consistently and so
/// the matrix itself is unit-testable (`onprem_role_policy_test.dart`).
class OnPremRolePolicy {
  const OnPremRolePolicy(this.role, {this.factories = const []});

  final OnPremRole role;

  /// Factories the user may touch. Empty means "all" for owner/PM and
  /// "none" for supervisors (fail closed).
  final List<String> factories;

  bool get canManageBranding => role == OnPremRole.companyOwner;
  bool get canManageUsers => role == OnPremRole.companyOwner;
  bool get canManageConnectors => role == OnPremRole.companyOwner;

  /// Deployment secrets (TLS keys, PocketBase admin password, worker shared
  /// secret, license keys) are NEVER stored in PocketBase and are not
  /// reachable through any SIAS role — they live in the host's `.env` /
  /// encrypted secret store, readable only by the machine operator. This
  /// getter exists so UI code can assert the invariant explicitly.
  bool get canAccessDeploymentSecrets => false;

  bool get canManageFactoryOperations =>
      role == OnPremRole.companyOwner || role == OnPremRole.productionManager;

  bool get canManageEscalationPolicy => canManageFactoryOperations;
  bool get canManageShifts => canManageFactoryOperations;

  bool get canHandleAlerts =>
      role == OnPremRole.supervisor || canManageFactoryOperations;

  /// Read-only diagnostics (health, logs) — the only thing vendor support gets.
  bool get canReadDiagnostics => true;

  bool get isReadOnly => role == OnPremRole.vendorSupport;

  /// Factory scoping: supervisors see only their assigned factories;
  /// owner/PM see everything; vendor support sees no operational alerts.
  bool canAccessFactory(String usine) {
    switch (role) {
      case OnPremRole.companyOwner:
      case OnPremRole.productionManager:
        return true;
      case OnPremRole.supervisor:
        final target = usine.trim().toLowerCase();
        return factories
            .map((f) => f.trim().toLowerCase())
            .contains(target);
      case OnPremRole.vendorSupport:
        return false;
    }
  }
}

/// Vendor-support account gate, mirrored by the PocketBase rules
/// (`vendorAccessExpiresAt > @now`). Disabled-by-default and time-limited.
class VendorAccessWindow {
  const VendorAccessWindow({this.enabled = false, this.expiresAt});

  final bool enabled;
  final DateTime? expiresAt;

  bool isActive(DateTime now) =>
      enabled && expiresAt != null && now.isBefore(expiresAt!);
}
