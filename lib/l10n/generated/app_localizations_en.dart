// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Smart Industrial Alert - SIA';

  @override
  String get loginTitle => 'Sign in';

  @override
  String get loginEmailLabel => 'Email';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginSubmit => 'Sign in';

  @override
  String get loginError =>
      'Could not sign you in. Check your credentials and try again.';

  @override
  String get dashboardHeaderTitle => 'Dashboard';

  @override
  String dashboardHeaderGreeting(String name) {
    return 'Welcome back, $name';
  }

  @override
  String get adminDashboardTitle => 'Admin Dashboard';

  @override
  String get adminTabOverview => 'Overview';

  @override
  String get adminTabSupervisors => 'Supervisors';

  @override
  String get adminTabShifts => 'Shifts';

  @override
  String get adminTabAlerts => 'Alerts';

  @override
  String get adminTabEscalations => 'Escalations';

  @override
  String get adminTabHierarchy => 'Hierarchy';

  @override
  String get offlineBannerMessage =>
      'You are offline. Changes will sync when reconnected.';

  @override
  String get voiceEnrollmentPromptTitle => 'Set up voice control';

  @override
  String get voiceEnrollmentPromptBody =>
      'Enroll your voice so you can claim and resolve alerts hands-free.';

  @override
  String get voiceEnrollmentPromptStart => 'Start enrollment';

  @override
  String get voiceEnrollmentPromptDismiss => 'Not now';
}
