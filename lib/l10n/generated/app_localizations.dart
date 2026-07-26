import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('ru')];

  /// No description provided for @appTitle.
  ///
  /// In ru, this message translates to:
  /// **'Мои финансы'**
  String get appTitle;

  /// No description provided for @defaultUserName.
  ///
  /// In ru, this message translates to:
  /// **'Пользователь'**
  String get defaultUserName;

  /// No description provided for @greeting.
  ///
  /// In ru, this message translates to:
  /// **'Доброе утро, {userName}'**
  String greeting(String userName);

  /// No description provided for @homeDate.
  ///
  /// In ru, this message translates to:
  /// **'Пятница, 11 июля'**
  String get homeDate;

  /// No description provided for @notificationsLabel.
  ///
  /// In ru, this message translates to:
  /// **'Уведомления, есть новые'**
  String get notificationsLabel;

  /// No description provided for @notificationsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Уведомления'**
  String get notificationsTitle;

  /// No description provided for @notificationsStubDescription.
  ///
  /// In ru, this message translates to:
  /// **'Центр уведомлений будет подключён на следующем этапе.'**
  String get notificationsStubDescription;

  /// No description provided for @openSettingsLabel.
  ///
  /// In ru, this message translates to:
  /// **'Открыть настройки'**
  String get openSettingsLabel;

  /// No description provided for @totalBalance.
  ///
  /// In ru, this message translates to:
  /// **'Общий баланс'**
  String get totalBalance;

  /// No description provided for @hideAmounts.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть суммы'**
  String get hideAmounts;

  /// No description provided for @showAmounts.
  ///
  /// In ru, this message translates to:
  /// **'Показать суммы'**
  String get showAmounts;

  /// No description provided for @monthDelta.
  ///
  /// In ru, this message translates to:
  /// **'за месяц'**
  String get monthDelta;

  /// No description provided for @activeAccounts.
  ///
  /// In ru, this message translates to:
  /// **'Все активные счета'**
  String get activeAccounts;

  /// No description provided for @addByVoice.
  ///
  /// In ru, this message translates to:
  /// **'Добавить голосом'**
  String get addByVoice;

  /// No description provided for @voiceEntryLabel.
  ///
  /// In ru, this message translates to:
  /// **'Добавить операцию голосом'**
  String get voiceEntryLabel;

  /// No description provided for @monthSummaryTitle.
  ///
  /// In ru, this message translates to:
  /// **'Итоги июля'**
  String get monthSummaryTitle;

  /// No description provided for @income.
  ///
  /// In ru, this message translates to:
  /// **'Доходы'**
  String get income;

  /// No description provided for @incomeCaption.
  ///
  /// In ru, this message translates to:
  /// **'поступило'**
  String get incomeCaption;

  /// No description provided for @expenses.
  ///
  /// In ru, this message translates to:
  /// **'Расходы'**
  String get expenses;

  /// No description provided for @expensesCaption.
  ///
  /// In ru, this message translates to:
  /// **'потрачено'**
  String get expensesCaption;

  /// No description provided for @netFlow.
  ///
  /// In ru, this message translates to:
  /// **'Чистый поток'**
  String get netFlow;

  /// No description provided for @netPositiveCaption.
  ///
  /// In ru, this message translates to:
  /// **'в плюсе'**
  String get netPositiveCaption;

  /// No description provided for @trendExpensesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Расходы'**
  String get trendExpensesTitle;

  /// No description provided for @trendBalanceTitle.
  ///
  /// In ru, this message translates to:
  /// **'Баланс'**
  String get trendBalanceTitle;

  /// No description provided for @trendUnknownTitle.
  ///
  /// In ru, this message translates to:
  /// **'Динамика'**
  String get trendUnknownTitle;

  /// No description provided for @trendLast7Days.
  ///
  /// In ru, this message translates to:
  /// **'последние 7 дней'**
  String get trendLast7Days;

  /// No description provided for @trendLast30Days.
  ///
  /// In ru, this message translates to:
  /// **'последние 30 дней'**
  String get trendLast30Days;

  /// No description provided for @trendPeriodUnknown.
  ///
  /// In ru, this message translates to:
  /// **'период'**
  String get trendPeriodUnknown;

  /// No description provided for @trend7DaysChip.
  ///
  /// In ru, this message translates to:
  /// **'7 дней'**
  String get trend7DaysChip;

  /// No description provided for @trend30DaysChip.
  ///
  /// In ru, this message translates to:
  /// **'30 дней'**
  String get trend30DaysChip;

  /// No description provided for @detailsAction.
  ///
  /// In ru, this message translates to:
  /// **'Подробнее'**
  String get detailsAction;

  /// No description provided for @trendEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Пока недостаточно данных для графика'**
  String get trendEmpty;

  /// No description provided for @trendSemantics.
  ///
  /// In ru, this message translates to:
  /// **'{title} за период, всего {amount}'**
  String trendSemantics(String title, String amount);

  /// No description provided for @amountsHidden.
  ///
  /// In ru, this message translates to:
  /// **'суммы скрыты'**
  String get amountsHidden;

  /// No description provided for @goalDueDate.
  ///
  /// In ru, this message translates to:
  /// **'до {date}'**
  String goalDueDate(String date);

  /// No description provided for @goalProgressSummary.
  ///
  /// In ru, this message translates to:
  /// **'из {target} · {progress}%'**
  String goalProgressSummary(String target, String progress);

  /// No description provided for @goalMonthlyContribution.
  ///
  /// In ru, this message translates to:
  /// **'Нужно откладывать примерно {amount} в месяц'**
  String goalMonthlyContribution(String amount);

  /// No description provided for @goalSemantics.
  ///
  /// In ru, this message translates to:
  /// **'{title}, накоплено {current}, цель {target}, прогресс {progress} процентов, открыть цель'**
  String goalSemantics(
    String title,
    String current,
    String target,
    String progress,
  );

  /// No description provided for @upcomingPaymentsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ближайшие платежи'**
  String get upcomingPaymentsTitle;

  /// No description provided for @allPaymentsAction.
  ///
  /// In ru, this message translates to:
  /// **'Все платежи'**
  String get allPaymentsAction;

  /// No description provided for @noUpcomingPayments.
  ///
  /// In ru, this message translates to:
  /// **'Ближайших платежей нет'**
  String get noUpcomingPayments;

  /// No description provided for @paymentDueDate.
  ///
  /// In ru, this message translates to:
  /// **'до {date}'**
  String paymentDueDate(String date);

  /// No description provided for @paymentOverdueDate.
  ///
  /// In ru, this message translates to:
  /// **'просрочен · {date}'**
  String paymentOverdueDate(String date);

  /// No description provided for @paymentDateUnknown.
  ///
  /// In ru, this message translates to:
  /// **'статус уточняется · {date}'**
  String paymentDateUnknown(String date);

  /// No description provided for @paymentSemantics.
  ///
  /// In ru, this message translates to:
  /// **'{title}, {due}, {amount}'**
  String paymentSemantics(String title, String due, String amount);

  /// No description provided for @recentTransactionsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Последние операции'**
  String get recentTransactionsTitle;

  /// No description provided for @noRecentTransactions.
  ///
  /// In ru, this message translates to:
  /// **'Подтверждённых операций пока нет'**
  String get noRecentTransactions;

  /// No description provided for @transactionMetadata.
  ///
  /// In ru, this message translates to:
  /// **'{category} · {date}'**
  String transactionMetadata(String category, String date);

  /// No description provided for @transactionIncome.
  ///
  /// In ru, this message translates to:
  /// **'доход'**
  String get transactionIncome;

  /// No description provided for @transactionExpense.
  ///
  /// In ru, this message translates to:
  /// **'расход'**
  String get transactionExpense;

  /// No description provided for @transactionTransfer.
  ///
  /// In ru, this message translates to:
  /// **'перевод'**
  String get transactionTransfer;

  /// No description provided for @transactionUnknown.
  ///
  /// In ru, this message translates to:
  /// **'операция'**
  String get transactionUnknown;

  /// No description provided for @transactionSemantics.
  ///
  /// In ru, this message translates to:
  /// **'{title}, {category}, {date}, {amount}, {kind}'**
  String transactionSemantics(
    String title,
    String category,
    String date,
    String amount,
    String kind,
  );

  /// No description provided for @refreshingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Обновляем данные'**
  String get refreshingTitle;

  /// No description provided for @refreshingDescription.
  ///
  /// In ru, this message translates to:
  /// **'Текущая финансовая картина остаётся доступной.'**
  String get refreshingDescription;

  /// No description provided for @partialDataTitle.
  ///
  /// In ru, this message translates to:
  /// **'Часть данных временно недоступна'**
  String get partialDataTitle;

  /// No description provided for @partialDataDescription.
  ///
  /// In ru, this message translates to:
  /// **'Доступные разделы продолжают работать.'**
  String get partialDataDescription;

  /// No description provided for @offlineTitle.
  ///
  /// In ru, this message translates to:
  /// **'Нет соединения'**
  String get offlineTitle;

  /// No description provided for @offlineDataAsOf.
  ///
  /// In ru, this message translates to:
  /// **'Данные актуальны на {date}, {time} UTC.'**
  String offlineDataAsOf(String date, String time);

  /// No description provided for @refreshFailedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось обновить данные'**
  String get refreshFailedTitle;

  /// No description provided for @refreshFailedDescription.
  ///
  /// In ru, this message translates to:
  /// **'Показываем предыдущую финансовую картину.'**
  String get refreshFailedDescription;

  /// No description provided for @retryAction.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get retryAction;

  /// No description provided for @fatalErrorTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить данные'**
  String get fatalErrorTitle;

  /// No description provided for @fatalErrorDescription.
  ///
  /// In ru, this message translates to:
  /// **'Попробуйте ещё раз. Если ошибка повторится, сообщите код запроса поддержке.'**
  String get fatalErrorDescription;

  /// No description provided for @requestIdLabel.
  ///
  /// In ru, this message translates to:
  /// **'Код запроса: {requestId}'**
  String requestIdLabel(String requestId);

  /// No description provided for @authExpiredTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сессия истекла'**
  String get authExpiredTitle;

  /// No description provided for @authExpiredDescription.
  ///
  /// In ru, this message translates to:
  /// **'Для защиты данных нужно войти снова.'**
  String get authExpiredDescription;

  /// No description provided for @signInAgainAction.
  ///
  /// In ru, this message translates to:
  /// **'Войти снова'**
  String get signInAgainAction;

  /// No description provided for @sessionExpiredStubTitle.
  ///
  /// In ru, this message translates to:
  /// **'Повторный вход'**
  String get sessionExpiredStubTitle;

  /// No description provided for @sessionExpiredStubDescription.
  ///
  /// In ru, this message translates to:
  /// **'Экран авторизации будет подключён вместе с настоящей сессией. Финансовые данные не удалены.'**
  String get sessionExpiredStubDescription;

  /// No description provided for @balanceUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Баланс временно недоступен'**
  String get balanceUnavailable;

  /// No description provided for @monthSummaryUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Итоги месяца временно недоступны'**
  String get monthSummaryUnavailable;

  /// No description provided for @trendUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'График временно недоступен'**
  String get trendUnavailable;

  /// No description provided for @goalNotSelected.
  ///
  /// In ru, this message translates to:
  /// **'Главная цель пока не выбрана'**
  String get goalNotSelected;

  /// No description provided for @goalUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Раздел целей временно недоступен. Мы уже обновляем данные.'**
  String get goalUnavailable;

  /// No description provided for @paymentsUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Ближайшие платежи временно недоступны'**
  String get paymentsUnavailable;

  /// No description provided for @transactionsUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Последние операции временно недоступны'**
  String get transactionsUnavailable;

  /// No description provided for @emptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте первую операцию, чтобы увидеть финансовую картину'**
  String get emptyTitle;

  /// No description provided for @emptyDescription.
  ///
  /// In ru, this message translates to:
  /// **'Просто скажите, что купили или получили — остальное мы сделаем сами.'**
  String get emptyDescription;

  /// No description provided for @loadingLabel.
  ///
  /// In ru, this message translates to:
  /// **'Загрузка финансовых данных'**
  String get loadingLabel;

  /// No description provided for @homeTab.
  ///
  /// In ru, this message translates to:
  /// **'Главная'**
  String get homeTab;

  /// No description provided for @chatTab.
  ///
  /// In ru, this message translates to:
  /// **'Чат'**
  String get chatTab;

  /// No description provided for @analyticsTab.
  ///
  /// In ru, this message translates to:
  /// **'Аналитика'**
  String get analyticsTab;

  /// No description provided for @goalsTab.
  ///
  /// In ru, this message translates to:
  /// **'Цели'**
  String get goalsTab;

  /// No description provided for @profileTab.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get profileTab;

  /// No description provided for @settingsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsTitle;

  /// No description provided for @backLabel.
  ///
  /// In ru, this message translates to:
  /// **'Назад'**
  String get backLabel;

  /// No description provided for @appearanceSection.
  ///
  /// In ru, this message translates to:
  /// **'ОФОРМЛЕНИЕ'**
  String get appearanceSection;

  /// No description provided for @lightTheme.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get darkTheme;

  /// No description provided for @accentColor.
  ///
  /// In ru, this message translates to:
  /// **'Акцентный цвет'**
  String get accentColor;

  /// No description provided for @tealAccent.
  ///
  /// In ru, this message translates to:
  /// **'Бирюзовый'**
  String get tealAccent;

  /// No description provided for @blueAccent.
  ///
  /// In ru, this message translates to:
  /// **'Синий'**
  String get blueAccent;

  /// No description provided for @purpleAccent.
  ///
  /// In ru, this message translates to:
  /// **'Фиолетовый'**
  String get purpleAccent;

  /// No description provided for @terracottaAccent.
  ///
  /// In ru, this message translates to:
  /// **'Терракотовый'**
  String get terracottaAccent;

  /// No description provided for @generalSection.
  ///
  /// In ru, this message translates to:
  /// **'ОБЩИЕ'**
  String get generalSection;

  /// No description provided for @privacySetting.
  ///
  /// In ru, this message translates to:
  /// **'Скрывать суммы'**
  String get privacySetting;

  /// No description provided for @languageSetting.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get languageSetting;

  /// No description provided for @russianLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Русский'**
  String get russianLanguage;

  /// No description provided for @baseCurrencySetting.
  ///
  /// In ru, this message translates to:
  /// **'Основная валюта'**
  String get baseCurrencySetting;

  /// No description provided for @settingsNote.
  ///
  /// In ru, this message translates to:
  /// **'Настройки языка и валюты пока демонстрационные.'**
  String get settingsNote;

  /// No description provided for @stubDescription.
  ///
  /// In ru, this message translates to:
  /// **'Раздел будет реализован на следующем этапе. Сейчас это навигационная заглушка.'**
  String get stubDescription;

  /// No description provided for @voiceStubTitle.
  ///
  /// In ru, this message translates to:
  /// **'Голосовой ввод'**
  String get voiceStubTitle;

  /// No description provided for @voiceStubDescription.
  ///
  /// In ru, this message translates to:
  /// **'Экран записи подготовлен как заглушка. Микрофон и распознавание речи появятся в следующем vertical slice.'**
  String get voiceStubDescription;

  /// No description provided for @backHome.
  ///
  /// In ru, this message translates to:
  /// **'На главную'**
  String get backHome;

  /// No description provided for @authLoadingLabel.
  ///
  /// In ru, this message translates to:
  /// **'Проверяем защищённую сессию'**
  String get authLoadingLabel;

  /// No description provided for @loginTitle.
  ///
  /// In ru, this message translates to:
  /// **'Вход'**
  String get loginTitle;

  /// No description provided for @loginDescription.
  ///
  /// In ru, this message translates to:
  /// **'Войдите, чтобы открыть свою финансовую картину.'**
  String get loginDescription;

  /// No description provided for @registerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Создание аккаунта'**
  String get registerTitle;

  /// No description provided for @registerDescription.
  ///
  /// In ru, this message translates to:
  /// **'Создайте защищённый аккаунт, чтобы начать вести финансы.'**
  String get registerDescription;

  /// No description provided for @displayNameField.
  ///
  /// In ru, this message translates to:
  /// **'Ваше имя'**
  String get displayNameField;

  /// No description provided for @displayNameRequired.
  ///
  /// In ru, this message translates to:
  /// **'Укажите имя'**
  String get displayNameRequired;

  /// No description provided for @emailField.
  ///
  /// In ru, this message translates to:
  /// **'Электронная почта'**
  String get emailField;

  /// No description provided for @emailInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Введите корректный адрес электронной почты'**
  String get emailInvalid;

  /// No description provided for @passwordField.
  ///
  /// In ru, this message translates to:
  /// **'Пароль'**
  String get passwordField;

  /// No description provided for @confirmPasswordField.
  ///
  /// In ru, this message translates to:
  /// **'Повторите пароль'**
  String get confirmPasswordField;

  /// No description provided for @passwordRequirements.
  ///
  /// In ru, this message translates to:
  /// **'Не менее 12 символов'**
  String get passwordRequirements;

  /// No description provided for @passwordInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Пароль должен содержать от 12 до 128 символов'**
  String get passwordInvalid;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In ru, this message translates to:
  /// **'Пароли не совпадают'**
  String get passwordsDoNotMatch;

  /// No description provided for @showPassword.
  ///
  /// In ru, this message translates to:
  /// **'Показать пароль'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть пароль'**
  String get hidePassword;

  /// No description provided for @loginAction.
  ///
  /// In ru, this message translates to:
  /// **'Войти'**
  String get loginAction;

  /// No description provided for @registerAction.
  ///
  /// In ru, this message translates to:
  /// **'Создать аккаунт'**
  String get registerAction;

  /// No description provided for @createAccountAction.
  ///
  /// In ru, this message translates to:
  /// **'Нет аккаунта? Создать'**
  String get createAccountAction;

  /// No description provided for @haveAccountAction.
  ///
  /// In ru, this message translates to:
  /// **'Уже есть аккаунт? Войти'**
  String get haveAccountAction;

  /// No description provided for @authSessionExpiredNotice.
  ///
  /// In ru, this message translates to:
  /// **'Сессия завершена. Войдите снова.'**
  String get authSessionExpiredNotice;

  /// No description provided for @signedOutNotice.
  ///
  /// In ru, this message translates to:
  /// **'Вы вышли из аккаунта.'**
  String get signedOutNotice;

  /// No description provided for @invalidCredentialsError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось войти. Проверьте почту и пароль.'**
  String get invalidCredentialsError;

  /// No description provided for @emailInUseError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось создать аккаунт. Возможно, эта почта уже используется.'**
  String get emailInUseError;

  /// No description provided for @authInvalidInputError.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте введённые данные и попробуйте снова.'**
  String get authInvalidInputError;

  /// No description provided for @authThrottledError.
  ///
  /// In ru, this message translates to:
  /// **'Слишком много попыток. Подождите и попробуйте снова.'**
  String get authThrottledError;

  /// No description provided for @authOfflineError.
  ///
  /// In ru, this message translates to:
  /// **'Нет соединения с интернетом. Проверьте сеть и повторите попытку.'**
  String get authOfflineError;

  /// No description provided for @authTimeoutError.
  ///
  /// In ru, this message translates to:
  /// **'Сервер не ответил вовремя. Попробуйте снова.'**
  String get authTimeoutError;

  /// No description provided for @authServiceError.
  ///
  /// In ru, this message translates to:
  /// **'Сервис входа временно недоступен. Попробуйте позже.'**
  String get authServiceError;

  /// No description provided for @authUnexpectedError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось завершить вход. Попробуйте снова.'**
  String get authUnexpectedError;

  /// No description provided for @authSecureStorageError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть защищённое хранилище устройства.'**
  String get authSecureStorageError;

  /// No description provided for @accountSection.
  ///
  /// In ru, this message translates to:
  /// **'АККАУНТ'**
  String get accountSection;

  /// No description provided for @signOutAction.
  ///
  /// In ru, this message translates to:
  /// **'Выйти из аккаунта'**
  String get signOutAction;

  /// No description provided for @signOutDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выйти из аккаунта?'**
  String get signOutDialogTitle;

  /// No description provided for @signOutDialogDescription.
  ///
  /// In ru, this message translates to:
  /// **'Для следующего входа потребуется снова ввести почту и пароль.'**
  String get signOutDialogDescription;

  /// No description provided for @cancelAction.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancelAction;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
