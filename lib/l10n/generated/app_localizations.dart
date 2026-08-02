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

  /// No description provided for @greetingMorningNeutral.
  ///
  /// In ru, this message translates to:
  /// **'Доброе утро'**
  String get greetingMorningNeutral;

  /// No description provided for @greetingDayNeutral.
  ///
  /// In ru, this message translates to:
  /// **'Добрый день'**
  String get greetingDayNeutral;

  /// No description provided for @greetingEveningNeutral.
  ///
  /// In ru, this message translates to:
  /// **'Добрый вечер'**
  String get greetingEveningNeutral;

  /// No description provided for @greetingNightNeutral.
  ///
  /// In ru, this message translates to:
  /// **'Доброй ночи'**
  String get greetingNightNeutral;

  /// No description provided for @greetingMorning.
  ///
  /// In ru, this message translates to:
  /// **'Доброе утро, {userName}'**
  String greetingMorning(String userName);

  /// No description provided for @greetingDay.
  ///
  /// In ru, this message translates to:
  /// **'Добрый день, {userName}'**
  String greetingDay(String userName);

  /// No description provided for @greetingEvening.
  ///
  /// In ru, this message translates to:
  /// **'Добрый вечер, {userName}'**
  String greetingEvening(String userName);

  /// No description provided for @greetingNight.
  ///
  /// In ru, this message translates to:
  /// **'Доброй ночи, {userName}'**
  String greetingNight(String userName);

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

  /// No description provided for @balanceDeltaUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Динамика за месяц недоступна'**
  String get balanceDeltaUnavailable;

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

  /// No description provided for @setupAccountAction.
  ///
  /// In ru, this message translates to:
  /// **'Настроить счёт'**
  String get setupAccountAction;

  /// No description provided for @monthSummaryTitle.
  ///
  /// In ru, this message translates to:
  /// **'Итоги за {month}'**
  String monthSummaryTitle(String month);

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

  /// No description provided for @transactionCategoryUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Без категории'**
  String get transactionCategoryUnavailable;

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

  /// No description provided for @financeEntryTitle.
  ///
  /// In ru, this message translates to:
  /// **'Финансовая операция'**
  String get financeEntryTitle;

  /// No description provided for @financeEntryLoading.
  ///
  /// In ru, this message translates to:
  /// **'Проверяем финансовый счёт'**
  String get financeEntryLoading;

  /// No description provided for @financeEntryLoadFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть ввод операции'**
  String get financeEntryLoadFailed;

  /// No description provided for @accountSetupTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настройте первый счёт'**
  String get accountSetupTitle;

  /// No description provided for @accountSetupDescription.
  ///
  /// In ru, this message translates to:
  /// **'Укажите фактический остаток и дату, с которой начинается учёт. Перед сохранением вы проверите все данные.'**
  String get accountSetupDescription;

  /// No description provided for @accountNameField.
  ///
  /// In ru, this message translates to:
  /// **'Название счёта'**
  String get accountNameField;

  /// No description provided for @accountNameHint.
  ///
  /// In ru, this message translates to:
  /// **'Например, Основной счёт'**
  String get accountNameHint;

  /// No description provided for @accountNameRequired.
  ///
  /// In ru, this message translates to:
  /// **'Укажите название счёта'**
  String get accountNameRequired;

  /// No description provided for @openingBalanceField.
  ///
  /// In ru, this message translates to:
  /// **'Начальный остаток'**
  String get openingBalanceField;

  /// No description provided for @openingBalanceHelp.
  ///
  /// In ru, this message translates to:
  /// **'Это исходный остаток, а не доход или расход.'**
  String get openingBalanceHelp;

  /// No description provided for @openingBalanceDateField.
  ///
  /// In ru, this message translates to:
  /// **'Дата начального остатка'**
  String get openingBalanceDateField;

  /// No description provided for @canonicalTimezoneLabel.
  ///
  /// In ru, this message translates to:
  /// **'Часовой пояс учёта'**
  String get canonicalTimezoneLabel;

  /// No description provided for @continueToReviewAction.
  ///
  /// In ru, this message translates to:
  /// **'Проверить данные'**
  String get continueToReviewAction;

  /// No description provided for @accountReviewTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте настройки счёта'**
  String get accountReviewTitle;

  /// No description provided for @reviewBeforeConfirmDescription.
  ///
  /// In ru, this message translates to:
  /// **'Финансовые данные сохранятся только после явного подтверждения.'**
  String get reviewBeforeConfirmDescription;

  /// No description provided for @confirmFinanceAction.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердить и сохранить'**
  String get confirmFinanceAction;

  /// No description provided for @editAction.
  ///
  /// In ru, this message translates to:
  /// **'Изменить'**
  String get editAction;

  /// No description provided for @accountCreatedNotice.
  ///
  /// In ru, this message translates to:
  /// **'Счёт подтверждён. Теперь добавьте первую операцию.'**
  String get accountCreatedNotice;

  /// No description provided for @manualOperationTitle.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте операцию вручную'**
  String get manualOperationTitle;

  /// No description provided for @manualOperationDescription.
  ///
  /// In ru, this message translates to:
  /// **'Заполните структурированные поля. Голос и автоматическое распознавание пока не используются.'**
  String get manualOperationDescription;

  /// No description provided for @accountLabel.
  ///
  /// In ru, this message translates to:
  /// **'Счёт'**
  String get accountLabel;

  /// No description provided for @operationExpense.
  ///
  /// In ru, this message translates to:
  /// **'Расход'**
  String get operationExpense;

  /// No description provided for @operationIncome.
  ///
  /// In ru, this message translates to:
  /// **'Доход'**
  String get operationIncome;

  /// No description provided for @operationTypeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Тип операции'**
  String get operationTypeLabel;

  /// No description provided for @operationAmountField.
  ///
  /// In ru, this message translates to:
  /// **'Сумма'**
  String get operationAmountField;

  /// No description provided for @merchantField.
  ///
  /// In ru, this message translates to:
  /// **'Место или получатель, необязательно'**
  String get merchantField;

  /// No description provided for @categoryField.
  ///
  /// In ru, this message translates to:
  /// **'Категория, необязательно'**
  String get categoryField;

  /// No description provided for @operationDateField.
  ///
  /// In ru, this message translates to:
  /// **'Дата операции'**
  String get operationDateField;

  /// No description provided for @operationReviewTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте операцию'**
  String get operationReviewTitle;

  /// No description provided for @addAnotherOperationAction.
  ///
  /// In ru, this message translates to:
  /// **'Добавить ещё одну'**
  String get addAnotherOperationAction;

  /// No description provided for @moneyInputInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Введите корректную сумму, например 1250,50 или -20'**
  String get moneyInputInvalid;

  /// No description provided for @positiveMoneyInputInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Введите сумму больше нуля, например 35 или 35,50'**
  String get positiveMoneyInputInvalid;

  /// No description provided for @financeInvalidInput.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте заполненные поля и попробуйте снова.'**
  String get financeInvalidInput;

  /// No description provided for @financeValidationRejected.
  ///
  /// In ru, this message translates to:
  /// **'Данные не прошли проверку. Проверьте поля перед повторной отправкой.'**
  String get financeValidationRejected;

  /// No description provided for @financeDateRejected.
  ///
  /// In ru, this message translates to:
  /// **'Дата не может быть позже сегодняшнего дня.'**
  String get financeDateRejected;

  /// No description provided for @operationBeforeOpeningDateError.
  ///
  /// In ru, this message translates to:
  /// **'Дата операции не может быть раньше даты начального остатка.'**
  String get operationBeforeOpeningDateError;

  /// No description provided for @financeAccountUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Счёт недоступен для этой операции. Обновите экран и попробуйте снова.'**
  String get financeAccountUnavailable;

  /// No description provided for @financeConflictError.
  ///
  /// In ru, this message translates to:
  /// **'Команда конфликтует с уже обработанной записью. Измените данные и создайте новое подтверждение.'**
  String get financeConflictError;

  /// No description provided for @financeOfflineError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось связаться с сервером. Проверьте подключение к API и повторите попытку.'**
  String get financeOfflineError;

  /// No description provided for @financeTimeoutError.
  ///
  /// In ru, this message translates to:
  /// **'Сервер не ответил вовремя. Подтверждение можно безопасно повторить.'**
  String get financeTimeoutError;

  /// No description provided for @financeServiceError.
  ///
  /// In ru, this message translates to:
  /// **'Сервис финансовых операций временно недоступен. Попробуйте снова позже.'**
  String get financeServiceError;

  /// No description provided for @financeSecurityError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось подтвердить безопасное соединение. Проверьте настройки и повторите позже.'**
  String get financeSecurityError;

  /// No description provided for @financeLocalStorageError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось надёжно сохранить подтверждение на устройстве. Запрос на сервер не отправлялся. Освободите место или разблокируйте защищённое хранилище и повторите.'**
  String get financeLocalStorageError;

  /// No description provided for @financeUnexpectedError.
  ///
  /// In ru, this message translates to:
  /// **'Получен некорректный ответ. Финансовые данные не были изменены клиентом.'**
  String get financeUnexpectedError;

  /// No description provided for @financeSessionChanged.
  ///
  /// In ru, this message translates to:
  /// **'Защищённая сессия обновилась. Повторите действие; подтверждение будет отправлено с теми же данными.'**
  String get financeSessionChanged;

  /// No description provided for @operationAcceptedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Операция сохранена'**
  String get operationAcceptedTitle;

  /// No description provided for @operationAcceptedUpdatingHome.
  ///
  /// In ru, this message translates to:
  /// **'Операция принята. Ждём новую версию главного экрана.'**
  String get operationAcceptedUpdatingHome;

  /// No description provided for @operationAcceptedHomeUpdated.
  ///
  /// In ru, this message translates to:
  /// **'Главный экран обновлён по новой авторитетной версии.'**
  String get operationAcceptedHomeUpdated;

  /// No description provided for @operationAcceptedProjectionDelayed.
  ///
  /// In ru, this message translates to:
  /// **'Операция уже сохранена, но обновление главного экрана задерживается. Повторно подтверждать её не нужно.'**
  String get operationAcceptedProjectionDelayed;

  /// No description provided for @operationAcceptedAuthRequired.
  ///
  /// In ru, this message translates to:
  /// **'Операция уже сохранена, но для обновления главного экрана потребуется снова войти.'**
  String get operationAcceptedAuthRequired;

  /// No description provided for @operationAcceptedSessionChanged.
  ///
  /// In ru, this message translates to:
  /// **'Операция уже сохранена, но сессия изменилась во время обновления. Откройте главный экран ещё раз.'**
  String get operationAcceptedSessionChanged;

  /// No description provided for @operationAcceptedRefreshFailed.
  ///
  /// In ru, this message translates to:
  /// **'Операция уже сохранена. Главный экран можно обновить позже.'**
  String get operationAcceptedRefreshFailed;

  /// No description provided for @operationQueuedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Операция сохранена на устройстве'**
  String get operationQueuedTitle;

  /// No description provided for @operationQueuedDescription.
  ///
  /// In ru, this message translates to:
  /// **'Подтверждение защищённо сохранено. Если сервер ещё не принял его, оно не влияет на баланс. Актуальный статус показан на главном экране.'**
  String get operationQueuedDescription;

  /// No description provided for @operationQueuedAuthDescription.
  ///
  /// In ru, this message translates to:
  /// **'Подтверждение защищённо сохранено. Для продолжения отправки может понадобиться повторный вход. Актуальный статус показан на главном экране.'**
  String get operationQueuedAuthDescription;

  /// No description provided for @operationAlreadySyncedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Операция уже синхронизирована'**
  String get operationAlreadySyncedTitle;

  /// No description provided for @operationAlreadySyncedDescription.
  ///
  /// In ru, this message translates to:
  /// **'Сервер подтвердил эту же операцию ранее. Повторная запись не создана.'**
  String get operationAlreadySyncedDescription;

  /// No description provided for @operationAttentionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Операция требует проверки'**
  String get operationAttentionTitle;

  /// No description provided for @operationAttentionConflict.
  ///
  /// In ru, this message translates to:
  /// **'Сохранённое подтверждение конфликтует с уже обработанной командой и не будет отправляться автоматически.'**
  String get operationAttentionConflict;

  /// No description provided for @operationAttentionRejected.
  ///
  /// In ru, this message translates to:
  /// **'Finance Core отклонил подтверждение. Баланс не изменён.'**
  String get operationAttentionRejected;

  /// No description provided for @operationAttentionSecurity.
  ///
  /// In ru, this message translates to:
  /// **'Отправка остановлена из-за проверки безопасности. Баланс не изменён.'**
  String get operationAttentionSecurity;

  /// No description provided for @operationAttentionInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Подтверждение нельзя безопасно отправить автоматически. Баланс не изменён.'**
  String get operationAttentionInvalid;

  /// No description provided for @operationSyncingBannerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отправляем сохранённую операцию'**
  String get operationSyncingBannerTitle;

  /// No description provided for @operationSyncingBannerDescription.
  ///
  /// In ru, this message translates to:
  /// **'До подтверждения сервера она не влияет на баланс.'**
  String get operationSyncingBannerDescription;

  /// No description provided for @operationHomeUpdatingBannerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Главный экран обновляется'**
  String get operationHomeUpdatingBannerTitle;

  /// No description provided for @operationHomeUpdatingBannerDescription.
  ///
  /// In ru, this message translates to:
  /// **'Операция уже сохранена сервером. Баланс обновится после готовности данных; повторно подтверждать её не нужно.'**
  String get operationHomeUpdatingBannerDescription;

  /// No description provided for @operationHomeUpdatingAction.
  ///
  /// In ru, this message translates to:
  /// **'Обновить сейчас'**
  String get operationHomeUpdatingAction;

  /// No description provided for @operationPendingBannerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Операция ждёт синхронизации'**
  String get operationPendingBannerTitle;

  /// No description provided for @operationPendingBannerDescription.
  ///
  /// In ru, this message translates to:
  /// **'Она защищённо сохранена на устройстве и пока не влияет на баланс.'**
  String get operationPendingBannerDescription;

  /// No description provided for @operationAuthBannerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Нужен повторный вход'**
  String get operationAuthBannerTitle;

  /// No description provided for @operationAuthBannerDescription.
  ///
  /// In ru, this message translates to:
  /// **'Сохранённая операция останется на устройстве до безопасной авторизации.'**
  String get operationAuthBannerDescription;

  /// No description provided for @operationAttentionBannerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте сохранённую операцию'**
  String get operationAttentionBannerTitle;

  /// No description provided for @operationAttentionBannerDescription.
  ///
  /// In ru, this message translates to:
  /// **'Автоматическая отправка остановлена. Баланс не изменён.'**
  String get operationAttentionBannerDescription;

  /// No description provided for @operationLockedBannerDescription.
  ///
  /// In ru, this message translates to:
  /// **'Отправка финансовых операций заблокирована после проверки безопасности. Новые подтверждения не будут отправляться автоматически.'**
  String get operationLockedBannerDescription;

  /// No description provided for @operationRetryNowAction.
  ///
  /// In ru, this message translates to:
  /// **'Повторить отправку'**
  String get operationRetryNowAction;

  /// Explains the account baseline bound and the recovery path.
  ///
  /// In ru, this message translates to:
  /// **'Учёт по счёту начинается {openingDate}. Операции раньше этой даты записать нельзя. Дату начала можно перенести назад в настройках счёта.'**
  String operationBeforeOpeningDateDetail(String openingDate);
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
