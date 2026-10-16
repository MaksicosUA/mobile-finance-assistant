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

  /// Balance card title when the snapshot names no wallet. The card shows the default wallet only and never a total across currencies (ADR 0029), so it must not claim one.
  ///
  /// In ru, this message translates to:
  /// **'Баланс'**
  String get balanceTitle;

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

  /// Home's one-tap entry. It opens the sentence field, not a microphone: voice will feed the same path once it exists.
  ///
  /// In ru, this message translates to:
  /// **'Записать фразой'**
  String get addBySentence;

  /// Screen-reader label for the Home entry action.
  ///
  /// In ru, this message translates to:
  /// **'Записать операцию одной фразой'**
  String get sentenceEntryLabel;

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
  /// **'Переключение языка пока недоступно.'**
  String get settingsNote;

  /// No description provided for @baselineSettingsAction.
  ///
  /// In ru, this message translates to:
  /// **'Дата начала учёта'**
  String get baselineSettingsAction;

  /// No description provided for @baselineSettingsDescription.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить операции за более ранний период'**
  String get baselineSettingsDescription;

  /// No description provided for @baselineCorrectionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Дата начала учёта'**
  String get baselineCorrectionTitle;

  /// No description provided for @baselineCorrectionLoading.
  ///
  /// In ru, this message translates to:
  /// **'Загружаем настройки счёта'**
  String get baselineCorrectionLoading;

  /// No description provided for @baselineCorrectionDescription.
  ///
  /// In ru, this message translates to:
  /// **'Перенесите дату назад, чтобы добавить более ранние операции. Начальный остаток и валюта не изменятся.'**
  String get baselineCorrectionDescription;

  /// No description provided for @baselineCurrentDateLabel.
  ///
  /// In ru, this message translates to:
  /// **'Текущая дата начала учёта'**
  String get baselineCurrentDateLabel;

  /// No description provided for @baselineNewDateLabel.
  ///
  /// In ru, this message translates to:
  /// **'Новая дата'**
  String get baselineNewDateLabel;

  /// No description provided for @baselineChooseDateAction.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать дату'**
  String get baselineChooseDateAction;

  /// No description provided for @baselineDateRangeHelp.
  ///
  /// In ru, this message translates to:
  /// **'Можно выбрать только дату раньше текущей даты начала учёта.'**
  String get baselineDateRangeHelp;

  /// No description provided for @baselineReviewTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте новую дату'**
  String get baselineReviewTitle;

  /// No description provided for @baselineReviewDescription.
  ///
  /// In ru, this message translates to:
  /// **'После подтверждения главный экран и месячные итоги будут пересчитаны из авторитетных данных.'**
  String get baselineReviewDescription;

  /// No description provided for @baselineConfirmAction.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердить новую дату'**
  String get baselineConfirmAction;

  /// No description provided for @baselineSuccessTitle.
  ///
  /// In ru, this message translates to:
  /// **'Дата начала учёта изменена'**
  String get baselineSuccessTitle;

  /// No description provided for @baselineSuccessDescription.
  ///
  /// In ru, this message translates to:
  /// **'Теперь можно добавлять операции начиная с {date}.'**
  String baselineSuccessDescription(String date);

  /// No description provided for @baselineHomeDelayedDescription.
  ///
  /// In ru, this message translates to:
  /// **'Дата уже сохранена. Главный экран обновится позже; повторно подтверждать изменение не нужно.'**
  String get baselineHomeDelayedDescription;

  /// No description provided for @baselineDoneAction.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get baselineDoneAction;

  /// No description provided for @baselineUnavailableTitle.
  ///
  /// In ru, this message translates to:
  /// **'Дату пока нельзя изменить'**
  String get baselineUnavailableTitle;

  /// No description provided for @baselineAccountRequired.
  ///
  /// In ru, this message translates to:
  /// **'Сначала настройте первый счёт.'**
  String get baselineAccountRequired;

  /// No description provided for @baselineMinimumDateReached.
  ///
  /// In ru, this message translates to:
  /// **'Счёт уже начинается с самой ранней поддерживаемой даты.'**
  String get baselineMinimumDateReached;

  /// No description provided for @baselineNotEarlierError.
  ///
  /// In ru, this message translates to:
  /// **'Выберите дату раньше текущей даты начала учёта.'**
  String get baselineNotEarlierError;

  /// No description provided for @baselineFutureError.
  ///
  /// In ru, this message translates to:
  /// **'Дата начала учёта не может быть позже сегодняшнего дня.'**
  String get baselineFutureError;

  /// No description provided for @baselineAfterOperationError.
  ///
  /// In ru, this message translates to:
  /// **'Новая дата не может быть позже самой ранней сохранённой операции.'**
  String get baselineAfterOperationError;

  /// No description provided for @baselineLoadFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить настройки счёта.'**
  String get baselineLoadFailed;

  /// No description provided for @baselineChangeFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось изменить дату. Финансовые данные не были изменены клиентом.'**
  String get baselineChangeFailed;

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
  /// **'Укажите фактический остаток. Дата начала задаёт самый ранний день, за который можно добавить операцию. Перед сохранением вы проверите данные.'**
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

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Запланировать трату'**
  String get plannedCostSettingsAction;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Например аренда или подписка'**
  String get plannedCostSettingsDescription;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Планируемая трата'**
  String get plannedCostTitle;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Загружаем счёт'**
  String get plannedCostLoading;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Планируемая трата не меняет баланс. Она появится в списке предстоящих платежей, пока вы её не подтвердите.'**
  String get plannedCostDescription;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Сначала нужно создать счёт: планируемая трата привязывается к нему.'**
  String get plannedCostAccountRequired;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get plannedCostTitleLabel;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Аренда'**
  String get plannedCostTitleHint;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Сумма'**
  String get plannedCostAmountLabel;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Дата платежа'**
  String get plannedCostDateLabel;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Выбрать дату'**
  String get plannedCostChooseDateAction;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Запланировать'**
  String get plannedCostSubmitAction;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get plannedCostRetryAction;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Трата запланирована'**
  String get plannedCostAcceptedTitle;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Она не влияет на баланс и ждёт подтверждения.'**
  String get plannedCostAcceptedDescription;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Обновляем главный экран'**
  String get plannedCostHomePending;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Главный экран обновлён'**
  String get plannedCostHomeUpdated;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Главный экран обновится чуть позже'**
  String get plannedCostHomeDelayed;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось обновить главный экран'**
  String get plannedCostHomeFailed;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Проверьте название, сумму и дату.'**
  String get plannedCostInvalidInput;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Счёт недоступен.'**
  String get plannedCostIssueAccountUnavailable;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Валюта не совпадает с валютой счёта.'**
  String get plannedCostIssueCurrencyMismatch;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Эта валюта пока не поддерживается.'**
  String get plannedCostIssueUnsupportedCurrency;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Дата раньше начала учёта по счёту. Выберите более позднюю дату.'**
  String get plannedCostIssueBeforeBaseline;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось запланировать трату.'**
  String get plannedCostGenericFailure;

  /// Planned cost flow (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get plannedCostDoneAction;

  /// Planned cost list (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Запланировано'**
  String get plannedCostListTitle;

  /// Planned cost list (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Пока ничего не запланировано.'**
  String get plannedCostListEmpty;

  /// Planned cost list (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Отменить'**
  String get plannedCostCancelAction;

  /// Planned cost list (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Отменить план'**
  String get plannedCostCancelSemantics;

  /// Planned cost list (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Срок'**
  String get plannedCostDueLabel;

  /// Planned cost list (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Просрочено'**
  String get plannedCostOverdueLabel;

  /// Planned cost list (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось отменить план.'**
  String get plannedCostCancelFailure;

  /// Planned cost confirmation (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Оплачено'**
  String get plannedCostConfirmAction;

  /// Planned cost confirmation (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Отметить план оплаченным'**
  String get plannedCostConfirmSemantics;

  /// Planned cost confirmation (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось записать операцию. План остался в списке — попробуйте ещё раз.'**
  String get plannedCostConfirmFailure;

  /// Planned cost confirmation (ADR 0018).
  ///
  /// In ru, this message translates to:
  /// **'«Оплачено» создаст обычную операцию расхода и уберёт план из списка.'**
  String get plannedCostConfirmHint;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Цели'**
  String get savingsGoalTitle;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Загружаем цели'**
  String get savingsGoalLoading;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Сначала создайте счёт — цель копится в его валюте.'**
  String get savingsGoalAccountRequired;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось выполнить действие. Попробуйте ещё раз.'**
  String get savingsGoalGenericFailure;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Проверьте название, сумму и дату.'**
  String get savingsGoalInvalidInput;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get savingsGoalRetryAction;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Цель показывает, сколько вы уже отложили. Отложенные деньги остаются на счёте: баланс, доходы и расходы не меняются.'**
  String get savingsGoalDescription;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Пока нет ни одной цели.'**
  String get savingsGoalEmpty;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Новая цель'**
  String get savingsGoalCreateAction;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get savingsGoalCancelCreateAction;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get savingsGoalTitleLabel;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Отпуск'**
  String get savingsGoalTitleHint;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Сколько нужно'**
  String get savingsGoalTargetLabel;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Планирую откладывать в месяц'**
  String get savingsGoalMonthlyLabel;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Необязательно. Это ориентир, а не обязательство.'**
  String get savingsGoalMonthlyHelper;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'К какой дате'**
  String get savingsGoalDateLabel;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Выбрать дату'**
  String get savingsGoalChooseDateAction;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Создать цель'**
  String get savingsGoalSubmitAction;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Сумма'**
  String get savingsGoalContributionLabel;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Отложить'**
  String get savingsGoalDepositAction;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Забрать'**
  String get savingsGoalWithdrawAction;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Отказаться от цели'**
  String get savingsGoalCancelAction;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Отказаться от цели и убрать её из списка'**
  String get savingsGoalCancelSemantics;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Отложить указанную сумму на эту цель'**
  String get savingsGoalDepositSemantics;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Забрать указанную сумму с этой цели'**
  String get savingsGoalWithdrawSemantics;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Цель достигнута'**
  String get savingsGoalAchievedLabel;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Счёт недоступен. Обновите экран.'**
  String get savingsGoalIssueAccountUnavailable;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Валюта цели должна совпадать с валютой счёта.'**
  String get savingsGoalIssueCurrencyMismatch;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Пока поддерживается только EUR.'**
  String get savingsGoalIssueUnsupportedCurrency;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Дата раньше даты открытия счёта.'**
  String get savingsGoalIssueBeforeBaseline;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Отложить можно только за сегодня или раньше.'**
  String get savingsGoalIssueFutureContribution;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'Цель уже закрыта. Обновите экран.'**
  String get savingsGoalIssueNotActive;

  /// Savings goals (ADR 0019).
  ///
  /// In ru, this message translates to:
  /// **'На цели меньше денег, чем вы пытаетесь забрать.'**
  String get savingsGoalIssueWithdrawalTooLarge;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Без категории'**
  String get categoryPickerNone;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Другое (ввести текстом)'**
  String get categoryPickerOther;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Своя категория'**
  String get categoryPickerOtherLabel;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Загружаем категории'**
  String get categoryPickerLoading;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Список категорий недоступен — впишите название вручную.'**
  String get categoryPickerUnavailable;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Продукты'**
  String get categorySeedGroceries;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Кафе и рестораны'**
  String get categorySeedEatingOut;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Транспорт'**
  String get categorySeedTransport;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Жильё'**
  String get categorySeedHousing;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Связь и интернет'**
  String get categorySeedUtilities;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Здоровье'**
  String get categorySeedHealth;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Одежда'**
  String get categorySeedClothing;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Развлечения'**
  String get categorySeedEntertainment;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Образование'**
  String get categorySeedEducation;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Подарки'**
  String get categorySeedGiftsOut;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Прочее'**
  String get categorySeedOtherExpense;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Зарплата'**
  String get categorySeedSalary;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Подработка'**
  String get categorySeedFreelance;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Подарки'**
  String get categorySeedGiftsIn;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Проценты'**
  String get categorySeedInterest;

  /// Category catalogue (ADR 0020).
  ///
  /// In ru, this message translates to:
  /// **'Прочее'**
  String get categorySeedOtherIncome;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Категории'**
  String get categoriesSettingsAction;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Свои названия для трат и доходов'**
  String get categoriesSettingsDescription;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Категории'**
  String get categoriesTitle;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Расходы'**
  String get categoriesExpenseTab;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Доходы'**
  String get categoriesIncomeTab;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Добавить категорию'**
  String get categoryAddAction;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get categoryNameLabel;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Создать'**
  String get categoryCreateAction;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get categorySaveAction;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Переименовать'**
  String get categoryRenameAction;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Скрыть'**
  String get categoryHideAction;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Вернуть'**
  String get categoryRestoreAction;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Скрытые: {count}'**
  String categoryHiddenSection(int count);

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Скрытая категория не предлагается при новой записи, но остаётся на прошлых операциях.'**
  String get categoryHiddenNote;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Пока ни одной категории'**
  String get categoryListEmpty;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Скрыть категорию?'**
  String get categoryHideDialogTitle;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Она исчезнет из списка при новой записи. Прошлые операции останутся в ней, и её можно вернуть.'**
  String get categoryHideDialogDescription;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Такое название уже есть'**
  String get categoryNameTakenError;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Категория скрыта — сначала верните её'**
  String get categoryArchivedError;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Категория не найдена'**
  String get categoryNotFoundError;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Введите название до 100 символов'**
  String get categoryNameInvalidError;

  /// Category management (ADR 0020, step 2b).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить категории'**
  String get categoryLoadError;

  /// Opens the correction sheet for one confirmed operation.
  ///
  /// In ru, this message translates to:
  /// **'Изменить'**
  String get operationCorrectAction;

  /// Withdraws one confirmed operation without replacing it.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get operationRemoveAction;

  /// Title of the correction sheet.
  ///
  /// In ru, this message translates to:
  /// **'Исправить операцию'**
  String get operationCorrectTitle;

  /// Confirms the correction.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get operationCorrectSave;

  /// Shown after a correction is accepted.
  ///
  /// In ru, this message translates to:
  /// **'Операция исправлена'**
  String get operationCorrectedMessage;

  /// Shown after a removal is accepted.
  ///
  /// In ru, this message translates to:
  /// **'Операция удалена'**
  String get operationRemovedMessage;

  /// Confirmation dialog title before withdrawing an operation.
  ///
  /// In ru, this message translates to:
  /// **'Удалить операцию?'**
  String get operationRemoveDialogTitle;

  /// Explains that a removal withdraws rather than erases.
  ///
  /// In ru, this message translates to:
  /// **'Она перестанет учитываться в балансе и отчётах. Сама запись сохранится в истории изменений.'**
  String get operationRemoveDialogBody;

  /// Generic correction failure.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить изменение. Попробуйте ещё раз.'**
  String get operationCorrectionFailed;

  /// The operation was already corrected or removed.
  ///
  /// In ru, this message translates to:
  /// **'Эту операцию уже исправили. Обновите список.'**
  String get operationAlreadyReversedMessage;

  /// The operation is gone or belongs to someone else.
  ///
  /// In ru, this message translates to:
  /// **'Такой операции больше нет.'**
  String get operationNotFoundMessage;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'Все операции'**
  String get operationHistoryTitle;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'Все операции'**
  String get operationHistorySettingsAction;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'История записей и что было вписано'**
  String get operationHistorySettingsDescription;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'Пока ни одной записи'**
  String get operationHistoryEmpty;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'Показать ещё'**
  String get operationHistoryMore;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить операции'**
  String get operationHistoryLoadError;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить продолжение'**
  String get operationHistoryLoadMoreError;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'{date}'**
  String operationHistoryDate(DateTime date);

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'Дата'**
  String get operationDetailDate;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'Категория'**
  String get operationDetailCategory;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'Где'**
  String get operationDetailMerchant;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'Было вписано'**
  String get operationDetailOriginalText;

  /// Operation history (ADR 0020, step 4).
  ///
  /// In ru, this message translates to:
  /// **'Категорию позже переименовали'**
  String get operationDetailOriginalTextHint;

  /// Analytics (ADR 0020, step 5).
  ///
  /// In ru, this message translates to:
  /// **'Расходы по категориям'**
  String get analyticsExpenseByCategory;

  /// Analytics (ADR 0020, step 5).
  ///
  /// In ru, this message translates to:
  /// **'Доходы по категориям'**
  String get analyticsIncomeByCategory;

  /// Analytics (ADR 0020, step 5).
  ///
  /// In ru, this message translates to:
  /// **'За этот месяц записей нет'**
  String get analyticsBreakdownEmpty;

  /// Analytics (ADR 0020, step 5).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось посчитать аналитику'**
  String get analyticsLoadError;

  /// Analytics (ADR 0020, step 5).
  ///
  /// In ru, this message translates to:
  /// **'{percent}%'**
  String analyticsShare(String percent);

  /// Analytics (ADR 0020, step 5).
  ///
  /// In ru, this message translates to:
  /// **'{month}'**
  String analyticsMonth(DateTime month);

  /// Profile screen.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить профиль'**
  String get profileLoadError;

  /// Profile screen.
  ///
  /// In ru, this message translates to:
  /// **'Почта для входа'**
  String get profileEmailLabel;

  /// Profile screen.
  ///
  /// In ru, this message translates to:
  /// **'СЧЁТ'**
  String get profileAccountSection;

  /// Profile screen: the canonical reporting timezone (ADR 0010).
  ///
  /// In ru, this message translates to:
  /// **'Часовой пояс'**
  String get profileTimezoneSetting;

  /// Profile screen: a registered user without an account is a real state.
  ///
  /// In ru, this message translates to:
  /// **'Счёт появится после первой записи'**
  String get profileNoAccount;

  /// Profile screen: the opening baseline date beside the action that changes it.
  ///
  /// In ru, this message translates to:
  /// **'Сейчас {date}'**
  String profileOpeningDateValue(DateTime date);

  /// Profile screen: which build is installed.
  ///
  /// In ru, this message translates to:
  /// **'Версия {version}'**
  String profileVersion(String version);

  /// Natural-language entry (ADR 0022).
  ///
  /// In ru, this message translates to:
  /// **'Опишите операцию одной фразой'**
  String get entrySentenceField;

  /// Natural-language entry (ADR 0022).
  ///
  /// In ru, this message translates to:
  /// **'Потратил 12,50 на продукты вчера'**
  String get entrySentenceHint;

  /// Natural-language entry (ADR 0022).
  ///
  /// In ru, this message translates to:
  /// **'Разобрать'**
  String get entrySentenceParseAction;

  /// Natural-language entry (ADR 0022).
  ///
  /// In ru, this message translates to:
  /// **'Заполнил поля ниже — проверьте и подтвердите.'**
  String get entrySentenceFilled;

  /// Natural-language entry (ADR 0022).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось разобрать фразу.'**
  String get entrySentenceParseError;

  /// Natural-language entry (ADR 0022).
  ///
  /// In ru, this message translates to:
  /// **'Напишите фразу покороче или начните с суммы.'**
  String get entrySentenceEmpty;

  /// Natural-language entry (ADR 0022).
  ///
  /// In ru, this message translates to:
  /// **'Сумму не нашёл — впишите её.'**
  String get entrySentenceGapAmount;

  /// Natural-language entry (ADR 0022).
  ///
  /// In ru, this message translates to:
  /// **'В фразе несколько чисел — уточните сумму.'**
  String get entrySentenceGapAmbiguous;

  /// Natural-language entry (ADR 0022).
  ///
  /// In ru, this message translates to:
  /// **'Дату не понял — проверьте её.'**
  String get entrySentenceGapDate;

  /// Natural-language entry (ADR 0022).
  ///
  /// In ru, this message translates to:
  /// **'Категорию не подобрал — выберите её.'**
  String get entrySentenceGapCategory;

  /// Natural-language entry (ADR 0022): the sentence is a transfer (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Это перевод между кошельками, а не доход или трата — поэтому ничего не заполнил.'**
  String get entrySentenceGapTransfer;

  /// Natural-language entry (ADR 0022): opens the transfer screen with both sides filled.
  ///
  /// In ru, this message translates to:
  /// **'Открыть перевод'**
  String get entrySentenceOpenTransfer;

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Слова категории'**
  String get categoryKeywordsTitle;

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Слова'**
  String get categoryKeywordsAction;

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Если слово из фразы начинается с одного из этих, операция попадёт в эту категорию. «авто» поймает и «автохимию», «продукт» — и «продуктов».'**
  String get categoryKeywordsDescription;

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Слов пока нет — категория подберётся только по названию.'**
  String get categoryKeywordsEmpty;

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Добавить слово'**
  String get categoryKeywordsField;

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get categoryKeywordsAdd;

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Убрать слово {keyword}'**
  String categoryKeywordsRemove(String keyword);

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Слово — от трёх букв или цифр, без пробелов.'**
  String get categoryKeywordsInvalid;

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Это слово уже ведёт в другую категорию. Уберите его там.'**
  String get categoryKeywordsTaken;

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Скрытая категория не участвует в подборе.'**
  String get categoryKeywordsArchived;

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить слова'**
  String get categoryKeywordsLoadError;

  /// Category keywords (ADR 0020, step 3).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить слово'**
  String get categoryKeywordsSaveError;

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'7 дней'**
  String get analyticsPeriod7Days;

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'Месяц'**
  String get analyticsPeriodMonth;

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'Квартал'**
  String get analyticsPeriodQuarter;

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'Год'**
  String get analyticsPeriodYear;

  /// Opens a date range picker for an arbitrary analytics window.
  ///
  /// In ru, this message translates to:
  /// **'Свой период'**
  String get analyticsPeriodCustom;

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'Период'**
  String get analyticsPeriodLabel;

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'Баланс'**
  String get analyticsBalanceTitle;

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'{opening} → {closing}'**
  String analyticsBalanceFromTo(String opening, String closing);

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'за период {change}'**
  String analyticsBalanceChange(String change);

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'За этот период трат не было'**
  String get analyticsNoSpending;

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'было {amount}'**
  String analyticsPreviousAmount(String amount);

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'{from} — {to}'**
  String analyticsWindowRange(String from, String to);

  /// Analytics periods (balance line and comparison).
  ///
  /// In ru, this message translates to:
  /// **'в сравнении с {from} — {to}'**
  String analyticsComparedWith(String from, String to);

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Эта категория недоступна. Выберите другую.'**
  String get plannedCostIssueCategoryUnavailable;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Повторять каждый месяц'**
  String get plannedCostRepeatToggle;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'День месяца'**
  String get plannedCostRepeatDayLabel;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Последний день месяца'**
  String get plannedCostRepeatLastDay;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'В коротких месяцах платёж сдвинется на последний день: 31 января, 28 февраля, 31 марта.'**
  String get plannedCostRepeatShortMonthHint;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Ближайшие даты'**
  String get plannedCostRepeatFirstDatesTitle;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Повторяется'**
  String get plannedCostRecurrenceListTitle;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Повторяющихся трат пока нет.'**
  String get plannedCostRecurrenceListEmpty;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Каждый месяц, {day} числа'**
  String plannedCostRecurrenceMonthlyOnDay(int day);

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Каждый месяц, последний день'**
  String get plannedCostRecurrenceMonthlyLastDay;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Закончить'**
  String get plannedCostRecurrenceEndAction;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Закончить серию?'**
  String get plannedCostRecurrenceEndDialogTitle;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Новые платежи создаваться не будут. Будущие запланированные платежи из этой серии отменятся, а уже наступившие останутся — их нужно подтвердить или пропустить.'**
  String get plannedCostRecurrenceEndDialogBody;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Серия закончена. Отменено будущих платежей: {count}'**
  String plannedCostRecurrenceEndedMessage(int count);

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Пропустить'**
  String get plannedCostSkipAction;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'«Пропустить» убирает один платёж, серия продолжится.'**
  String get plannedCostSkipHint;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Повторяющаяся трата записана'**
  String get plannedCostRecurrenceAcceptedTitle;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Платежи будут появляться сами. Это прогноз: баланс он не меняет.'**
  String get plannedCostRecurrenceAcceptedDescription;

  /// Repeating planned cost (ADR 0025).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось изменить повторяющуюся трату.'**
  String get plannedCostRecurrenceFailure;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Проверить обновления'**
  String get appUpdateCheckAction;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Спросить сервер, вышла ли новая версия'**
  String get appUpdateCheckDescription;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Проверяем…'**
  String get appUpdateChecking;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'У вас последняя версия.'**
  String get appUpdateUpToDate;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Доступна версия {version}, {size}'**
  String appUpdateAvailable(String version, String size);

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Что нового'**
  String get appUpdateNotesLabel;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Скачать и установить'**
  String get appUpdateDownloadAction;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Скачиваем… {percent}%'**
  String appUpdateDownloading(int percent);

  /// Exporting the person's own data (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Выгрузить мои данные'**
  String get accountExportAction;

  /// Exporting the person's own data (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Полный файл со всеми данными и таблица операций для Excel'**
  String get accountExportDescription;

  /// Exporting the person's own data (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Готовлю файлы…'**
  String get accountExportPreparing;

  /// Exporting the person's own data (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось связаться с сервером. Проверьте интернет и попробуйте ещё раз.'**
  String get accountExportFailedUnreachable;

  /// Exporting the person's own data (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Сервер не смог подготовить выгрузку. Попробуйте позже.'**
  String get accountExportFailedUnavailable;

  /// Exporting the person's own data (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Сессия закончилась — войдите снова.'**
  String get accountExportFailedAuthentication;

  /// Exporting the person's own data (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Файлы готовы, но окно «Поделиться» не открылось.'**
  String get accountExportFailedShare;

  /// Exporting the person's own data (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось записать файлы на телефон.'**
  String get accountExportFailedStorage;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Удалить аккаунт'**
  String get accountDeletionAction;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Через 7 дней. Передумали — просто войдите снова'**
  String get accountDeletionActionDescription;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Удаление аккаунта'**
  String get accountDeletionTitle;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт удалится через 7 дней'**
  String get accountDeletionHeadline;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Удалится всё: кошельки, операции, переводы, категории, планы, бюджеты и цели. Вернуть их потом будет нельзя.'**
  String get accountDeletionWhat;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Вы сразу выйдете на всех устройствах. Если передумаете — войдите в течение 7 дней, и удаление отменится.'**
  String get accountDeletionSignedOut;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'В резервных копиях сервера данные хранятся ещё до 14 дней, потом исчезают и оттуда.'**
  String get accountDeletionBackups;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Сначала выгрузить мои данные'**
  String get accountDeletionExportFirst;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Операций на этом телефоне, ещё не дошедших до сервера: {count}. Их нет в выгрузке, и они пропадут вместе с аккаунтом. Лучше дождаться отправки.'**
  String accountDeletionUnsent(int count);

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Пароль'**
  String get accountDeletionPasswordLabel;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Тот же, которым вы входите. Нужен, чтобы удалить аккаунт мог только его владелец.'**
  String get accountDeletionPasswordHelp;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Неверный пароль'**
  String get accountDeletionPasswordRejected;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Удалить аккаунт'**
  String get accountDeletionSubmit;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Удалить аккаунт?'**
  String get accountDeletionConfirmTitle;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Вы выйдете на всех устройствах. Через 7 дней все данные будут удалены, если вы не войдёте раньше.'**
  String get accountDeletionConfirmBody;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get accountDeletionConfirmCancel;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get accountDeletionConfirmAccept;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось связаться с сервером. Ничего не удалено — проверьте интернет и попробуйте ещё раз.'**
  String get accountDeletionUnreachable;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Сервер не смог принять запрос. Ничего не удалено — попробуйте позже.'**
  String get accountDeletionUnavailable;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Сессия закончилась — войдите снова. Ничего не удалено.'**
  String get accountDeletionAuthentication;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт будет удалён {date}. Чтобы отменить удаление, просто войдите до этого дня.'**
  String accountDeletionScheduledNotice(DateTime date);

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт будет удалён через 7 дней. Чтобы отменить удаление, просто войдите до этого срока.'**
  String get accountDeletionScheduledNoticeUndated;

  /// Erasing the person's own account (ADR 0030).
  ///
  /// In ru, this message translates to:
  /// **'Удаление аккаунта отменено — вы вошли, и все данные на месте.'**
  String get accountDeletionCancelled;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Файл скачан и проверен. Подтвердите установку в системном окне — Android ставит обновление сам, и это занимает до минуты. Скачивать заново не нужно: файл сейчас нужен установщику.'**
  String get appUpdateHandedToInstaller;

  /// In-app update (ADR 0026): reopens the installer for the package already downloaded (issue 0010).
  ///
  /// In ru, this message translates to:
  /// **'Открыть окно установки снова'**
  String get appUpdateOpenInstallerAction;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Android просит разрешить установку из этого приложения. Это делается один раз.'**
  String get appUpdateNeedsPermission;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Открыть настройки'**
  String get appUpdatePermissionAction;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Сервер недоступен. Попробуйте позже.'**
  String get appUpdateFailedUnreachable;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Сервер не смог ответить про обновления.'**
  String get appUpdateFailedServer;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Файл скачался повреждённым и удалён. Попробуйте ещё раз.'**
  String get appUpdateFailedCorrupted;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть установщик Android.'**
  String get appUpdateFailedInstaller;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Нужно войти заново.'**
  String get appUpdateFailedAuth;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get appUpdateRetryAction;

  /// In-app update (ADR 0026).
  ///
  /// In ru, this message translates to:
  /// **'{megabytes} МБ'**
  String appUpdateMegabytes(String megabytes);

  /// Notification centre (ADR 0026 amendment).
  ///
  /// In ru, this message translates to:
  /// **'Уведомления'**
  String get notificationsQuietLabel;

  /// Notification centre (ADR 0026 amendment).
  ///
  /// In ru, this message translates to:
  /// **'Ничего, что требует внимания.'**
  String get notificationsEmpty;

  /// Notification centre (ADR 0026 amendment).
  ///
  /// In ru, this message translates to:
  /// **'Здесь появятся напоминания о платежах и новые версии приложения.'**
  String get notificationsEmptyHint;

  /// Notification centre (ADR 0026 amendment).
  ///
  /// In ru, this message translates to:
  /// **'Доступна версия {version}'**
  String notificationUpdateTitle(String version);

  /// Notification centre (ADR 0026 amendment).
  ///
  /// In ru, this message translates to:
  /// **'Обновить можно в профиле.'**
  String get notificationUpdateBody;

  /// Notification centre (ADR 0026 amendment).
  ///
  /// In ru, this message translates to:
  /// **'Открыть профиль'**
  String get notificationUpdateAction;

  /// Notification centre (ADR 0026 amendment).
  ///
  /// In ru, this message translates to:
  /// **'Просрочен платёж: {title}'**
  String notificationPaymentOverdueTitle(String title);

  /// Notification centre (ADR 0026 amendment).
  ///
  /// In ru, this message translates to:
  /// **'Скоро платёж: {title}'**
  String notificationPaymentDueSoonTitle(String title);

  /// Notification centre (ADR 0026 amendment).
  ///
  /// In ru, this message translates to:
  /// **'{date}, {amount}'**
  String notificationPaymentBody(String date, String amount);

  /// Notification centre (ADR 0026 amendment).
  ///
  /// In ru, this message translates to:
  /// **'Открыть запланированные'**
  String get notificationPaymentAction;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Бюджеты'**
  String get budgetsTitle;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Бюджеты'**
  String get budgetsSettingsAction;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Месячные лимиты и сколько осталось'**
  String get budgetsSettingsDescription;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'{from} — {to}'**
  String budgetsPeriod(String from, String to);

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Все траты'**
  String get budgetsOverallTitle;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Лимитов пока нет.'**
  String get budgetsEmpty;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Поставьте месячный лимит на категорию или сразу на все траты.'**
  String get budgetsEmptyHint;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Потрачено {spent} из {limit}'**
  String budgetsSpentOfLimit(String spent, String limit);

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Осталось {amount}'**
  String budgetsRemaining(String amount);

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Перерасход {amount}'**
  String budgetsOverspentBy(String amount);

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Ещё запланировано {amount}'**
  String budgetsPlanned(String amount);

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Поставить лимит'**
  String get budgetsAddAction;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Снять'**
  String get budgetsRemoveAction;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Снять лимит?'**
  String get budgetsRemoveDialogTitle;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Трата останется, перестанет считаться только лимит. Поставить новый можно в любой момент.'**
  String get budgetsRemoveDialogBody;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'На что'**
  String get budgetsCategoryLabel;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Лимит в месяц'**
  String get budgetsLimitLabel;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get budgetsSaveAction;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить бюджеты.'**
  String get budgetsLoadError;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить лимит.'**
  String get budgetsWriteError;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Для всех категорий лимиты уже стоят.'**
  String get budgetsNoCategoriesLeft;

  /// Monthly budgets (ADR 0027).
  ///
  /// In ru, this message translates to:
  /// **'Сначала создайте счёт.'**
  String get budgetsAccountRequired;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Часовой пояс учёта'**
  String get timezoneTitle;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Сейчас {zone}'**
  String timezoneCurrent(String zone);

  /// Reporting timezone correction (ADR 0028): history is not re-filed.
  ///
  /// In ru, this message translates to:
  /// **'Здесь решается, где проходит граница дня и месяца. Уже записанные операции остаются на своих датах — меняется только то, что считается «сегодня» и «этот месяц».'**
  String get timezoneExplanation;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Поиск города или зоны'**
  String get timezoneSearchField;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'ПОЯС ТЕЛЕФОНА'**
  String get timezoneDeviceSection;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'ВСЕ ПОЯСА'**
  String get timezoneAllSection;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get timezoneNothingFound;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Перенести учёт в {zone}?'**
  String timezoneConfirmTitle(String zone);

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Суммы и даты уже записанных операций не изменятся. По-новому будут считаться только «сегодня» и границы месяца.'**
  String get timezoneConfirmBody;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Перенести'**
  String get timezoneConfirmAction;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Учёт ведётся в {zone}'**
  String timezoneCorrected(String zone);

  /// Reporting timezone correction (ADR 0028): TIMEZONE_UNCHANGED.
  ///
  /// In ru, this message translates to:
  /// **'Учёт уже ведётся в этом поясе.'**
  String get timezoneUnchangedError;

  /// Reporting timezone correction (ADR 0028): TIMEZONE_BEHIND_RECORDED_OPERATIONS.
  ///
  /// In ru, this message translates to:
  /// **'В этом поясе последняя запись оказалась бы в будущем, и её сумма пропала бы из баланса до завтра. Выберите пояс восточнее или попробуйте позже.'**
  String get timezoneBehindOperationsError;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось изменить часовой пояс.'**
  String get timezoneWriteError;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить счёт.'**
  String get timezoneLoadError;

  /// Reporting timezone correction (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Сначала создайте счёт.'**
  String get timezoneAccountRequired;

  /// Profile action opening the reporting timezone screen (ADR 0028).
  ///
  /// In ru, this message translates to:
  /// **'Где проходит граница дня и месяца'**
  String get timezoneSettingsDescription;

  /// Entry by sentence: a currency sign the parser cannot name (issue 0007).
  ///
  /// In ru, this message translates to:
  /// **'Валюту не разобрал — впишите сумму сами.'**
  String get entrySentenceGapCurrency;

  /// Entry by sentence: the sentence named a currency this account does not hold (issue 0007).
  ///
  /// In ru, this message translates to:
  /// **'Сумма в {parsed}, а счёт в {account} — не подставил её.'**
  String entrySentenceCurrencyMismatch(String parsed, String account);

  /// Home: wallets in other currencies, listed beside the balance card and never summed with it (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'ДРУГИЕ КОШЕЛЬКИ'**
  String get otherWalletsTitle;

  /// Transfer between wallets (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Перевод между счетами'**
  String get transferTitle;

  /// Profile action opening the transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Перевод между счетами'**
  String get transferSettingsAction;

  /// Profile action subtitle.
  ///
  /// In ru, this message translates to:
  /// **'Переложить деньги из одного кошелька в другой'**
  String get transferSettingsDescription;

  /// Transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Откуда'**
  String get transferFromField;

  /// Transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Куда'**
  String get transferToField;

  /// Transfer screen: the amount that left the source wallet.
  ///
  /// In ru, this message translates to:
  /// **'Сколько ушло'**
  String get transferFromAmountField;

  /// Transfer screen: the amount that arrived in the target wallet.
  ///
  /// In ru, this message translates to:
  /// **'Сколько пришло'**
  String get transferToAmountField;

  /// Transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Когда'**
  String get transferDateField;

  /// Transfer screen: the rate the two amounts imply, shown and never stored (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Курс: 1 {from} = {rate} {to}'**
  String transferRateLabel(String from, String rate, String to);

  /// Transfer screen: why no rate is fetched (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Курс не берётся из интернета — он следует из двух сумм, которые вы ввели.'**
  String get transferRateHint;

  /// Transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get transferReviewAction;

  /// Transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Перевести'**
  String get transferConfirmAction;

  /// Transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Изменить'**
  String get transferEditAction;

  /// Transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Перевод записан'**
  String get transferAcceptedTitle;

  /// Transfer screen: what left and what arrived.
  ///
  /// In ru, this message translates to:
  /// **'{fromAmount} → {toAmount}'**
  String transferAcceptedBody(String fromAmount, String toAmount);

  /// Transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Для перевода нужен второй кошелёк в другой валюте.'**
  String get transferSecondWalletRequired;

  /// Transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить счета.'**
  String get transferLoadError;

  /// Transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось выполнить перевод.'**
  String get transferWriteError;

  /// Transfer screen.
  ///
  /// In ru, this message translates to:
  /// **'Выберите два разных кошелька.'**
  String get transferSameWalletError;

  /// Transfer refusal (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Кошелёк недоступен.'**
  String get transferIssueWalletUnavailable;

  /// Transfer refusal (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Валюта суммы не совпадает с валютой кошелька.'**
  String get transferIssueCurrencyMismatch;

  /// Transfer refusal (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Деньги не могли уйти раньше, чем кошелёк появился.'**
  String get transferIssueBeforeBaseline;

  /// Transfer refusal (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Дата перевода в будущем.'**
  String get transferIssueFutureDate;

  /// Transfer refusal (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Подтверждение раньше самой записи.'**
  String get transferIssueConfirmationBeforeCapture;

  /// Opening a wallet in another currency (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Новый кошелёк'**
  String get walletTitle;

  /// Profile action opening the wallet screen.
  ///
  /// In ru, this message translates to:
  /// **'Открыть кошелёк'**
  String get walletSettingsAction;

  /// Profile action subtitle.
  ///
  /// In ru, this message translates to:
  /// **'Счёт в другой валюте — деньги не конвертируются'**
  String get walletSettingsDescription;

  /// Wallet screen.
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get walletNameField;

  /// Wallet screen.
  ///
  /// In ru, this message translates to:
  /// **'Валюта'**
  String get walletCurrencyField;

  /// Wallet screen: the opening balance.
  ///
  /// In ru, this message translates to:
  /// **'Сколько сейчас на нём'**
  String get walletOpeningBalanceField;

  /// Wallet screen.
  ///
  /// In ru, this message translates to:
  /// **'С какого числа'**
  String get walletOpeningDateField;

  /// Wallet screen: currency picker.
  ///
  /// In ru, this message translates to:
  /// **'Поиск валюты'**
  String get walletCurrencySearch;

  /// Wallet screen: a currency this profile already holds.
  ///
  /// In ru, this message translates to:
  /// **'Уже есть'**
  String get walletCurrencyHeld;

  /// Wallet screen: no conversion happens (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Деньги между кошельками не конвертируются. Каждый живёт в своей валюте, а перевод записывается двумя суммами.'**
  String get walletExplanation;

  /// Wallet screen.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get walletReviewAction;

  /// Wallet screen.
  ///
  /// In ru, this message translates to:
  /// **'Открыть'**
  String get walletConfirmAction;

  /// Wallet screen.
  ///
  /// In ru, this message translates to:
  /// **'Кошелёк открыт'**
  String get walletOpenedTitle;

  /// Wallet screen.
  ///
  /// In ru, this message translates to:
  /// **'Сначала создайте основной счёт.'**
  String get walletAccountRequired;

  /// Wallet screen.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить счета.'**
  String get walletLoadError;

  /// Wallet screen.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть кошелёк.'**
  String get walletWriteError;

  /// Entry form: which wallet the operation is recorded in (ADR 0029).
  ///
  /// In ru, this message translates to:
  /// **'Кошелёк'**
  String get operationWalletField;
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
