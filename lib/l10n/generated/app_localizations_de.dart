// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Meine Finanzen';

  @override
  String get greetingMorningNeutral => 'Guten Morgen';

  @override
  String get greetingDayNeutral => 'Guten Tag';

  @override
  String get greetingEveningNeutral => 'Guten Abend';

  @override
  String get greetingNightNeutral => 'Hallo';

  @override
  String greetingMorning(String userName) {
    return 'Guten Morgen, $userName';
  }

  @override
  String greetingDay(String userName) {
    return 'Guten Tag, $userName';
  }

  @override
  String greetingEvening(String userName) {
    return 'Guten Abend, $userName';
  }

  @override
  String greetingNight(String userName) {
    return 'Hallo, $userName';
  }

  @override
  String get notificationsLabel => 'Benachrichtigungen, neue vorhanden';

  @override
  String get notificationsTitle => 'Benachrichtigungen';

  @override
  String get notificationsStubDescription =>
      'Die Benachrichtigungen folgen im nächsten Schritt.';

  @override
  String get openSettingsLabel => 'Einstellungen öffnen';

  @override
  String get balanceTitle => 'Kontostand';

  @override
  String get hideAmounts => 'Beträge ausblenden';

  @override
  String get showAmounts => 'Beträge anzeigen';

  @override
  String get monthDelta => 'diesen Monat';

  @override
  String get balanceDeltaUnavailable => 'Änderung im Monat nicht verfügbar';

  @override
  String get addBySentence => 'Satz eingeben';

  @override
  String get sentenceEntryLabel => 'Buchung in einem Satz erfassen';

  @override
  String get addByVoice => 'Einsprechen';

  @override
  String get voiceEntryLabel => 'Buchung per Sprache erfassen';

  @override
  String get typeBySentence => 'Satz schreiben';

  @override
  String get voicePrompt =>
      'Sag zum Beispiel: „12,50 Euro für Lebensmittel ausgegeben“';

  @override
  String get voiceNothingHeard => 'Nichts verstanden. Versuch es noch einmal.';

  @override
  String get voiceNeedsNetwork =>
      'Die Spracherkennung braucht Internet oder das heruntergeladene Sprachpaket Deutsch in den Einstellungen der Spracheingabe.';

  @override
  String get voiceUnavailable =>
      'Dieses Handy hat keine Spracherkennung. Du kannst den Satz auch schreiben.';

  @override
  String get voiceFailed =>
      'Sprache konnte nicht erkannt werden. Versuch es noch einmal.';

  @override
  String get voiceTypeInsteadAction => 'Schreiben';

  @override
  String get setupAccountAction => 'Konto einrichten';

  @override
  String monthSummaryTitle(String month) {
    return 'Übersicht für $month';
  }

  @override
  String get income => 'Einnahmen';

  @override
  String get incomeCaption => 'eingegangen';

  @override
  String get expenses => 'Ausgaben';

  @override
  String get expensesCaption => 'ausgegeben';

  @override
  String get netFlow => 'Bilanz';

  @override
  String get netPositiveCaption => 'im Plus';

  @override
  String get trendExpensesTitle => 'Ausgaben';

  @override
  String get trendBalanceTitle => 'Kontostand';

  @override
  String get trendUnknownTitle => 'Verlauf';

  @override
  String get trendLast7Days => 'letzte 7 Tage';

  @override
  String get trendLast30Days => 'letzte 30 Tage';

  @override
  String get trendPeriodUnknown => 'Zeitraum';

  @override
  String get trend7DaysChip => '7 Tage';

  @override
  String get trend30DaysChip => '30 Tage';

  @override
  String get detailsAction => 'Details';

  @override
  String get trendEmpty => 'Noch zu wenig Daten für ein Diagramm';

  @override
  String trendSemantics(String title, String amount) {
    return '$title im Zeitraum, insgesamt $amount';
  }

  @override
  String get amountsHidden => 'Beträge ausgeblendet';

  @override
  String goalDueDate(String date) {
    return 'bis $date';
  }

  @override
  String goalProgressSummary(String target, String progress) {
    return 'von $target · $progress%';
  }

  @override
  String goalMonthlyContribution(String amount) {
    return 'Etwa $amount pro Monat zurücklegen';
  }

  @override
  String goalSemantics(
    String title,
    String current,
    String target,
    String progress,
  ) {
    return '$title, gespart $current, Ziel $target, Fortschritt $progress Prozent, Sparziel öffnen';
  }

  @override
  String get upcomingPaymentsTitle => 'Nächste Zahlungen';

  @override
  String get allPaymentsAction => 'Alle Zahlungen';

  @override
  String get noUpcomingPayments => 'Keine anstehenden Zahlungen';

  @override
  String paymentDueDate(String date) {
    return 'fällig am $date';
  }

  @override
  String paymentOverdueDate(String date) {
    return 'überfällig · $date';
  }

  @override
  String paymentDateUnknown(String date) {
    return 'Status wird geprüft · $date';
  }

  @override
  String paymentSemantics(String title, String due, String amount) {
    return '$title, $due, $amount';
  }

  @override
  String get recentTransactionsTitle => 'Letzte Buchungen';

  @override
  String get noRecentTransactions => 'Noch keine bestätigten Buchungen';

  @override
  String get transactionCategoryUnavailable => 'Ohne Kategorie';

  @override
  String transactionMetadata(String category, String date) {
    return '$category · $date';
  }

  @override
  String get transactionIncome => 'Einnahme';

  @override
  String get transactionExpense => 'Ausgabe';

  @override
  String get transactionTransfer => 'Umbuchung';

  @override
  String get transactionUnknown => 'Buchung';

  @override
  String transactionSemantics(
    String title,
    String category,
    String date,
    String amount,
    String kind,
  ) {
    return '$title, $category, $date, $amount, $kind';
  }

  @override
  String get refreshingTitle => 'Daten werden aktualisiert';

  @override
  String get refreshingDescription => 'Deine Finanzübersicht bleibt verfügbar.';

  @override
  String get partialDataTitle => 'Einige Daten sind gerade nicht verfügbar';

  @override
  String get partialDataDescription =>
      'Die übrigen Bereiche funktionieren weiter.';

  @override
  String get offlineTitle => 'Keine Verbindung';

  @override
  String offlineDataAsOf(String date, String time) {
    return 'Datenstand: $date, $time UTC.';
  }

  @override
  String get refreshFailedTitle => 'Aktualisierung fehlgeschlagen';

  @override
  String get refreshFailedDescription =>
      'Wir zeigen die vorherige Finanzübersicht.';

  @override
  String get retryAction => 'Wiederholen';

  @override
  String get fatalErrorTitle => 'Daten konnten nicht geladen werden';

  @override
  String get fatalErrorDescription =>
      'Versuch es noch einmal. Tritt der Fehler wieder auf, nenne dem Support den Anfragecode.';

  @override
  String requestIdLabel(String requestId) {
    return 'Anfragecode: $requestId';
  }

  @override
  String get authExpiredTitle => 'Sitzung abgelaufen';

  @override
  String get authExpiredDescription =>
      'Melde dich zum Schutz deiner Daten neu an.';

  @override
  String get signInAgainAction => 'Neu anmelden';

  @override
  String get sessionExpiredStubTitle => 'Erneute Anmeldung';

  @override
  String get sessionExpiredStubDescription =>
      'Der Anmeldebildschirm kommt zusammen mit der echten Sitzung. Deine Finanzdaten wurden nicht gelöscht.';

  @override
  String get balanceUnavailable => 'Kontostand gerade nicht verfügbar';

  @override
  String get monthSummaryUnavailable =>
      'Monatsübersicht gerade nicht verfügbar';

  @override
  String get trendUnavailable => 'Diagramm gerade nicht verfügbar';

  @override
  String get goalNotSelected => 'Noch kein Hauptziel gewählt';

  @override
  String get goalUnavailable =>
      'Ziele sind gerade nicht verfügbar. Die Daten werden bereits aktualisiert.';

  @override
  String get paymentsUnavailable => 'Nächste Zahlungen gerade nicht verfügbar';

  @override
  String get transactionsUnavailable =>
      'Letzte Buchungen gerade nicht verfügbar';

  @override
  String get emptyTitle =>
      'Erfasse deine erste Buchung, um deine Finanzübersicht zu sehen';

  @override
  String get emptyDescription =>
      'Sag einfach, was du gekauft oder bekommen hast — den Rest machen wir.';

  @override
  String get loadingLabel => 'Finanzdaten werden geladen';

  @override
  String get homeTab => 'Start';

  @override
  String get chatTab => 'Chat';

  @override
  String get analyticsTab => 'Analyse';

  @override
  String get goalsTab => 'Ziele';

  @override
  String get profileTab => 'Profil';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get backLabel => 'Zurück';

  @override
  String get appearanceSection => 'DARSTELLUNG';

  @override
  String get lightTheme => 'Hell';

  @override
  String get darkTheme => 'Dunkel';

  @override
  String get accentColor => 'Akzentfarbe';

  @override
  String get tealAccent => 'Türkis';

  @override
  String get blueAccent => 'Blau';

  @override
  String get purpleAccent => 'Violett';

  @override
  String get terracottaAccent => 'Terrakotta';

  @override
  String get generalSection => 'ALLGEMEIN';

  @override
  String get privacySetting => 'Beträge ausblenden';

  @override
  String get languageSetting => 'Sprache';

  @override
  String get baseCurrencySetting => 'Hauptwährung';

  @override
  String get baselineSettingsAction => 'Startdatum';

  @override
  String get baselineSettingsDescription => 'Frühere Buchungen zulassen';

  @override
  String get baselineCorrectionTitle => 'Startdatum';

  @override
  String get baselineCorrectionLoading => 'Kontoeinstellungen werden geladen';

  @override
  String get baselineCorrectionDescription =>
      'Lege das Datum weiter zurück, um frühere Buchungen zu erfassen. Anfangssaldo und Währung bleiben gleich.';

  @override
  String get baselineCurrentDateLabel => 'Aktuelles Startdatum';

  @override
  String get baselineNewDateLabel => 'Neues Datum';

  @override
  String get baselineChooseDateAction => 'Datum wählen';

  @override
  String get baselineDateRangeHelp =>
      'Du kannst nur ein Datum vor dem aktuellen Startdatum wählen.';

  @override
  String get baselineReviewTitle => 'Neues Datum prüfen';

  @override
  String get baselineReviewDescription =>
      'Nach der Bestätigung werden Startseite und Monatsübersicht aus den maßgeblichen Daten neu berechnet.';

  @override
  String get baselineConfirmAction => 'Neues Datum bestätigen';

  @override
  String get baselineSuccessTitle => 'Startdatum geändert';

  @override
  String baselineSuccessDescription(String date) {
    return 'Du kannst jetzt Buchungen ab $date erfassen.';
  }

  @override
  String get baselineHomeDelayedDescription =>
      'Das Datum ist gespeichert. Die Startseite wird später aktualisiert; du musst die Änderung nicht noch einmal bestätigen.';

  @override
  String get baselineDoneAction => 'Fertig';

  @override
  String get baselineUnavailableTitle =>
      'Datum kann noch nicht geändert werden';

  @override
  String get baselineAccountRequired => 'Richte zuerst dein erstes Konto ein.';

  @override
  String get baselineMinimumDateReached =>
      'Das Konto beginnt bereits am frühesten möglichen Datum.';

  @override
  String get baselineNotEarlierError =>
      'Wähle ein Datum vor dem aktuellen Startdatum.';

  @override
  String get baselineFutureError =>
      'Das Startdatum darf nicht nach dem heutigen Tag liegen.';

  @override
  String get baselineAfterOperationError =>
      'Das neue Datum darf nicht nach der frühesten gespeicherten Buchung liegen.';

  @override
  String get baselineLoadFailed =>
      'Kontoeinstellungen konnten nicht geladen werden.';

  @override
  String get baselineChangeFailed =>
      'Datum konnte nicht geändert werden. Die App hat keine Finanzdaten verändert.';

  @override
  String get stubDescription =>
      'Dieser Bereich folgt im nächsten Schritt. Im Moment ist er nur ein Platzhalter.';

  @override
  String get voiceStubTitle => 'Spracheingabe';

  @override
  String get voiceStubDescription =>
      'Der Aufnahmebildschirm ist noch ein Platzhalter. Mikrofon und Spracherkennung kommen im nächsten Schritt.';

  @override
  String get backHome => 'Zum Start';

  @override
  String get authLoadingLabel => 'Sichere Sitzung wird geprüft';

  @override
  String get loginTitle => 'Anmelden';

  @override
  String get loginDescription =>
      'Melde dich an, um deine Finanzübersicht zu öffnen.';

  @override
  String get registerTitle => 'Account erstellen';

  @override
  String get registerDescription =>
      'Erstelle einen geschützten Account, um deine Finanzen zu führen.';

  @override
  String get displayNameField => 'Dein Name';

  @override
  String get displayNameRequired => 'Gib deinen Namen ein';

  @override
  String get emailField => 'E-Mail';

  @override
  String get emailInvalid => 'Gib eine gültige E-Mail-Adresse ein';

  @override
  String get passwordField => 'Passwort';

  @override
  String get confirmPasswordField => 'Passwort wiederholen';

  @override
  String get passwordRequirements => 'Mindestens 12 Zeichen';

  @override
  String get passwordInvalid =>
      'Das Passwort muss 12 bis 128 Zeichen lang sein';

  @override
  String get passwordsDoNotMatch => 'Passwörter stimmen nicht überein';

  @override
  String get showPassword => 'Passwort anzeigen';

  @override
  String get hidePassword => 'Passwort verbergen';

  @override
  String get loginAction => 'Anmelden';

  @override
  String get registerAction => 'Account erstellen';

  @override
  String get createAccountAction => 'Kein Account? Erstellen';

  @override
  String get haveAccountAction => 'Schon einen Account? Anmelden';

  @override
  String get authSessionExpiredNotice => 'Sitzung beendet. Melde dich neu an.';

  @override
  String get signedOutNotice => 'Du bist abgemeldet.';

  @override
  String get invalidCredentialsError =>
      'Anmeldung fehlgeschlagen. Prüfe E-Mail und Passwort.';

  @override
  String get emailInUseError =>
      'Account konnte nicht erstellt werden. Diese E-Mail wird vielleicht schon verwendet.';

  @override
  String get authInvalidInputError =>
      'Prüfe deine Eingaben und versuch es noch einmal.';

  @override
  String get authThrottledError =>
      'Zu viele Versuche. Warte kurz und versuch es noch einmal.';

  @override
  String get authOfflineError =>
      'Keine Internetverbindung. Prüfe dein Netz und versuch es noch einmal.';

  @override
  String get authTimeoutError =>
      'Der Server hat nicht rechtzeitig geantwortet. Versuch es noch einmal.';

  @override
  String get authServiceError =>
      'Die Anmeldung ist gerade nicht verfügbar. Versuch es später noch einmal.';

  @override
  String get authUnexpectedError =>
      'Die Anmeldung konnte nicht abgeschlossen werden. Versuch es noch einmal.';

  @override
  String get authSecureStorageError =>
      'Der sichere Speicher des Geräts konnte nicht geöffnet werden.';

  @override
  String get accountSection => 'ACCOUNT';

  @override
  String get signOutAction => 'Abmelden';

  @override
  String get signOutDialogTitle => 'Abmelden?';

  @override
  String get signOutDialogDescription =>
      'Beim nächsten Mal musst du E-Mail und Passwort erneut eingeben.';

  @override
  String get cancelAction => 'Abbrechen';

  @override
  String get financeEntryTitle => 'Buchung';

  @override
  String get financeEntryLoading => 'Konto wird geprüft';

  @override
  String get financeEntryLoadFailed => 'Eingabe konnte nicht geöffnet werden';

  @override
  String get accountSetupTitle => 'Erstes Konto einrichten';

  @override
  String get accountSetupDescription =>
      'Gib deinen tatsächlichen Kontostand ein. Das Startdatum ist der früheste Tag, für den du eine Buchung erfassen kannst. Vor dem Speichern prüfst du alles noch einmal.';

  @override
  String get accountNameField => 'Kontoname';

  @override
  String get accountNameHint => 'Zum Beispiel Hauptkonto';

  @override
  String get accountNameRequired => 'Gib einen Kontonamen ein';

  @override
  String get accountCurrencyRequired => 'Wähle eine Währung';

  @override
  String get accountCurrencyHelp =>
      'Die Währung dieses Kontos lässt sich später nicht ändern. Für andere Währungen kannst du eigene Konten eröffnen.';

  @override
  String get openingBalanceField => 'Anfangssaldo';

  @override
  String get openingBalanceHelp =>
      'Das ist der Stand zum Start, weder Einnahme noch Ausgabe.';

  @override
  String get openingBalanceDateField => 'Datum des Anfangssaldos';

  @override
  String get canonicalTimezoneLabel => 'Zeitzone';

  @override
  String get continueToReviewAction => 'Daten prüfen';

  @override
  String get accountReviewTitle => 'Kontoeinstellungen prüfen';

  @override
  String get reviewBeforeConfirmDescription =>
      'Finanzdaten werden erst nach deiner ausdrücklichen Bestätigung gespeichert.';

  @override
  String get confirmFinanceAction => 'Bestätigen und speichern';

  @override
  String get editAction => 'Ändern';

  @override
  String get accountCreatedNotice =>
      'Konto bestätigt. Erfasse jetzt deine erste Buchung.';

  @override
  String get manualOperationTitle => 'Buchung manuell erfassen';

  @override
  String get manualOperationDescription =>
      'Fülle die Felder aus. Sprache und automatische Erkennung werden hier noch nicht genutzt.';

  @override
  String get accountLabel => 'Konto';

  @override
  String get operationExpense => 'Ausgabe';

  @override
  String get operationIncome => 'Einnahme';

  @override
  String get operationTypeLabel => 'Buchungsart';

  @override
  String get operationAmountField => 'Betrag';

  @override
  String get merchantField => 'Ort oder Empfänger, optional';

  @override
  String get categoryField => 'Kategorie, optional';

  @override
  String get operationDateField => 'Buchungsdatum';

  @override
  String get operationReviewTitle => 'Buchung prüfen';

  @override
  String get addAnotherOperationAction => 'Noch eine erfassen';

  @override
  String get moneyInputInvalid =>
      'Gib einen gültigen Betrag ein, zum Beispiel 1250,50 oder -20';

  @override
  String get positiveMoneyInputInvalid =>
      'Gib einen Betrag über null ein, zum Beispiel 35 oder 35,50';

  @override
  String get financeInvalidInput =>
      'Prüfe die Felder und versuch es noch einmal.';

  @override
  String get financeValidationRejected =>
      'Die Daten wurden abgelehnt. Prüfe die Felder vor dem erneuten Senden.';

  @override
  String get financeDateRejected =>
      'Das Datum darf nicht nach dem heutigen Tag liegen.';

  @override
  String get operationBeforeOpeningDateError =>
      'Das Buchungsdatum darf nicht vor dem Datum des Anfangssaldos liegen.';

  @override
  String get financeAccountUnavailable =>
      'Das Konto ist für diese Buchung nicht verfügbar. Aktualisiere die Ansicht und versuch es noch einmal.';

  @override
  String get financeConflictError =>
      'Das steht im Konflikt mit einem bereits verarbeiteten Eintrag. Ändere die Daten und bestätige neu.';

  @override
  String get financeOfflineError =>
      'Server nicht erreichbar. Prüfe die Verbindung zur API und versuch es noch einmal.';

  @override
  String get financeTimeoutError =>
      'Der Server hat nicht rechtzeitig geantwortet. Du kannst die Bestätigung gefahrlos wiederholen.';

  @override
  String get financeServiceError =>
      'Der Buchungsdienst ist gerade nicht verfügbar. Versuch es später noch einmal.';

  @override
  String get financeSecurityError =>
      'Die sichere Verbindung konnte nicht bestätigt werden. Prüfe die Einstellungen und versuch es später noch einmal.';

  @override
  String get financeLocalStorageError =>
      'Die Bestätigung konnte nicht sicher auf dem Gerät gespeichert werden. Es wurde keine Anfrage an den Server gesendet. Gib Speicher frei oder entsperre den sicheren Speicher und wiederhole den Vorgang.';

  @override
  String get financeUnexpectedError =>
      'Die Antwort war ungültig. Die App hat keine Finanzdaten verändert.';

  @override
  String get financeSessionChanged =>
      'Die sichere Sitzung wurde aktualisiert. Wiederhole den Vorgang; die Bestätigung wird mit denselben Daten gesendet.';

  @override
  String get operationAcceptedTitle => 'Buchung gespeichert';

  @override
  String get operationAcceptedUpdatingHome =>
      'Buchung angenommen. Wir warten auf die neue Startseite.';

  @override
  String get operationAcceptedHomeUpdated =>
      'Die Startseite ist auf dem neuen, maßgeblichen Stand.';

  @override
  String get operationAcceptedProjectionDelayed =>
      'Die Buchung ist gespeichert, aber die Startseite wird erst später aktualisiert. Du musst sie nicht noch einmal bestätigen.';

  @override
  String get operationAcceptedAuthRequired =>
      'Die Buchung ist gespeichert, aber für die Aktualisierung der Startseite musst du dich neu anmelden.';

  @override
  String get operationAcceptedSessionChanged =>
      'Die Buchung ist gespeichert, aber die Sitzung hat sich während der Aktualisierung geändert. Öffne die Startseite noch einmal.';

  @override
  String get operationAcceptedRefreshFailed =>
      'Die Buchung ist gespeichert. Die Startseite kannst du später aktualisieren.';

  @override
  String get operationQueuedTitle => 'Buchung auf dem Gerät gespeichert';

  @override
  String get operationQueuedDescription =>
      'Die Bestätigung ist sicher gespeichert. Solange der Server sie nicht angenommen hat, ändert sie deinen Kontostand nicht. Den aktuellen Status siehst du auf der Startseite.';

  @override
  String get operationQueuedAuthDescription =>
      'Die Bestätigung ist sicher gespeichert. Zum Weitersenden musst du dich eventuell neu anmelden. Den aktuellen Status siehst du auf der Startseite.';

  @override
  String get operationAlreadySyncedTitle => 'Buchung bereits synchronisiert';

  @override
  String get operationAlreadySyncedDescription =>
      'Der Server hat diese Buchung schon früher bestätigt. Es wurde kein zweiter Eintrag angelegt.';

  @override
  String get operationAttentionTitle => 'Buchung muss geprüft werden';

  @override
  String get operationAttentionConflict =>
      'Die gespeicherte Bestätigung steht im Konflikt mit einem bereits verarbeiteten Befehl und wird nicht automatisch gesendet.';

  @override
  String get operationAttentionRejected =>
      'Finance Core hat die Bestätigung abgelehnt. Dein Kontostand ist unverändert.';

  @override
  String get operationAttentionSecurity =>
      'Der Versand wurde wegen einer Sicherheitsprüfung gestoppt. Dein Kontostand ist unverändert.';

  @override
  String get operationAttentionInvalid =>
      'Die Bestätigung kann nicht sicher automatisch gesendet werden. Dein Kontostand ist unverändert.';

  @override
  String get operationSyncingBannerTitle =>
      'Gespeicherte Buchung wird gesendet';

  @override
  String get operationSyncingBannerDescription =>
      'Bis der Server bestätigt, ändert sie deinen Kontostand nicht.';

  @override
  String get operationHomeUpdatingBannerTitle => 'Startseite wird aktualisiert';

  @override
  String get operationHomeUpdatingBannerDescription =>
      'Die Buchung ist auf dem Server gespeichert. Der Kontostand folgt gleich; du musst nichts erneut bestätigen.';

  @override
  String get operationHomeUpdatingAction => 'Jetzt aktualisieren';

  @override
  String get operationPendingBannerTitle =>
      'Buchung wartet auf Synchronisierung';

  @override
  String get operationPendingBannerDescription =>
      'Sie ist sicher auf dem Gerät gespeichert und ändert deinen Kontostand noch nicht.';

  @override
  String get operationAuthBannerTitle => 'Erneute Anmeldung nötig';

  @override
  String get operationAuthBannerDescription =>
      'Die gespeicherte Buchung bleibt auf dem Gerät, bis du dich sicher angemeldet hast.';

  @override
  String get operationAttentionBannerTitle => 'Gespeicherte Buchung prüfen';

  @override
  String get operationAttentionBannerDescription =>
      'Automatischer Versand gestoppt. Dein Kontostand ist unverändert.';

  @override
  String get operationLockedBannerDescription =>
      'Das Senden von Buchungen ist nach einer Sicherheitsprüfung gesperrt. Neue Bestätigungen werden nicht automatisch gesendet.';

  @override
  String get operationRetryNowAction => 'Erneut senden';

  @override
  String operationBeforeOpeningDateDetail(String openingDate) {
    return 'Das Konto beginnt am $openingDate. Frühere Buchungen sind nicht möglich. Du kannst das Startdatum in den Kontoeinstellungen vorverlegen.';
  }

  @override
  String get plannedCostSettingsAction => 'Zahlung planen';

  @override
  String get plannedCostSettingsDescription => 'Zum Beispiel Miete oder Abo';

  @override
  String get plannedCostTitle => 'Geplante Zahlung';

  @override
  String get plannedCostLoading => 'Konto wird geladen';

  @override
  String get plannedCostDescription =>
      'Eine geplante Zahlung ändert deinen Kontostand nicht. Sie steht bei den anstehenden Zahlungen, bis du sie bestätigst.';

  @override
  String get plannedCostAccountRequired =>
      'Lege zuerst ein Konto an: Die geplante Zahlung gehört zu einem Konto.';

  @override
  String get plannedCostTitleLabel => 'Name';

  @override
  String get plannedCostTitleHint => 'Miete';

  @override
  String get plannedCostAmountLabel => 'Betrag';

  @override
  String get plannedCostDateLabel => 'Zahlungsdatum';

  @override
  String get plannedCostChooseDateAction => 'Datum wählen';

  @override
  String get plannedCostSubmitAction => 'Planen';

  @override
  String get plannedCostRetryAction => 'Wiederholen';

  @override
  String get plannedCostAcceptedTitle => 'Zahlung geplant';

  @override
  String get plannedCostAcceptedDescription =>
      'Sie ändert deinen Kontostand nicht und wartet auf deine Bestätigung.';

  @override
  String get plannedCostHomePending => 'Startseite wird aktualisiert';

  @override
  String get plannedCostHomeUpdated => 'Startseite aktualisiert';

  @override
  String get plannedCostHomeDelayed =>
      'Startseite wird etwas später aktualisiert';

  @override
  String get plannedCostHomeFailed =>
      'Startseite konnte nicht aktualisiert werden';

  @override
  String get plannedCostInvalidInput => 'Prüfe Name, Betrag und Datum.';

  @override
  String get plannedCostIssueAccountUnavailable => 'Konto nicht verfügbar.';

  @override
  String get plannedCostIssueCurrencyMismatch =>
      'Die Währung passt nicht zur Kontowährung.';

  @override
  String get plannedCostIssueUnsupportedCurrency =>
      'Diese Währung wird noch nicht unterstützt.';

  @override
  String get plannedCostIssueBeforeBaseline =>
      'Das Datum liegt vor dem Startdatum des Kontos. Wähle ein späteres.';

  @override
  String get plannedCostGenericFailure =>
      'Zahlung konnte nicht geplant werden.';

  @override
  String get plannedCostDoneAction => 'Fertig';

  @override
  String get plannedCostListTitle => 'Geplant';

  @override
  String get plannedCostListEmpty => 'Noch nichts geplant.';

  @override
  String get plannedCostCancelAction => 'Verwerfen';

  @override
  String get plannedCostCancelSemantics => 'Plan verwerfen';

  @override
  String get plannedCostDueLabel => 'Fällig';

  @override
  String get plannedCostOverdueLabel => 'Überfällig';

  @override
  String get plannedCostCancelFailure => 'Plan konnte nicht verworfen werden.';

  @override
  String get plannedCostConfirmAction => 'Bezahlt';

  @override
  String get plannedCostConfirmSemantics => 'Plan als bezahlt markieren';

  @override
  String get plannedCostConfirmFailure =>
      'Buchung konnte nicht gespeichert werden. Der Plan bleibt in der Liste — versuch es noch einmal.';

  @override
  String get plannedCostConfirmHint =>
      '„Bezahlt“ erstellt eine normale Ausgabe und nimmt den Plan aus der Liste.';

  @override
  String get savingsGoalTitle => 'Ziele';

  @override
  String get savingsGoalLoading => 'Ziele werden geladen';

  @override
  String get savingsGoalAccountRequired =>
      'Lege zuerst ein Konto an — das Sparziel läuft in dessen Währung.';

  @override
  String get savingsGoalGenericFailure =>
      'Das hat nicht geklappt. Versuch es noch einmal.';

  @override
  String get savingsGoalInvalidInput => 'Prüfe Name, Betrag und Datum.';

  @override
  String get savingsGoalRetryAction => 'Wiederholen';

  @override
  String get savingsGoalDescription =>
      'Ein Sparziel zeigt, wie viel du schon zurückgelegt hast. Das Geld bleibt auf dem Konto: Kontostand, Einnahmen und Ausgaben ändern sich nicht.';

  @override
  String get savingsGoalEmpty => 'Noch kein Sparziel.';

  @override
  String get savingsGoalCreateAction => 'Neues Sparziel';

  @override
  String get savingsGoalCancelCreateAction => 'Abbrechen';

  @override
  String get savingsGoalTitleLabel => 'Name';

  @override
  String get savingsGoalTitleHint => 'Urlaub';

  @override
  String get savingsGoalTargetLabel => 'Zielbetrag';

  @override
  String get savingsGoalMonthlyLabel => 'Sparrate pro Monat';

  @override
  String get savingsGoalMonthlyHelper =>
      'Optional. Ein Richtwert, keine Verpflichtung.';

  @override
  String get savingsGoalDateLabel => 'Bis wann';

  @override
  String get savingsGoalChooseDateAction => 'Datum wählen';

  @override
  String get savingsGoalSubmitAction => 'Sparziel anlegen';

  @override
  String get savingsGoalContributionLabel => 'Betrag';

  @override
  String get savingsGoalDepositAction => 'Zurücklegen';

  @override
  String get savingsGoalWithdrawAction => 'Entnehmen';

  @override
  String get savingsGoalCancelAction => 'Sparziel aufgeben';

  @override
  String get savingsGoalCancelSemantics =>
      'Sparziel aufgeben und aus der Liste entfernen';

  @override
  String get savingsGoalDepositSemantics =>
      'Angegebenen Betrag für dieses Sparziel zurücklegen';

  @override
  String get savingsGoalWithdrawSemantics =>
      'Angegebenen Betrag aus diesem Sparziel entnehmen';

  @override
  String get savingsGoalAchievedLabel => 'Sparziel erreicht';

  @override
  String get savingsGoalIssueAccountUnavailable =>
      'Konto nicht verfügbar. Aktualisiere die Ansicht.';

  @override
  String get savingsGoalIssueCurrencyMismatch =>
      'Die Währung des Sparziels muss zur Kontowährung passen.';

  @override
  String get savingsGoalIssueUnsupportedCurrency =>
      'Diese Währung wird noch nicht unterstützt.';

  @override
  String get savingsGoalIssueBeforeBaseline =>
      'Das Datum liegt vor der Kontoeröffnung.';

  @override
  String get savingsGoalIssueFutureContribution =>
      'Zurücklegen geht nur für heute oder früher.';

  @override
  String get savingsGoalIssueNotActive =>
      'Das Sparziel ist bereits abgeschlossen. Aktualisiere die Ansicht.';

  @override
  String get savingsGoalIssueWithdrawalTooLarge =>
      'Im Sparziel ist weniger Geld, als du entnehmen willst.';

  @override
  String get categoryPickerNone => 'Ohne Kategorie';

  @override
  String get categoryPickerOther => 'Andere (eintippen)';

  @override
  String get categoryPickerOtherLabel => 'Eigene Kategorie';

  @override
  String get categoryPickerLoading => 'Kategorien werden geladen';

  @override
  String get categoryPickerUnavailable =>
      'Kategorieliste nicht verfügbar — gib den Namen selbst ein.';

  @override
  String get categorySeedGroceries => 'Lebensmittel';

  @override
  String get categorySeedEatingOut => 'Cafés und Restaurants';

  @override
  String get categorySeedTransport => 'Verkehr';

  @override
  String get categorySeedHousing => 'Wohnen';

  @override
  String get categorySeedUtilities => 'Telefon und Internet';

  @override
  String get categorySeedHealth => 'Gesundheit';

  @override
  String get categorySeedClothing => 'Kleidung';

  @override
  String get categorySeedEntertainment => 'Freizeit';

  @override
  String get categorySeedEducation => 'Bildung';

  @override
  String get categorySeedGiftsOut => 'Geschenke';

  @override
  String get categorySeedOtherExpense => 'Sonstiges';

  @override
  String get categorySeedSalary => 'Gehalt';

  @override
  String get categorySeedFreelance => 'Nebenverdienst';

  @override
  String get categorySeedGiftsIn => 'Geschenke';

  @override
  String get categorySeedInterest => 'Zinsen';

  @override
  String get categorySeedOtherIncome => 'Sonstiges';

  @override
  String get categoriesSettingsAction => 'Kategorien';

  @override
  String get categoriesSettingsDescription =>
      'Eigene Namen für Ausgaben und Einnahmen';

  @override
  String get categoriesTitle => 'Kategorien';

  @override
  String get categoriesExpenseTab => 'Ausgaben';

  @override
  String get categoriesIncomeTab => 'Einnahmen';

  @override
  String get categoryAddAction => 'Kategorie hinzufügen';

  @override
  String get categoryNameLabel => 'Name';

  @override
  String get categoryCreateAction => 'Erstellen';

  @override
  String get categorySaveAction => 'Speichern';

  @override
  String get categoryRenameAction => 'Umbenennen';

  @override
  String get categoryHideAction => 'Ausblenden';

  @override
  String get categoryRestoreAction => 'Einblenden';

  @override
  String categoryHiddenSection(int count) {
    return 'Ausgeblendet: $count';
  }

  @override
  String get categoryHiddenNote =>
      'Eine ausgeblendete Kategorie wird bei neuen Einträgen nicht angeboten, bleibt aber bei früheren Buchungen erhalten.';

  @override
  String get categoryListEmpty => 'Noch keine Kategorie';

  @override
  String get categoryHideDialogTitle => 'Kategorie ausblenden?';

  @override
  String get categoryHideDialogDescription =>
      'Sie verschwindet aus der Auswahl für neue Einträge. Frühere Buchungen bleiben darin, und du kannst sie wieder einblenden.';

  @override
  String get categoryNameTakenError => 'Diesen Namen gibt es schon';

  @override
  String get categoryArchivedError =>
      'Kategorie ist ausgeblendet — blende sie zuerst ein';

  @override
  String get categoryNotFoundError => 'Kategorie nicht gefunden';

  @override
  String get categoryNameInvalidError =>
      'Gib einen Namen mit bis zu 100 Zeichen ein';

  @override
  String get categoryLoadError => 'Kategorien konnten nicht geladen werden';

  @override
  String get operationCorrectAction => 'Ändern';

  @override
  String get operationRemoveAction => 'Löschen';

  @override
  String get operationCorrectTitle => 'Buchung korrigieren';

  @override
  String get operationCorrectSave => 'Speichern';

  @override
  String get operationCorrectedMessage => 'Buchung korrigiert';

  @override
  String get operationRemovedMessage => 'Buchung gelöscht';

  @override
  String get operationRemoveDialogTitle => 'Buchung löschen?';

  @override
  String get operationRemoveDialogBody =>
      'Sie zählt nicht mehr für Kontostand und Auswertungen. Der Eintrag selbst bleibt im Änderungsverlauf erhalten.';

  @override
  String get operationCorrectionFailed =>
      'Änderung konnte nicht gespeichert werden. Versuch es noch einmal.';

  @override
  String get operationAlreadyReversedMessage =>
      'Diese Buchung wurde schon korrigiert. Aktualisiere die Liste.';

  @override
  String get operationNotFoundMessage => 'Diese Buchung gibt es nicht mehr.';

  @override
  String get operationHistoryTitle => 'Alle Buchungen';

  @override
  String get operationHistorySettingsAction => 'Alle Buchungen';

  @override
  String get operationHistorySettingsDescription =>
      'Verlauf und ursprüngliche Eingaben';

  @override
  String get operationHistoryEmpty => 'Noch keine Einträge';

  @override
  String get operationHistoryMore => 'Mehr anzeigen';

  @override
  String get operationHistoryLoadError =>
      'Buchungen konnten nicht geladen werden';

  @override
  String get operationHistoryLoadMoreError =>
      'Weitere Einträge konnten nicht geladen werden';

  @override
  String operationHistoryDate(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get operationDetailDate => 'Datum';

  @override
  String get operationDetailCategory => 'Kategorie';

  @override
  String get operationDetailMerchant => 'Wo';

  @override
  String get operationDetailOriginalText => 'Ursprünglich eingegeben';

  @override
  String get operationDetailOriginalTextHint =>
      'Die Kategorie wurde später umbenannt';

  @override
  String get analyticsExpenseByCategory => 'Ausgaben nach Kategorie';

  @override
  String get analyticsIncomeByCategory => 'Einnahmen nach Kategorie';

  @override
  String get analyticsBreakdownEmpty => 'Keine Einträge in diesem Monat';

  @override
  String get analyticsLoadError => 'Analyse konnte nicht berechnet werden';

  @override
  String analyticsShare(String percent) {
    return '$percent%';
  }

  @override
  String analyticsMonth(DateTime month) {
    final intl.DateFormat monthDateFormat = intl.DateFormat.LLLL(localeName);
    final String monthString = monthDateFormat.format(month);

    return '$monthString';
  }

  @override
  String get profileLoadError => 'Profil konnte nicht geladen werden';

  @override
  String get profileEmailLabel => 'Anmelde-E-Mail';

  @override
  String get profileAccountSection => 'KONTO';

  @override
  String get profileTimezoneSetting => 'Zeitzone';

  @override
  String get profileNoAccount => 'Das Konto erscheint nach dem ersten Eintrag';

  @override
  String profileOpeningDateValue(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Aktuell $dateString';
  }

  @override
  String profileVersion(String version) {
    return 'Version $version';
  }

  @override
  String get entrySentenceField => 'Beschreibe die Buchung in einem Satz';

  @override
  String get entrySentenceHint =>
      'Gestern 12,50 Euro für Lebensmittel ausgegeben';

  @override
  String get entrySentenceParseAction => 'Auswerten';

  @override
  String get entrySentenceFilled =>
      'Felder unten ausgefüllt — prüfe und bestätige sie.';

  @override
  String get entrySentenceParseError => 'Satz konnte nicht ausgewertet werden.';

  @override
  String get entrySentenceEmpty =>
      'Schreib einen kürzeren Satz oder beginne mit dem Betrag.';

  @override
  String get entrySentenceGapAmount => 'Keinen Betrag gefunden — trag ihn ein.';

  @override
  String get entrySentenceGapAmbiguous =>
      'Mehrere Zahlen im Satz — gib den Betrag an.';

  @override
  String get entrySentenceGapDate => 'Datum nicht verstanden — prüfe es.';

  @override
  String get entrySentenceGapCategory =>
      'Keine Kategorie gefunden — wähle eine aus.';

  @override
  String get entrySentenceGapTransfer =>
      'Das ist eine Umbuchung, keine Einnahme oder Ausgabe — deshalb habe ich nichts ausgefüllt.';

  @override
  String get entrySentenceOpenTransfer => 'Umbuchung öffnen';

  @override
  String get categoryKeywordsTitle => 'Stichwörter der Kategorie';

  @override
  String get categoryKeywordsAction => 'Stichwörter';

  @override
  String get categoryKeywordsDescription =>
      'Beginnt ein Wort im Satz mit einem dieser Wörter, landet die Buchung in dieser Kategorie. „auto“ findet auch „Autowäsche“, „lebensmittel“ auch „Lebensmitteln“.';

  @override
  String get categoryKeywordsEmpty =>
      'Noch keine Wörter — die Kategorie wird nur über ihren Namen gefunden.';

  @override
  String get categoryKeywordsField => 'Wort hinzufügen';

  @override
  String get categoryKeywordsAdd => 'Hinzufügen';

  @override
  String categoryKeywordsRemove(String keyword) {
    return 'Wort $keyword entfernen';
  }

  @override
  String get categoryKeywordsInvalid =>
      'Ein Wort braucht mindestens drei Buchstaben oder Ziffern, ohne Leerzeichen.';

  @override
  String get categoryKeywordsTaken =>
      'Dieses Wort führt schon zu einer anderen Kategorie. Entferne es dort.';

  @override
  String get categoryKeywordsArchived =>
      'Eine ausgeblendete Kategorie wird nicht zugeordnet.';

  @override
  String get categoryKeywordsLoadError => 'Wörter konnten nicht geladen werden';

  @override
  String get categoryKeywordsSaveError =>
      'Wort konnte nicht gespeichert werden';

  @override
  String get analyticsPeriod7Days => '7 Tage';

  @override
  String get analyticsPeriodMonth => 'Monat';

  @override
  String get analyticsPeriodQuarter => 'Quartal';

  @override
  String get analyticsPeriodYear => 'Jahr';

  @override
  String get analyticsPeriodCustom => 'Eigener Zeitraum';

  @override
  String get analyticsPeriodLabel => 'Zeitraum';

  @override
  String get analyticsBalanceTitle => 'Kontostand';

  @override
  String analyticsBalanceFromTo(String opening, String closing) {
    return '$opening → $closing';
  }

  @override
  String analyticsBalanceChange(String change) {
    return 'im Zeitraum $change';
  }

  @override
  String get analyticsNoSpending => 'Keine Ausgaben in diesem Zeitraum';

  @override
  String analyticsPreviousAmount(String amount) {
    return 'vorher $amount';
  }

  @override
  String analyticsWindowRange(String from, String to) {
    return '$from — $to';
  }

  @override
  String analyticsComparedWith(String from, String to) {
    return 'im Vergleich zu $from — $to';
  }

  @override
  String get plannedCostIssueCategoryUnavailable =>
      'Diese Kategorie ist nicht verfügbar. Wähle eine andere.';

  @override
  String get plannedCostRepeatToggle => 'Jeden Monat wiederholen';

  @override
  String get plannedCostRepeatDayLabel => 'Tag im Monat';

  @override
  String get plannedCostRepeatLastDay => 'Letzter Tag im Monat';

  @override
  String get plannedCostRepeatShortMonthHint =>
      'In kurzen Monaten rückt die Zahlung auf den letzten Tag: 31. Januar, 28. Februar, 31. März.';

  @override
  String get plannedCostRepeatFirstDatesTitle => 'Nächste Termine';

  @override
  String get plannedCostRecurrenceListTitle => 'Wiederkehrend';

  @override
  String get plannedCostRecurrenceListEmpty =>
      'Noch keine wiederkehrenden Zahlungen.';

  @override
  String plannedCostRecurrenceMonthlyOnDay(int day) {
    return 'Jeden Monat am $day.';
  }

  @override
  String get plannedCostRecurrenceMonthlyLastDay =>
      'Jeden Monat am letzten Tag';

  @override
  String get plannedCostRecurrenceEndAction => 'Beenden';

  @override
  String get plannedCostRecurrenceEndDialogTitle => 'Serie beenden?';

  @override
  String get plannedCostRecurrenceEndDialogBody =>
      'Es werden keine neuen Zahlungen angelegt. Künftige geplante Zahlungen dieser Serie werden verworfen, bereits fällige bleiben — du musst sie bestätigen oder überspringen.';

  @override
  String plannedCostRecurrenceEndedMessage(int count) {
    return 'Serie beendet. Verworfene künftige Zahlungen: $count';
  }

  @override
  String get plannedCostSkipAction => 'Überspringen';

  @override
  String get plannedCostSkipHint =>
      '„Überspringen“ entfernt eine Zahlung, die Serie läuft weiter.';

  @override
  String get plannedCostRecurrenceAcceptedTitle =>
      'Wiederkehrende Zahlung gespeichert';

  @override
  String get plannedCostRecurrenceAcceptedDescription =>
      'Die Zahlungen erscheinen von selbst. Das ist eine Prognose: Sie ändert deinen Kontostand nicht.';

  @override
  String get plannedCostRecurrenceFailure =>
      'Wiederkehrende Zahlung konnte nicht geändert werden.';

  @override
  String get appUpdateCheckAction => 'Nach Updates suchen';

  @override
  String get appUpdateCheckDescription =>
      'Beim Server nachfragen, ob es eine neue Version gibt';

  @override
  String get appUpdateChecking => 'Wird geprüft…';

  @override
  String get appUpdateUpToDate => 'Du hast die neueste Version.';

  @override
  String appUpdateAvailable(String version, String size) {
    return 'Version $version verfügbar, $size';
  }

  @override
  String get appUpdateNotesLabel => 'Was ist neu';

  @override
  String get appUpdateDownloadAction => 'Laden und installieren';

  @override
  String appUpdateDownloading(int percent) {
    return 'Wird geladen… $percent%';
  }

  @override
  String get accountExportAction => 'Meine Daten exportieren';

  @override
  String get accountExportDescription =>
      'Vollständige Datei mit allen Daten und eine Buchungstabelle für Excel';

  @override
  String get accountExportPreparing => 'Dateien werden vorbereitet…';

  @override
  String get accountExportFailedUnreachable =>
      'Server nicht erreichbar. Prüfe deine Internetverbindung und versuch es noch einmal.';

  @override
  String get accountExportFailedUnavailable =>
      'Der Server konnte den Datenexport nicht vorbereiten. Versuch es später noch einmal.';

  @override
  String get accountExportFailedAuthentication =>
      'Sitzung beendet — melde dich neu an.';

  @override
  String get accountExportFailedShare =>
      'Die Dateien sind fertig, aber das Fenster „Teilen“ hat sich nicht geöffnet.';

  @override
  String get accountExportFailedStorage =>
      'Die Dateien konnten nicht auf dem Handy gespeichert werden.';

  @override
  String get accountDeletionAction => 'Account löschen';

  @override
  String get accountDeletionActionDescription =>
      'In 7 Tagen. Anders überlegt — melde dich einfach wieder an';

  @override
  String get accountDeletionTitle => 'Account löschen';

  @override
  String get accountDeletionHeadline => 'Dein Account wird in 7 Tagen gelöscht';

  @override
  String get accountDeletionWhat =>
      'Alles wird gelöscht: Konten, Buchungen, Umbuchungen, Kategorien, Pläne, Budgets und Sparziele. Du kannst sie danach nicht wiederherstellen.';

  @override
  String get accountDeletionSignedOut =>
      'Du wirst sofort auf allen Geräten abgemeldet. Überlegst du es dir anders, melde dich innerhalb von 7 Tagen an — dann wird die Löschung abgebrochen.';

  @override
  String get accountDeletionBackups =>
      'In den Server-Backups bleiben die Daten noch bis zu 14 Tage gespeichert, danach verschwinden sie auch dort.';

  @override
  String get accountDeletionExportFirst => 'Zuerst meine Daten exportieren';

  @override
  String accountDeletionUnsent(int count) {
    return 'Buchungen auf diesem Handy, die den Server noch nicht erreicht haben: $count. Sie fehlen im Datenexport und gehen mit dem Account verloren. Warte besser, bis sie gesendet sind.';
  }

  @override
  String get accountDeletionPasswordLabel => 'Passwort';

  @override
  String get accountDeletionPasswordHelp =>
      'Dasselbe, mit dem du dich anmeldest. So kannst nur du deinen Account löschen.';

  @override
  String get accountDeletionPasswordRejected => 'Falsches Passwort';

  @override
  String get accountDeletionSubmit => 'Account löschen';

  @override
  String get accountDeletionConfirmTitle => 'Account löschen?';

  @override
  String get accountDeletionConfirmBody =>
      'Du wirst auf allen Geräten abgemeldet. In 7 Tagen werden alle Daten gelöscht, wenn du dich nicht vorher anmeldest.';

  @override
  String get accountDeletionConfirmCancel => 'Abbrechen';

  @override
  String get accountDeletionConfirmAccept => 'Löschen';

  @override
  String get accountDeletionUnreachable =>
      'Server nicht erreichbar. Es wurde nichts gelöscht — prüfe deine Internetverbindung und versuch es noch einmal.';

  @override
  String get accountDeletionUnavailable =>
      'Der Server konnte die Anfrage nicht annehmen. Es wurde nichts gelöscht — versuch es später noch einmal.';

  @override
  String get accountDeletionAuthentication =>
      'Sitzung beendet — melde dich neu an. Es wurde nichts gelöscht.';

  @override
  String accountDeletionScheduledNotice(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Dein Account wird am $dateString gelöscht. Um das abzubrechen, melde dich einfach vor diesem Tag an.';
  }

  @override
  String get accountDeletionScheduledNoticeUndated =>
      'Dein Account wird in 7 Tagen gelöscht. Um das abzubrechen, melde dich einfach vorher an.';

  @override
  String get accountDeletionCancelled =>
      'Löschung abgebrochen — du bist angemeldet und alle Daten sind noch da.';

  @override
  String get appUpdateHandedToInstaller =>
      'Datei geladen und geprüft. Bestätige die Installation im Systemfenster — Android installiert das Update selbst, das dauert bis zu einer Minute. Du musst nichts neu laden: Der Installer braucht die Datei gerade.';

  @override
  String get appUpdateOpenInstallerAction => 'Installation wieder öffnen';

  @override
  String get appUpdateNeedsPermission =>
      'Android möchte, dass du Installationen aus dieser App erlaubst. Das ist nur einmal nötig.';

  @override
  String get appUpdatePermissionAction => 'Einstellungen öffnen';

  @override
  String get appUpdateFailedUnreachable =>
      'Server nicht erreichbar. Versuch es später noch einmal.';

  @override
  String get appUpdateFailedServer =>
      'Der Server konnte keine Auskunft zu Updates geben.';

  @override
  String get appUpdateFailedCorrupted =>
      'Die Datei war beschädigt und wurde gelöscht. Versuch es noch einmal.';

  @override
  String get appUpdateFailedInstaller =>
      'Android-Installer konnte nicht geöffnet werden.';

  @override
  String get appUpdateFailedAuth => 'Du musst dich neu anmelden.';

  @override
  String get appUpdateRetryAction => 'Wiederholen';

  @override
  String appUpdateMegabytes(String megabytes) {
    return '$megabytes MB';
  }

  @override
  String get notificationsQuietLabel => 'Benachrichtigungen';

  @override
  String get notificationsEmpty => 'Nichts, was deine Aufmerksamkeit braucht.';

  @override
  String get notificationsEmptyHint =>
      'Hier erscheinen Erinnerungen an Zahlungen und neue App-Versionen.';

  @override
  String notificationUpdateTitle(String version) {
    return 'Version $version verfügbar';
  }

  @override
  String get notificationUpdateBody => 'Du kannst im Profil aktualisieren.';

  @override
  String get notificationUpdateAction => 'Profil öffnen';

  @override
  String notificationPaymentOverdueTitle(String title) {
    return 'Zahlung überfällig: $title';
  }

  @override
  String notificationPaymentDueSoonTitle(String title) {
    return 'Zahlung bald fällig: $title';
  }

  @override
  String notificationPaymentBody(String date, String amount) {
    return '$date, $amount';
  }

  @override
  String get notificationPaymentAction => 'Geplante Zahlungen';

  @override
  String get budgetsTitle => 'Budgets';

  @override
  String get budgetsSettingsAction => 'Budgets';

  @override
  String get budgetsSettingsDescription =>
      'Monatslimits und was noch übrig ist';

  @override
  String budgetsPeriod(String from, String to) {
    return '$from — $to';
  }

  @override
  String get budgetsOverallTitle => 'Alle Ausgaben';

  @override
  String get budgetsEmpty => 'Noch keine Limits.';

  @override
  String get budgetsEmptyHint =>
      'Setze ein Monatslimit für eine Kategorie oder für alle Ausgaben.';

  @override
  String budgetsSpentOfLimit(String spent, String limit) {
    return '$spent von $limit ausgegeben';
  }

  @override
  String budgetsRemaining(String amount) {
    return 'Noch $amount übrig';
  }

  @override
  String budgetsOverspentBy(String amount) {
    return '$amount überzogen';
  }

  @override
  String budgetsPlanned(String amount) {
    return 'Noch $amount geplant';
  }

  @override
  String get budgetsAddAction => 'Limit setzen';

  @override
  String get budgetsRemoveAction => 'Entfernen';

  @override
  String get budgetsRemoveDialogTitle => 'Limit entfernen?';

  @override
  String get budgetsRemoveDialogBody =>
      'Die Ausgaben bleiben, nur das Limit zählt nicht mehr. Du kannst jederzeit ein neues setzen.';

  @override
  String get budgetsCategoryLabel => 'Wofür';

  @override
  String get budgetsLimitLabel => 'Limit pro Monat';

  @override
  String get budgetsSaveAction => 'Speichern';

  @override
  String get budgetsLoadError => 'Budgets konnten nicht geladen werden.';

  @override
  String get budgetsWriteError => 'Limit konnte nicht gespeichert werden.';

  @override
  String get budgetsNoCategoriesLeft =>
      'Alle Kategorien haben schon ein Limit.';

  @override
  String get budgetsAccountRequired => 'Lege zuerst ein Konto an.';

  @override
  String get timezoneTitle => 'Zeitzone';

  @override
  String timezoneCurrent(String zone) {
    return 'Aktuell $zone';
  }

  @override
  String get timezoneExplanation =>
      'Hier legst du fest, wo Tag und Monat enden. Bereits erfasste Buchungen behalten ihr Datum — es ändert sich nur, was als „heute“ und „dieser Monat“ gilt.';

  @override
  String get timezoneSearchField => 'Stadt oder Zone suchen';

  @override
  String get timezoneDeviceSection => 'ZEITZONE DES HANDYS';

  @override
  String get timezoneAllSection => 'ALLE ZEITZONEN';

  @override
  String get timezoneNothingFound => 'Nichts gefunden';

  @override
  String timezoneConfirmTitle(String zone) {
    return 'Zeitzone auf $zone ändern?';
  }

  @override
  String get timezoneConfirmBody =>
      'Beträge und Daten erfasster Buchungen ändern sich nicht. Neu berechnet werden nur „heute“ und die Monatsgrenzen.';

  @override
  String get timezoneConfirmAction => 'Ändern';

  @override
  String timezoneCorrected(String zone) {
    return 'Zeitzone: $zone';
  }

  @override
  String get timezoneUnchangedError =>
      'Diese Zeitzone ist bereits eingestellt.';

  @override
  String get timezoneBehindOperationsError =>
      'In dieser Zeitzone läge die letzte Buchung in der Zukunft, und ihr Betrag würde bis morgen im Kontostand fehlen. Wähle eine Zone weiter östlich oder versuch es später noch einmal.';

  @override
  String get timezoneWriteError => 'Zeitzone konnte nicht geändert werden.';

  @override
  String get timezoneLoadError => 'Konto konnte nicht geladen werden.';

  @override
  String get timezoneAccountRequired => 'Lege zuerst ein Konto an.';

  @override
  String get timezoneSettingsDescription => 'Wo Tag und Monat enden';

  @override
  String get entrySentenceGapCurrency =>
      'Währung nicht erkannt — trag den Betrag selbst ein.';

  @override
  String entrySentenceCurrencyMismatch(String parsed, String account) {
    return 'Betrag in $parsed, Konto in $account — nicht übernommen.';
  }

  @override
  String get otherWalletsTitle => 'WEITERE KONTEN';

  @override
  String get transferTitle => 'Umbuchung';

  @override
  String get transferSettingsAction => 'Umbuchung';

  @override
  String get transferSettingsDescription =>
      'Geldbewegung zwischen zwei Konten erfassen';

  @override
  String get transferFromField => 'Von';

  @override
  String get transferToField => 'Nach';

  @override
  String get transferFromAmountField => 'Abgebucht';

  @override
  String get transferToAmountField => 'Angekommen';

  @override
  String get transferDateField => 'Wann';

  @override
  String transferRateLabel(String from, String rate, String to) {
    return 'Kurs: 1 $from = $rate $to';
  }

  @override
  String get transferRateHint =>
      'Der Kurs kommt nicht aus dem Internet — er ergibt sich aus den zwei Beträgen, die du eingegeben hast.';

  @override
  String get transferReviewAction => 'Weiter';

  @override
  String get transferConfirmAction => 'Umbuchen';

  @override
  String get transferEditAction => 'Ändern';

  @override
  String get transferAcceptedTitle => 'Umbuchung gespeichert';

  @override
  String transferAcceptedBody(String fromAmount, String toAmount) {
    return '$fromAmount → $toAmount';
  }

  @override
  String get transferSecondWalletRequired =>
      'Für eine Umbuchung brauchst du ein zweites Konto in einer anderen Währung.';

  @override
  String get transferLoadError => 'Konten konnten nicht geladen werden.';

  @override
  String get transferWriteError => 'Umbuchung konnte nicht gespeichert werden.';

  @override
  String get transferSameWalletError => 'Wähle zwei verschiedene Konten.';

  @override
  String get transferIssueWalletUnavailable => 'Konto nicht verfügbar.';

  @override
  String get transferIssueCurrencyMismatch =>
      'Die Währung des Betrags passt nicht zur Kontowährung.';

  @override
  String get transferIssueBeforeBaseline =>
      'Das Geld kann nicht abgegangen sein, bevor es das Konto gab.';

  @override
  String get transferIssueFutureDate =>
      'Das Datum der Umbuchung liegt in der Zukunft.';

  @override
  String get transferIssueConfirmationBeforeCapture =>
      'Die Bestätigung liegt vor der Erfassung.';

  @override
  String get walletTitle => 'Neues Konto';

  @override
  String get walletSettingsAction => 'Konto anlegen';

  @override
  String get walletSettingsDescription =>
      'Konto in einer anderen Währung — das Geld wird nicht umgerechnet';

  @override
  String get walletNameField => 'Name';

  @override
  String get walletCurrencyField => 'Währung';

  @override
  String get walletOpeningBalanceField => 'Anfangssaldo';

  @override
  String get walletOpeningDateField => 'Ab welchem Datum';

  @override
  String get walletCurrencySearch => 'Währung suchen';

  @override
  String get walletCurrencyHeld => 'Schon vorhanden';

  @override
  String get walletExplanation =>
      'Zwischen Konten wird nichts umgerechnet. Jedes Konto hat seine eigene Währung, und eine Umbuchung wird mit zwei Beträgen erfasst.';

  @override
  String get walletReviewAction => 'Weiter';

  @override
  String get walletConfirmAction => 'Anlegen';

  @override
  String get walletOpenedTitle => 'Konto angelegt';

  @override
  String get walletAccountRequired => 'Lege zuerst dein Hauptkonto an.';

  @override
  String get walletLoadError => 'Konten konnten nicht geladen werden.';

  @override
  String get walletWriteError => 'Konto konnte nicht angelegt werden.';

  @override
  String get operationWalletField => 'Konto';

  @override
  String get spokenSentenceKept =>
      'Der Satz ist auf dem Handy gespeichert. Sobald du Internet hast, wartet er hier und auf der Startseite auf die Auswertung — bis zu 30 Tage.';

  @override
  String get spokenSentenceNotKept =>
      'Dieser Satz konnte nicht gespeichert werden. Sag ihn noch einmal, sobald du Internet hast.';

  @override
  String entrySentenceSaidAt(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat(
      'd MMMM, HH:mm',
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return 'Gesagt: $dateString — Datumsangaben zählen ab diesem Moment';
  }

  @override
  String waitingPhrasesTitle(int count) {
    return 'Warten auf Auswertung: $count';
  }

  @override
  String get waitingPhrasesDescription =>
      'Ohne Internet gesagt. Tippe auf einen Satz, um ihn auszuwerten; danach wird er vom Handy gelöscht.';

  @override
  String get waitingPhraseHidden => 'Satz ausgeblendet';

  @override
  String waitingPhraseSaidAt(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat(
      'd MMMM, HH:mm',
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return 'Gesagt: $dateString';
  }

  @override
  String get waitingPhraseForget => 'Satz löschen';

  @override
  String get waitingPhrasesNoticeDescription =>
      'Ohne Internet gesagt — tippe zum Auswerten';

  @override
  String waitingPhrasesNoticeLabel(int count) {
    return 'Ohne Internet gesagte Sätze warten auf Auswertung: $count. Öffnen';
  }

  @override
  String get languageFollowPhone => 'Wie auf dem Handy';

  @override
  String get languageSettingDescription => 'Anzeige und Spracheingabe';

  @override
  String currencyName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'EUR': 'Euro',
      'USD': 'US-Dollar',
      'UAH': 'Griwna',
      'GBP': 'Pfund Sterling',
      'PLN': 'Zloty',
      'CHF': 'Schweizer Franken',
      'CZK': 'Tschechische Krone',
      'SEK': 'Schwedische Krone',
      'NOK': 'Norwegische Krone',
      'DKK': 'Dänische Krone',
      'HUF': 'Forint',
      'RON': 'Rumänischer Leu',
      'BGN': 'Bulgarischer Lew',
      'RSD': 'Serbischer Dinar',
      'ALL': 'Albanischer Lek',
      'MKD': 'Mazedonischer Denar',
      'BAM': 'Konvertible Mark',
      'TRY': 'Türkische Lira',
      'MDL': 'Moldauischer Leu',
      'RUB': 'Russischer Rubel',
      'BYN': 'Belarussischer Rubel',
      'GEL': 'Lari',
      'AMD': 'Armenischer Dram',
      'AZN': 'Aserbaidschan-Manat',
      'KZT': 'Tenge',
      'UZS': 'Usbekischer Sum',
      'KGS': 'Kirgisischer Som',
      'ILS': 'Schekel',
      'AED': 'VAE-Dirham',
      'EGP': 'Ägyptisches Pfund',
      'INR': 'Indische Rupie',
      'CNY': 'Yuan',
      'JPY': 'Yen',
      'KRW': 'Won',
      'THB': 'Baht',
      'VND': 'Dong',
      'IDR': 'Indonesische Rupiah',
      'SGD': 'Singapur-Dollar',
      'HKD': 'Hongkong-Dollar',
      'AUD': 'Australischer Dollar',
      'NZD': 'Neuseeland-Dollar',
      'CAD': 'Kanadischer Dollar',
      'MXN': 'Mexikanischer Peso',
      'BRL': 'Brasilianischer Real',
      'ARS': 'Argentinischer Peso',
      'CLP': 'Chilenischer Peso',
      'ZAR': 'Südafrikanischer Rand',
      'MAD': 'Marokkanischer Dirham',
      'TND': 'Tunesischer Dinar',
      'ISK': 'Isländische Krone',
      'other': '$code',
    });
    return '$_temp0';
  }

  @override
  String timezoneCity(String zone) {
    String _temp0 = intl.Intl.selectLogic(zone, {
      'Europe_Lisbon': 'Lissabon',
      'Europe_Dublin': 'Dublin',
      'Europe_London': 'London',
      'Atlantic_Canary': 'Kanarische Inseln',
      'Europe_Madrid': 'Madrid',
      'Europe_Paris': 'Paris',
      'Europe_Brussels': 'Brüssel',
      'Europe_Amsterdam': 'Amsterdam',
      'Europe_Berlin': 'Berlin',
      'Europe_Zurich': 'Zürich',
      'Europe_Vienna': 'Wien',
      'Europe_Prague': 'Prag',
      'Europe_Rome': 'Rom',
      'Europe_Warsaw': 'Warschau',
      'Europe_Budapest': 'Budapest',
      'Europe_Stockholm': 'Stockholm',
      'Europe_Oslo': 'Oslo',
      'Europe_Copenhagen': 'Kopenhagen',
      'Europe_Belgrade': 'Belgrad',
      'Europe_Zagreb': 'Zagreb',
      'Europe_Ljubljana': 'Ljubljana',
      'Europe_Bratislava': 'Bratislava',
      'Europe_Athens': 'Athen',
      'Europe_Bucharest': 'Bukarest',
      'Europe_Sofia': 'Sofia',
      'Europe_Helsinki': 'Helsinki',
      'Europe_Tallinn': 'Tallinn',
      'Europe_Riga': 'Riga',
      'Europe_Vilnius': 'Vilnius',
      'Europe_Kyiv': 'Kiew',
      'Europe_Chisinau': 'Chișinău',
      'Europe_Minsk': 'Minsk',
      'Europe_Istanbul': 'Istanbul',
      'Europe_Moscow': 'Moskau',
      'Asia_Tbilisi': 'Tiflis',
      'Asia_Yerevan': 'Jerewan',
      'Asia_Baku': 'Baku',
      'Asia_Nicosia': 'Nikosia',
      'Asia_Jerusalem': 'Jerusalem',
      'Asia_Dubai': 'Dubai',
      'Asia_Tashkent': 'Taschkent',
      'Asia_Almaty': 'Almaty',
      'Asia_Bishkek': 'Bischkek',
      'Asia_Bangkok': 'Bangkok',
      'Asia_Singapore': 'Singapur',
      'Asia_Hong_Kong': 'Hongkong',
      'Asia_Shanghai': 'Shanghai',
      'Asia_Seoul': 'Seoul',
      'Asia_Tokyo': 'Tokio',
      'Australia_Perth': 'Perth',
      'Australia_Sydney': 'Sydney',
      'Pacific_Auckland': 'Auckland',
      'Africa_Cairo': 'Kairo',
      'Africa_Johannesburg': 'Johannesburg',
      'America_Sao_Paulo': 'São Paulo',
      'America_Argentina_Buenos_Aires': 'Buenos Aires',
      'America_New_York': 'New York',
      'America_Toronto': 'Toronto',
      'America_Chicago': 'Chicago',
      'America_Denver': 'Denver',
      'America_Los_Angeles': 'Los Angeles',
      'America_Mexico_City': 'Mexiko-Stadt',
      'other': 'UTC',
    });
    return '$_temp0';
  }
}
