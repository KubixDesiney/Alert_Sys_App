import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../firebase_options.dart';
import '../../services/sso_config_service.dart';
import '../mfa_enrollment_screen.dart';
import 'superadmin_theme.dart';

/// SuperAdmin → Access & Identity.
///
/// Lets the company's IT team turn on Single Sign-On against their own identity
/// provider (Microsoft Entra, Google Workspace, Okta, Keycloak, or any custom
/// OIDC/SAML) without a rebuild. The runtime config is stored at
/// `auth_config/sso` and the login screen reads it live.
class AccessIdentityTab extends StatefulWidget {
  const AccessIdentityTab({super.key});

  @override
  State<AccessIdentityTab> createState() => _AccessIdentityTabState();
}

class _Template {
  final String key, name, type, providerId, issuer, label;
  const _Template(
    this.key,
    this.name,
    this.type,
    this.providerId,
    this.issuer,
    this.label,
  );
}

const _templates = <_Template>[
  _Template('entra', 'Microsoft Entra ID (Azure AD)', 'oidc', 'oidc.entra',
      'https://login.microsoftonline.com/<tenant-id>/v2.0',
      'Sign in with Microsoft'),
  _Template('google', 'Google Workspace', 'oidc', 'oidc.google',
      'https://accounts.google.com', 'Sign in with Google'),
  _Template('okta', 'Okta', 'oidc', 'oidc.okta',
      'https://<your-domain>.okta.com', 'Sign in with Okta'),
  _Template('keycloak', 'Keycloak', 'oidc', 'oidc.keycloak',
      'https://<host>/realms/<realm>', 'Sign in with Keycloak'),
  _Template('custom_oidc', 'Custom OpenID Connect', 'oidc', 'oidc.',
      '', 'Sign in with SSO'),
  _Template('custom_saml', 'Custom SAML', 'saml', 'saml.', '',
      'Sign in with SSO'),
];

class _AccessIdentityTabState extends State<AccessIdentityTab> {
  final _service = SsoConfigService();
  final _providerId = TextEditingController();
  final _label = TextEditingController();
  final _issuer = TextEditingController();

  String _template = 'entra';
  String _type = 'oidc';
  bool _enabled = false;
  bool _loaded = false;
  bool _saving = false;
  String? _status;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _service.load().then((c) {
      if (!mounted) return;
      setState(() {
        _enabled = c.enabled;
        _type = c.type;
        _template = c.template.isEmpty ? 'entra' : c.template;
        _providerId.text = c.providerId;
        _label.text = c.label;
        _issuer.text = c.issuer;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _providerId.dispose();
    _label.dispose();
    _issuer.dispose();
    super.dispose();
  }

  String get _redirectUri {
    final pid = DefaultFirebaseOptions.currentPlatform.projectId;
    return 'https://$pid.firebaseapp.com/__/auth/handler';
  }

  void _applyTemplate(String key) {
    final t = _templates.firstWhere((e) => e.key == key,
        orElse: () => _templates.last);
    setState(() {
      _template = key;
      _type = t.type;
      _providerId.text = t.providerId;
      _issuer.text = t.issuer;
      _label.text = t.label;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _status = null;
    });
    final pid = _providerId.text.trim();
    if (_enabled && (pid.isEmpty || (!pid.startsWith('oidc.') && !pid.startsWith('saml.')))) {
      setState(() {
        _saving = false;
        _ok = false;
        _status = 'Provider ID must look like "oidc.name" or "saml.name".';
      });
      return;
    }
    final cfg = SsoConfig(
      enabled: _enabled,
      type: _type,
      providerId: pid,
      label: _label.text.trim().isEmpty ? 'Sign in with SSO' : _label.text.trim(),
      issuer: _issuer.text.trim(),
      template: _template,
    );
    try {
      await _service.save(cfg);
      if (mounted) {
        setState(() {
          _saving = false;
          _ok = true;
          _status = 'Saved. The login screen now reflects this.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _ok = false;
          _status = 'Save failed: $e';
        });
      }
    }
  }

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what copied'), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Center(child: CircularProgressIndicator(color: Sa.cyan));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassPanel(
              accent: Sa.violet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SaSectionHeader(
                    icon: Icons.vpn_key_outlined,
                    title: 'Single Sign-On',
                    subtitle:
                        'Let staff sign in with your company identity provider',
                    accent: Sa.violet,
                    trailing: GlowChip(
                      label: _enabled ? 'ENABLED' : 'DISABLED',
                      color: _enabled ? Sa.green : Sa.muted,
                      pulse: _enabled,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _enableRow(),
                  const SizedBox(height: 18),
                  Text('IDENTITY PROVIDER', style: Sa.mono(size: 10, color: Sa.muted)),
                  const SizedBox(height: 6),
                  _dropdown(),
                  const SizedBox(height: 16),
                  _field('PROVIDER ID', _providerId,
                      hint: 'oidc.sias',
                      help: 'Must match the provider you create in Firebase.'),
                  _field('BUTTON LABEL', _label, hint: 'Sign in with SIAS'),
                  _field('ISSUER URL (reference)', _issuer,
                      hint: 'https://login.microsoftonline.com/<tenant>/v2.0'),
                  const SizedBox(height: 4),
                  _saveButton(),
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    Text(_status!,
                        style: Sa.body(
                            size: 12, color: _ok ? Sa.green : Sa.red)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _activationPanel(),
            const SizedBox(height: 16),
            _previewPanel(),
            const SizedBox(height: 16),
            _mfaPanel(),
          ],
        ),
      ),
    );
  }

  Widget _enableRow() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enable SSO', style: Sa.heading(size: 14)),
              const SizedBox(height: 2),
              Text('Shows the SSO button on the login screen',
                  style: Sa.body(size: 12, color: Sa.muted)),
            ],
          ),
        ),
        Switch(
          value: _enabled,
          activeColor: Sa.cyan,
          onChanged: (v) => setState(() => _enabled = v),
        ),
      ],
    );
  }

  Widget _dropdown() {
    return DropdownButtonFormField<String>(
      value: _template,
      dropdownColor: Sa.panelSolid,
      isExpanded: true,
      style: Sa.body(size: 13, color: Sa.text),
      icon: Icon(Icons.expand_more, color: Sa.muted),
      decoration: _inputDecoration(),
      items: _templates
          .map((t) => DropdownMenuItem(
                value: t.key,
                child: Text(t.name, style: Sa.body(size: 13, color: Sa.text)),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) _applyTemplate(v);
      },
    );
  }

  Widget _field(String label, TextEditingController c,
      {String? hint, String? help}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Sa.mono(size: 10, color: Sa.muted)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          style: Sa.body(size: 13, color: Sa.text),
          decoration: _inputDecoration(hint: hint),
        ),
        if (help != null) ...[
          const SizedBox(height: 5),
          Text(help, style: Sa.body(size: 11, color: Sa.muted)),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: Sa.body(size: 12, color: Sa.muted),
      filled: true,
      fillColor: Sa.bgRaised,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Sa.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Sa.cyan),
      ),
    );
  }

  Widget _saveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.save_outlined, size: 18),
        label: Text(_saving ? 'Saving…' : 'Save configuration'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Sa.cyan,
          foregroundColor: Sa.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _activationPanel() {
    return GlassPanel(
      accent: Sa.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.cloud_done_outlined,
            title: 'Finish in Firebase Identity Platform',
            subtitle: 'One-time, server-side — it holds the client secret safely',
            accent: Sa.amber,
          ),
          const SizedBox(height: 16),
          Text(
            'In the Firebase console → Authentication, enable Identity Platform, '
            'then add a provider whose ID matches the Provider ID above. Paste in '
            'the client ID, issuer, and client secret from your identity provider, '
            'and register this redirect URL:',
            style: Sa.body(size: 12.5, color: Sa.textDim),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: Sa.bgRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Sa.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(_redirectUri,
                      style: Sa.mono(size: 11.5, color: Sa.cyan)),
                ),
                IconButton(
                  icon: Icon(Icons.copy, size: 16, color: Sa.muted),
                  tooltip: 'Copy redirect URL',
                  onPressed: () => _copy(_redirectUri, 'Redirect URL'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'New SSO users are created with no role — grant access from Production '
            'Managers before they can sign in.',
            style: Sa.body(size: 11.5, color: Sa.muted),
          ),
        ],
      ),
    );
  }

  Widget _previewPanel() {
    final label = _label.text.trim().isEmpty ? 'Sign in with SSO' : _label.text.trim();
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LOGIN PREVIEW', style: Sa.mono(size: 10, color: Sa.muted)),
          const SizedBox(height: 12),
          Opacity(
            opacity: _enabled ? 1 : 0.4,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Sa.borderBright),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.business, size: 18, color: Sa.text),
                  const SizedBox(width: 10),
                  Text(label, style: Sa.heading(size: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _enabled
                ? 'Staff will see this button beneath the email/password fields.'
                : 'Hidden until you enable SSO above.',
            style: Sa.body(size: 11.5, color: Sa.muted),
          ),
        ],
      ),
    );
  }

  Widget _mfaPanel() {
    return GlassPanel(
      accent: Sa.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.sms_outlined,
            title: 'Two-factor authentication (SMS)',
            subtitle: 'Add a phone second factor to your own account',
            accent: Sa.green,
          ),
          const SizedBox(height: 14),
          Text(
            'Enable SMS multi-factor in Firebase Identity Platform, then enrol '
            'your phone here. Staff enrol the same way from their profile.',
            style: Sa.body(size: 12.5, color: Sa.textDim),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MfaEnrollmentScreen(),
                ),
              ),
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: const Text('Set up / manage 2FA'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Sa.green,
                side: BorderSide(color: Sa.green.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
