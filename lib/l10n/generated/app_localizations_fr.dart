// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Smart Industrial Alert - SIA';

  @override
  String get loginTitle => 'Connexion';

  @override
  String get loginEmailLabel => 'E-mail';

  @override
  String get loginPasswordLabel => 'Mot de passe';

  @override
  String get loginSubmit => 'Se connecter';

  @override
  String get loginError =>
      'Connexion impossible. Vérifiez vos identifiants et réessayez.';

  @override
  String get dashboardHeaderTitle => 'Tableau de bord';

  @override
  String dashboardHeaderGreeting(String name) {
    return 'Bon retour, $name';
  }

  @override
  String get adminDashboardTitle => 'Tableau de bord administrateur';

  @override
  String get adminTabOverview => 'Vue d\'ensemble';

  @override
  String get adminTabSupervisors => 'Superviseurs';

  @override
  String get adminTabShifts => 'Équipes';

  @override
  String get adminTabAlerts => 'Alertes';

  @override
  String get adminTabEscalations => 'Escalades';

  @override
  String get adminTabHierarchy => 'Hiérarchie';

  @override
  String get offlineBannerMessage =>
      'Vous êtes hors ligne. Les modifications seront synchronisées à la reconnexion.';

  @override
  String get voiceEnrollmentPromptTitle => 'Configurer la commande vocale';

  @override
  String get voiceEnrollmentPromptBody =>
      'Enregistrez votre voix pour réclamer et résoudre les alertes mains libres.';

  @override
  String get voiceEnrollmentPromptStart => 'Démarrer l\'enregistrement';

  @override
  String get voiceEnrollmentPromptDismiss => 'Plus tard';
}
