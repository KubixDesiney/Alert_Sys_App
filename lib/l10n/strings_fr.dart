// French translations for SIA.
//
// Keyed by the English source string used in `context.tr('...')`. A missing key
// falls back to English automatically, so this map can grow incrementally as
// screens are localized. Keep entries sorted loosely by area for readability.
//
// Placeholders use `{name}` tokens that `context.tr(source, params)` fills in;
// keep the same tokens in the French value.
const Map<String, String> kStringsFr = {
  // ── Industrial connectors (Infrastructure tab) ──
  'INDUSTRIAL CONNECTORS': 'CONNECTEURS INDUSTRIELS',
  'Feed alerts from SCADA · PLC · Historian · MQTT · REST — on top of what the plant already runs':
      'Alimentez les alertes depuis SCADA · PLC · Historian · MQTT · REST — par-dessus ce que l’usine exécute déjà',
  'Add a connector, enter its endpoint and credentials, then run the Verify link test — the link reads LINKED only when real data is genuinely flowing.':
      'Ajoutez un connecteur, saisissez son point de terminaison et ses identifiants, puis lancez le test de liaison — la liaison affiche CONNECTÉ uniquement lorsque des données réelles circulent vraiment.',
  'CONFIGURED CONNECTORS': 'CONNECTEURS CONFIGURÉS',
  'No connectors yet': 'Aucun connecteur pour l’instant',
  'Pick a system above to wire your first live data source.':
      'Choisissez un système ci-dessus pour brancher votre première source de données en direct.',
  'LINKED': 'CONNECTÉ',
  'WAITING': 'EN ATTENTE',
  'ERROR': 'ERREUR',
  'NOT VERIFIED': 'NON VÉRIFIÉ',
  'CLOUD-PULL': 'RELEVÉ CLOUD',
  'EDGE-PUSH': 'ENVOI EDGE',
  'BROKER': 'BROKER',
  'Subscribe to OPC-UA nodes via an edge bridge. The SCADA / DCS standard.':
      'Abonnez-vous aux nœuds OPC-UA via une passerelle edge. Le standard SCADA / DCS.',
  'Poll Modbus TCP registers from a gateway near the PLC.':
      'Interrogez les registres Modbus TCP depuis une passerelle proche de l’automate.',
  'MQTT / Sparkplug B broker. Live CONNACK handshake verify.':
      'Broker MQTT / Sparkplug B. Vérification par handshake CONNACK en direct.',
  'OSIsoft / AVEVA PI Web API. Cloud-pulled on a schedule.':
      'API Web OSIsoft / AVEVA PI. Relevé cloud planifié.',
  'Ignition (Inductive Automation) HTTP / WebDev tag reads.':
      'Lectures de tags HTTP / WebDev Ignition (Inductive Automation).',
  'Any MES / CMMS / quality system with an HTTPS endpoint.':
      'Tout système MES / GMAO / qualité avec un point de terminaison HTTPS.',
  'ESP32 / Arduino + buttons POSTing structured telemetry.':
      'ESP32 / Arduino + boutons envoyant une télémétrie structurée.',
  'Anything else that can POST JSON or expose a value.':
      'Tout autre système capable d’envoyer du JSON ou d’exposer une valeur.',
  'events': 'évén.',
  'last': 'dernier',
  'seen': 'vu',
  'just now': 'à l’instant',
  'Verify link test': 'Tester la liaison',
  'Poll now': 'Interroger maintenant',
  'Polling…': 'Interrogation…',
  'Endpoint & key': 'Point de terminaison et clé',
  'Remove connector?': 'Retirer le connecteur ?',
  '“{name}” will stop feeding alerts. This cannot be undone.':
      '« {name} » cessera d’alimenter les alertes. Cette action est irréversible.',
  'Point your gateway here': 'Pointez votre passerelle ici',
  'Ingest URL': 'URL d’ingestion',
  'Ingest key (x-alertsys-ingest header)': 'Clé d’ingestion (en-tête x-alertsys-ingest)',
  'READY-TO-RUN GATEWAY': 'PASSERELLE PRÊTE À L’EMPLOI',
  'Copy snippet': 'Copier l’extrait',
  'Gateway snippet copied.': 'Extrait de passerelle copié.',
  'Copied.': 'Copié.',
  'New connector': 'Nouveau connecteur',
  'Edit connector': 'Modifier le connecteur',
  'Connector name': 'Nom du connecteur',
  'Line': 'Ligne',
  'Endpoint URL': 'URL du point de terminaison',
  'Poll interval (seconds)': 'Intervalle d’interrogation (secondes)',
  'Broker URL (MQTT over WebSocket)': 'URL du broker (MQTT sur WebSocket)',
  'Topic': 'Sujet',
  'Client ID': 'ID client',
  'Username': 'Nom d’utilisateur',
  'optional': 'optionnel',
  'Verify opens a real MQTT connection and waits for the broker CONNACK. For steady-state, forward matching topics to the ingest URL (shown after Save).':
      'La vérification ouvre une vraie connexion MQTT et attend le CONNACK du broker. En régime permanent, transférez les sujets correspondants vers l’URL d’ingestion (affichée après l’enregistrement).',
  'Edge-push connector. After Save you get a dedicated ingest URL + key and a ready-to-run gateway snippet. Verify reads LINKED once your gateway sends its first packet.':
      'Connecteur en envoi edge. Après l’enregistrement, vous obtenez une URL d’ingestion + clé dédiées et un extrait de passerelle prêt à l’emploi. La vérification affiche CONNECTÉ dès que votre passerelle envoie son premier paquet.',
  'Per-connector ingest key': 'Clé d’ingestion par connecteur',
  'Optional tag mapping (metric · thresholds for incoming readings)':
      'Mappage de tags optionnel (métrique · seuils pour les relevés entrants)',
  'Authentication': 'Authentification',
  'Bearer token': 'Jeton Bearer',
  'Basic (user + password)': 'Basic (utilisateur + mot de passe)',
  'API key header': 'Clé API (en-tête)',
  'API key query param': 'Clé API (paramètre d’URL)',
  'Header name': 'Nom de l’en-tête',
  'Query parameter': 'Paramètre d’URL',
  'Token / API key': 'Jeton / clé API',
  'leave blank to keep current': 'laisser vide pour conserver l’actuel',
  'Tags to read': 'Tags à lire',
  'Tag mappings': 'Mappages de tags',
  'Tag / node / register': 'Tag / nœud / registre',
  'Incoming tag': 'Tag entrant',
  'Metric': 'Métrique',
  'Value JSON path': 'Chemin JSON de la valeur',
  'Unit': 'Unité',
  'Warn ≥': 'Alerte ≥',
  'Critical ≥': 'Critique ≥',
  'Higher is worse': 'Plus haut = pire',
  'Lower is worse': 'Plus bas = pire',
  'Type: auto': 'Type : auto',
  'Mechanical': 'Mécanique',
  'Electrical': 'Électrique',
  'Safety': 'Sécurité',

  // ── Generic actions ──
  'Cancel': 'Annuler',
  'Save': 'Enregistrer',
  'Save changes': 'Enregistrer les modifications',
  'Delete': 'Supprimer',
  'Edit': 'Modifier',
  'Add': 'Ajouter',
  'Close': 'Fermer',
  'Confirm': 'Confirmer',
  'Retry': 'Réessayer',
  'Refresh': 'Actualiser',
  'Search': 'Rechercher',
  'Apply': 'Appliquer',
  'Clear': 'Effacer',
  'Submit': 'Envoyer',
  'Verify': 'Vérifier',
  'Continue': 'Continuer',
  'Back': 'Retour',
  'Next': 'Suivant',
  'Previous': 'Précédent',
  'Done': 'Terminé',
  'Yes': 'Oui',
  'No': 'Non',
  'OK': 'OK',
  'Open': 'Ouvrir',
  'Create': 'Créer',
  'Update': 'Mettre à jour',
  'Remove': 'Retirer',
  'Send': 'Envoyer',
  'Export': 'Exporter',
  'Download': 'Télécharger',
  'Upload': 'Téléverser',
  'Reset': 'Réinitialiser',
  'Select': 'Sélectionner',
  'View': 'Voir',
  'View details': 'Voir les détails',
  'Details': 'Détails',
  'Loading…': 'Chargement…',
  'Loading...': 'Chargement...',
  'Please wait': 'Veuillez patienter',
  'Something went wrong': 'Une erreur est survenue',
  'Try again': 'Réessayer',
  'Copied': 'Copié',
  'Copy': 'Copier',
  'All': 'Tous',
  'None': 'Aucun',
  'More': 'Plus',
  'Show more': 'Afficher plus',
  'Show less': 'Afficher moins',
  'Enabled': 'Activé',
  'Disabled': 'Désactivé',
  'Optional': 'Facultatif',
  'Required': 'Requis',

  // ── Language / theme ──
  'Switch language': 'Changer de langue',
  'Language': 'Langue',
  'English': 'Anglais',
  'French': 'Français',
  'Français': 'Français',
  'Light mode': 'Mode clair',
  'Dark mode': 'Mode sombre',

  // ── Auth / login ──
  'Sign In': 'Connexion',
  'All rights reserved.': 'Tous droits réservés.',
  'Sign in': 'Se connecter',
  'Sign out': 'Se déconnecter',
  'Log out': 'Se déconnecter',
  'Logout': 'Déconnexion',
  'Email': 'E-mail',
  'Password': 'Mot de passe',
  'your@email.com': 'votre@email.com',
  'Could not sign you in. Check your credentials and try again.':
      'Connexion impossible. Vérifiez vos identifiants et réessayez.',
  'Download APK': 'Télécharger l\'APK',
  'Unable to open download link': 'Impossible d\'ouvrir le lien de téléchargement',
  'Two-factor code': 'Code à deux facteurs',
  '6-digit code': 'Code à 6 chiffres',
  'Could not send the verification SMS.': 'Impossible d\'envoyer le SMS de vérification.',
  'Authentication error': 'Erreur d\'authentification',
  'User not found.': 'Utilisateur introuvable.',
  'Incorrect password.': 'Mot de passe incorrect.',
  'SSO is not configured.': 'Le SSO n\'est pas configuré.',
  'Not signed in.': 'Vous n\'êtes pas connecté.',
  'No MFA challenge is pending.': 'Aucune vérification à deux facteurs en attente.',

  // ── Roles ──
  'Supervisor': 'Superviseur',
  'Supervisors': 'Superviseurs',
  'Admin': 'Administrateur',
  'Administrator': 'Administrateur',
  'Production Manager': 'Responsable de production',
  'Production Managers': 'Responsables de production',
  'SuperAdmin': 'SuperAdmin',

  // ── Navigation / tabs ──
  'Dashboard': 'Tableau de bord',
  'Admin Dashboard': 'Tableau de bord administrateur',
  'Overview': 'Vue d\'ensemble',
  'Shifts': 'Équipes',
  'Alerts': 'Alertes',
  'Escalations': 'Escalades',
  'Hierarchy': 'Hiérarchie',
  'Settings': 'Paramètres',
  'Collaborations': 'Collaborations',
  'Management': 'Gestion',
  'Profile': 'Profil',
  'Notifications': 'Notifications',
  'Map': 'Carte',
  'Locator': 'Localisateur',
  'Scan': 'Scanner',
  'Home': 'Accueil',
  'Logs': 'Journaux',
  'AI Training': 'Entraînement IA',
  'AI Agents': 'Agents IA',
  'Overview Monitor': 'Moniteur de supervision',
  'Hardware': 'Matériel',
  'Hardware Lab': 'Labo matériel',

  // ── Alert lifecycle ──
  'Alert': 'Alerte',
  'Claim': 'Réclamer',
  'Claim alert': 'Réclamer l\'alerte',
  'Take': 'Prendre',
  'Take alert': 'Prendre l\'alerte',
  'Resolve': 'Résoudre',
  'Resolve alert': 'Résoudre l\'alerte',
  'Resolved': 'Résolue',
  'Escalate': 'Escalader',
  'Escalated': 'Escaladée',
  'Critical': 'Critique',
  'Mark as critical': 'Marquer comme critique',
  'Pending': 'En attente',
  'In progress': 'En cours',
  'Available': 'Disponible',
  'Validated': 'Validée',
  'Validate': 'Valider',
  'Return to queue': 'Remettre en file',
  'Assign': 'Assigner',
  'Assigned': 'Assignée',
  'Unassigned': 'Non assignée',
  'Assistance': 'Assistance',
  'Request assistance': 'Demander de l\'assistance',
  'Help': 'Aide',
  'Request help': 'Demander de l\'aide',
  'Accept': 'Accepter',
  'Refuse': 'Refuser',
  'Reject': 'Rejeter',
  'Approve': 'Approuver',
  'Comment': 'Commentaire',
  'Comments': 'Commentaires',
  'Add a comment': 'Ajouter un commentaire',
  'No alerts': 'Aucune alerte',
  'No alerts yet': 'Aucune alerte pour le moment',
  'New alert': 'Nouvelle alerte',
  'Critical alerts': 'Alertes critiques',
  'Resolution': 'Résolution',
  'Resolution reason': 'Motif de résolution',
  'Elapsed time': 'Temps écoulé',

  // ── Status ──
  'Active': 'Actif',
  'Inactive': 'Inactif',
  'Online': 'En ligne',
  'Offline': 'Hors ligne',
  'Busy': 'Occupé',
  'Ready': 'Prêt',
  'Not ready': 'Pas prêt',
  'Absent': 'Absent',
  'Connected': 'Connecté',
  'Not connected': 'Non connecté',
  'Status': 'Statut',

  // ── Common field labels ──
  'Name': 'Nom',
  'First name': 'Prénom',
  'Last name': 'Nom de famille',
  'Phone': 'Téléphone',
  'Role': 'Rôle',
  'Factory': 'Usine',
  'Factories': 'Usines',
  'All factories': 'Toutes les usines',
  'Type': 'Type',
  'Location': 'Emplacement',
  'Time': 'Heure',
  'Date': 'Date',
  'Description': 'Description',
  'Conveyor': 'Convoyeur',
  'Station': 'Poste',
  'Machine': 'Machine',
  'Asset': 'Équipement',
  'Confidence': 'Confiance',
  'Reason': 'Motif',

  // ── Offline / connectivity ──
  'You are offline. Changes will sync when reconnected.':
      'Vous êtes hors ligne. Les modifications seront synchronisées à la reconnexion.',
  'You are offline': 'Vous êtes hors ligne',
  'Back online': 'De nouveau en ligne',
  'Offline account data is not cached yet.':
      'Les données du compte hors ligne ne sont pas encore en cache.',
  'Connect once so Smart Industrial Alert - SIA can save this account for offline startup.':
      'Connectez-vous une fois pour que Smart Industrial Alert - SIA enregistre ce compte pour un démarrage hors ligne.',

  // ── Empty / generic states ──
  'No data': 'Aucune donnée',
  'No results': 'Aucun résultat',
  'No results found': 'Aucun résultat trouvé',
  'Nothing here yet': 'Rien pour le moment',
  'Coming soon': 'Bientôt disponible',

  // ── Supervisor dashboard ──
  'Fixed Alerts': 'Alertes corrigées',
  'Claimed Alerts': 'Alertes réclamées',
  'Manage Pending Alerts': 'Gérer les alertes en attente',
  'Click to see details': 'Cliquez pour voir les détails',
  'All Notifications': 'Toutes les notifications',
  'View and manage your alerts and PM actions':
      'Consultez et gérez vos alertes et actions du responsable',
  '{n} unread': '{n} non lues',
  'PM Actions': 'Actions du responsable',
  'PM Action': 'Action du responsable',
  'Stop Buzzing': 'Arrêter la vibration',
  'Action required': 'Action requise',
  'Phone is buzzing': 'Le téléphone vibre',
  'Help request accepted': 'Demande d\'aide acceptée',
  'Help request refused': 'Demande d\'aide refusée',
  'No active supervisors available': 'Aucun superviseur actif disponible',
  'Assign Assistant': 'Assigner un assistant',
  'Assigned {name} as assistant': '{name} assigné comme assistant',
  'Collaboration request': 'Demande de collaboration',
  'From: {name}': 'De : {name}',
  'You accepted — waiting for PM approval':
      'Vous avez accepté — en attente de l\'approbation du responsable',
  'You declined this request': 'Vous avez refusé cette demande',
  'Collaboration declined': 'Collaboration refusée',
  'Collaboration accepted! Waiting for PM.':
      'Collaboration acceptée ! En attente du responsable.',
  'Collaboration request marked as read':
      'Demande de collaboration marquée comme lue',
  'Notification': 'Notification',
  'PM action marked as read': 'Action du responsable marquée comme lue',
  'Mark as read': 'Marquer comme lu',
  'Decline': 'Refuser',
  'Request Collaboration': 'Demander une collaboration',
  'Hold detected! Would you like to request collaboration for this alert?':
      'Blocage détecté ! Souhaitez-vous demander une collaboration pour cette alerte ?',
  'Collab': 'Collab',
  'Resolve Alert': 'Résoudre l\'alerte',
  'AI Suggestion': 'Suggestion IA',
  'Mark as Critical': 'Marquer comme critique',
  'Optional note (reason, impact, etc.)':
      'Note facultative (motif, impact, etc.)',
  'Mark Critical': 'Marquer critique',
  'Assistance offered. The claimant will be notified.':
      'Assistance proposée. Le demandeur sera notifié.',
  'Fixed': 'Corrigée',
  'Suspend Alert': 'Suspendre l\'alerte',
  'Optional reason for suspension': 'Motif facultatif de suspension',
  'Suspend': 'Suspendre',
  'AI Assist': 'Assistance IA',
  'Assisted by: {name}': 'Assisté par : {name}',
  'Resolution time: {time}': 'Temps de résolution : {time}',
  'Fixed by: ': 'Corrigée par : ',
  'Assisted {name}': 'Assisté {name}',
  'No fixed alerts': 'Aucune alerte corrigée',
  'Fixed alerts will appear here': 'Les alertes corrigées apparaîtront ici',
  'Assisted': 'Assisté',
  'No pending alerts': 'Aucune alerte en attente',
  'All alerts are being handled': 'Toutes les alertes sont prises en charge',
  'No claimed alerts': 'Aucune alerte réclamée',
  'Claim an alert to start': 'Réclamez une alerte pour commencer',
  'Assisting {name}': 'Assistance de {name}',
  'My Claim (assisted by {name})': 'Ma réclamation (assisté par {name})',
  'Claimed by {name} (assisted by {assistant})':
      'Réclamée par {name} (assisté par {assistant})',
  'My Claim': 'Ma réclamation',
  'Claimed by {name}': 'Réclamée par {name}',
  'someone': 'quelqu\'un',
  'other': 'autre',
  'Assist': 'Assister',
  'Station Scan': 'Scan de poste',
  'Collab Progress': 'Suivi collaboration',
  'No notifications': 'Aucune notification',

  // ── Admin / Production Manager dashboard ──
  'Production Manager - Dashboard': 'Responsable de production - Tableau de bord',
  'Simulate Alert': 'Simuler une alerte',
  'Sign Out': 'Se déconnecter',
  'Simulate Custom Alert': 'Simuler une alerte personnalisée',
  'Alert Type': 'Type d\'alerte',
  'Quality': 'Qualité',
  'Maintenance': 'Maintenance',
  'Damaged Product': 'Produit défectueux',
  'Resource Shortage': 'Manque de ressource',
  'Factory (Usine)': 'Usine',
  'Conveyor {n}': 'Convoyeur {n}',
  'Workstation (Poste)': 'Poste de travail',
  'Description (optional)': 'Description (facultatif)',
  'e.g., Motor overheating (optional)':
      'ex. : surchauffe du moteur (facultatif)',
  'Create Alert': 'Créer l\'alerte',
  'Please select factory, conveyor, and workstation':
      'Veuillez sélectionner l\'usine, le convoyeur et le poste',
  'Failed: {error}': 'Échec : {error}',
  'No alerts to export': 'Aucune alerte à exporter',
  'Assign Supervisor': 'Assigner un superviseur',
  'Assigned to {name}': 'Assigné à {name}',
  'No active supervisors available for this factory':
      'Aucun superviseur actif disponible pour cette usine',
  'New Supervisor Account': 'Nouveau compte superviseur',
  'First Name': 'Prénom',
  'Last Name': 'Nom de famille',
  'Confirm Password': 'Confirmer le mot de passe',
  'Min 6 characters': 'Min. 6 caractères',
  'Repeat password': 'Répéter le mot de passe',
  'Assigned Plant': 'Usine assignée',
  'Select a factory': 'Sélectionner une usine',
  'Hire Date': 'Date d\'embauche',
  'All fields are required.': 'Tous les champs sont requis.',
  'Passwords do not match.': 'Les mots de passe ne correspondent pas.',
  'Password must be at least 6 characters.':
      'Le mot de passe doit comporter au moins 6 caractères.',
  'Please select a factory.': 'Veuillez sélectionner une usine.',
  'Supervisor created': 'Superviseur créé',
  'Supervisor removed': 'Superviseur supprimé',
  'Creating…': 'Création…',
  'Create Account': 'Créer le compte',
  'Recommendation approved': 'Recommandation approuvée',
  'Recommendation declined': 'Recommandation refusée',
  'Recommendation was already processed':
      'La recommandation a déjà été traitée',
  'AI cross-factory recommendation': 'Recommandation IA inter-usines',
  'Recommended: {name}': 'Recommandé : {name}',
  'Help request': 'Demande d\'aide',
  'Tap to accept or refuse': 'Touchez pour accepter ou refuser',
  'Assistance request': 'Demande d\'assistance',

  // ── SuperAdmin console shell ──
  'OVERVIEW MONITOR': 'MONITEUR DE SUPERVISION',
  'AI TRAINING': 'ENTRAÎNEMENT IA',
  'AI AGENTS': 'AGENTS IA',
  'PRODUCTION MANAGERS': 'RESPONSABLES DE PRODUCTION',
  'ACCESS & IDENTITY': 'ACCÈS ET IDENTITÉ',
  'RELIABILITY': 'FIABILITÉ',
  'BRANDING': 'IMAGE DE MARQUE',
  'INFRASTRUCTURE': 'INFRASTRUCTURE',
  'HARDWARE': 'MATÉRIEL',
  'COMMAND CENTER · SMART INDUSTRIAL ALERT':
      'CENTRE DE COMMANDE · SMART INDUSTRIAL ALERT',
  'COMMAND': 'CENTRE DE',
  'CENTER': 'COMMANDE',
  'Sign out of the console?': 'Se déconnecter de la console ?',
  'A model training run is in progress. It keeps running while this app stays open, and its checkpoint lets any future session finish it — signing out is safe.':
      'Un entraînement de modèle est en cours. Il continue tant que l\'application reste ouverte, et son point de contrôle permet à toute session future de le terminer — la déconnexion est sans risque.',
  'SYSTEM: PROBING': 'SYSTÈME : SONDAGE',
  'SYSTEM: NOMINAL': 'SYSTÈME : NOMINAL',
  'SYSTEM: DEGRADED': 'SYSTÈME : DÉGRADÉ',
  'SYSTEM: CRON STALLED': 'SYSTÈME : CRON BLOQUÉ',

  // ── Alert detail screen ──
  'Alert Details': 'Détails de l\'alerte',
  'Alert {label}': 'Alerte {label}',
  'Type: {type}': 'Type : {type}',
  'Location: {usine} - Line {conv} - Post {poste}':
      'Emplacement : {usine} - Ligne {conv} - Poste {poste}',
  'Address: {address}': 'Adresse : {address}',
  'Description: {description}': 'Description : {description}',
  'Timestamp: {time}': 'Horodatage : {time}',
  'Elapsed: {time}': 'Écoulé : {time}',
  'Reason: {reason}': 'Motif : {reason}',
  'AI Assignment Insight': 'Analyse d\'affectation IA',
  'Decision: Auto-assigned': 'Décision : auto-assignée',
  'Decision: Recommendation pending PM confirmation':
      'Décision : recommandation en attente de confirmation du responsable',
  'Decision: AI evaluation available': 'Décision : évaluation IA disponible',
  'Recommended supervisor: {name}': 'Superviseur recommandé : {name}',
  'Recommendation reason: {reason}': 'Motif de la recommandation : {reason}',
  'Confidence: {pct}% • {label}': 'Confiance : {pct}% • {label}',
  'Collaboration Request': 'Demande de collaboration',
  'You are not a target for this collaboration request.':
      'Vous n\'êtes pas destinataire de cette demande de collaboration.',
  'Decision: {decision}': 'Décision : {decision}',
  'Add comment...': 'Ajouter un commentaire...',
  'Unflag Critical': 'Retirer le marquage critique',

  // ── Supervisors tab (PM) ──
  'Update failed: {error}': 'Échec de la mise à jour : {error}',
  'Delete Supervisor': 'Supprimer le superviseur',
  'This permanently removes {name} from {place}.':
      'Cela retire définitivement {name} de {place}.',
  'the roster': 'l\'effectif',
  'Modify Supervisor': 'Modifier le superviseur',
  'Email address': 'Adresse e-mail',
  'Phone number': 'Numéro de téléphone',
  'First name, last name, and email are required':
      'Le prénom, le nom et l\'e-mail sont requis',
  'Please enter a valid email': 'Veuillez saisir un e-mail valide',
  'Supervisor updated successfully': 'Superviseur mis à jour avec succès',
  'Roster, plant assignments, and on-demand performance.':
      'Effectif, affectations d\'usine et performance à la demande.',
  '{n} active': '{n} actifs',
  '{n} absent': '{n} absents',
  '{n} plants': '{n} usines',
  'Add Supervisor': 'Ajouter un superviseur',
  'Weekly Team Resolution Heatmap':
      'Carte thermique hebdomadaire des résolutions de l\'équipe',
  'Total resolved alerts by day': 'Total des alertes résolues par jour',
  'Alert Type Distribution': 'Répartition des types d\'alertes',
  'Combined supervisor workload mix':
      'Mix de charge de travail combiné des superviseurs',
  'Supervisor Leaderboard': 'Classement des superviseurs',
  'Top 5 by impact score': 'Top 5 par score d\'impact',
  'Live Activity Pulse': 'Pouls d\'activité en direct',
  'Rolling alert activity window': 'Fenêtre glissante d\'activité des alertes',
  'Factory Workload Map': 'Carte de charge des usines',
  'Supervisor load by factory': 'Charge des superviseurs par usine',
  'Performance': 'Performance',
  'Resize panel': 'Redimensionner le panneau',
  'Toggle size': 'Basculer la taille',
  'Roster': 'Effectif',
  'Search supervisor': 'Rechercher un superviseur',
  'Factory Assignments': 'Affectations d\'usine',
  'Live supervisor placement by plant.':
      'Placement des superviseurs en direct par usine.',
  'Avg Time': 'Temps moyen',
  'Top Plant': 'Usine principale',
  'Resolved Alerts': 'Alertes résolues',
  'Average Resolution': 'Résolution moyenne',
  'Validation Rate': 'Taux de validation',
  'AI Assigned': 'Assignées par l\'IA',
  'Critical Load': 'Charge critique',
  'Performance Graph': 'Graphique de performance',
  'Resolved alerts over time': 'Alertes résolues dans le temps',
  'Validations': 'Validations',
  'Alert Type Breakdown': 'Ventilation par type d\'alerte',
  'Validated alerts by class': 'Alertes validées par catégorie',
  'Open slot': 'Emplacement libre',
  'Awaiting plant placement': 'En attente d\'affectation d\'usine',
  'No unassigned supervisors': 'Aucun superviseur non assigné',
  'plant lanes': 'lignes d\'usine',
  'assigned': 'assignés',
  'unassigned': 'non assignés',
  'active': 'actifs',
  'staffed plants': 'usines dotées',
  'Assignment Board': 'Tableau d\'affectation',
  'Roster source, factory lanes, and unassigned pool':
      'Source de l\'effectif, lignes d\'usine et pool non assigné',
  'Validated Alert Trail': 'Historique des alertes validées',
  '{n} resolved records': '{n} enregistrements résolus',
  'No alert type activity': 'Aucune activité par type d\'alerte',
  'No supervisor scores yet': 'Aucun score de superviseur pour l\'instant',
  'No factory workload yet': 'Aucune charge d\'usine pour l\'instant',
  'No validated alerts yet': 'Aucune alerte validée pour l\'instant',
  'Rank #{rank}': 'Rang #{rank}',
  'Not validated': 'Non validée',

  // ── Overview tab (PM) ──
  'Critical pending': 'Critiques en attente',
  'Avg response': 'Réponse moyenne',
  'Total this period': 'Total cette période',
  'No alerts match the selected filters':
      'Aucune alerte ne correspond aux filtres sélectionnés',
  'All Plants': 'Toutes les usines',
  'PDF export failed: {error}': 'Échec de l\'export PDF : {error}',
  'Claimed': 'Réclamées',
  'Total': 'Total',
  'Plant': 'Usine',
  'All Conveyors': 'Tous les convoyeurs',
  'Conv. {n}': 'Conv. {n}',
  'Workstation': 'Poste de travail',
  'All Workstations': 'Tous les postes',
  'WS {n}': 'Poste {n}',
  'All Types': 'Tous les types',
  'All Statuses': 'Tous les statuts',
  'CRITICALITY': 'CRITICITÉ',
  'Critical Only': 'Critiques uniquement',
  'Normal Only': 'Normales uniquement',
  'Time Range': 'Plage de temps',
  'All Time': 'Toute la période',
  'Today': 'Aujourd\'hui',
  'Last 7 Days': '7 derniers jours',
  'This Month': 'Ce mois-ci',
  'This Year': 'Cette année',
  'Previous page': 'Page précédente',
  'Next page': 'Page suivante',
  'Post': 'Poste',
  'All Posts': 'Tous les postes',
  'Post {n}': 'Poste {n}',
  'Custom': 'Personnalisé',
  'Reset filters': 'Réinitialiser les filtres',
  'Criticality': 'Criticité',
  'Report Name': 'Nom du rapport',
  'Report name': 'Nom du rapport',
  'Reset to auto-generated name': 'Rétablir le nom généré automatiquement',
  'Custom report name': 'Nom de rapport personnalisé',
  'Auto-generated from current filters':
      'Généré automatiquement à partir des filtres actuels',
  'Location Scope': 'Portée géographique',
  'Date Range': 'Plage de dates',
  'From': 'De',
  'To': 'À',
  'Alert Types': 'Types d\'alertes',
  'Generating...': 'Génération...',
  'Generate PDF': 'Générer le PDF',
  'Export Report': 'Exporter le rapport',
  'Generate a professional PDF tailored to your filters':
      'Générez un PDF professionnel adapté à vos filtres',

  // ── Shifts (PM) ──
  'Shift saved': 'Équipe enregistrée',
  'Delete shift?': 'Supprimer l\'équipe ?',
  'This will permanently remove "{name}". Active assignments will not be affected.':
      'Cela supprimera définitivement « {name} ». Les affectations actives ne seront pas touchées.',
  'Shift deleted': 'Équipe supprimée',
  'No shifts yet': 'Aucune équipe pour l\'instant',
  'Tap the glowing + button to define your first shift. Pick a name, time range, supervisors, and AI behavior.':
      'Appuyez sur le bouton + lumineux pour définir votre première équipe. Choisissez un nom, une plage horaire, des superviseurs et le comportement de l\'IA.',
  'Shift roster': 'Effectif de l\'équipe',
  'Tap a card to bring its live controls into focus.':
      'Touchez une carte pour afficher ses contrôles en direct.',
  'Live shift detail': 'Détail de l\'équipe en direct',
  'Presence, AI logs, handover, and PDF export in one place.':
      'Présence, journaux IA, passation et export PDF au même endroit.',
  'No shifts match your filters': 'Aucune équipe ne correspond à vos filtres',
  'Clear filters': 'Effacer les filtres',
  'Shift Filters': 'Filtres d\'équipe',
  'Refine the shift roster the same way you filter alerts.':
      'Affinez l\'effectif comme vous filtrez les alertes.',
  'Shift kind': 'Type d\'équipe',
  'Morning': 'Matin',
  'Evening': 'Soir',
  'Night': 'Nuit',
  'AI Commander': 'Commandant IA',
  'Time window': 'Fenêtre temporelle',
  'Anytime': 'À tout moment',
  'Live now': 'En direct',
  'This week': 'Cette semaine',
  'Edit shift settings': 'Modifier les paramètres de l\'équipe',
  'Delete shift': 'Supprimer l\'équipe',
  'Select at least one action type': 'Sélectionnez au moins un type d\'action',
  'Reset name': 'Réinitialiser le nom',
  'Report date': 'Date du rapport',
  'No timeline yet': 'Aucune chronologie pour l\'instant',
  'Once you create shifts, they\'ll appear here as colored blocks across a 24-hour timeline. The pulsing line shows the current time.':
      'Une fois les équipes créées, elles apparaîtront ici sous forme de blocs colorés sur une chronologie de 24 heures. La ligne pulsée indique l\'heure actuelle.',
  'AI logs': 'Journaux IA',
  'Shift name': 'Nom de l\'équipe',
  'e.g. Morning Shift': 'ex. Équipe du matin',
  'Starts': 'Début',
  'Ends': 'Fin',
  'Maximum supervisors per shift': 'Nombre maximum de superviseurs par équipe',
  'Search supervisors': 'Rechercher des superviseurs',
  'Filter by name, factory, or email…':
      'Filtrer par nom, usine ou e-mail…',
  'AI Commander Settings': 'Paramètres du commandant IA',
  'Choose exactly what the commander is allowed to handle during this shift.':
      'Choisissez exactement ce que le commandant peut gérer pendant cette équipe.',
  'Handle Assignments': 'Gérer les affectations',
  'Auto-assign supervisors to alerts.':
      'Affecter automatiquement les superviseurs aux alertes.',
  'Handle Collaborations': 'Gérer les collaborations',
  'Approve collaboration requests after assistant approvals.':
      'Approuver les demandes de collaboration après l\'accord des assistants.',
  'Handle Cross-factory Transfer': 'Gérer les transferts inter-usines',
  'Allow rostered supervisors to cover alerts across factories.':
      'Permettre aux superviseurs inscrits de couvrir les alertes entre usines.',
  'Monitor supervisor activity and prompt confirm-presence pushes when idle.':
      'Surveiller l\'activité des superviseurs et envoyer des notifications de confirmation de présence en cas d\'inactivité.',
  'Full control': 'Contrôle total',
  'Commander manages assignments, collaborations, and transfers.':
      'Le commandant gère les affectations, les collaborations et les transferts.',
  'Max cross-factory distance': 'Distance inter-usines maximale',
  'Skip rostered supervisors whose home factory is farther than this from the alert factory. Leave empty for no limit.':
      'Ignorer les superviseurs dont l\'usine d\'origine est plus éloignée que cette distance de l\'usine de l\'alerte. Laissez vide pour aucune limite.',
  'e.g. 50': 'ex. 50',
  'Randomize shift assignment': 'Affectation aléatoire de l\'équipe',
  'AI picks supervisors at random from the active pool, spread across factories.':
      'L\'IA choisit des superviseurs au hasard dans le pool actif, répartis entre les usines.',
  'Re-randomize': 'Relancer le tirage',
  'No supervisors match this search':
      'Aucun superviseur ne correspond à cette recherche',
  '{count} / {max} selected': '{count} / {max} sélectionnés',
  'Saving…': 'Enregistrement…',
  'Save Shift': 'Enregistrer l\'équipe',
  'Double Assignment Blocked': 'Double affectation bloquée',
  '{name} is already assigned': '{name} est déjà affecté',
  'A supervisor cannot work two shifts at the same time. {name} is already assigned to:':
      'Un superviseur ne peut pas travailler sur deux équipes en même temps. {name} est déjà affecté à :',
  'If you need to move {name} to "{target}", first remove them from "{current}".':
      'Si vous devez déplacer {name} vers « {target} », retirez-le d\'abord de « {current} ».',
  'Understood': 'Compris',
  'No supervisors assigned to this shift':
      'Aucun superviseur affecté à cette équipe',
  'Shift Commander · Live Presence': 'Commandant d\'équipe · Présence en direct',
  'Awaiting': 'En attente',
  'Clear all logs': 'Effacer tous les journaux',

  // ── Escalations (PM) ──
  'Escalation Settings': 'Paramètres d\'escalade',
  '{n} New': '{n} nouvelles',
  'All Read': 'Toutes lues',
  'read': 'lue',
  'Claimed - Time Exceeded': 'Réclamée - Délai dépassé',
  'Unclaimed - Time Exceeded': 'Non réclamée - Délai dépassé',
  '{elapsed} / {limit} min': '{elapsed} / {limit} min',
  'Original alert: {time} ago': 'Alerte d\'origine : il y a {time}',
  'Escalated: {time} ago': 'Escaladée : il y a {time}',
  'Resolve Escalated Alert': 'Résoudre l\'alerte escaladée',
  'What fixed or closed this alert?':
      'Qu\'est-ce qui a corrigé ou clôturé cette alerte ?',
  '{label} resolved': '{label} résolue',
  'Marked Read': 'Marquée comme lue',
  'Mark as Read': 'Marquer comme lue',
  'Settings saved successfully': 'Paramètres enregistrés avec succès',
  'Quality Issues': 'Problèmes de qualité',
  'Resource Deficiency': 'Manque de ressources',
  'PENDING': 'EN ATTENTE',
  'CLAIMED': 'PRISE EN CHARGE',
  'RESOLVED': 'RÉSOLUE',
  'Collaborators added to the request':
      'Collaborateurs ajoutés à la demande',
  'Remove Assistant?': 'Retirer l\'assistant ?',
  'Remove @{name} from this collaboration?':
      'Retirer @{name} de cette collaboration ?',
  'Collaboration rejected': 'Collaboration rejetée',
  'Collaboration approved successfully': 'Collaboration approuvée avec succès',
  'Search by name, factory, email, or phone':
      'Rechercher par nom, usine, e-mail ou téléphone',
  'Assigned: {factory}': 'Assigné : {factory}',
  'Affected: {factory}': 'Affecté : {factory}',

  // ── Hierarchy (PM) ──
  'Select a valid station before generating a QR code.':
      'Sélectionnez un poste valide avant de générer un code QR.',
  'Could not create Asset ID: {error}':
      'Impossible de créer l\'ID d\'équipement : {error}',
  'Relink Asset ID': 'Relier l\'ID d\'équipement',
  'Asset ID': 'ID d\'équipement',
  'Asset ID is required': 'L\'ID d\'équipement est requis',
  'Relink': 'Relier',
  'Could not delete station: {error}':
      'Impossible de supprimer le poste : {error}',
  'Move Station': 'Déplacer le poste',
  'Current location': 'Emplacement actuel',
  'Asset ID: {id}': 'ID d\'équipement : {id}',
  'Destination Factory': 'Usine de destination',
  'Destination Conveyor': 'Convoyeur de destination',
  'Selected conveyor is full.': 'Le convoyeur sélectionné est plein.',
  'The station will be placed in slot {n} and its address will be updated automatically.':
      'Le poste sera placé dans l\'emplacement {n} et son adresse sera mise à jour automatiquement.',
  'Select a different destination.': 'Sélectionnez une autre destination.',
  'Select a destination conveyor.':
      'Sélectionnez un convoyeur de destination.',
  'The selected conveyor has no free station slots.':
      'Le convoyeur sélectionné n\'a aucun emplacement de poste libre.',
  'Add Factory': 'Ajouter une usine',
  'Add a new factory': 'Ajouter une nouvelle usine',
  'Factory Name': 'Nom de l\'usine',
  'Ex: Factory C': 'Ex : Usine C',
  'Ex: Casablanca': 'Ex : Casablanca',
  'Map pin: {lat}, {lng}': 'Épingle : {lat}, {lng}',
  'Pick on map': 'Choisir sur la carte',
  'Number of Conveyors': 'Nombre de convoyeurs',
  'Ex: 3': 'Ex : 3',
  'Factory name is required': 'Le nom de l\'usine est requis',
  'Enter a valid number of conveyors (≥1)':
      'Saisissez un nombre de convoyeurs valide (≥1)',
  'Factory added': 'Usine ajoutée',
  'Edit Factory': 'Modifier l\'usine',
  'Factory updated': 'Usine mise à jour',
  'Add Conveyor': 'Ajouter un convoyeur',
  'Enter conveyor number': 'Saisissez le numéro du convoyeur',
  'Conveyor Number': 'Numéro du convoyeur',
  'Conveyor {n} added': 'Convoyeur {n} ajouté',
  'Edit Conveyor': 'Modifier le convoyeur',
  'Update the conveyor number': 'Mettre à jour le numéro du convoyeur',
  'Conveyor updated': 'Convoyeur mis à jour',
  'Add Station': 'Ajouter un poste',
  'Add stations to Conveyor {n}': 'Ajouter des postes au convoyeur {n}',
  'Current stations: {count}/{max}': 'Postes actuels : {count}/{max}',
  'Remaining: {n}': 'Restant : {n}',
  'Number of Stations to Add': 'Nombre de postes à ajouter',
  'Ex: 2': 'Ex : 2',
  'Maximum: {n} station(s)': 'Maximum : {n} poste(s)',
  'Invalid number': 'Nombre invalide',
  'Added {n} station(s)': '{n} poste(s) ajouté(s)',
  'Delete Factory': 'Supprimer l\'usine',
  'Delete "{name}" and all its conveyors/stations?':
      'Supprimer « {name} » et tous ses convoyeurs/postes ?',
  'Factory deleted': 'Usine supprimée',
  'Cannot delete Conveyor {n}: {count} active alert(s) are still disponible/en_cours.':
      'Impossible de supprimer le convoyeur {n} : {count} alerte(s) active(s) sont encore disponibles/en cours.',
  'Delete Conveyor': 'Supprimer le convoyeur',
  'Delete Conveyor {n} and all its stations?':
      'Supprimer le convoyeur {n} et tous ses postes ?',
  'Conveyor deleted': 'Convoyeur supprimé',
  'Structure & factory floor map': 'Structure et plan de l\'usine',
  'Structure': 'Structure',
  'Factory Mapping': 'Plan de l\'usine',
  'Factories ({n})': 'Usines ({n})',
  'No factories': 'Aucune usine',
  'Conveyors ({n})': 'Convoyeurs ({n})',
  'Select a factory first': 'Sélectionnez d\'abord une usine',
  'No conveyors': 'Aucun convoyeur',
  'Stations ({count}/{max})': 'Postes ({count}/{max})',
  'Add Stations': 'Ajouter des postes',
  'Select a conveyor first': 'Sélectionnez d\'abord un convoyeur',
  'No stations': 'Aucun poste',
  'Generate station QR': 'Générer le QR du poste',
  'Delete station': 'Supprimer le poste',
  'Asset Record': 'Fiche d\'équipement',
  'The hierarchy entry will be removed immediately.':
      'L\'entrée de hiérarchie sera supprimée immédiatement.',
  'Asset {id} will stay under /assets with its last known location and deletion metadata.':
      'L\'équipement {id} restera sous /assets avec sa dernière position connue et ses métadonnées de suppression.',
  'Delete Station': 'Supprimer le poste',
  'QR saved as {name}.png': 'QR enregistré sous {name}.png',
  'Print failed: {error}': 'Échec de l\'impression : {error}',
  'Station QR Code': 'Code QR du poste',
  'Print QR': 'Imprimer le QR',
  'Download PNG': 'Télécharger le PNG',
  'Selected location': 'Emplacement sélectionné',
  'Factory Location': 'Emplacement de l\'usine',
  'Search address': 'Rechercher une adresse',
  'Clear location': 'Effacer l\'emplacement',

  // ── Alerts tree (PM) ──
  'Reset view': 'Réinitialiser la vue',
  '{matching} of {total} nodes match filters':
      '{matching} sur {total} nœuds correspondent aux filtres',
  'Open Alert': 'Ouvrir l\'alerte',
  'Asset History': 'Historique de l\'équipement',
  'Workstation History': 'Historique du poste',
  'No factories configured': 'Aucune usine configurée',
  'Add a factory in the Hierarchy tab to start tracking alerts.':
      'Ajoutez une usine dans l\'onglet Hiérarchie pour commencer à suivre les alertes.',
  'Zoom in': 'Zoom avant',
  'Zoom out': 'Zoom arrière',
  'AI Assignment': 'Affectation IA',
  'Auto-assigning new alerts': 'Affectation automatique des nouvelles alertes',
  'Manual assignment only': 'Affectation manuelle uniquement',
  'Collapse': 'Réduire',
  'Expand': 'Développer',
  'ON': 'ON',
  'OFF': 'OFF',
  'AI-LOGS': 'JOURNAUX-IA',
  'LOCAL FALLBACK': 'REPLI LOCAL',
  'Global AI ON — auto-assignment enabled':
      'IA globale ACTIVÉE — affectation automatique activée',
  'Global AI OFF — manual assignment only':
      'IA globale DÉSACTIVÉE — affectation manuelle uniquement',
  '{n} conveyor': '{n} convoyeur',
  '{n} conveyors': '{n} convoyeurs',
  '{n} station': '{n} poste',
  '{n} stations': '{n} postes',
  '{n} active alert': '{n} alerte active',
  '{n} active alerts': '{n} alertes actives',
  'Healthy': 'Sain',
  '{n}m ago': 'il y a {n} min',
  '{n}h ago': 'il y a {n} h',
  '{n}d ago': 'il y a {n} j',
  'Search factory, conveyor, station…':
      'Rechercher usine, convoyeur, poste…',
  'Tree view': 'Vue arborescente',
  'Heatmap view': 'Vue carte thermique',
  'Open Full Details': 'Ouvrir tous les détails',

  // ── Supervisor collaboration screen ──
  'No Collaboration Requests': 'Aucune demande de collaboration',
  'Your collaboration requests will appear here':
      'Vos demandes de collaboration apparaîtront ici',
  'Cancel Collaboration?': 'Annuler la collaboration ?',
  'This will permanently cancel the request.':
      'Cela annulera définitivement la demande.',
  'Request ID': 'ID de la demande',
  'Members': 'Membres',
  'Alert type': 'Type d\'alerte',
  'Keep': 'Conserver',
  'Cancel Request': 'Annuler la demande',
  'Sent Request': 'Demande envoyée',
  'ID: collab-{id}': 'ID : collab-{id}',
  'Request Sent': 'Demande envoyée',
  'Sent to {names}': 'Envoyée à {names}',
  'Accepted': 'Acceptée',
  'Declined': 'Refusée',
  'Waiting': 'En attente',
  'PM Approval': 'Approbation du responsable',
  'Approved by Production Manager': 'Approuvée par le responsable de production',
  'All assistants declined': 'Tous les assistants ont refusé',
  'Declined by Production Manager': 'Refusée par le responsable de production',
  'All assistants accepted — awaiting PM':
      'Tous les assistants ont accepté — en attente du responsable',
  'Some assistants declined — awaiting PM':
      'Certains assistants ont refusé — en attente du responsable',
  'Waiting for assistants to respond':
      'En attente de la réponse des assistants',
  'PM Approved': 'Approuvée par le responsable',
  'Awaiting you': 'En attente de vous',
  'Collaboration fully approved by Production Manager':
      'Collaboration entièrement approuvée par le responsable de production',
  'You accepted. Waiting for all assistants.':
      'Vous avez accepté. En attente de tous les assistants.',
  'You declined this request.': 'Vous avez refusé cette demande.',
  'Last interaction: {label} - {time}':
      'Dernière interaction : {label} - {time}',
  'accepted': 'accepté',
  'declined': 'refusé',
  'PM approved': 'approuvé par le responsable',
  'rejected': 'rejeté',
  'incoming request': 'demande entrante',
  'approved': 'approuvé',
  'responded': 'répondu',
  'sent request': 'demande envoyée',
  'SELECT SUPERVISOR(S)': 'SÉLECTIONNER SUPERVISEUR(S)',
  'TAGGED': 'IDENTIFIÉS',
  'MESSAGE': 'MESSAGE',
  'Enter your message...': 'Saisissez votre message...',
  'Send Request': 'Envoyer la demande',
  'Collaboration request sent!': 'Demande de collaboration envoyée !',

  // ── Locator + scan (supervisor) ──
  'No factory': 'Aucune usine',
  'No matching factory for {name}.': 'Aucune usine correspondante pour {name}.',
  'Map not configured': 'Plan non configuré',
  'Ask the production manager to build this factory in Hierarchy → Factory Mapping.':
      'Demandez au responsable de production de créer cette usine dans Hiérarchie → Plan de l\'usine.',
  'Focus route': 'Centrer l\'itinéraire',
  'Use entrance': 'Utiliser l\'entrée',
  'Show full map': 'Afficher tout le plan',
  'No active claim': 'Aucune réclamation active',
  'Claim an alert to view its blue route.':
      'Réclamez une alerte pour voir son itinéraire bleu.',
  'Station not on map': 'Poste absent du plan',
  'C{conv}S{poste} has not been placed yet.':
      'C{conv}S{poste} n\'a pas encore été placé.',
  'Live station status': 'État des postes en direct',
  'All mapped stations idle': 'Tous les postes du plan sont au repos',
  'All idle': 'Tous au repos',
  'Web mode: paste QR text or enter the station':
      'Mode web : collez le texte QR ou saisissez le poste',
  'Web Station Lookup': 'Recherche de poste (web)',
  'QR payload or station link': 'Charge QR ou lien du poste',
  'Load QR': 'Charger le QR',
  'Load History': 'Charger l\'historique',
  'No station loaded': 'Aucun poste chargé',
  'Paste a station QR payload or enter a station manually.':
      'Collez une charge QR de poste ou saisissez un poste manuellement.',
  'Could not load history': 'Impossible de charger l\'historique',
  '{n} fixed': '{n} corrigées',
  'No alerts have been recorded at this station.':
      'Aucune alerte n\'a été enregistrée à ce poste.',
  'QR code detected, but it is not a station QR.':
      'Code QR détecté, mais ce n\'est pas un QR de poste.',
  'Rescan': 'Rescanner',
  'Scanner paused': 'Scanner en pause',
  'Open Settings': 'Ouvrir les paramètres',
  'No station scanned': 'Aucun poste scanné',
  'Point the camera at a station QR code above to load its full alert history.':
      'Pointez la caméra vers un code QR de poste ci-dessus pour charger tout son historique d\'alertes.',
  'No alerts have ever been raised at this station. Once one is created it will appear here.':
      'Aucune alerte n\'a jamais été déclenchée à ce poste. Dès qu\'une alerte sera créée, elle apparaîtra ici.',
  'Taken {time}': 'Prise {time}',
  'Station scanned: {usine} / C{conv} / P{poste}':
      'Poste scanné : {usine} / C{conv} / P{poste}',
  'Camera permission permanently denied. Open Settings to enable it.':
      'Autorisation caméra définitivement refusée. Ouvrez les paramètres pour l\'activer.',
  'Camera permission denied.': 'Autorisation caméra refusée.',

  // ── MFA / voice enrollment / factory mapping ──
  'Two-factor authentication': 'Authentification à deux facteurs',
  'Verify your email first': 'Vérifiez d\'abord votre e-mail',
  'Two-factor authentication can only be added after your email ({email}) is verified.':
      'L\'authentification à deux facteurs ne peut être ajoutée qu\'après vérification de votre e-mail ({email}).',
  'Send verification email': 'Envoyer l\'e-mail de vérification',
  'I have verified — continue': 'J\'ai vérifié — continuer',
  'Your account is protected by SMS two-factor authentication.':
      'Votre compte est protégé par l\'authentification à deux facteurs par SMS.',
  'At each sign-in you will be asked for a code sent by text message.':
      'À chaque connexion, un code envoyé par SMS vous sera demandé.',
  'Continue to app': 'Continuer vers l\'application',
  'Add an extra layer of security':
      'Ajoutez une couche de sécurité supplémentaire',
  'We will text a verification code to your phone each time you sign in.':
      'Nous enverrons un code de vérification par SMS à votre téléphone à chaque connexion.',
  'Country': 'Pays',
  'Mobile number': 'Numéro de portable',
  'Send code': 'Envoyer le code',
  'Verification code': 'Code de vérification',
  'Verify & enable': 'Vérifier et activer',
  'Verifying…': 'Vérification…',
  'Change number': 'Changer de numéro',
  'Voiceprint enrolled.': 'Empreinte vocale enregistrée.',
  'Voice Enrollment': 'Enregistrement vocal',
  'Map saved for {name}': 'Plan enregistré pour {name}',
  'Save failed: {error}': 'Échec de l\'enregistrement : {error}',
  'Add a factory in the Structure tab first.':
      'Ajoutez d\'abord une usine dans l\'onglet Structure.',
  'Drag stations onto the grid, then connect each conveyor.':
      'Glissez les postes sur la grille, puis reliez chaque convoyeur.',
  'Entrance': 'Entrée',
  'Place': 'Placer',
  'Connect': 'Relier',
  'Erase': 'Effacer',
  'Undo': 'Annuler',
  'Saved': 'Enregistré',
  '{n} placed': '{n} placés',
  'Drag a chip onto the grid. Live updates from Hierarchy.':
      'Glissez une puce sur la grille. Mises à jour en direct depuis la Hiérarchie.',
  'No conveyors yet': 'Aucun convoyeur pour l\'instant',

  // ── SuperAdmin · Production Managers tab ──
  'PRODUCTION MANAGER ACCOUNTS': 'COMPTES RESPONSABLES DE PRODUCTION',
  '{n} ACTIVE': '{n} ACTIFS',
  'Managers run the admin dashboard: alerts, shifts, supervisors and AI oversight.':
      'Les responsables gèrent le tableau de bord : alertes, équipes, superviseurs et supervision IA.',
  'Search by name, email or plant…':
      'Rechercher par nom, e-mail ou usine…',
  'NEW MANAGER': 'NOUVEAU RESPONSABLE',
  'Cannot load accounts': 'Impossible de charger les comptes',
  'No Production Managers yet': 'Aucun responsable de production pour l\'instant',
  'Create the first manager account — they will land on the admin dashboard at next sign-in.':
      'Créez le premier compte responsable — il accédera au tableau de bord administrateur à la prochaine connexion.',
  'Password reset email sent to {email}':
      'E-mail de réinitialisation du mot de passe envoyé à {email}',
  'Revoke {name}?': 'Révoquer {name} ?',
  'The account record and dashboard access are removed immediately. The Firebase Auth login remains but has no role.':
      'Le compte et l\'accès au tableau de bord sont supprimés immédiatement. La connexion Firebase Auth subsiste mais sans rôle.',
  'Revoke access': 'Révoquer l\'accès',
  'NEW PRODUCTION MANAGER': 'NOUVEAU RESPONSABLE DE PRODUCTION',
  'Provision dashboard access': 'Provisionner l\'accès au tableau de bord',
  'Plant scope (optional)': 'Portée d\'usine (facultatif)',
  'All plants': 'Toutes les usines',
  'CREATING…': 'CRÉATION…',
  'CREATE ACCOUNT': 'CRÉER LE COMPTE',
  'Plant: {usine}': 'Usine : {usine}',
  'Send password reset': 'Envoyer la réinitialisation du mot de passe',

  // ── SuperAdmin · Access & Identity tab ──
  'Single Sign-On': 'Authentification unique (SSO)',
  'Let staff sign in with your company identity provider':
      'Permettez au personnel de se connecter via le fournisseur d\'identité de l\'entreprise',
  'ENABLED': 'ACTIVÉ',
  'DISABLED': 'DÉSACTIVÉ',
  'IDENTITY PROVIDER': 'FOURNISSEUR D\'IDENTITÉ',
  'Enable SSO': 'Activer le SSO',
  'Shows the SSO button on the login screen':
      'Affiche le bouton SSO sur l\'écran de connexion',
  'PROVIDER ID': 'ID DU FOURNISSEUR',
  'Must match the provider you create in Firebase.':
      'Doit correspondre au fournisseur créé dans Firebase.',
  'BUTTON LABEL': 'LIBELLÉ DU BOUTON',
  'ISSUER URL (reference)': 'URL DE L\'ÉMETTEUR (référence)',
  'Save configuration': 'Enregistrer la configuration',
  'Saved. The login screen now reflects this.':
      'Enregistré. L\'écran de connexion est à jour.',
  'Finish in Firebase Identity Platform':
      'Terminer dans Firebase Identity Platform',
  'One-time, server-side — it holds the client secret safely':
      'Une seule fois, côté serveur — il conserve le secret client en sécurité',
  'In the Firebase console → Authentication, enable Identity Platform, then add a provider whose ID matches the Provider ID above. Paste in the client ID, issuer, and client secret from your identity provider, and register this redirect URL:':
      'Dans la console Firebase → Authentication, activez Identity Platform, puis ajoutez un fournisseur dont l\'ID correspond à l\'ID du fournisseur ci-dessus. Collez l\'ID client, l\'émetteur et le secret client de votre fournisseur d\'identité, et enregistrez cette URL de redirection :',
  'Copy redirect URL': 'Copier l\'URL de redirection',
  'New SSO users are created with no role — grant access from Production Managers before they can sign in.':
      'Les nouveaux utilisateurs SSO sont créés sans rôle — accordez l\'accès depuis Responsables de production avant qu\'ils ne puissent se connecter.',
  'Sign in with SSO': 'Se connecter avec le SSO',
  'LOGIN PREVIEW': 'APERÇU DE LA CONNEXION',
  'Staff will see this button beneath the email/password fields.':
      'Le personnel verra ce bouton sous les champs e-mail/mot de passe.',
  'Hidden until you enable SSO above.':
      'Masqué jusqu\'à ce que vous activiez le SSO ci-dessus.',
  'Two-factor authentication (SMS)':
      'Authentification à deux facteurs (SMS)',
  'Add a phone second factor to your own account':
      'Ajoutez un second facteur téléphonique à votre propre compte',
  'Enable SMS multi-factor in Firebase Identity Platform, then enrol your phone here. Staff enrol the same way from their profile.':
      'Activez le multi-facteur SMS dans Firebase Identity Platform, puis enregistrez votre téléphone ici. Le personnel s\'inscrit de la même manière depuis son profil.',
  'Set up / manage 2FA': 'Configurer / gérer la 2FA',

  // ── SuperAdmin · Reliability tab ──
  'Backups': 'Sauvegardes',
  'Nightly snapshot to Cloudflare R2': 'Instantané nocturne vers Cloudflare R2',
  'Last backup': 'Dernière sauvegarde',
  'Size': 'Taille',
  'Error': 'Erreur',
  'Storage and retention are managed in Cloudflare (alertsys-backups, last 30 nightly). See DISASTER_RECOVERY.md.':
      'Le stockage et la rétention sont gérés dans Cloudflare (alertsys-backups, 30 dernières nuits). Voir DISASTER_RECOVERY.md.',
  'PROBING': 'SONDAGE',
  'DEGRADED': 'DÉGRADÉ',
  'NOMINAL': 'NOMINAL',
  'System monitor': 'Moniteur système',
  'Deadman switch · every 5 min': 'Veille automatique · toutes les 5 min',
  'Last check': 'Dernière vérification',
  'All checks passing.': 'Toutes les vérifications réussies.',
  'Alert destination': 'Destination des alertes',
  'Get pinged the moment the system degrades':
      'Soyez averti dès que le système se dégrade',
  'Enable alerts': 'Activer les alertes',
  'Post to your chat tool on every state change':
      'Publier vers votre outil de chat à chaque changement d\'état',
  'PROVIDER': 'FOURNISSEUR',
  'WEBHOOK URL': 'URL DU WEBHOOK',
  'TELEGRAM CHAT ID': 'ID DE CHAT TELEGRAM',
  'App health (today)': 'Santé de l\'app (aujourd\'hui)',
  'Crash-free sessions & error rate — SLA alert below {slo}%':
      'Sessions sans plantage et taux d\'erreur — alerte SLA sous {slo}%',
  'Crash-free': 'Sans plantage',
  'Sessions': 'Sessions',
  'Crashed': 'Plantées',
  'Errors': 'Erreurs',
  'Below SLO — the monitor will alert your webhook.':
      'Sous le SLO — le moniteur alertera votre webhook.',
  'Meeting the {slo}% crash-free SLO.':
      'Respecte le SLO de {slo}% sans plantage.',
  'Collecting data ({n}/20 sessions before SLO alerting).':
      'Collecte de données ({n}/20 sessions avant alerte SLO).',
  'AI worker': 'Worker IA',
  'Assignment / escalation / predictions edge':
      'Affectation / escalade / prédictions (edge)',
  'Notification worker': 'Worker de notifications',
  'Push fan-out edge': 'Diffusion push (edge)',
  'Cron freshness': 'Fraîcheur du cron',
  'The every-minute engine is alive': 'Le moteur à la minute est actif',
  'Nightly snapshot ran and succeeded':
      'L\'instantané nocturne s\'est exécuté avec succès',
  'Error spike': 'Pic d\'erreurs',
  'Surge of client errors in the last hour':
      'Surcharge d\'erreurs clientes durant la dernière heure',
  'Notification backlog': 'Arriéré de notifications',
  'Notify worker keeping up': 'Le worker de notifications suit le rythme',
  'App error budget': 'Budget d\'erreurs de l\'app',
  'Crash-free below the {slo}% SLO': 'Sans plantage sous le SLO de {slo}%',
  'AI model drift': 'Dérive du modèle IA',
  'A deployed agent model regressed in quality':
      'Un modèle d\'agent déployé a régressé en qualité',
  'What gets monitored': 'Ce qui est surveillé',
  'Toggle the checks the deadman switch runs':
      'Activez les vérifications exécutées par la veille automatique',
  'Saved with the Save button above; applied on the next monitor run.':
      'Enregistré avec le bouton ci-dessus ; appliqué à la prochaine exécution du moniteur.',
  'Send test': 'Envoyer un test',
  'Save monitoring settings': 'Enregistrer les paramètres de surveillance',

  // ── SuperAdmin · Branding & Theme tab ──
  'BRANDING & THEME': 'IMAGE DE MARQUE ET THÈME',
  'Logo and color identity, applied across login, supervisor, Production Manager, and SuperAdmin surfaces.':
      'Identité visuelle (logo et couleurs), appliquée à la connexion, au superviseur, au responsable de production et aux interfaces SuperAdmin.',
  'LIVE': 'EN DIRECT',
  'PRIMARY · BRAND': 'PRIMAIRE · MARQUE',
  'App bars, buttons, nav, accents.':
      'Barres d\'app, boutons, navigation, accents.',
  'ACCENT': 'ACCENT',
  'Secondary highlights and gradients.':
      'Surlignages secondaires et dégradés.',
  'LOGO': 'LOGO',
  'Uploaded image.': 'Image téléversée.',
  'Default Smart Industrial Alert mark.':
      'Logo Smart Industrial Alert par défaut.',
  'Logo from URL.': 'Logo depuis une URL.',
  '…or paste an image URL (https://…/logo.png)':
      '…ou collez une URL d\'image (https://…/logo.png)',
  'Backgroundless logo': 'Logo sans arrière-plan',
  'Drop the plate so the logo sits transparently.':
      'Retirez la plaque pour que le logo soit transparent.',
  'Unsaved changes': 'Modifications non enregistrées',
  'All changes applied': 'Toutes les modifications appliquées',
  'Applying…': 'Application…',
  'Apply & Deploy': 'Appliquer et déployer',
  'PALETTE': 'PALETTE',

  // ── SuperAdmin · Infrastructure tab ──
  'Connect your own backend and edge, then deploy your dedicated instance. Secrets go to your pipeline — never the database.':
      'Connectez votre propre backend et edge, puis déployez votre instance dédiée. Les secrets vont vers votre pipeline — jamais dans la base de données.',
  'Firebase project ID': 'ID du projet Firebase',
  'Realtime Database URL': 'URL Realtime Database',
  'Web API key': 'Clé API web',
  'Service account JSON': 'JSON du compte de service',
  'Paste the service-account JSON — sent to your pipeline, never stored':
      'Collez le JSON du compte de service — envoyé à votre pipeline, jamais stocké',
  'CLOUDFLARE & WORKERS': 'CLOUDFLARE ET WORKERS',
  'Account ID': 'ID du compte',
  'workers.dev subdomain': 'Sous-domaine workers.dev',
  'R2 bucket': 'Bucket R2',
  'Cloudflare API token': 'Jeton API Cloudflare',
  'Worker shared secret': 'Secret partagé du worker',
  'WORKERS · OUR EXACT SETUP': 'WORKERS · NOTRE CONFIGURATION EXACTE',
  'DATABASE · YOUR FIREBASE': 'BASE DE DONNÉES · VOTRE FIREBASE',
  'SCIM PROVISIONING': 'PROVISIONNEMENT SCIM',
  'Point your IdP (Okta / Entra) SCIM connector here with the token below to auto-provision and deprovision users.':
      'Pointez le connecteur SCIM de votre IdP (Okta / Entra) ici avec le jeton ci-dessous pour provisionner et déprovisionner automatiquement les utilisateurs.',
  'SCIM bearer token': 'Jeton bearer SCIM',
  'SCIM base URL': 'URL de base SCIM',
  'set subdomain first': 'définissez d\'abord le sous-domaine',
  'DEPLOY': 'DÉPLOYER',
  'Deploy fires a GitHub repository_dispatch to the deploy-instance workflow, which provisions and deploys your 5 workers + R2 + database rules. Only non-secret config is sent — set the secrets once in GitHub Actions with the button below.':
      'Le déploiement déclenche un repository_dispatch GitHub vers le workflow deploy-instance, qui provisionne et déploie vos 5 workers + R2 + règles de base de données. Seule la config non secrète est envoyée — définissez les secrets une fois dans GitHub Actions avec le bouton ci-dessous.',
  'Deploy webhook URL': 'URL du webhook de déploiement',
  'GitHub token (repo scope)': 'Jeton GitHub (portée repo)',
  'Copy GitHub secret commands': 'Copier les commandes de secrets GitHub',
  'Last deploy: {at} · {status}': 'Dernier déploiement : {at} · {status}',
  'Save config': 'Enregistrer la config',
  'Deploy instance': 'Déployer l\'instance',
  'Deploying…': 'Déploiement…',
  'DEPLOYED': 'DÉPLOYÉ',
  'DEPLOY FAILED': 'ÉCHEC DU DÉPLOIEMENT',
  'write-only': 'écriture seule',

  // ── SuperAdmin · AI Training tab ──
  'DEPLOYED FORECAST MODEL': 'MODÈLE DE PRÉVISION DÉPLOYÉ',
  'No model deployed yet — every dashboard is waiting for its first model.':
      'Aucun modèle déployé — chaque tableau de bord attend son premier modèle.',
  'Gradient-boosted trees serving live next-24h forecasts on all Production Manager dashboards.':
      'Arbres à gradient boosté servant des prévisions 24h en direct sur tous les tableaux de bord des responsables.',
  'OFFLINE': 'HORS LIGNE',
  'LEARNING VERIFIED': 'APPRENTISSAGE VÉRIFIÉ',
  'CONTINUOUS LEARNING': 'APPRENTISSAGE CONTINU',
  'TRAINING DATA INTAKE': 'INGESTION DES DONNÉES D\'ENTRAÎNEMENT',
  'HYPERPARAMETERS': 'HYPERPARAMÈTRES',
  'AUTO-TUNE': 'AUTO-RÉGLAGE',
  'TRAINING MONITOR': 'MONITEUR D\'ENTRAÎNEMENT',
  'FORECAST PREVIEW — NEXT 24H': 'APERÇU DES PRÉVISIONS — 24 PROCHAINES HEURES',
  'No machines with enough history to forecast.':
      'Aucune machine avec un historique suffisant pour prévoir.',
  'TRAINING…': 'ENTRAÎNEMENT…',
  'START TRAINING': 'DÉMARRER L\'ENTRAÎNEMENT',
  'STOP': 'ARRÊTER',

  // ── AI logs panel (shared) ──
  'AI settings — enable/disable per factory':
      'Paramètres IA — activer/désactiver par usine',
  'Close panel': 'Fermer le panneau',
  'Skip': 'Ignoré',
  'Rec': 'Reco',
  'Abort': 'Abandonner',
  'Rej': 'Rejet',
  'Clear logs': 'Effacer les journaux',
  'Abort AI assignment?': 'Abandonner l\'affectation IA ?',
  'This will remove {name} from "{label}" and return the alert to the queue. AI will keep running for future alerts.':
      'Cela retirera {name} de « {label} » et remettra l\'alerte en file. L\'IA continuera pour les futures alertes.',
  'the supervisor': 'le superviseur',
  'AI assignment aborted — alert returned to queue':
      'Affectation IA abandonnée — alerte remise en file',
  'Recommendation approved and assigned':
      'Recommandation approuvée et assignée',
  'Recommendation is no longer pending':
      'La recommandation n\'est plus en attente',
  'Decline recommendation?': 'Refuser la recommandation ?',
  'This will reject the AI cross-factory transfer recommendation for this alert.':
      'Cela rejettera la recommandation de transfert inter-usines de l\'IA pour cette alerte.',
  'Open alert': 'Ouvrir l\'alerte',
  'Failed to save: {error}': 'Échec de l\'enregistrement : {error}',
  'AI Assignment Settings': 'Paramètres d\'affectation IA',
  'Enable auto-assignment per factory':
      'Activer l\'affectation automatique par usine',
  'No factories configured.': 'Aucune usine configurée.',
  'AI Activity': 'Activité IA',
  'No AI activity yet': 'Aucune activité IA pour l\'instant',
  'AI summary': 'Résumé IA',
  'Why this supervisor': 'Pourquoi ce superviseur',
  'Why not others': 'Pourquoi pas les autres',

  // ── SuperAdmin · AI Agents fleet ──
  'SHIFT COMMANDER': 'COMMANDANT D\'ÉQUIPE',
  'Runs shifts: AI assignments, collaborations, handovers':
      'Gère les équipes : affectations IA, collaborations, passations',
  'BRIEFING OFFICER': 'OFFICIER DE BRIEFING',
  'Writes the morning briefings every PM reads':
      'Rédige les briefings du matin que chaque responsable lit',
  'AI ASSIST': 'ASSISTANT IA',
  'Suggests resolutions to supervisors from past fixes':
      'Suggère des résolutions aux superviseurs à partir des corrections passées',
  'SECURITY SENTINEL': 'SENTINELLE DE SÉCURITÉ',
  'Blocks injections, floods and anomalies at the edge':
      'Bloque les injections, les floods et les anomalies à l\'edge',
  'PREDICTIVE CORE': 'CŒUR PRÉDICTIF',
  'Forecasts machine failures and grades itself daily':
      'Prévoit les pannes machine et s\'auto-évalue chaque jour',
  'GUARDIAN': 'GARDIEN',
  'Under maintenance — capabilities not yet disclosed':
      'En maintenance — capacités non encore divulguées',
  '{name} is OFFLINE. The edge worker skips its duties until you re-enable it; history below stays readable.':
      '{name} est HORS LIGNE. Le worker edge ignore ses tâches jusqu\'à réactivation ; l\'historique ci-dessous reste lisible.',
  '{name} is back online.': '{name} est de nouveau en ligne.',
  '{name} taken offline — the worker stands down within 60s.':
      '{name} mis hors ligne — le worker s\'arrête sous 60 s.',
  'Could not update {name}: {error}':
      'Impossible de mettre à jour {name} : {error}',
  '{name} deployed to the fleet.': '{name} déployé dans la flotte.',
  '{name} updated.': '{name} mis à jour.',
  'Could not save agent: {error}':
      'Impossible d\'enregistrer l\'agent : {error}',
  '{name} decommissioned and wiped.': '{name} retiré du service et effacé.',
  'Delete failed: {error}': 'Échec de la suppression : {error}',
  'AI AGENT FLEET': 'FLOTTE D\'AGENTS IA',
  'Six autonomous units · toggles propagate to the edge worker within 60 seconds':
      'Six unités autonomes · les bascules se propagent au worker edge sous 60 secondes',
  '{online}/{total} UNITS ONLINE': '{online}/{total} UNITÉS EN LIGNE',
  'EDGE LINK LIVE': 'LIAISON EDGE ACTIVE',
  'EDGE LINK STALE': 'LIAISON EDGE PÉRIMÉE',
  '{count} ASSIGNED · LAST CRON': '{count} AFFECTÉS · DERNIER CRON',
  '{count} THREATS BLOCKED': '{count} MENACES BLOQUÉES',
  'MAINTENANCE': 'MAINTENANCE',
  'ONLINE': 'EN LIGNE',
  'DEPLOY AGENT': 'DÉPLOYER UN AGENT',
  'Add a unit to the fleet': 'Ajouter une unité à la flotte',
  '{n}s ago': 'il y a {n} s',
  'Assignments': 'Affectations',
  'Handovers': 'Passations',
  'Presence checks': 'Vérifications de présence',
  'Blocked / skipped': 'Bloqué / ignoré',
  'Other': 'Autre',
  'COMMAND DECK': 'POSTE DE COMMANDE',
  'BRAIN': 'CERVEAU',
  'MODEL ENGINE': 'MOTEUR DE MODÈLE',
  'Actions · 24h': 'Actions · 24 h',
  'Assignments · last cron': 'Affectations · dernier cron',
  'Collabs · last cron': 'Collaborations · dernier cron',
  'Handovers · last cron': 'Passations · dernier cron',
  'Last pulse': 'Dernière pulsation',
  'TASK BREAKDOWN': 'RÉPARTITION DES TÂCHES',
  'Distribution of the commander’s recent decisions.':
      'Répartition des décisions récentes du commandant.',
  'No shift AI activity recorded yet.':
      'Aucune activité IA d\'équipe enregistrée pour l\'instant.',
  'ACTION LOG': 'JOURNAL D\'ACTIONS',
  'Tap any entry for the full unredacted reasoning, confidence and gate diagnostics.':
      'Appuyez sur une entrée pour voir le raisonnement complet, la confiance et les diagnostics de porte.',
  'Cannot read shift AI logs': 'Impossible de lire les journaux IA d\'équipe',
  'No actions yet': 'Aucune action pour l\'instant',
  'The commander logs here the moment a shift with AI Commander enabled goes live.':
      'Le commandant journalise ici dès qu\'une équipe avec Commandant IA activé démarre.',

  // ── AI Agents fleet · Shift Commander brain ──
  'Every decision the AI commander takes across active shifts — assignments, collaborations, handovers, presence.':
      'Chaque décision prise par le commandant IA sur les équipes actives — affectations, collaborations, passations, présence.',
  'Almost every factor is near zero — the commander has little left to weigh, so picks become close to random.':
      'Presque tous les facteurs sont proches de zéro — il ne reste presque rien au commandant pour décider, les choix deviennent quasi aléatoires.',
  '“{label}” is switched off — it no longer sways the decision.':
      '« {label} » est désactivé — il n\'influence plus la décision.',
  'One factor dominates everything else — the commander will mostly ignore the rest.':
      'Un facteur domine tous les autres — le commandant ignorera presque tout le reste.',
  'Factory fit is near zero — supervisors from any plant score the same, so alerts can land on a distant factory.':
      'L\'adéquation usine est proche de zéro — les superviseurs de n\'importe quelle usine obtiennent le même score, les alertes peuvent atterrir sur une usine éloignée.',
  'Load balancing is off — a single supervisor can be piled with every new alert.':
      'L\'équilibrage de charge est désactivé — un seul superviseur peut se voir attribuer toutes les nouvelles alertes.',
  'Distance cap barely counts — the commander may pull supervisors from far-away plants.':
      'Le plafond de distance ne compte presque pas — le commandant peut faire appel à des superviseurs d\'usines très éloignées.',
  'Proximity barely counts — distant supervisors compete as if they were next door.':
      'La proximité ne compte presque pas — des superviseurs éloignés sont en compétition comme s\'ils étaient à côté.',
  'Assistant consensus barely counts — collaborations may be approved before everyone agrees.':
      'Le consensus des assistants ne compte presque pas — des collaborations peuvent être approuvées avant que tout le monde soit d\'accord.',
  'Check the {tab} weighting': 'Vérifier la pondération « {tab} »',
  'These settings may make the Shift Commander behave in ways you might not expect:':
      'Ces réglages peuvent faire agir le Commandant d\'équipe de façon inattendue :',
  'Reset to defaults': 'Réinitialiser aux valeurs par défaut',
  'Keep anyway': 'Conserver quand même',
  'INSIDE THE COMMANDER’S MIND': 'DANS L\'ESPRIT DU COMMANDANT',
  'COGNITION': 'COGNITION',
  'WHAT HE KNOWS': 'CE QU\'IL SAIT',
  'The memory the commander carries into each decision.':
      'La mémoire que le commandant porte dans chaque décision.',
  'Supervisors profiled': 'Superviseurs profilés',
  'Decisions in memory': 'Décisions en mémoire',
  'Signals learned': 'Signaux appris',
  'Avg confidence': 'Confiance moyenne',
  'REASONING FACTORS': 'FACTEURS DE RAISONNEMENT',
  '{count} WARNINGS': '{count} AVERTISSEMENTS',
  '{count} WARNING': '{count} AVERTISSEMENT',
  'Drag any bar to retune — changes feed the Shift Commander’s live assignment scoring instantly.':
      'Faites glisser une barre pour réajuster — les changements alimentent instantanément le score d\'affectation en direct du Commandant d\'équipe.',
  'Drag any bar to retune — changes save to the Shift Commander instantly.':
      'Faites glisser une barre pour réajuster — les changements sont enregistrés instantanément pour le Commandant d\'équipe.',
  'LEARNED SIGNALS': 'SIGNAUX APPRIS',
  'Per-supervisor reinforcement from accepted, rejected and resolved assignments.':
      'Renforcement par superviseur à partir des affectations acceptées, rejetées et résolues.',
  'Nothing learned yet': 'Rien appris pour l\'instant',
  'Once supervisors accept or reject AI assignments, the commander starts tuning their rank here.':
      'Dès que les superviseurs acceptent ou rejettent des affectations IA, le commandant commence à ajuster leur classement ici.',
  'THOUGHT REPLAY': 'REJEU DES PENSÉES',
  'Recent decisions — the situation, the pick, the confidence, the reasoning.':
      'Décisions récentes — la situation, le choix, la confiance, le raisonnement.',
  'No thoughts yet': 'Aucune pensée pour l\'instant',
  'When a shift with AI Commander goes live, each decision replays here.':
      'Quand une équipe avec Commandant IA démarre, chaque décision se rejoue ici.',
  '{message}  (+{extra} more)': '{message}  (+{extra} de plus)',
  'Review': 'Examiner',
  'Decision': 'Décision',

  // ── AI Agents fleet · Briefing Officer ──
  'BRIEFING DESK': 'BUREAU DE BRIEFING',
  'Writes the factory-aware morning briefing each Production Manager wakes up to.':
      'Rédige le briefing matinal contextualisé par usine que chaque responsable de production découvre au réveil.',
  'REGENERATE NOW': 'RÉGÉNÉRER MAINTENANT',
  'Briefings archived': 'Briefings archivés',
  'Factory scopes': 'Périmètres d\'usine',
  'Generated total': 'Total généré',
  'Last generated': 'Dernière génération',
  'LATEST DISPATCH': 'DERNIER ENVOI',
  'The exact words the PMs are reading right now.':
      'Les mots exacts que lisent actuellement les responsables de production.',
  'No briefing yet today': 'Aucun briefing aujourd\'hui pour l\'instant',
  'No briefing yet for {factory}': 'Aucun briefing pour {factory} pour l\'instant',
  'The officer writes the first dispatch when a PM opens their dashboard (or hit REGENERATE NOW).':
      'L\'officier rédige le premier envoi quand un responsable de production ouvre son tableau de bord (ou via RÉGÉNÉRER MAINTENANT).',
  'MODEL ACCURACY {pct}%': 'PRÉCISION DU MODÈLE {pct}%',
  'ALL FACTORIES': 'TOUTES LES USINES',

  // ── AI Agents fleet · AI Assist ──
  'CO-PILOT STATUS': 'ÉTAT DU COPILOTE',
  'Serves resolution suggestions to supervisors, grounded in this plant’s real past fixes.':
      'Fournit des suggestions de résolution aux superviseurs, fondées sur les corrections réelles passées de cette usine.',
  'Suggestions served': 'Suggestions fournies',
  'Last served': 'Dernière fournie',
  'Knowledge entries': 'Entrées de connaissance',
  'Prompt': 'Invite',
  'CUSTOM': 'PERSONNALISÉ',
  'FACTORY DEFAULT': 'PAR DÉFAUT USINE',
  'PROMPT LAB': 'LABORATOIRE D\'INVITES',
  'The exact instruction sent to Llama on Cloudflare for every suggestion. Edit, deploy, or revert to the factory default.':
      'L\'instruction exacte envoyée à Llama sur Cloudflare pour chaque suggestion. Modifiez, déployez, ou revenez à la valeur par défaut.',
  'OVERRIDE ACTIVE': 'SURCHARGE ACTIVE',
  'DEFAULT': 'PAR DÉFAUT',
  'Human-readable alert type': 'Type d\'alerte lisible',
  'Supervisor’s sanitized description': 'Description nettoyée du superviseur',
  'Factory name': 'Nom de l\'usine',
  'Conveyor line number': 'Numéro de ligne de convoyeur',
  'Workstation number': 'Numéro de poste',
  'Block of past resolutions for this exact location':
      'Bloc des résolutions passées pour cet emplacement exact',
  'DEPLOY PROMPT': 'DÉPLOYER L\'INVITE',
  'REVERT TO DEFAULT': 'REVENIR PAR DÉFAUT',
  'KNOWLEDGE BASE': 'BASE DE CONNAISSANCES',
  'What the agent learns from: the latest validated resolutions it cites when supervisors ask for help.':
      'Ce dont l\'agent s\'inspire : les dernières résolutions validées qu\'il cite quand les superviseurs demandent de l\'aide.',
  'No learned fixes yet': 'Aucune correction apprise pour l\'instant',
  'Resolved alerts with a written resolution become this agent’s study material automatically.':
      'Les alertes résolues avec une résolution écrite deviennent automatiquement le matériel d\'étude de cet agent.',
  'SERVICE LOG': 'JOURNAL DE SERVICE',
  'Recent suggestion requests answered at the edge.':
      'Demandes de suggestion récentes traitées à l\'edge.',
  'No requests logged yet — entries appear the moment a supervisor asks for an AI suggestion.':
      'Aucune demande journalisée pour l\'instant — les entrées apparaissent dès qu\'un superviseur demande une suggestion IA.',
  '{prefix} · {count} past fixes cited': '{prefix} · {count} corrections passées citées',

  // ── AI Agents fleet · shared model engine panel ──
  '{label} needs an API key — paste it first.':
      '{label} nécessite une clé API — collez-la d\'abord.',
  'Model saved — {label}. Live within 60s.':
      'Modèle enregistré — {label}. Actif dans les 60 s.',
  '{label} needs an API key to test.':
      '{label} nécessite une clé API pour tester.',
  'Test failed: {error}': 'Échec du test : {error}',
  'Drift detected — {reason}': 'Dérive détectée — {reason}',
  'quality regressed': 'qualité en régression',
  'Quality stable · {pct}%{baseline}': 'Qualité stable · {pct}%{baseline}',
  ' vs {pct}% baseline': ' contre {pct}% de référence',
  'checked {time}': 'vérifié {time}',
  'Choose which AI model writes this agent’s output. Llama runs free on the edge; any other provider uses your own API key — stored in a SuperAdmin-only node and used edge-side only.':
      'Choisissez le modèle IA qui rédige la sortie de cet agent. Llama tourne gratuitement à l\'edge ; tout autre fournisseur utilise votre propre clé API — stockée dans un nœud réservé au SuperAdmin et utilisée uniquement côté edge.',
  'BRING-YOUR-OWN-KEY': 'CLÉ PERSONNELLE',
  'BUILT-IN': 'INTÉGRÉ',
  '{label} — API key': '{label} — clé API',
  'Paste your {provider} API key': 'Collez votre clé API {provider}',
  'Show': 'Afficher',
  'Hide': 'Masquer',
  'The key is read only by the edge worker and SuperAdmin. It never reaches supervisor or PM devices. If a call fails, the agent falls back to built-in Llama automatically.':
      'La clé n\'est lue que par le worker edge et le SuperAdmin. Elle n\'atteint jamais les appareils des superviseurs ou des responsables de production. Si un appel échoue, l\'agent revient automatiquement à Llama intégré.',
  'Built-in Llama 3.2 runs on Cloudflare Workers AI — no API key, no extra cost. Pick another provider above to use a stronger model.':
      'Llama 3.2 intégré tourne sur Cloudflare Workers AI — pas de clé API, pas de coût supplémentaire. Choisissez un autre fournisseur ci-dessus pour un modèle plus puissant.',
  'TEST THIS MODEL': 'TESTER CE MODÈLE',
  'SAVE MODEL': 'ENREGISTRER LE MODÈLE',
  'Running both models on golden tasks and scoring them…':
      'Exécution des deux modèles sur des tâches de référence et notation en cours…',
  'built-in': 'intégré',
  'BETTER — safe to deploy': 'MEILLEUR — déploiement sûr',
  'WORSE — keep current': 'MOINS BON — garder l\'actuel',
  'SIMILAR — no real gain': 'SIMILAIRE — pas de gain réel',
  'This model': 'Ce modèle',
  'Current · {model}': 'Actuel · {model}',
  'Both models ran the same golden tasks; we score grounding, structure, on-topic accuracy and length. Higher is better.':
      'Les deux modèles ont exécuté les mêmes tâches de référence ; nous notons l\'ancrage factuel, la structure, la pertinence et la longueur. Plus c\'est haut, mieux c\'est.',
  'default · no key': 'par défaut · sans clé',

  // ── AI Agents fleet · Security Sentinel ──
  'Defense disabled. The edge worker drops this shield within 60s — re-arm it when done testing.':
      'Défense désactivée. Le worker edge désactive ce bouclier dans les 60 s — réarmez-le une fois les tests terminés.',
  'THREAT CONSOLE': 'CONSOLE DES MENACES',
  'Standing guard on every worker endpoint. Blocks are logged with the exact signature that fired.':
      'Veille active sur chaque point d\'accès du worker. Les blocages sont journalisés avec la signature exacte déclenchée.',
  '{armed}/{total} DEFENSES ARMED': '{armed}/{total} DÉFENSES ARMÉES',
  'Blocks · 24h': 'Blocages · 24 h',
  'Actions · last cron': 'Actions · dernier cron',
  'Attack signatures': 'Signatures d\'attaque',
  'Last block': 'Dernier blocage',
  'DEFENSE GRID': 'GRILLE DE DÉFENSE',
  'Arm or stand down individual shields. Changes reach the edge worker within 60 seconds.':
      'Armez ou désarmez chaque bouclier individuellement. Les changements atteignent le worker edge dans les 60 secondes.',
  'THREAT MIX · 24H': 'RÉPARTITION DES MENACES · 24 H',
  'What the sentinel has been deflecting.': 'Ce que la sentinelle a repoussé.',
  'Clean skies — no blocks in the last 24 hours.':
      'Ciel dégagé — aucun blocage lors des dernières 24 heures.',
  'ENFORCEMENT LOG': 'JOURNAL D\'APPLICATION',
  'Every block with endpoint, fingerprint and matched patterns. Tap for the full record.':
      'Chaque blocage avec point d\'accès, empreinte et motifs détectés. Touchez pour le détail complet.',
  'Cannot read security actions': 'Impossible de lire les actions de sécurité',
  'No enforcement actions': 'Aucune action d\'application',
  'The sentinel has not needed to block anything yet.':
      'La sentinelle n\'a encore rien eu à bloquer.',

  // ── AI Agents fleet · Predictive Core ──
  'MODEL CORE': 'CŒUR DU MODÈLE',
  'On-device gradient-boosted forecaster, live on every Production Manager dashboard.':
      'Prévisionniste à gradient-boosting sur l\'appareil, actif sur chaque tableau de bord responsable de production.',
  'No model deployed yet — train one in the AI Training tab.':
      'Aucun modèle déployé pour l\'instant — entraînez-en un dans l\'onglet Entraînement IA.',
  'LEARNING ✓': 'APPRENTISSAGE ✓',
  'Dataset': 'Jeu de données',
  'Training samples': 'Échantillons d\'entraînement',
  'Boosted rounds': 'Cycles de boosting',
  '{rounds} + {adapted} adapted': '{rounds} + {adapted} adaptés',
  'Val accuracy': 'Précision de validation',
  'Machines forecast': 'Machines prévues',
  'Trained': 'Entraîné',
  'The core snapshots tomorrow’s forecast daily, grades itself against the alerts that really happened, and boosts adaptation trees on fresh data.':
      'Le cœur capture chaque jour la prévision de demain, s\'auto-évalue par rapport aux alertes réellement survenues, et ajoute des arbres d\'adaptation sur des données fraîches.',
  'AWAITING FIRST GRADE': 'EN ATTENTE DE LA PREMIÈRE NOTE',
  '{count} DAYS GRADED': '{count} JOURS NOTÉS',
  'PRECISION': 'PRÉCISION',
  'RECALL': 'RAPPEL',
  'BRIER': 'BRIER',
  'FORECAST QUALITY TREND · BRIER PER GRADED DAY':
      'TENDANCE DE QUALITÉ DES PRÉVISIONS · BRIER PAR JOUR NOTÉ',
  'Trend appears after the first graded day.':
      'La tendance apparaît après le premier jour noté.',
  'DATA ABSORPTION · ADAPTATION BUDGET': 'ABSORPTION DE DONNÉES · BUDGET D\'ADAPTATION',
  '{adapted} / 60 extra trees per type': '{adapted} / 60 arbres supplémentaires par type',
  'Graded {pairs} machine-type pairs · {hits} confirmed hits · last adapted {time} · a full retrain resets the budget.':
      '{pairs} paires machine-type notées · {hits} succès confirmés · dernière adaptation {time} · un réentraînement complet réinitialise le budget.',
  'LEARNING CONTROLS': 'CONTRÔLES D\'APPRENTISSAGE',
  'Pause parts of the learning loop without undeploying the model.':
      'Mettez en pause des parties de la boucle d\'apprentissage sans retirer le modèle.',
  'Continuous adaptation': 'Adaptation continue',
  'Boost a few stiffly-regularized trees onto the live ensemble (~daily) from recent production alerts.':
      'Ajoute quelques arbres fortement régularisés à l\'ensemble en direct (~quotidien) à partir des alertes de production récentes.',
  'Outcome grading': 'Notation des résultats',
  'Snapshot tomorrow’s forecast each day and grade it against reality (precision/recall/Brier above).':
      'Capture la prévision de demain chaque jour et la note par rapport à la réalité (précision/rappel/Brier ci-dessus).',
  'GRADED DAYS': 'JOURS NOTÉS',
  'Each elapsed forecast day, scored against the alerts that materialized.':
      'Chaque jour de prévision écoulé, noté par rapport aux alertes survenues.',
  'No graded days yet': 'Aucun jour noté pour l\'instant',
  'The first grade lands the day after a forecast snapshot — fully automatic, server-side.':
      'La première note arrive le lendemain d\'une capture de prévision — entièrement automatique, côté serveur.',
  '{day} · {pairs} pairs · {hits} hits · Brier {brier}':
      '{day} · {pairs} paires · {hits} succès · Brier {brier}',
  'INSIDE THE FORECASTER’S MIND': 'DANS L\'ESPRIT DU PRÉVISIONNISTE',
  'A gradient-boosted ensemble — hundreds of decision trees, rendered as one rotating neural mesh.':
      'Un ensemble à gradient-boosting — des centaines d\'arbres de décision, rendus comme un maillage neuronal tournant.',
  'No model deployed yet — train one in the AI Training tab to wake the mind.':
      'Aucun modèle déployé pour l\'instant — entraînez-en un dans l\'onglet Entraînement IA pour éveiller l\'esprit.',
  'It studies the last weeks of alerts, learns which machines tend to fail and when, then forecasts each machine’s risk for the next 24 hours — a weather forecast for the factory ({machines} machines covered).':
      'Il étudie les alertes des dernières semaines, apprend quelles machines ont tendance à tomber en panne et quand, puis prévoit le risque de chaque machine pour les 24 prochaines heures — une météo pour l\'usine ({machines} machines couvertes).',
  'Once a model is trained, it forecasts each machine’s risk for the next 24 hours — like a weather forecast for the factory.':
      'Une fois un modèle entraîné, il prévoit le risque de chaque machine pour les 24 prochaines heures — comme une météo pour l\'usine.',
  'MODEL ANATOMY': 'ANATOMIE DU MODÈLE',
  'Four boosted ensembles — one prediction head per alert type.':
      'Quatre ensembles boostés — une tête de prédiction par type d\'alerte.',
  'Adapted trees': 'Arbres adaptés',
  'SIGNALS IT READS': 'SIGNAUX LUS',
  'The engineered features each machine-day is scored on.':
      'Les caractéristiques élaborées sur lesquelles chaque jour-machine est noté.',
  'SELF-ASSESSMENT': 'AUTO-ÉVALUATION',
  'How the model grades its own forecasts against reality.':
      'Comment le modèle note ses propres prévisions par rapport à la réalité.',
  'No grades yet': 'Aucune note pour l\'instant',
  'The first self-grade lands the day after a forecast snapshot — fully automatic.':
      'La première auto-note arrive le lendemain d\'une capture de prévision — entièrement automatique.',
  'Precision': 'Précision',
  'Recall': 'Rappel',
  'Brier score': 'Score de Brier',
  'Days graded': 'Jours notés',
  'ensemble': 'ensemble',

  // ── AI Agents fleet · Guardian ──
  'autonomous fix pipeline': 'pipeline de correction autonome',
  'Automatic': 'Automatique',
  'Human review': 'Revue humaine',
  'ARMED': 'ARMÉ',
  'Connected - waiting for live sync': 'Connecté - en attente de synchronisation en direct',
  'AI CONFIGURATION': 'CONFIGURATION IA',
  'Fix AI': 'IA de correction',
  'Review AI': 'IA de revue',
  'Auto-select model by severity': 'Sélection automatique du modèle selon la sévérité',
  '{title} API key': 'Clé API {title}',
  '•••••••• set': '•••••••• définie',
  'set API key': 'définir la clé API',
  'GITHUB CONNECTION': 'CONNEXION GITHUB',
  'link repository (owner/name)': 'lier un dépôt (propriétaire/nom)',
  'GitHub token': 'Jeton GitHub',
  'set token': 'définir le jeton',
  'Verify connection': 'Vérifier la connexion',
  'contacting GitHub…': 'contact de GitHub…',
  'Guardian proxy check failed before credentials were verified: {error}':
      'La vérification du proxy Guardian a échoué avant la vérification des identifiants : {error}',
  'KNOWLEDGE · upload .md': 'CONNAISSANCES · charger un .md',
  'Instructions': 'Instructions',
  'Skills': 'Compétences',
  'Upload .md': 'Charger un .md',
  'custom endpoint': 'point d\'accès personnalisé',
  'Link GitHub repository': 'Lier un dépôt GitHub',
  'owner/repository': 'propriétaire/dépôt',
  'GitHub repository cleared.': 'Dépôt GitHub effacé.',
  'Invalid GitHub repository. Use owner/name or a GitHub URL.':
      'Dépôt GitHub invalide. Utilisez propriétaire/nom ou une URL GitHub.',
  'Enable automatic deployment?': 'Activer le déploiement automatique ?',
  'Guardian will ship fixes with no human in the loop':
      'Guardian déploiera des correctifs sans intervention humaine',
  'Verified AI fixes are pushed straight to ': 'Les correctifs IA vérifiés sont poussés directement sur ',
  ' — no pull request, no review.': ' — pas de pull request, pas de revue.',
  'Each healed commit ': 'Chaque commit corrigé ',
  'auto-deploys to production': 'se déploie automatiquement en production',
  ' (web + app builds).': ' (builds web + app).',
  'A person is only notified ': 'Une personne n\'est notifiée ',
  'after the fact': 'qu\'après coup',
  ', or when a fix fails to verify.': ', ou quand un correctif échoue à la vérification.',
  'A safety-restore still protects ': 'Une restauration de sécurité protège toujours ',
  ' if a fix can’t be validated.': ' si un correctif ne peut être validé.',
  'Recommended only once you trust the Fix + Review AI pairing on your codebase.':
      'Recommandé uniquement une fois que vous faites confiance au tandem IA de correction + revue sur votre code.',
  'Keep human review': 'Conserver la revue humaine',
  'Enable automatic': 'Activer l\'automatique',

  // ── AI Agents fleet · custom agent panel + editor ──
  'NO CREDENTIAL ON FILE': 'AUCUN IDENTIFIANT ENREGISTRÉ',
  'CUSTOM UNIT': 'UNITÉ PERSONNALISÉE',
  'Provider': 'Fournisseur',
  'Model': 'Modèle',
  'Credential': 'Identifiant',
  'MISSING': 'MANQUANT',
  'ON FILE': 'ENREGISTRÉ',
  'Deployed': 'Déployé',
  'EDIT AGENT': 'MODIFIER L\'AGENT',
  'DELETE': 'SUPPRIMER',
  'PROFILE': 'PROFIL',
  'Who this agent is and what it stands for.':
      'Qui est cet agent et ce qu\'il représente.',
  'No description provided.': 'Aucune description fournie.',
  'MISSION BRIEF': 'BRIEF DE MISSION',
  'The tasks this agent is responsible for.': 'Les tâches dont cet agent est responsable.',
  'No tasks defined yet — edit the agent to brief it.':
      'Aucune tâche définie pour l\'instant — modifiez l\'agent pour le briefer.',
  'SKILLS & CAPABILITIES': 'COMPÉTENCES ET CAPACITÉS',
  'What this agent knows how to do.': 'Ce que cet agent sait faire.',
  'No skills listed yet.': 'Aucune compétence listée pour l\'instant.',
  'CREDENTIALS': 'IDENTIFIANTS',
  'The LLM provider and API token this agent authenticates with.':
      'Le fournisseur LLM et le jeton API avec lesquels cet agent s\'authentifie.',
  'Default model': 'Modèle par défaut',
  'Reveal': 'Révéler',
  'Token copied to clipboard.': 'Jeton copié dans le presse-papiers.',
  'Stored separately in a superadmin-only credential vault. Treat it as a secret — rotate it from EDIT AGENT if it leaks.':
      'Stocké séparément dans un coffre d\'identifiants réservé au SuperAdmin. Traitez-le comme un secret — faites-le tourner depuis MODIFIER L\'AGENT s\'il est exposé.',
  'DEPLOY NEW AGENT': 'DÉPLOYER UN NOUVEL AGENT',
  'Configure a custom autonomous unit for the fleet':
      'Configurer une unité autonome personnalisée pour la flotte',
  'IDENTITY': 'IDENTITÉ',
  'Agent name (e.g. Quality Inspector)': 'Nom de l\'agent (ex. Inspecteur Qualité)',
  'Codename (optional, e.g. UNIT-07 · SENTRY)':
      'Nom de code (facultatif, ex. UNITÉ-07 · SENTRY)',
  'Short description of what this agent is for':
      'Brève description du rôle de cet agent',
  'APPEARANCE': 'APPARENCE',
  'MISSION · TASKS': 'MISSION · TÂCHES',
  'Describe the tasks, or attach a brief / spec file.':
      'Décrivez les tâches, ou joignez un brief / fichier de spécification.',
  'e.g. Review incoming quality alerts, draft a containment checklist…':
      'ex. Examiner les alertes qualité entrantes, rédiger une checklist de confinement…',
  'SKILLS · CAPABILITIES': 'COMPÉTENCES · CAPACITÉS',
  'List the skills, or attach a capability sheet.':
      'Listez les compétences, ou joignez une fiche de capacités.',
  'e.g. Root-cause analysis, ISO 9001 knowledge, French + English…':
      'ex. Analyse des causes racines, connaissance ISO 9001, français + anglais…',
  'MODEL PROVIDER': 'FOURNISSEUR DE MODÈLE',
  'Model id (e.g. {hint})': 'Identifiant du modèle (ex. {hint})',
  'API token / key': 'Jeton / clé API',
  'API token — {hint}': 'Jeton API — {hint}',
  'A name and a model provider are required.':
      'Un nom et un fournisseur de modèle sont requis.',
  'CANCEL': 'ANNULER',
  'SAVE CHANGES': 'ENREGISTRER LES MODIFICATIONS',
  'REPLACE LOGO': 'REMPLACER LE LOGO',
  'UPLOAD LOGO': 'CHARGER UN LOGO',
  'REMOVE': 'RETIRER',
  'Custom logo set': 'Logo personnalisé défini',
  'No logo · pick an icon': 'Pas de logo · choisissez une icône',
  'ATTACH FILE': 'JOINDRE UN FICHIER',
  'DECOMMISSION AGENT': 'METTRE HORS SERVICE',
  'This permanently removes the agent, its mission brief, skills and stored API credential from the fleet registry.\n\nThis action cannot be undone.':
      'Ceci retire définitivement l\'agent, son brief de mission, ses compétences et son identifiant API enregistré du registre de la flotte.\n\nCette action est irréversible.',
  'DELETE PERMANENTLY': 'SUPPRIMER DÉFINITIVEMENT',

  // ── AI Training tab ──
  'val loss': 'perte de validation',
  'val accuracy': 'précision de validation',
  'trees': 'arbres',
  'samples trained': 'échantillons entraînés',
  'trained': 'entraîné',
  'dataset': 'jeu de données',
  'ADAPTED +{rounds} ROUNDS': 'ADAPTÉ +{rounds} CYCLES',
  'forecasts graded': 'prévisions notées',
  'live precision': 'précision en direct',
  'live recall': 'rappel en direct',
  'brier score': 'score de Brier',
  'last adapted': 'dernière adaptation',
  'not yet': 'pas encore',
  'Every deployed forecast is graded against the alerts that actually happened (hit rate + Brier calibration), and the ensemble boosts a few extra trees per day on fresh production data — no manual retraining needed until you want a full reset.':
      'Chaque prévision déployée est notée par rapport aux alertes réellement survenues (taux de succès + calibration de Brier), et l\'ensemble ajoute quelques arbres supplémentaires par jour sur des données de production fraîches — aucun réentraînement manuel nécessaire avant une réinitialisation complète.',
  'Dump your company\'s alert history in any structured export — the model handles the rest.':
      'Déposez l\'historique des alertes de votre entreprise dans n\'importe quel export structuré — le modèle se charge du reste.',
  '{count} ROWS LOADED': '{count} LIGNES CHARGÉES',
  'Restoring previous session…': 'Restauration de la session précédente…',
  'Parsing and engineering features…': 'Analyse et ingénierie des caractéristiques…',
  'SELECT A DATA FILE': 'SÉLECTIONNER UN FICHIER',
  'REPLACE DATASET': 'REMPLACER LE JEU DE DONNÉES',
  'rows parsed': 'lignes analysées',
  'machines': 'machines',
  'history span': 'étendue d\'historique',
  '{days} days': '{days} jours',
  'training samples': 'échantillons d\'entraînement',
  'skipped rows': 'lignes ignorées',
  'Auto-tuned from the dataset shape ({count} samples). Adjust if you know what you\'re doing.':
      'Auto-ajusté selon la forme du jeu de données ({count} échantillons). Modifiez si vous savez ce que vous faites.',
  'BOOSTING ROUNDS': 'CYCLES DE BOOSTING',
  'Trees grown per alert type': 'Arbres générés par type d\'alerte',
  'LEARNING RATE': 'TAUX D\'APPRENTISSAGE',
  'Shrinkage per tree': 'Atténuation par arbre',
  'MAX TREE DEPTH': 'PROFONDEUR MAX DES ARBRES',
  'Interaction depth per tree': 'Profondeur d\'interaction par arbre',
  'MIN LEAF SAMPLES': 'ÉCHANTILLONS MIN PAR FEUILLE',
  'Smallest allowed leaf': 'Plus petite feuille autorisée',
  'SUBSAMPLE': 'SOUS-ÉCHANTILLON',
  'Row fraction per tree (0.3–1)': 'Fraction de lignes par arbre (0,3–1)',
  'L2 REGULARIZATION': 'RÉGULARISATION L2',
  'Leaf-weight damping (λ)': 'Amortissement du poids des feuilles (λ)',
  'POS-CLASS WEIGHT CAP': 'PLAFOND DE POIDS CLASSE POSITIVE',
  'Max miss-vs-false-alarm penalty ratio (1–200)':
      'Ratio max de pénalité manque/fausse alerte (1–200)',
  'Engine: XGBoost-class gradient-boosted decision trees · {features} engineered features (lags, rolling counts, recency, calendar) · 4 ensembles (one per alert type) · second-order logistic boosting · histogram splits · class-imbalance weighting · early stopping (patience {patience}).':
      'Moteur : arbres de décision à gradient-boosting de classe XGBoost · {features} caractéristiques élaborées (décalages, comptes glissants, récence, calendrier) · 4 ensembles (un par type d\'alerte) · boosting logistique du second ordre · découpes par histogramme · pondération du déséquilibre de classes · arrêt anticipé (patience {patience}).',
  'Training is autonomous: it keeps running if you switch tabs, work elsewhere in the console, or sign out while the app stays open. If this tab or browser is closed mid-run, the checkpoint resumes automatically the next time the command center opens.':
      'L\'entraînement est autonome : il continue si vous changez d\'onglet, travaillez ailleurs dans la console, ou vous déconnectez tant que l\'app reste ouverte. Si cet onglet ou le navigateur est fermé en cours d\'exécution, le point de contrôle reprend automatiquement à la prochaine ouverture du centre de commande.',
  'Waiting for first round…': 'En attente du premier cycle…',
  'LIVE · ANOTHER SESSION': 'EN DIRECT · AUTRE SESSION',
  'RESUMED FROM CHECKPOINT': 'REPRIS DEPUIS LE POINT DE CONTRÔLE',
  'LEARNING': 'APPRENTISSAGE',
  'WARMING UP': 'DÉMARRAGE',
  'NOT LEARNING': 'N\'APPREND PAS',
  'ROUND 0': 'CYCLE 0',
  'ROUND {round} / {total}': 'CYCLE {round} / {total}',
  'LOSS CURVES': 'COURBES DE PERTE',
  'train': 'entraînement',
  'validation': 'validation',
  'VALIDATION ACCURACY / F1': 'PRÉCISION DE VALIDATION / F1',
  'accuracy': 'précision',
  'macro-F1': 'F1 macro',
  'train loss': 'perte d\'entraînement',
  'macro F1': 'F1 macro',
  'Inference on the uploaded history with the freshly trained ensemble.':
      'Inférence sur l\'historique chargé avec l\'ensemble fraîchement entraîné.',
  'READY TO DEPLOY': 'PRÊT À DÉPLOYER',
  'WEAK MODEL': 'MODÈLE FAIBLE',
  'DEPLOYING…': 'DÉPLOIEMENT…',
  'DEPLOY TO PRODUCTION': 'DÉPLOYER EN PRODUCTION',
  'Fix the points above, replace or extend the dataset, and retrain. A model that is not learning is not blocked from deployment, but its forecasts will be close to guesswork.':
      'Corrigez les points ci-dessus, remplacez ou enrichissez le jeu de données, puis réentraînez. Un modèle qui n\'apprend pas n\'est pas bloqué au déploiement, mais ses prévisions seront proches du hasard.',
  'TYPE DISTRIBUTION': 'RÉPARTITION PAR TYPE',
  'RISK': 'RISQUE',
  '{usine} · Conveyor {convoyeur} · Station {poste}':
      '{usine} · Convoyeur {convoyeur} · Poste {poste}',

  // ── SuperAdmin · Overview Monitor war-room ──
  'DATABASE CONCEPTION': 'CONCEPTION DE LA BASE',
  'Live Realtime Database topology, relationships and per-node health.':
      'Topologie en direct de la Realtime Database, relations et santé par nœud.',
  'probed {time}': 'sondé {time}',
  'RESCAN': 'RESCANNER',
  'Six autonomous units, live across the platform edge.':
      'Six unités autonomes, en direct sur l\'edge de la plateforme.',
  '{online} / {total} ONLINE': '{online} / {total} EN LIGNE',
  'AI CORE': 'CŒUR IA',
  '{online} ACTIVE': '{online} ACTIF(S)',
  'No recorded actions yet.': 'Aucune action enregistrée pour l\'instant.',
  'ID': 'ID',
  'CODE': 'CODE',
  'BRIEF INSIGHT': 'APERÇU BREF',
  'LATEST ACTION': 'DERNIÈRE ACTION',
  'AT': 'À',
  'STATUS': 'STATUT',
  'Enabled · {headline}': 'Activé · {headline}',
  'AI · SECURITY': 'IA · SÉCURITÉ',
  'assigns': 'affectations',
  'security': 'sécurité',
  'errors': 'erreurs',
  'NOTIFICATIONS': 'NOTIFICATIONS',
  'alerts': 'alertes',
  'notifs': 'notifs',
  'BACKUP': 'SAUVEGARDE',
  'snapshot': 'instantané',
  'MONITOR': 'MONITEUR',
  'issues': 'problèmes',
  'CLOUDFLARE EDGE WORKERS': 'WORKERS EDGE CLOUDFLARE',
  'Five workers at the edge — live cron heartbeat and throughput.':
      'Cinq workers à l\'edge — pulsation cron et débit en direct.',
  'GITHUB PROXY': 'PROXY GITHUB',
  'CONNECTED': 'CONNECTÉ',
  'guardian console link': 'lien console Guardian',
  'no cron · pure HTTP proxy': 'pas de cron · proxy HTTP pur',
  'AI FLEET': 'FLOTTE IA',
  'All units online': 'Toutes les unités en ligne',
  'Some units paused': 'Certaines unités en pause',
  '{active} of {total} active': '{active} sur {total} actives',
  'WORKERS': 'WORKERS',
  'Edge nominal': 'Edge nominal',
  'Edge degraded': 'Edge dégradé',
  'DATABASE': 'BASE DE DONNÉES',
  '{count} roots reachable': '{count} racines accessibles',
  'OPERATIONAL INSIGHT': 'APERÇU OPÉRATIONNEL',
  'One-glance posture across fleet, hardware, edge and data.':
      'Posture en un coup d\'œil sur la flotte, le matériel, l\'edge et les données.',
  'never': 'jamais',
  'IDLE': 'INACTIF',
  'NO DATA': 'AUCUNE DONNÉE',
  'CRITICAL': 'CRITIQUE',
  'EDGE WORKERS': 'WORKERS EDGE',
  'cloudflare cron live': 'cron Cloudflare en direct',
  'autonomous units': 'unités autonomes',
  'LIVE SESSIONS': 'SESSIONS EN DIRECT',
  '{count} accounts total': '{count} comptes au total',
  'MACHINES ACTIVE': 'MACHINES ACTIVES',
  '{count} units mapped': '{count} unités cartographiées',
  'DB ROOTS LIVE': 'RACINES BD EN DIRECT',
  'realtime topology': 'topologie en temps réel',
  'CRASH-FREE': 'SANS CRASH',
  'today · {count} errors': 'aujourd\'hui · {count} erreurs',
  'GLOBAL OVERVIEW MONITOR': 'MONITEUR DE VUE D\'ENSEMBLE GLOBALE',
  'BACKEND · INFRASTRUCTURE · APPLICATION — ALL LAYERS, ONE GLASS':
      'BACKEND · INFRASTRUCTURE · APPLICATION — TOUTES LES COUCHES, UNE VITRE',
  'SYSTEM {label}': 'SYSTÈME {label}',
  'SYNC': 'SYNCHRONISER',
  'SECURITY & INTEGRITY': 'SÉCURITÉ & INTÉGRITÉ',
  'Edge Sentinel enforcements and platform error budget, live.':
      'Actions de la Sentinelle edge et budget d\'erreur de la plateforme, en direct.',
  'NO THREATS': 'AUCUNE MENACE',
  '{count} BLOCKED': '{count} BLOQUÉ(S)',
  'enforcements': 'actions d\'application',
  'open bugs': 'bugs ouverts',
  'bugs total': 'bugs au total',
  'No hostile traffic has reached the workers recently — the edge is quiet.':
      'Aucun trafic hostile n\'a atteint les workers récemment — l\'edge est calme.',
  'ACTIVE SESSIONS': 'SESSIONS ACTIVES',
  'Live presence across every provisioned account.':
      'Présence en direct sur chaque compte provisionné.',
  '{count} LIVE': '{count} EN DIRECT',
  'TOTAL ACCOUNTS': 'COMPTES TOTAUX',
  'TODAY · SESSIONS': 'AUJOURD\'HUI · SESSIONS',
  'No accounts match this filter.': 'Aucun compte ne correspond à ce filtre.',
  '+ {n} more accounts': '+ {n} comptes supplémentaires',
  'OPERATIONS': 'OPÉRATIONS',
  'PEOPLE': 'PERSONNES',
  'AI': 'IA',
  'COORDINATION': 'COORDINATION',
  'PLATFORM': 'PLATEFORME',

  // ── Hardware Lab · factory machinery map ──
  'Booting hardware bench…': 'Démarrage du banc matériel…',
  'Factory Machinery Map': 'Carte des machines de l\'usine',
  '{devices} device(s) bound · {machines} machine(s) in plant inventory':
      '{devices} appareil(s) lié(s) · {machines} machine(s) dans l\'inventaire',
  'ADD MACHINE': 'AJOUTER UNE MACHINE',
  'BIND DEVICE': 'LIER UN APPAREIL',
  'No machinery bound yet': 'Aucune machine liée pour l\'instant',
  'Bind a controller + its sensors/actuators to a machine to build the factory-wide hardware map. e.g. MACH-001 ← ESP32 with heat sensor, LED bank and 4 colored buttons.':
      'Liez un contrôleur + ses capteurs/actionneurs à une machine pour construire la carte matérielle de toute l\'usine. ex. MACH-001 ← ESP32 avec capteur de chaleur, bloc LED et 4 boutons colorés.',
  'Unnamed machine': 'Machine sans nom',
  'No peripherals listed': 'Aucun périphérique listé',
  'Bind Device to Machine': 'Lier un appareil à une machine',
  'Edit Device Binding': 'Modifier la liaison d\'appareil',
  'Pick the factory, line and machine from live plant inventory — MACH-001 (LEDs · buttons · sensors) ← its controller.':
      'Choisissez l\'usine, la ligne et la machine depuis l\'inventaire en direct — MACH-001 (LED · boutons · capteurs) ← son contrôleur.',
  'FACTORY': 'USINE',
  'No factories in the hierarchy yet — bind without one or create factories in Production Manager.':
      'Aucune usine dans la hiérarchie pour l\'instant — liez sans usine ou créez des usines dans Responsable de Production.',
  'CONVEYOR LINE': 'LIGNE DE CONVOYEUR',
  'Pick a factory first': 'Choisissez d\'abord une usine',
  'Select a conveyor line': 'Sélectionner une ligne de convoyeur',
  'MACHINE (MACH-XXX)': 'MACHINE (MACH-XXX)',
  'NEW MACHINE': 'NOUVELLE MACHINE',
  'Select a machine': 'Sélectionner une machine',
  'No machines match — tap NEW MACHINE to add one.':
      'Aucune machine ne correspond — touchez NOUVELLE MACHINE pour en ajouter une.',
  'CONTROLLER': 'CONTRÔLEUR',
  'Controller board': 'Carte contrôleur',
  'PERIPHERALS': 'PÉRIPHÉRIQUES',
  'e.g. Flow meter': 'ex. Débitmètre',
  'Add custom peripheral': 'Ajouter un périphérique personnalisé',
  'ADD': 'AJOUTER',
  'DEPLOY STATUS': 'STATUT DE DÉPLOIEMENT',
  'SAVE BINDING': 'ENREGISTRER LA LIAISON',
  'No description recorded.': 'Aucune description enregistrée.',
  'Edit machine': 'Modifier la machine',
  'NAME': 'NOM',
  'LOCATION': 'EMPLACEMENT',
  'DESCRIPTION': 'DESCRIPTION',
  'DATE': 'DATE',
  'No wired hardware.': 'Aucun matériel câblé.',
  'Edit Machine': 'Modifier la machine',
  'Register Machine': 'Enregistrer une machine',
  'A MACH-XXX unit on a conveyor line': 'Une unité MACH-XXX sur une ligne de convoyeur',
  'This is a live plant asset. Edits here are kept in the lab overlay and do not change /assets.':
      'C\'est un actif d\'usine en direct. Les modifications ici sont conservées dans la surcouche labo et ne changent pas /assets.',
  'MACHINE ID': 'ID MACHINE',
  'e.g. MACH-001': 'ex. MACH-001',
  'e.g. Bottling head A': 'ex. Tête d\'embouteillage A',
  'What this machine does, what hardware it carries…':
      'Ce que fait cette machine, le matériel qu\'elle porte…',
  'Select a conveyor line (optional)': 'Sélectionner une ligne de convoyeur (facultatif)',
  'SAVE': 'ENREGISTRER',
  'PLANT MACHINES': 'MACHINES DE L\'USINE',
  'MACH-XXX · read from /assets + lab': 'MACH-XXX · lu depuis /assets + labo',
  'No machines found yet. Add one, or create stations in the factory hierarchy — their MACH-XXX assets appear here.':
      'Aucune machine trouvée pour l\'instant. Ajoutez-en une, ou créez des postes dans la hiérarchie d\'usine — leurs actifs MACH-XXX apparaissent ici.',
  'Heat sensor': 'Capteur de chaleur',
  'Vibration sensor': 'Capteur de vibration',
  'PIR motion': 'Mouvement PIR',
  'LED indicators': 'Indicateurs LED',
  '4 colored buttons': '4 boutons colorés',
  'LCD display': 'Écran LCD',
  'Buzzer alarm': 'Alarme buzzer',
  'Servo actuator': 'Actionneur servo',
  'Potentiometer': 'Potentiomètre',
  'Designed': 'Conçu',
  'Wired': 'Câblé',
  'Verified': 'Vérifié',
  'Live': 'En direct',
  'ACTIVE': 'ACTIF',
  'OUT OF SERVICE': 'HORS SERVICE',
  'DELETED': 'SUPPRIMÉ',

  // ── PM Overview: Predictive Failure Alerts card ──
  'Predictive Failure Alerts': 'Alertes de défaillance prédictives',
  'Edge model warming up — first inference within 60s.':
      'Le modèle Edge démarre — première inférence dans les 60s.',
  'Top probable next failures · on-device AI forecaster · next 24h':
      'Prochaines défaillances probables · prévision IA embarquée · 24h',
  'Top probable next failures · trained on last 30d':
      'Prochaines défaillances probables · entraîné sur 30 derniers jours',
  'Based on the last {n} validated predictions.':
      'Basé sur les {n} dernières prédictions validées.',
  'Accuracy: {pct}%': 'Précision : {pct} %',
  'AI · LIVE': 'IA · EN DIRECT',
  'Not enough history yet': 'Pas encore assez d\'historique',
  'The model needs a few days of alerts to learn patterns.':
      'Le modèle a besoin de quelques jours d\'alertes pour apprendre les tendances.',
  'No ETA yet': 'Pas encore d\'ETA',
  'Overdue · expected': 'En retard · attendu',
  'Within {n} min': 'Dans {n} min',
  'In ~{n}h': 'Dans ~{n} h',
  'In ~{n}d': 'Dans ~{n} j',
  'Last {time}': 'Dernière {time}',
  'conf.': 'conf.',
  '{factory} · Line {line} · WS {station}':
      '{factory} · Ligne {line} · Poste {station}',
  '{n} critical': '{n} critique(s)',

  // ── PM Overview: Critical Alerts card ──
  'Critical · {n} pending': 'Critique · {n} en attente',
  'Awaiting assignment for over 10 minutes':
      'En attente d\'affectation depuis plus de 10 minutes',
  'AI is matching the best supervisor…':
      'L\'IA recherche le meilleur superviseur…',
  'Assigned to {name} — supervisor notified.':
      'Affecté à {name} — superviseur notifié.',
  'supervisor': 'superviseur',
  'No eligible supervisor right now.':
      'Aucun superviseur éligible pour le moment.',
  'AI suggests: ': 'L\'IA suggère : ',
  '  ·  {pct}% match': '  ·  {pct} % de correspondance',

  // ── PM Overview: Predictive Risk heatmap card ──
  'Predictive Risk · Next 24h': 'Risque prédictif · 24h à venir',
  'Awaiting first model from edge inference…':
      'En attente du premier modèle d\'inférence edge…',
  'On-device AI forecaster · probability per 2h window · tap row to filter':
      'Prévision IA embarquée · probabilité par tranche de 2h · touchez une ligne pour filtrer',
  'Probability per 2h window · tap row to filter history':
      'Probabilité par tranche de 2h · touchez une ligne pour filtrer l\'historique',
  'ML': 'ML',
  'High': 'Élevé',
  'Elevated': 'Accru',
  'Watch': 'À surveiller',
  'Low': 'Faible',
  '{n} past · awaiting forecast': '{n} passées · prévision en attente',
  '{past} past · {solved} resolved · peak @ {hour}:00':
      '{past} passées · {solved} résolues · pic à {hour}:00',
  '{label} · {pct}%': '{label} · {pct} %',
  'now': 'maintenant',

  // ── PM Overview: Operations Briefing hero card ──
  'Operations Briefing': 'Briefing des opérations',
  'Working late': 'Travail tardif',
  'Good morning': 'Bonjour',
  'Good afternoon': 'Bon après-midi',
  'Good evening': 'Bonsoir',
  '{greeting}, supervisor. Your AI briefing is warming up — historical patterns are being analysed in the background. Hard data and a personalised summary will land here within the next minute.':
      '{greeting}, superviseur. Votre briefing IA démarre — les tendances historiques sont analysées en arrière-plan. Des données concrètes et un résumé personnalisé apparaîtront ici dans la minute qui suit.',
  '{factory} most active': '{factory} la plus active',
  'Expected: {type}{line} ({pct}%)': 'Attendu : {type}{line} ({pct} %)',
  ' · Line {line}': ' · Ligne {line}',
  'Updated {time}': 'Mis à jour {time}',
  'Generating…': 'Génération…',
  'Regenerate': 'Régénérer',

  // ── PM Overview: Production Health card ──
  'Production Health': 'Santé de la production',
  'Composite of resolution rate and critical backlog.':
      'Composite du taux de résolution et de l\'arriéré critique.',
  'Outstanding': 'Excellente',
  'Watchful': 'À surveiller',
  'At risk': 'À risque',
  'Quality issue detected on production line':
      'Problème de qualité détecté sur la ligne de production',
  'Maintenance required on equipment':
      'Maintenance requise sur l\'équipement',
  'Damaged product detected': 'Produit endommagé détecté',
  'Resource deficiency - missing raw materials':
      'Manque de ressources - matières premières manquantes',
  'Alert detected': 'Alerte détectée',

  // ── PM Overview: Alert History card & filters ──
  'History Filters': 'Filtres d\'historique',
  'Refine alert history only — dashboard stats are unaffected':
      'Affine uniquement l\'historique des alertes — les statistiques du tableau de bord ne sont pas affectées',
  'FIXED': 'RÉSOLUE',
  'TOTAL': 'TOTAL',
  'Alert History': 'Historique des alertes',
  '{n} alert · {scope}': '{n} alerte · {scope}',
  '{n} alerts · {scope}': '{n} alertes · {scope}',
  'Filters': 'Filtres',
  'All clear': 'Tout est en ordre',
  'No alerts match your filters.':
      'Aucune alerte ne correspond à vos filtres.',
  'Filter alerts': 'Filtrer les alertes',
  'Refine the history list — every selection scopes the dashboard':
      'Affine la liste de l\'historique — chaque sélection recadre le tableau de bord',
  '(no description)': '(aucune description)',
  '{factory}  ·  Line {line}  ·  Post {station}  ·  {time}':
      '{factory}  ·  Ligne {line}  ·  Poste {station}  ·  {time}',
  'Assigned: {name}': 'Affecté à : {name}',
  'Critical note: {note}': 'Note critique : {note}',

  // ── PM Overview: Export Report dialog ──
  'Custom Range': 'Plage personnalisée',
  'No alerts match': 'Aucune alerte ne correspond',
  '{n} alert included': '{n} alerte incluse',
  '{n} alerts included': '{n} alertes incluses',
  'Clear location filters': 'Effacer les filtres de localisation',
  'Select date': 'Choisir une date',
  'Clear all': 'Tout désélectionner',
  'Select all': 'Tout sélectionner',

  // ── Admin dashboard: time range header chip ──
  'Last Week': 'Semaine dernière',
  'All time': 'Toujours',
  'Showing today\'s data': 'Données du jour',
  'Showing last 7 days': '7 derniers jours affichés',
  'Showing this month': 'Ce mois-ci affiché',
  'Showing this year': 'Cette année affichée',
  'Filtered view': 'Vue filtrée',

  // ── PM Overview: Critical Arrival dialog & factory master bar ──
  'AI assignment': 'Affectation IA',
  'Assignment failed. Please retry.':
      'Échec de l\'affectation. Veuillez réessayer.',
  'CRITICAL ALERT ARRIVED': 'ALERTE CRITIQUE REÇUE',
  'AI suggestion: analyzing best supervisor...':
      'Suggestion IA : analyse du meilleur superviseur...',
  'AI suggestion: {name} ({pct}%)': 'Suggestion IA : {name} ({pct} %)',
  'AI suggestion: no eligible supervisor right now.':
      'Suggestion IA : aucun superviseur éligible pour le moment.',
  'Immediate attention required': 'Attention immédiate requise',
  'Assigning...': 'Affectation...',
  'PLANT SCOPE': 'PORTÉE USINE',
  'Aggregate': 'Agrégé',
  'Scoped': 'Ciblé',

  // ── Shifts: shift creation dialog ──
  'Failed to load supervisors': 'Échec du chargement des superviseurs',
  'Please enter a shift name': 'Veuillez saisir un nom de quart',
  'Edit Shift': 'Modifier le quart',
  'New Shift': 'Nouveau quart',
  'Configure schedule, supervisors, and AI commander':
      'Configurer l\'horaire, les superviseurs et le commandant IA',
  'Hard cap on supervisors assigned at once':
      'Limite stricte de superviseurs affectés à la fois',
  'AI Shift Commander': 'Commandant de quart IA',
  'Let AI manage this shift: accept collaborations, assign supervisors to alerts, handle cross-factory transfers automatically.':
      'Laissez l\'IA gérer ce quart : accepter les collaborations, affecter les superviseurs aux alertes, gérer automatiquement les transferts entre usines.',
  '24-hour timeline': 'Chronologie sur 24 heures',
  'Now': 'Maintenant',

  // ── Shifts: live panel & export report dialog ──
  'Time remaining': 'Temps restant',
  'Starts in': 'Débute dans',
  'Generating PDF…': 'Génération du PDF…',
  'Export PDF report': 'Exporter le rapport PDF',
  'Created': 'Créée',
  'AI Assignments': 'Affectations IA',
  'Export Shift Report': 'Exporter le rapport de quart',
  'Choose date, factory, and action types':
      'Choisissez la date, l\'usine et les types d\'action',
  'Action types': 'Types d\'action',
  'AI only': 'IA uniquement',
  '{n} action type selected': '{n} type d\'action sélectionné',
  '{n} action types selected': '{n} types d\'action sélectionnés',
  'No action types selected': 'Aucun type d\'action sélectionné',
  'Generate': 'Générer',
  'Shift ends in {n} min — generate AI handover?':
      'Le quart se termine dans {n} min — générer la passation IA ?',

  // ── Alerts tree: alert detail sheet ──
  'People': 'Personnes',
  'Assistant': 'Assistant',
  'Comments ({n})': 'Commentaires ({n})',
  'Auto-assigned': 'Affectée automatiquement',
  '{pct}% confidence': 'confiance {pct} %',
};
