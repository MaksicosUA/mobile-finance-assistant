// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'My finances';

  @override
  String get greetingMorningNeutral => 'Good morning';

  @override
  String get greetingDayNeutral => 'Good afternoon';

  @override
  String get greetingEveningNeutral => 'Good evening';

  @override
  String get greetingNightNeutral => 'Good night';

  @override
  String greetingMorning(String userName) {
    return 'Good morning, $userName';
  }

  @override
  String greetingDay(String userName) {
    return 'Good afternoon, $userName';
  }

  @override
  String greetingEvening(String userName) {
    return 'Good evening, $userName';
  }

  @override
  String greetingNight(String userName) {
    return 'Good night, $userName';
  }

  @override
  String get notificationsLabel => 'Notifications, new ones available';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsStubDescription =>
      'The notification center will be connected at the next stage.';

  @override
  String get openSettingsLabel => 'Open settings';

  @override
  String get balanceTitle => 'Balance';

  @override
  String get hideAmounts => 'Hide amounts';

  @override
  String get showAmounts => 'Show amounts';

  @override
  String get monthDelta => 'this month';

  @override
  String get balanceDeltaUnavailable => 'Monthly change unavailable';

  @override
  String get addBySentence => 'Record in a sentence';

  @override
  String get sentenceEntryLabel => 'Record a transaction in one sentence';

  @override
  String get addByVoice => 'Add by voice';

  @override
  String get voiceEntryLabel => 'Add a transaction by voice';

  @override
  String get typeBySentence => 'Type a sentence';

  @override
  String get voicePrompt => 'Say, for example: “spent 12.50 on groceries”';

  @override
  String get voiceNothingHeard => 'Nothing heard. Try again.';

  @override
  String get voiceNeedsNetwork =>
      'Speech recognition needs internet or English downloaded in the voice input settings.';

  @override
  String get voiceUnavailable =>
      'This phone has no speech recognition. You can type a sentence instead.';

  @override
  String get voiceFailed => 'Could not recognize your speech. Try again.';

  @override
  String get voiceTypeInsteadAction => 'Type';

  @override
  String get setupAccountAction => 'Set up account';

  @override
  String monthSummaryTitle(String month) {
    return 'Summary for $month';
  }

  @override
  String get income => 'Income';

  @override
  String get incomeCaption => 'received';

  @override
  String get expenses => 'Expenses';

  @override
  String get expensesCaption => 'spent';

  @override
  String get netFlow => 'Net flow';

  @override
  String get netPositiveCaption => 'positive';

  @override
  String get trendExpensesTitle => 'Expenses';

  @override
  String get trendBalanceTitle => 'Balance';

  @override
  String get trendUnknownTitle => 'Trend';

  @override
  String get trendLast7Days => 'last 7 days';

  @override
  String get trendLast30Days => 'last 30 days';

  @override
  String get trendPeriodUnknown => 'period';

  @override
  String get trend7DaysChip => '7 days';

  @override
  String get trend30DaysChip => '30 days';

  @override
  String get detailsAction => 'Details';

  @override
  String get trendEmpty => 'Not enough data for a chart yet';

  @override
  String trendSemantics(String title, String amount) {
    return '$title for the period, total $amount';
  }

  @override
  String get amountsHidden => 'amounts hidden';

  @override
  String goalDueDate(String date) {
    return 'by $date';
  }

  @override
  String goalProgressSummary(String target, String progress) {
    return 'of $target · $progress%';
  }

  @override
  String goalMonthlyContribution(String amount) {
    return 'You need to set aside about $amount a month';
  }

  @override
  String goalSemantics(
    String title,
    String current,
    String target,
    String progress,
  ) {
    return '$title, saved $current, goal $target, progress $progress percent, open goal';
  }

  @override
  String get upcomingPaymentsTitle => 'Upcoming payments';

  @override
  String get allPaymentsAction => 'All payments';

  @override
  String get noUpcomingPayments => 'No upcoming payments';

  @override
  String paymentDueDate(String date) {
    return 'due $date';
  }

  @override
  String paymentOverdueDate(String date) {
    return 'overdue · $date';
  }

  @override
  String paymentDateUnknown(String date) {
    return 'status being checked · $date';
  }

  @override
  String paymentSemantics(String title, String due, String amount) {
    return '$title, $due, $amount';
  }

  @override
  String get recentTransactionsTitle => 'Recent transactions';

  @override
  String get noRecentTransactions => 'No confirmed transactions yet';

  @override
  String get transactionCategoryUnavailable => 'No category';

  @override
  String transactionMetadata(String category, String date) {
    return '$category · $date';
  }

  @override
  String get transactionIncome => 'income';

  @override
  String get transactionExpense => 'expense';

  @override
  String get transactionTransfer => 'transfer';

  @override
  String get transactionUnknown => 'transaction';

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
  String get refreshingTitle => 'Updating data';

  @override
  String get refreshingDescription =>
      'Your current financial picture stays available.';

  @override
  String get partialDataTitle => 'Some data is temporarily unavailable';

  @override
  String get partialDataDescription => 'Available sections keep working.';

  @override
  String get offlineTitle => 'No connection';

  @override
  String offlineDataAsOf(String date, String time) {
    return 'Data as of $date, $time UTC.';
  }

  @override
  String get refreshFailedTitle => 'Could not update data';

  @override
  String get refreshFailedDescription =>
      'Showing your previous financial picture.';

  @override
  String get retryAction => 'Retry';

  @override
  String get fatalErrorTitle => 'Could not load data';

  @override
  String get fatalErrorDescription =>
      'Try again. If the error repeats, give support the request code.';

  @override
  String requestIdLabel(String requestId) {
    return 'Request code: $requestId';
  }

  @override
  String get authExpiredTitle => 'Session expired';

  @override
  String get authExpiredDescription =>
      'To protect your data, you need to sign in again.';

  @override
  String get signInAgainAction => 'Sign in again';

  @override
  String get sessionExpiredStubTitle => 'Sign in again';

  @override
  String get sessionExpiredStubDescription =>
      'The sign-in screen will be connected together with a real session. Financial data was not deleted.';

  @override
  String get balanceUnavailable => 'Balance temporarily unavailable';

  @override
  String get monthSummaryUnavailable => 'Month summary temporarily unavailable';

  @override
  String get trendUnavailable => 'Chart temporarily unavailable';

  @override
  String get goalNotSelected => 'No main goal selected yet';

  @override
  String get goalUnavailable =>
      'Goals are temporarily unavailable. We are already updating the data.';

  @override
  String get paymentsUnavailable => 'Upcoming payments temporarily unavailable';

  @override
  String get transactionsUnavailable =>
      'Recent transactions temporarily unavailable';

  @override
  String get emptyTitle =>
      'Add your first transaction to see your financial picture';

  @override
  String get emptyDescription =>
      'Just say what you bought or received — we will do the rest.';

  @override
  String get loadingLabel => 'Loading financial data';

  @override
  String get homeTab => 'Home';

  @override
  String get chatTab => 'Chat';

  @override
  String get analyticsTab => 'Analytics';

  @override
  String get goalsTab => 'Goals';

  @override
  String get profileTab => 'Profile';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get backLabel => 'Back';

  @override
  String get appearanceSection => 'APPEARANCE';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get accentColor => 'Accent color';

  @override
  String get tealAccent => 'Teal';

  @override
  String get blueAccent => 'Blue';

  @override
  String get purpleAccent => 'Purple';

  @override
  String get terracottaAccent => 'Terracotta';

  @override
  String get generalSection => 'GENERAL';

  @override
  String get privacySetting => 'Hide amounts';

  @override
  String get languageSetting => 'Language';

  @override
  String get baseCurrencySetting => 'Main currency';

  @override
  String get baselineSettingsAction => 'Tracking start date';

  @override
  String get baselineSettingsDescription =>
      'Allow transactions from an earlier period';

  @override
  String get baselineCorrectionTitle => 'Tracking start date';

  @override
  String get baselineCorrectionLoading => 'Loading account settings';

  @override
  String get baselineCorrectionDescription =>
      'Move the date back to add earlier transactions. The opening balance and currency will not change.';

  @override
  String get baselineCurrentDateLabel => 'Current tracking start date';

  @override
  String get baselineNewDateLabel => 'New date';

  @override
  String get baselineChooseDateAction => 'Choose date';

  @override
  String get baselineDateRangeHelp =>
      'You can only choose a date before the current tracking start date.';

  @override
  String get baselineReviewTitle => 'Review the new date';

  @override
  String get baselineReviewDescription =>
      'After you confirm, Home and the monthly totals will be recalculated from the server data.';

  @override
  String get baselineConfirmAction => 'Confirm new date';

  @override
  String get baselineSuccessTitle => 'Tracking start date changed';

  @override
  String baselineSuccessDescription(String date) {
    return 'You can now add transactions from $date onward.';
  }

  @override
  String get baselineHomeDelayedDescription =>
      'The date is saved. Home will update later; you do not need to confirm the change again.';

  @override
  String get baselineDoneAction => 'Done';

  @override
  String get baselineUnavailableTitle => 'The date cannot be changed yet';

  @override
  String get baselineAccountRequired => 'You need to set up an account first.';

  @override
  String get baselineMinimumDateReached =>
      'The account already starts at the earliest supported date.';

  @override
  String get baselineNotEarlierError =>
      'Choose a date before the current tracking start date.';

  @override
  String get baselineFutureError =>
      'The tracking start date cannot be later than today.';

  @override
  String get baselineAfterOperationError =>
      'The new date cannot be later than the earliest saved transaction.';

  @override
  String get baselineLoadFailed => 'Could not load account settings.';

  @override
  String get baselineChangeFailed =>
      'Could not change the date. Your financial data was not changed by the app.';

  @override
  String get stubDescription =>
      'This section will be built at the next stage. For now it is a navigation placeholder.';

  @override
  String get voiceStubTitle => 'Voice input';

  @override
  String get voiceStubDescription =>
      'The recording screen is a placeholder for now. The microphone and speech recognition will arrive at the next stage.';

  @override
  String get backHome => 'Back to Home';

  @override
  String get authLoadingLabel => 'Checking your secure session';

  @override
  String get loginTitle => 'Sign in';

  @override
  String get loginDescription => 'Sign in to open your financial picture.';

  @override
  String get registerTitle => 'Create account';

  @override
  String get registerDescription =>
      'Create a secure account to start tracking your finances.';

  @override
  String get displayNameField => 'Your name';

  @override
  String get displayNameRequired => 'Enter your name';

  @override
  String get emailField => 'Email';

  @override
  String get emailInvalid => 'Enter a valid email address';

  @override
  String get passwordField => 'Password';

  @override
  String get confirmPasswordField => 'Repeat password';

  @override
  String get passwordRequirements => 'At least 12 characters';

  @override
  String get passwordInvalid =>
      'The password must be 12 to 128 characters long';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get loginAction => 'Sign in';

  @override
  String get registerAction => 'Create account';

  @override
  String get createAccountAction => 'No account? Create one';

  @override
  String get haveAccountAction => 'Already have an account? Sign in';

  @override
  String get authSessionExpiredNotice =>
      'Your session has ended. Sign in again.';

  @override
  String get signedOutNotice => 'You have signed out.';

  @override
  String get invalidCredentialsError =>
      'Could not sign in. Check your email and password.';

  @override
  String get emailInUseError =>
      'Could not create the account. This email may already be in use.';

  @override
  String get authInvalidInputError => 'Check what you entered and try again.';

  @override
  String get authThrottledError => 'Too many attempts. Wait and try again.';

  @override
  String get authOfflineError =>
      'No internet connection. Check your network and try again.';

  @override
  String get authTimeoutError =>
      'The server did not respond in time. Try again.';

  @override
  String get authServiceError =>
      'Sign-in is temporarily unavailable. Try later.';

  @override
  String get authUnexpectedError => 'Could not finish signing in. Try again.';

  @override
  String get authSecureStorageError =>
      'Could not open secure storage on the device.';

  @override
  String get accountSection => 'USER ACCOUNT';

  @override
  String get signOutAction => 'Sign out';

  @override
  String get signOutDialogTitle => 'Sign out?';

  @override
  String get signOutDialogDescription =>
      'You will need to enter your email and password again to sign in next time.';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get financeEntryTitle => 'Transaction';

  @override
  String get financeEntryLoading => 'Checking your account';

  @override
  String get financeEntryLoadFailed => 'Could not open transaction entry';

  @override
  String get accountSetupTitle => 'Set up your first account';

  @override
  String get accountSetupDescription =>
      'Enter your actual balance. The start date sets the earliest day you can add a transaction for. You will review the data before saving.';

  @override
  String get accountNameField => 'Account name';

  @override
  String get accountNameHint => 'For example, Main account';

  @override
  String get accountNameRequired => 'Enter an account name';

  @override
  String get accountCurrencyRequired => 'Choose a currency';

  @override
  String get accountCurrencyHelp =>
      'This account\'s currency can\'t be changed later. You can open separate wallets for other currencies.';

  @override
  String get openingBalanceField => 'Opening balance';

  @override
  String get openingBalanceHelp =>
      'This is your starting balance, not income or an expense.';

  @override
  String get openingBalanceDateField => 'Opening balance date';

  @override
  String get canonicalTimezoneLabel => 'Tracking time zone';

  @override
  String get continueToReviewAction => 'Review data';

  @override
  String get accountReviewTitle => 'Review your account settings';

  @override
  String get reviewBeforeConfirmDescription =>
      'Financial data is saved only after you explicitly confirm.';

  @override
  String get confirmFinanceAction => 'Confirm and save';

  @override
  String get editAction => 'Edit';

  @override
  String get accountCreatedNotice =>
      'Account confirmed. Now add your first transaction.';

  @override
  String get manualOperationTitle => 'Add a transaction manually';

  @override
  String get manualOperationDescription =>
      'Fill in the fields. Voice and automatic recognition are not used yet.';

  @override
  String get accountLabel => 'Account';

  @override
  String get operationExpense => 'Expense';

  @override
  String get operationIncome => 'Income';

  @override
  String get operationTypeLabel => 'Transaction type';

  @override
  String get operationAmountField => 'Amount';

  @override
  String get merchantField => 'Place or recipient, optional';

  @override
  String get categoryField => 'Category, optional';

  @override
  String get operationDateField => 'Transaction date';

  @override
  String get operationReviewTitle => 'Review the transaction';

  @override
  String get addAnotherOperationAction => 'Add another';

  @override
  String get moneyInputInvalid =>
      'Enter a valid amount, such as 1250.50 or -20';

  @override
  String get positiveMoneyInputInvalid =>
      'Enter an amount above zero, such as 35 or 35.50';

  @override
  String get financeInvalidInput => 'Check the fields and try again.';

  @override
  String get financeValidationRejected =>
      'The data did not pass validation. Check the fields before sending again.';

  @override
  String get financeDateRejected => 'The date cannot be later than today.';

  @override
  String get operationBeforeOpeningDateError =>
      'The transaction date cannot be earlier than the opening balance date.';

  @override
  String get financeAccountUnavailable =>
      'This account is not available for this transaction. Refresh the screen and try again.';

  @override
  String get financeConflictError =>
      'This conflicts with a record already processed. Change the data and create a new confirmation.';

  @override
  String get financeOfflineError =>
      'Could not reach the server. Check your connection and try again.';

  @override
  String get financeTimeoutError =>
      'The server did not respond in time. You can safely repeat the confirmation.';

  @override
  String get financeServiceError =>
      'The transaction service is temporarily unavailable. Try again later.';

  @override
  String get financeSecurityError =>
      'Could not verify a secure connection. Check your settings and try again later.';

  @override
  String get financeLocalStorageError =>
      'Could not save the confirmation safely on the device. No request was sent to the server. Free up space or unlock secure storage and try again.';

  @override
  String get financeUnexpectedError =>
      'Received an invalid response. Your financial data was not changed by the app.';

  @override
  String get financeSessionChanged =>
      'Your secure session was renewed. Repeat the action; the confirmation will be sent with the same data.';

  @override
  String get operationAcceptedTitle => 'Transaction saved';

  @override
  String get operationAcceptedUpdatingHome =>
      'Transaction accepted. Waiting for a new version of Home.';

  @override
  String get operationAcceptedHomeUpdated =>
      'Home updated from the latest server version.';

  @override
  String get operationAcceptedProjectionDelayed =>
      'The transaction is saved, but the Home update is delayed. You do not need to confirm it again.';

  @override
  String get operationAcceptedAuthRequired =>
      'The transaction is saved, but you will need to sign in again to update Home.';

  @override
  String get operationAcceptedSessionChanged =>
      'The transaction is saved, but the session changed during the update. Open Home again.';

  @override
  String get operationAcceptedRefreshFailed =>
      'The transaction is saved. You can update Home later.';

  @override
  String get operationQueuedTitle => 'Transaction saved on the device';

  @override
  String get operationQueuedDescription =>
      'The confirmation is stored securely. If the server has not accepted it yet, it does not affect your balance. The current status is shown on Home.';

  @override
  String get operationQueuedAuthDescription =>
      'The confirmation is stored securely. You may need to sign in again to continue sending it. The current status is shown on Home.';

  @override
  String get operationAlreadySyncedTitle => 'Transaction already synced';

  @override
  String get operationAlreadySyncedDescription =>
      'The server confirmed this same transaction earlier. No duplicate record was created.';

  @override
  String get operationAttentionTitle => 'Transaction needs review';

  @override
  String get operationAttentionConflict =>
      'The saved confirmation conflicts with a request already processed and will not be sent automatically.';

  @override
  String get operationAttentionRejected =>
      'Finance Core rejected the confirmation. The balance is unchanged.';

  @override
  String get operationAttentionSecurity =>
      'Sending stopped by a security check. The balance is unchanged.';

  @override
  String get operationAttentionInvalid =>
      'The confirmation cannot be safely sent automatically. The balance is unchanged.';

  @override
  String get operationSyncingBannerTitle => 'Sending the saved transaction';

  @override
  String get operationSyncingBannerDescription =>
      'It does not affect your balance until the server confirms it.';

  @override
  String get operationHomeUpdatingBannerTitle => 'Home is updating';

  @override
  String get operationHomeUpdatingBannerDescription =>
      'The server has saved the transaction. Your balance will update when the data is ready; you do not need to confirm it again.';

  @override
  String get operationHomeUpdatingAction => 'Update now';

  @override
  String get operationPendingBannerTitle => 'Transaction waiting to sync';

  @override
  String get operationPendingBannerDescription =>
      'It is stored securely on the device and does not affect your balance yet.';

  @override
  String get operationAuthBannerTitle => 'You need to sign in again';

  @override
  String get operationAuthBannerDescription =>
      'The saved transaction stays on the device until you sign in securely.';

  @override
  String get operationAttentionBannerTitle => 'Check the saved transaction';

  @override
  String get operationAttentionBannerDescription =>
      'Automatic sending has stopped. The balance is unchanged.';

  @override
  String get operationLockedBannerDescription =>
      'Sending transactions is blocked after a security check. New confirmations will not be sent automatically.';

  @override
  String get operationRetryNowAction => 'Retry sending';

  @override
  String operationBeforeOpeningDateDetail(String openingDate) {
    return 'Tracking for this account starts on $openingDate. You cannot record transactions before that date. You can move the start date back in the account settings.';
  }

  @override
  String get plannedCostSettingsAction => 'Plan a payment';

  @override
  String get plannedCostSettingsDescription => 'Such as rent or a subscription';

  @override
  String get plannedCostTitle => 'Planned payment';

  @override
  String get plannedCostLoading => 'Loading account';

  @override
  String get plannedCostDescription =>
      'A planned payment does not change your balance. It appears in your upcoming payments until you confirm it.';

  @override
  String get plannedCostAccountRequired =>
      'Create an account first: a planned payment is linked to it.';

  @override
  String get plannedCostTitleLabel => 'Name';

  @override
  String get plannedCostTitleHint => 'Rent';

  @override
  String get plannedCostAmountLabel => 'Amount';

  @override
  String get plannedCostDateLabel => 'Payment date';

  @override
  String get plannedCostChooseDateAction => 'Choose date';

  @override
  String get plannedCostSubmitAction => 'Plan';

  @override
  String get plannedCostRetryAction => 'Retry';

  @override
  String get plannedCostAcceptedTitle => 'Payment planned';

  @override
  String get plannedCostAcceptedDescription =>
      'It does not affect your balance and is waiting for confirmation.';

  @override
  String get plannedCostHomePending => 'Updating Home';

  @override
  String get plannedCostHomeUpdated => 'Home updated';

  @override
  String get plannedCostHomeDelayed => 'Home will update a little later';

  @override
  String get plannedCostHomeFailed => 'Could not update Home';

  @override
  String get plannedCostInvalidInput => 'Check the name, amount, and date.';

  @override
  String get plannedCostIssueAccountUnavailable =>
      'The account is unavailable.';

  @override
  String get plannedCostIssueCurrencyMismatch =>
      'The currency does not match the account currency.';

  @override
  String get plannedCostIssueUnsupportedCurrency =>
      'This currency is not supported yet.';

  @override
  String get plannedCostIssueBeforeBaseline =>
      'The date is before tracking starts for this account. Choose a later date.';

  @override
  String get plannedCostGenericFailure => 'Could not plan the payment.';

  @override
  String get plannedCostDoneAction => 'Done';

  @override
  String get plannedCostListTitle => 'Planned';

  @override
  String get plannedCostListEmpty => 'Nothing planned yet.';

  @override
  String get plannedCostCancelAction => 'Cancel';

  @override
  String get plannedCostCancelSemantics => 'Cancel plan';

  @override
  String get plannedCostDueLabel => 'Due';

  @override
  String get plannedCostOverdueLabel => 'Overdue';

  @override
  String get plannedCostCancelFailure => 'Could not cancel the plan.';

  @override
  String get plannedCostConfirmAction => 'Paid';

  @override
  String get plannedCostConfirmSemantics => 'Mark plan as paid';

  @override
  String get plannedCostConfirmFailure =>
      'Could not record the transaction. The plan is still in the list — try again.';

  @override
  String get plannedCostConfirmHint =>
      '“Paid” creates a normal expense transaction and removes the plan from the list.';

  @override
  String get savingsGoalTitle => 'Goals';

  @override
  String get savingsGoalLoading => 'Loading goals';

  @override
  String get savingsGoalAccountRequired =>
      'Create an account first — a goal saves up in its currency.';

  @override
  String get savingsGoalGenericFailure =>
      'Could not complete the action. Try again.';

  @override
  String get savingsGoalInvalidInput => 'Check the name, amount, and date.';

  @override
  String get savingsGoalRetryAction => 'Retry';

  @override
  String get savingsGoalDescription =>
      'A goal shows how much you have already set aside. Money set aside stays in the account: balance, income, and expenses do not change.';

  @override
  String get savingsGoalEmpty => 'No goals yet.';

  @override
  String get savingsGoalCreateAction => 'New goal';

  @override
  String get savingsGoalCancelCreateAction => 'Cancel';

  @override
  String get savingsGoalTitleLabel => 'Name';

  @override
  String get savingsGoalTitleHint => 'Vacation';

  @override
  String get savingsGoalTargetLabel => 'Amount needed';

  @override
  String get savingsGoalMonthlyLabel => 'I plan to set aside per month';

  @override
  String get savingsGoalMonthlyHelper =>
      'Optional. This is a guide, not a commitment.';

  @override
  String get savingsGoalDateLabel => 'By what date';

  @override
  String get savingsGoalChooseDateAction => 'Choose date';

  @override
  String get savingsGoalSubmitAction => 'Create goal';

  @override
  String get savingsGoalContributionLabel => 'Amount';

  @override
  String get savingsGoalDepositAction => 'Set aside';

  @override
  String get savingsGoalWithdrawAction => 'Take back';

  @override
  String get savingsGoalCancelAction => 'Give up goal';

  @override
  String get savingsGoalCancelSemantics =>
      'Give up the goal and remove it from the list';

  @override
  String get savingsGoalDepositSemantics =>
      'Set aside the entered amount for this goal';

  @override
  String get savingsGoalWithdrawSemantics =>
      'Take the entered amount back from this goal';

  @override
  String get savingsGoalAchievedLabel => 'Goal reached';

  @override
  String get savingsGoalIssueAccountUnavailable =>
      'The account is unavailable. Refresh the screen.';

  @override
  String get savingsGoalIssueCurrencyMismatch =>
      'The goal currency must match the account currency.';

  @override
  String get savingsGoalIssueUnsupportedCurrency =>
      'This currency isn\'t supported yet.';

  @override
  String get savingsGoalIssueBeforeBaseline =>
      'The date is before the account was opened.';

  @override
  String get savingsGoalIssueFutureContribution =>
      'You can only set money aside for today or earlier.';

  @override
  String get savingsGoalIssueNotActive =>
      'This goal is already closed. Refresh the screen.';

  @override
  String get savingsGoalIssueWithdrawalTooLarge =>
      'The goal holds less money than you are trying to take back.';

  @override
  String get categoryPickerNone => 'No category';

  @override
  String get categoryPickerOther => 'Other (type it in)';

  @override
  String get categoryPickerOtherLabel => 'Your own category';

  @override
  String get categoryPickerLoading => 'Loading categories';

  @override
  String get categoryPickerUnavailable =>
      'Category list unavailable — type the name yourself.';

  @override
  String get categorySeedGroceries => 'Groceries';

  @override
  String get categorySeedEatingOut => 'Cafes and restaurants';

  @override
  String get categorySeedTransport => 'Transport';

  @override
  String get categorySeedHousing => 'Housing';

  @override
  String get categorySeedUtilities => 'Phone and internet';

  @override
  String get categorySeedHealth => 'Health';

  @override
  String get categorySeedClothing => 'Clothing';

  @override
  String get categorySeedEntertainment => 'Entertainment';

  @override
  String get categorySeedEducation => 'Education';

  @override
  String get categorySeedGiftsOut => 'Gifts';

  @override
  String get categorySeedOtherExpense => 'Other';

  @override
  String get categorySeedSalary => 'Salary';

  @override
  String get categorySeedFreelance => 'Side income';

  @override
  String get categorySeedGiftsIn => 'Gifts';

  @override
  String get categorySeedInterest => 'Interest';

  @override
  String get categorySeedOtherIncome => 'Other';

  @override
  String get categoriesSettingsAction => 'Categories';

  @override
  String get categoriesSettingsDescription =>
      'Your own names for spending and income';

  @override
  String get categoriesTitle => 'Categories';

  @override
  String get categoriesExpenseTab => 'Expenses';

  @override
  String get categoriesIncomeTab => 'Income';

  @override
  String get categoryAddAction => 'Add category';

  @override
  String get categoryNameLabel => 'Name';

  @override
  String get categoryCreateAction => 'Create';

  @override
  String get categorySaveAction => 'Save';

  @override
  String get categoryRenameAction => 'Rename';

  @override
  String get categoryHideAction => 'Hide';

  @override
  String get categoryRestoreAction => 'Restore';

  @override
  String categoryHiddenSection(int count) {
    return 'Hidden: $count';
  }

  @override
  String get categoryHiddenNote =>
      'A hidden category is not offered for new records but stays on past transactions.';

  @override
  String get categoryListEmpty => 'No categories yet';

  @override
  String get categoryHideDialogTitle => 'Hide category?';

  @override
  String get categoryHideDialogDescription =>
      'It will disappear from the list for new records. Past transactions stay in it, and you can restore it.';

  @override
  String get categoryNameTakenError => 'This name already exists';

  @override
  String get categoryArchivedError =>
      'This category is hidden — restore it first';

  @override
  String get categoryNotFoundError => 'Category not found';

  @override
  String get categoryNameInvalidError => 'Enter a name of up to 100 characters';

  @override
  String get categoryLoadError => 'Could not load categories';

  @override
  String get operationCorrectAction => 'Edit';

  @override
  String get operationRemoveAction => 'Delete';

  @override
  String get operationCorrectTitle => 'Correct transaction';

  @override
  String get operationCorrectSave => 'Save';

  @override
  String get operationCorrectedMessage => 'Transaction corrected';

  @override
  String get operationRemovedMessage => 'Transaction deleted';

  @override
  String get operationRemoveDialogTitle => 'Delete transaction?';

  @override
  String get operationRemoveDialogBody =>
      'It will no longer count in your balance and reports. The record itself stays in the change history.';

  @override
  String get operationCorrectionFailed =>
      'Could not save the change. Try again.';

  @override
  String get operationAlreadyReversedMessage =>
      'This transaction was already corrected. Refresh the list.';

  @override
  String get operationNotFoundMessage => 'This transaction no longer exists.';

  @override
  String get operationHistoryTitle => 'All transactions';

  @override
  String get operationHistorySettingsAction => 'All transactions';

  @override
  String get operationHistorySettingsDescription =>
      'History of records and what was entered';

  @override
  String get operationHistoryEmpty => 'No records yet';

  @override
  String get operationHistoryMore => 'Show more';

  @override
  String get operationHistoryLoadError => 'Could not load transactions';

  @override
  String get operationHistoryLoadMoreError => 'Could not load more';

  @override
  String operationHistoryDate(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get operationDetailDate => 'Date';

  @override
  String get operationDetailCategory => 'Category';

  @override
  String get operationDetailMerchant => 'Where';

  @override
  String get operationDetailOriginalText => 'Entered as';

  @override
  String get operationDetailOriginalTextHint =>
      'The category was renamed later';

  @override
  String get analyticsExpenseByCategory => 'Expenses by category';

  @override
  String get analyticsIncomeByCategory => 'Income by category';

  @override
  String get analyticsBreakdownEmpty => 'No records this month';

  @override
  String get analyticsLoadError => 'Could not calculate analytics';

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
  String get profileLoadError => 'Could not load profile';

  @override
  String get profileEmailLabel => 'Sign-in email';

  @override
  String get profileAccountSection => 'ACCOUNT';

  @override
  String get profileTimezoneSetting => 'Time zone';

  @override
  String get profileNoAccount =>
      'The account will appear after your first record';

  @override
  String profileOpeningDateValue(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Currently $dateString';
  }

  @override
  String profileVersion(String version) {
    return 'Version $version';
  }

  @override
  String get entrySentenceField => 'Describe the transaction in one sentence';

  @override
  String get entrySentenceHint => 'Spent 12.50 on groceries yesterday';

  @override
  String get entrySentenceParseAction => 'Read';

  @override
  String get entrySentenceFilled =>
      'Fields below are filled in — review and confirm.';

  @override
  String get entrySentenceParseError => 'Could not read the sentence.';

  @override
  String get entrySentenceEmpty =>
      'Write a shorter sentence or start with the amount.';

  @override
  String get entrySentenceGapAmount => 'No amount found — enter it.';

  @override
  String get entrySentenceGapAmbiguous =>
      'The sentence has several numbers — specify the amount.';

  @override
  String get entrySentenceGapDate => 'Date not understood — check it.';

  @override
  String get entrySentenceGapCategory => 'No category matched — choose one.';

  @override
  String get entrySentenceGapDirection =>
      'Not sure if this is an expense or income — choose one.';

  @override
  String get entrySentenceGapTransfer =>
      'This is a transfer between wallets, not income or spending — so nothing was filled in.';

  @override
  String get entrySentenceOpenTransfer => 'Open transfer';

  @override
  String get categoryKeywordsTitle => 'Category words';

  @override
  String get categoryKeywordsAction => 'Words';

  @override
  String get categoryKeywordsDescription =>
      'If a word in your sentence starts with one of these, the transaction goes into this category. “car” also catches “carwash”, and “grocer” — “groceries”.';

  @override
  String get categoryKeywordsEmpty =>
      'No words yet — the category will be matched by its name only.';

  @override
  String get categoryKeywordsField => 'Add a word';

  @override
  String get categoryKeywordsAdd => 'Add';

  @override
  String categoryKeywordsRemove(String keyword) {
    return 'Remove word $keyword';
  }

  @override
  String get categoryKeywordsInvalid =>
      'A word needs at least three letters or digits, no spaces.';

  @override
  String get categoryKeywordsTaken =>
      'This word already leads to another category. Remove it there.';

  @override
  String get categoryKeywordsArchived =>
      'A hidden category is not used for matching.';

  @override
  String get categoryKeywordsLoadError => 'Could not load words';

  @override
  String get categoryKeywordsSaveError => 'Could not save the word';

  @override
  String get analyticsPeriod7Days => '7 days';

  @override
  String get analyticsPeriodMonth => 'Month';

  @override
  String get analyticsPeriodQuarter => 'Quarter';

  @override
  String get analyticsPeriodYear => 'Year';

  @override
  String get analyticsPeriodCustom => 'Custom period';

  @override
  String get analyticsPeriodLabel => 'Period';

  @override
  String get analyticsBalanceTitle => 'Balance';

  @override
  String analyticsBalanceFromTo(String opening, String closing) {
    return '$opening → $closing';
  }

  @override
  String analyticsBalanceChange(String change) {
    return 'over the period $change';
  }

  @override
  String get analyticsNoSpending => 'No spending in this period';

  @override
  String analyticsPreviousAmount(String amount) {
    return 'was $amount';
  }

  @override
  String analyticsWindowRange(String from, String to) {
    return '$from — $to';
  }

  @override
  String analyticsComparedWith(String from, String to) {
    return 'compared with $from — $to';
  }

  @override
  String get plannedCostIssueCategoryUnavailable =>
      'This category is unavailable. Choose another.';

  @override
  String get plannedCostRepeatToggle => 'Repeat every month';

  @override
  String get plannedCostRepeatDayLabel => 'Day of the month';

  @override
  String get plannedCostRepeatLastDay => 'Last day of the month';

  @override
  String get plannedCostRepeatShortMonthHint =>
      'In short months the payment moves to the last day: January 31, February 28, March 31.';

  @override
  String get plannedCostRepeatFirstDatesTitle => 'Next dates';

  @override
  String get plannedCostRecurrenceListTitle => 'Repeating';

  @override
  String get plannedCostRecurrenceListEmpty => 'No repeating payments yet.';

  @override
  String plannedCostRecurrenceMonthlyOnDay(int day) {
    return 'Every month, day $day';
  }

  @override
  String get plannedCostRecurrenceMonthlyLastDay => 'Every month, last day';

  @override
  String get plannedCostRecurrenceEndAction => 'End';

  @override
  String get plannedCostRecurrenceEndDialogTitle => 'End the series?';

  @override
  String get plannedCostRecurrenceEndDialogBody =>
      'No new payments will be created. Future planned payments in this series will be canceled, and those already due will stay — you need to confirm or skip them.';

  @override
  String plannedCostRecurrenceEndedMessage(int count) {
    return 'Series ended. Future payments canceled: $count';
  }

  @override
  String get plannedCostSkipAction => 'Skip';

  @override
  String get plannedCostSkipHint =>
      '“Skip” removes one payment; the series continues.';

  @override
  String get plannedCostRecurrenceAcceptedTitle => 'Repeating payment recorded';

  @override
  String get plannedCostRecurrenceAcceptedDescription =>
      'Payments will appear on their own. This is a forecast: it does not change your balance.';

  @override
  String get plannedCostRecurrenceFailure =>
      'Could not change the repeating payment.';

  @override
  String get appUpdateCheckAction => 'Check for updates';

  @override
  String get appUpdateCheckDescription =>
      'Ask the server whether a new version is out';

  @override
  String get appUpdateChecking => 'Checking…';

  @override
  String get appUpdateUpToDate => 'You have the latest version.';

  @override
  String appUpdateAvailable(String version, String size) {
    return 'Version $version available, $size';
  }

  @override
  String get appUpdateNotesLabel => 'What is new';

  @override
  String get appUpdateDownloadAction => 'Download and install';

  @override
  String appUpdateDownloading(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get accountExportAction => 'Export my data';

  @override
  String get accountExportDescription =>
      'A full file with all your data and a transaction table for Excel';

  @override
  String get accountExportPreparing => 'Preparing files…';

  @override
  String get accountExportFailedUnreachable =>
      'Could not reach the server. Check your internet and try again.';

  @override
  String get accountExportFailedUnavailable =>
      'The server could not prepare the export. Try later.';

  @override
  String get accountExportFailedAuthentication =>
      'Your session has ended — sign in again.';

  @override
  String get accountExportFailedShare =>
      'The files are ready, but the “Share” window did not open.';

  @override
  String get accountExportFailedStorage =>
      'Could not write the files to the phone.';

  @override
  String get accountDeletionAction => 'Delete user account';

  @override
  String get accountDeletionActionDescription =>
      'In 7 days. Changed your mind — just sign in again';

  @override
  String get accountDeletionTitle => 'User account deletion';

  @override
  String get accountDeletionHeadline =>
      'Your user account will be deleted in 7 days';

  @override
  String get accountDeletionWhat =>
      'Everything will be deleted: wallets, transactions, transfers, categories, plans, budgets, and goals. You will not be able to get them back later.';

  @override
  String get accountDeletionSignedOut =>
      'You will be signed out on all devices at once. If you change your mind — sign in within 7 days, and the deletion is canceled.';

  @override
  String get accountDeletionBackups =>
      'Server backups keep the data for up to 14 more days, then it disappears from there too.';

  @override
  String get accountDeletionExportFirst => 'Export my data first';

  @override
  String accountDeletionUnsent(int count) {
    return 'Transactions on this phone that have not reached the server yet: $count. They are not in the export, and they will be lost with the user account. It is better to wait until they are sent.';
  }

  @override
  String get accountDeletionPasswordLabel => 'Password';

  @override
  String get accountDeletionPasswordHelp =>
      'The one you sign in with. It is needed so that only the owner can delete the user account.';

  @override
  String get accountDeletionPasswordRejected => 'Wrong password';

  @override
  String get accountDeletionSubmit => 'Delete user account';

  @override
  String get accountDeletionConfirmTitle => 'Delete user account?';

  @override
  String get accountDeletionConfirmBody =>
      'You will be signed out on all devices. In 7 days all data will be deleted, unless you sign in before then.';

  @override
  String get accountDeletionConfirmCancel => 'Cancel';

  @override
  String get accountDeletionConfirmAccept => 'Delete';

  @override
  String get accountDeletionUnreachable =>
      'Could not reach the server. Nothing was deleted — check your internet and try again.';

  @override
  String get accountDeletionUnavailable =>
      'The server could not accept the request. Nothing was deleted — try later.';

  @override
  String get accountDeletionAuthentication =>
      'Your session has ended — sign in again. Nothing was deleted.';

  @override
  String accountDeletionScheduledNotice(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Your user account will be deleted on $dateString. To cancel the deletion, just sign in before that day.';
  }

  @override
  String get accountDeletionScheduledNoticeUndated =>
      'Your user account will be deleted in 7 days. To cancel the deletion, just sign in before then.';

  @override
  String get accountDeletionCancelled =>
      'User account deletion canceled — you signed in, and all your data is in place.';

  @override
  String get appUpdateHandedToInstaller =>
      'The file is downloaded and verified. Confirm the installation in the system window — Android installs the update itself, and this takes up to a minute. You do not need to download it again: the installer needs the file now.';

  @override
  String get appUpdateOpenInstallerAction => 'Open the install window again';

  @override
  String get appUpdateNeedsPermission =>
      'Android asks you to allow installs from this app. You only need to do this once.';

  @override
  String get appUpdatePermissionAction => 'Open settings';

  @override
  String get appUpdateFailedUnreachable =>
      'The server is unavailable. Try later.';

  @override
  String get appUpdateFailedServer =>
      'The server could not answer about updates.';

  @override
  String get appUpdateFailedCorrupted =>
      'The downloaded file was damaged and has been deleted. Try again.';

  @override
  String get appUpdateFailedInstaller =>
      'Could not open the Android installer.';

  @override
  String get appUpdateFailedAuth => 'You need to sign in again.';

  @override
  String get appUpdateRetryAction => 'Retry';

  @override
  String appUpdateMegabytes(String megabytes) {
    return '$megabytes MB';
  }

  @override
  String get notificationsQuietLabel => 'Notifications';

  @override
  String get notificationsEmpty => 'Nothing needs your attention.';

  @override
  String get notificationsEmptyHint =>
      'Payment reminders and new app versions will appear here.';

  @override
  String notificationUpdateTitle(String version) {
    return 'Version $version available';
  }

  @override
  String get notificationUpdateBody => 'You can update in Profile.';

  @override
  String get notificationUpdateAction => 'Open Profile';

  @override
  String notificationPaymentOverdueTitle(String title) {
    return 'Overdue payment: $title';
  }

  @override
  String notificationPaymentDueSoonTitle(String title) {
    return 'Payment soon: $title';
  }

  @override
  String notificationPaymentBody(String date, String amount) {
    return '$date, $amount';
  }

  @override
  String get notificationPaymentAction => 'Open planned payments';

  @override
  String get budgetsTitle => 'Budgets';

  @override
  String get budgetsSettingsAction => 'Budgets';

  @override
  String get budgetsSettingsDescription =>
      'Monthly limits and how much is left';

  @override
  String budgetsPeriod(String from, String to) {
    return '$from — $to';
  }

  @override
  String get budgetsOverallTitle => 'All spending';

  @override
  String get budgetsEmpty => 'No limits yet.';

  @override
  String get budgetsEmptyHint =>
      'Set a monthly limit for a category or for all spending.';

  @override
  String budgetsSpentOfLimit(String spent, String limit) {
    return 'Spent $spent of $limit';
  }

  @override
  String budgetsRemaining(String amount) {
    return '$amount left';
  }

  @override
  String budgetsOverspentBy(String amount) {
    return 'Over by $amount';
  }

  @override
  String budgetsPlanned(String amount) {
    return 'Also planned $amount';
  }

  @override
  String get budgetsAddAction => 'Set limit';

  @override
  String get budgetsRemoveAction => 'Remove';

  @override
  String get budgetsRemoveDialogTitle => 'Remove limit?';

  @override
  String get budgetsRemoveDialogBody =>
      'Your spending stays; only the limit stops being counted. You can set a new one at any time.';

  @override
  String get budgetsCategoryLabel => 'For what';

  @override
  String get budgetsLimitLabel => 'Monthly limit';

  @override
  String get budgetsSaveAction => 'Save';

  @override
  String get budgetsLoadError => 'Could not load budgets.';

  @override
  String get budgetsWriteError => 'Could not save the limit.';

  @override
  String get budgetsNoCategoriesLeft => 'All categories already have limits.';

  @override
  String get budgetsAccountRequired => 'Create an account first.';

  @override
  String get timezoneTitle => 'Tracking time zone';

  @override
  String timezoneCurrent(String zone) {
    return 'Currently $zone';
  }

  @override
  String get timezoneExplanation =>
      'This decides where a day and a month begin and end. Transactions already recorded stay on their dates — only what counts as “today” and “this month” changes.';

  @override
  String get timezoneSearchField => 'Search for a city or zone';

  @override
  String get timezoneDeviceSection => 'PHONE TIME ZONE';

  @override
  String get timezoneAllSection => 'ALL TIME ZONES';

  @override
  String get timezoneNothingFound => 'Nothing found';

  @override
  String timezoneConfirmTitle(String zone) {
    return 'Move tracking to $zone?';
  }

  @override
  String get timezoneConfirmBody =>
      'Amounts and dates of transactions already recorded will not change. Only “today” and the month boundaries will be counted in the new way.';

  @override
  String get timezoneConfirmAction => 'Move';

  @override
  String timezoneCorrected(String zone) {
    return 'Tracking in $zone';
  }

  @override
  String get timezoneUnchangedError => 'Tracking is already in this time zone.';

  @override
  String get timezoneBehindOperationsError =>
      'In this time zone the latest record would land in the future, and its amount would disappear from the balance until tomorrow. Choose a time zone further east or try later.';

  @override
  String get timezoneWriteError => 'Could not change the time zone.';

  @override
  String get timezoneLoadError => 'Could not load the account.';

  @override
  String get timezoneAccountRequired => 'Create an account first.';

  @override
  String get timezoneSettingsDescription =>
      'Where a day and a month begin and end';

  @override
  String get entrySentenceGapCurrency =>
      'Currency not understood — enter the amount yourself.';

  @override
  String entrySentenceCurrencyMismatch(String parsed, String account) {
    return 'The amount is in $parsed, but the account is in $account — so it was not filled in.';
  }

  @override
  String get otherWalletsTitle => 'OTHER WALLETS';

  @override
  String get transferTitle => 'Transfer';

  @override
  String get transferSettingsAction => 'Transfer';

  @override
  String get transferSettingsDescription =>
      'Record money moved from one wallet to another';

  @override
  String get transferFromField => 'From';

  @override
  String get transferToField => 'To';

  @override
  String get transferFromAmountField => 'Amount sent';

  @override
  String get transferToAmountField => 'Amount received';

  @override
  String get transferDateField => 'When';

  @override
  String transferRateLabel(String from, String rate, String to) {
    return 'Rate: 1 $from = $rate $to';
  }

  @override
  String get transferRateHint =>
      'The rate does not come from the internet — it follows from the two amounts you entered.';

  @override
  String get transferReviewAction => 'Continue';

  @override
  String get transferConfirmAction => 'Record transfer';

  @override
  String get transferEditAction => 'Edit';

  @override
  String get transferAcceptedTitle => 'Transfer recorded';

  @override
  String transferAcceptedBody(String fromAmount, String toAmount) {
    return '$fromAmount → $toAmount';
  }

  @override
  String get transferSecondWalletRequired =>
      'A transfer needs a second wallet in another currency.';

  @override
  String get transferLoadError => 'Could not load accounts.';

  @override
  String get transferWriteError => 'Could not record the transfer.';

  @override
  String get transferSameWalletError => 'Choose two different wallets.';

  @override
  String get transferIssueWalletUnavailable => 'The wallet is unavailable.';

  @override
  String get transferIssueCurrencyMismatch =>
      'The amount currency does not match the wallet currency.';

  @override
  String get transferIssueBeforeBaseline =>
      'Money could not leave before the wallet existed.';

  @override
  String get transferIssueFutureDate => 'The transfer date is in the future.';

  @override
  String get transferIssueConfirmationBeforeCapture =>
      'The confirmation is earlier than the record itself.';

  @override
  String get walletTitle => 'New wallet';

  @override
  String get walletSettingsAction => 'Open a wallet';

  @override
  String get walletSettingsDescription =>
      'An account in another currency — money is not converted';

  @override
  String get walletNameField => 'Name';

  @override
  String get walletCurrencyField => 'Currency';

  @override
  String get walletOpeningBalanceField => 'How much is in it now';

  @override
  String get walletOpeningDateField => 'From what date';

  @override
  String get walletCurrencySearch => 'Search for a currency';

  @override
  String get walletCurrencyHeld => 'Already held';

  @override
  String get walletExplanation =>
      'Money is not converted between wallets. Each one stays in its own currency, and a transfer is recorded as two amounts.';

  @override
  String get walletReviewAction => 'Continue';

  @override
  String get walletConfirmAction => 'Open';

  @override
  String get walletOpenedTitle => 'Wallet opened';

  @override
  String get walletAccountRequired => 'Create your main account first.';

  @override
  String get walletLoadError => 'Could not load accounts.';

  @override
  String get walletWriteError => 'Could not open the wallet.';

  @override
  String get operationWalletField => 'Wallet';

  @override
  String get spokenSentenceKept =>
      'Sentence saved on the phone. When you are back online, it will wait to be read here and on Home — for up to 30 days.';

  @override
  String get spokenSentenceNotKept =>
      'Could not save this sentence. Say it again when you have internet.';

  @override
  String entrySentenceSaidAt(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat(
      'd MMMM, HH:mm',
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return 'Said on $dateString — dates count from that moment';
  }

  @override
  String waitingPhrasesTitle(int count) {
    return 'Waiting to be read: $count';
  }

  @override
  String get waitingPhrasesDescription =>
      'Said without internet. Tap a sentence to read it; once read, it is deleted from the phone.';

  @override
  String get waitingPhraseHidden => 'Sentence hidden';

  @override
  String waitingPhraseSaidAt(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat(
      'd MMMM, HH:mm',
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return 'Said on $dateString';
  }

  @override
  String get waitingPhraseForget => 'Delete sentence';

  @override
  String get waitingPhrasesNoticeDescription =>
      'Said without internet — tap to read';

  @override
  String waitingPhrasesNoticeLabel(int count) {
    return 'Sentences said without internet, waiting to be read: $count. Open';
  }

  @override
  String get languageFollowPhone => 'Same as phone';

  @override
  String get languageSettingDescription => 'Screens and voice input';

  @override
  String currencyName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'EUR': 'Euro',
      'USD': 'US dollar',
      'UAH': 'Hryvnia',
      'GBP': 'Pound sterling',
      'PLN': 'Zloty',
      'CHF': 'Swiss franc',
      'CZK': 'Czech koruna',
      'SEK': 'Swedish krona',
      'NOK': 'Norwegian krone',
      'DKK': 'Danish krone',
      'HUF': 'Forint',
      'RON': 'Romanian leu',
      'BGN': 'Bulgarian lev',
      'RSD': 'Serbian dinar',
      'ALL': 'Albanian lek',
      'MKD': 'Macedonian denar',
      'BAM': 'Convertible mark',
      'TRY': 'Turkish lira',
      'MDL': 'Moldovan leu',
      'RUB': 'Russian ruble',
      'BYN': 'Belarusian ruble',
      'GEL': 'Lari',
      'AMD': 'Armenian dram',
      'AZN': 'Azerbaijani manat',
      'KZT': 'Tenge',
      'UZS': 'Uzbek som',
      'KGS': 'Kyrgyz som',
      'ILS': 'Shekel',
      'AED': 'UAE dirham',
      'EGP': 'Egyptian pound',
      'INR': 'Indian rupee',
      'CNY': 'Yuan',
      'JPY': 'Yen',
      'KRW': 'Won',
      'THB': 'Baht',
      'VND': 'Dong',
      'IDR': 'Indonesian rupiah',
      'SGD': 'Singapore dollar',
      'HKD': 'Hong Kong dollar',
      'AUD': 'Australian dollar',
      'NZD': 'New Zealand dollar',
      'CAD': 'Canadian dollar',
      'MXN': 'Mexican peso',
      'BRL': 'Brazilian real',
      'ARS': 'Argentine peso',
      'CLP': 'Chilean peso',
      'ZAR': 'South African rand',
      'MAD': 'Moroccan dirham',
      'TND': 'Tunisian dinar',
      'ISK': 'Icelandic krona',
      'other': '$code',
    });
    return '$_temp0';
  }

  @override
  String timezoneCity(String zone) {
    String _temp0 = intl.Intl.selectLogic(zone, {
      'Europe_Lisbon': 'Lisbon',
      'Europe_Dublin': 'Dublin',
      'Europe_London': 'London',
      'Atlantic_Canary': 'Canary Islands',
      'Europe_Madrid': 'Madrid',
      'Europe_Paris': 'Paris',
      'Europe_Brussels': 'Brussels',
      'Europe_Amsterdam': 'Amsterdam',
      'Europe_Berlin': 'Berlin',
      'Europe_Zurich': 'Zurich',
      'Europe_Vienna': 'Vienna',
      'Europe_Prague': 'Prague',
      'Europe_Rome': 'Rome',
      'Europe_Warsaw': 'Warsaw',
      'Europe_Budapest': 'Budapest',
      'Europe_Stockholm': 'Stockholm',
      'Europe_Oslo': 'Oslo',
      'Europe_Copenhagen': 'Copenhagen',
      'Europe_Belgrade': 'Belgrade',
      'Europe_Zagreb': 'Zagreb',
      'Europe_Ljubljana': 'Ljubljana',
      'Europe_Bratislava': 'Bratislava',
      'Europe_Athens': 'Athens',
      'Europe_Bucharest': 'Bucharest',
      'Europe_Sofia': 'Sofia',
      'Europe_Helsinki': 'Helsinki',
      'Europe_Tallinn': 'Tallinn',
      'Europe_Riga': 'Riga',
      'Europe_Vilnius': 'Vilnius',
      'Europe_Kyiv': 'Kyiv',
      'Europe_Chisinau': 'Chisinau',
      'Europe_Minsk': 'Minsk',
      'Europe_Istanbul': 'Istanbul',
      'Europe_Moscow': 'Moscow',
      'Asia_Tbilisi': 'Tbilisi',
      'Asia_Yerevan': 'Yerevan',
      'Asia_Baku': 'Baku',
      'Asia_Nicosia': 'Nicosia',
      'Asia_Jerusalem': 'Jerusalem',
      'Asia_Dubai': 'Dubai',
      'Asia_Tashkent': 'Tashkent',
      'Asia_Almaty': 'Almaty',
      'Asia_Bishkek': 'Bishkek',
      'Asia_Bangkok': 'Bangkok',
      'Asia_Singapore': 'Singapore',
      'Asia_Hong_Kong': 'Hong Kong',
      'Asia_Shanghai': 'Shanghai',
      'Asia_Seoul': 'Seoul',
      'Asia_Tokyo': 'Tokyo',
      'Australia_Perth': 'Perth',
      'Australia_Sydney': 'Sydney',
      'Pacific_Auckland': 'Auckland',
      'Africa_Cairo': 'Cairo',
      'Africa_Johannesburg': 'Johannesburg',
      'America_Sao_Paulo': 'São Paulo',
      'America_Argentina_Buenos_Aires': 'Buenos Aires',
      'America_New_York': 'New York',
      'America_Toronto': 'Toronto',
      'America_Chicago': 'Chicago',
      'America_Denver': 'Denver',
      'America_Los_Angeles': 'Los Angeles',
      'America_Mexico_City': 'Mexico City',
      'other': 'UTC',
    });
    return '$_temp0';
  }
}
