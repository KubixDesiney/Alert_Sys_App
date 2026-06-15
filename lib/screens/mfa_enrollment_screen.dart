import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/enterprise_auth_service.dart';

/// A country option for the phone-number picker.
class _Country {
  final String name;
  final String iso;
  final String dial;
  const _Country(this.name, this.iso, this.dial);
}

const _countries = <_Country>[
  _Country('Tunisia', 'TN', '216'),
  _Country('Algeria', 'DZ', '213'),
  _Country('Morocco', 'MA', '212'),
  _Country('Libya', 'LY', '218'),
  _Country('Egypt', 'EG', '20'),
  _Country('Mauritania', 'MR', '222'),
  _Country('France', 'FR', '33'),
  _Country('Germany', 'DE', '49'),
  _Country('Spain', 'ES', '34'),
  _Country('Italy', 'IT', '39'),
  _Country('United Kingdom', 'GB', '44'),
  _Country('Netherlands', 'NL', '31'),
  _Country('Belgium', 'BE', '32'),
  _Country('Switzerland', 'CH', '41'),
  _Country('Portugal', 'PT', '351'),
  _Country('Ireland', 'IE', '353'),
  _Country('Austria', 'AT', '43'),
  _Country('Sweden', 'SE', '46'),
  _Country('Norway', 'NO', '47'),
  _Country('Denmark', 'DK', '45'),
  _Country('Finland', 'FI', '358'),
  _Country('Poland', 'PL', '48'),
  _Country('Greece', 'GR', '30'),
  _Country('Romania', 'RO', '40'),
  _Country('Czechia', 'CZ', '420'),
  _Country('Turkey', 'TR', '90'),
  _Country('United States', 'US', '1'),
  _Country('Canada', 'CA', '1'),
  _Country('United Arab Emirates', 'AE', '971'),
  _Country('Saudi Arabia', 'SA', '966'),
  _Country('Qatar', 'QA', '974'),
  _Country('Kuwait', 'KW', '965'),
  _Country('Bahrain', 'BH', '973'),
  _Country('Oman', 'OM', '968'),
  _Country('Jordan', 'JO', '962'),
  _Country('Lebanon', 'LB', '961'),
  _Country('Iraq', 'IQ', '964'),
  _Country('India', 'IN', '91'),
  _Country('China', 'CN', '86'),
  _Country('Japan', 'JP', '81'),
  _Country('South Korea', 'KR', '82'),
  _Country('Nigeria', 'NG', '234'),
  _Country('South Africa', 'ZA', '27'),
  _Country('Kenya', 'KE', '254'),
  _Country('Ghana', 'GH', '233'),
  _Country('Senegal', 'SN', '221'),
  _Country("Côte d'Ivoire", 'CI', '225'),
  _Country('Brazil', 'BR', '55'),
  _Country('Mexico', 'MX', '52'),
  _Country('Australia', 'AU', '61'),
];

/// Builds a flag emoji from a 2-letter ISO code using Unicode regional
/// indicators (e.g. 'TN' -> the Tunisia flag), so no emoji literals live in the
/// source.
String _flagOf(String iso) {
  if (iso.length != 2) return '';
  final a = iso.toUpperCase().codeUnitAt(0) - 0x41;
  final b = iso.toUpperCase().codeUnitAt(1) - 0x41;
  if (a < 0 || a > 25 || b < 0 || b > 25) return '';
  return String.fromCharCode(0x1F1E6 + a) + String.fromCharCode(0x1F1E6 + b);
}

/// Self-service SMS two-factor enrolment for the signed-in user.
///
/// Push it from anywhere a user manages their account (e.g. a profile/settings
/// action, or the SuperAdmin Access & Identity tab):
/// `Navigator.push(context, MaterialPageRoute(builder: (_) => const MfaEnrollmentScreen()));`
///
/// Requires SMS multi-factor enabled in Firebase Identity Platform.
class MfaEnrollmentScreen extends StatefulWidget {
  const MfaEnrollmentScreen({
    super.key,
    this.mandatory = false,
    this.onCompleted,
  });

  /// When true the screen is a non-dismissable gate (no back/skip) the
  /// RoleRouter shows to enforce enrolment before granting app access.
  final bool mandatory;

  /// Called once enrolment is satisfied in [mandatory] mode so the gate can let
  /// the user through to the dashboard.
  final VoidCallback? onCompleted;

  @override
  State<MfaEnrollmentScreen> createState() => _MfaEnrollmentScreenState();
}

class _MfaEnrollmentScreenState extends State<MfaEnrollmentScreen> {
  final _ent = EnterpriseAuthService();
  final _phone = TextEditingController();
  final _code = TextEditingController();

  bool _checking = true;
  bool _emailVerified = false;
  bool _enrolled = false;
  bool _busy = false;
  String? _verificationId;
  String? _error;
  String? _info;
  String _iso = 'TN';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final auth = FirebaseAuth.instance;
    try {
      await auth.currentUser?.reload();
    } catch (_) {}
    final verified = auth.currentUser?.emailVerified ?? false;
    // Firebase blocks second-factor enrolment until the email is verified.
    bool enrolled = false;
    if (verified) {
      enrolled = await _ent.hasEnrolledMfa();
    }
    if (!mounted) return;
    setState(() {
      _emailVerified = verified;
      _enrolled = enrolled;
      _checking = false;
    });
  }

  Future<void> _sendVerification() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) {
        setState(() {
          _busy = false;
          _info = 'Verification email sent. Open the link in it, then tap '
              '"I have verified".';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _recheckVerified() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final v = FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      if (mounted) {
        setState(() {
          _busy = false;
          _emailVerified = v;
          if (!v) {
            _error = 'Still not verified — open the link in the email, '
                'then tap this again.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _dial => _countries
      .firstWhere((c) => c.iso == _iso, orElse: () => _countries.first)
      .dial;

  Future<void> _sendCode() async {
    // Strip non-digits and any national leading zero, then prepend the dial code.
    final national = _phone.text
        .replaceAll(RegExp(r'[^0-9]'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    if (national.length < 6) {
      setState(() => _error = 'Enter your mobile number.');
      return;
    }
    final phone = '+$_dial$national';
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final r = await _ent.startPhoneEnrollment(phone);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.verificationId != null) {
        _verificationId = r.verificationId;
        _info = 'Code sent to $phone.';
      } else {
        _error = r.error ?? 'Could not send the code.';
      }
    });
  }

  Future<void> _verify() async {
    final vid = _verificationId;
    if (vid == null) return;
    if (_code.text.trim().length < 4) {
      setState(() => _error = 'Enter the code from the SMS.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await _ent.finishPhoneEnrollment(vid, _code.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) {
        _enrolled = true;
        _verificationId = null;
        _info = 'Two-factor authentication is now on.';
      } else {
        _error = err;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.mandatory,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Two-factor authentication'),
        automaticallyImplyLeading: !widget.mandatory,
        actions: widget.mandatory
            ? [
                TextButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Sign out'),
                ),
              ]
            : null,
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: !_emailVerified
                      ? _verifyEmailView()
                      : _enrolled
                          ? _enrolledView()
                          : _enrollForm(),
                ),
              ),
            ),
    ));
  }

  Widget _verifyEmailView() {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'your email';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.mark_email_unread_outlined,
                color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Verify your email first',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Two-factor authentication can only be added after your email '
          '($email) is verified.',
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _sendVerification,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.mail_outline),
            label: Text(_busy ? 'Sending…' : 'Send verification email'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busy ? null : _recheckVerified,
            child: const Text('I have verified — continue'),
          ),
        ),
        if (_info != null) ...[
          const SizedBox(height: 14),
          Text(_info!,
              style: const TextStyle(color: Colors.green, fontSize: 13)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!,
              style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
      ],
    );
  }

  Widget _enrolledView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.verified_user, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your account is protected by SMS two-factor authentication.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'At each sign-in you will be asked for a code sent by text message.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            if (widget.mandatory && widget.onCompleted != null) {
              widget.onCompleted!();
            } else {
              Navigator.of(context).maybePop();
            }
          },
          child: Text(widget.mandatory ? 'Continue to app' : 'Done'),
        ),
      ],
    );
  }

  Widget _enrollForm() {
    final codeStage = _verificationId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add an extra layer of security',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'We will text a verification code to your phone each time you sign in.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 145,
              child: DropdownButtonFormField<String>(
                value: _iso,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  border: OutlineInputBorder(),
                ),
                items: (List<_Country>.of(_countries)
                      ..sort((a, b) => a.name.compareTo(b.name)))
                    .map((c) => DropdownMenuItem(
                          value: c.iso,
                          child: Text('${_flagOf(c.iso)}  ${c.name} +${c.dial}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (codeStage || _busy)
                    ? null
                    : (v) => setState(() => _iso = v ?? _iso),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _phone,
                enabled: !codeStage && !_busy,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  hintText: '55 123 456',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!codeStage)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _sendCode,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sms_outlined),
              label: Text(_busy ? 'Sending…' : 'Send code'),
            ),
          ),
        if (codeStage) ...[
          TextField(
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Verification code',
              hintText: '6-digit code',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _verify,
                  child: Text(_busy ? 'Verifying…' : 'Verify & enable'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _verificationId = null;
                          _code.clear();
                          _info = null;
                        }),
                child: const Text('Change number'),
              ),
            ],
          ),
        ],
        if (_info != null) ...[
          const SizedBox(height: 14),
          Text(_info!,
              style: const TextStyle(color: Colors.green, fontSize: 13)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!,
              style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
      ],
    );
  }
}
