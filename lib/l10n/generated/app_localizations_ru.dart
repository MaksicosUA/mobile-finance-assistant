// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Мои финансы';

  @override
  String get greetingMorningNeutral => 'Доброе утро';

  @override
  String get greetingDayNeutral => 'Добрый день';

  @override
  String get greetingEveningNeutral => 'Добрый вечер';

  @override
  String get greetingNightNeutral => 'Доброй ночи';

  @override
  String greetingMorning(String userName) {
    return 'Доброе утро, $userName';
  }

  @override
  String greetingDay(String userName) {
    return 'Добрый день, $userName';
  }

  @override
  String greetingEvening(String userName) {
    return 'Добрый вечер, $userName';
  }

  @override
  String greetingNight(String userName) {
    return 'Доброй ночи, $userName';
  }

  @override
  String get notificationsLabel => 'Уведомления, есть новые';

  @override
  String get notificationsTitle => 'Уведомления';

  @override
  String get notificationsStubDescription =>
      'Центр уведомлений будет подключён на следующем этапе.';

  @override
  String get openSettingsLabel => 'Открыть настройки';

  @override
  String get balanceTitle => 'Баланс';

  @override
  String get hideAmounts => 'Скрыть суммы';

  @override
  String get showAmounts => 'Показать суммы';

  @override
  String get monthDelta => 'за месяц';

  @override
  String get balanceDeltaUnavailable => 'Динамика за месяц недоступна';

  @override
  String get addBySentence => 'Записать фразой';

  @override
  String get sentenceEntryLabel => 'Записать операцию одной фразой';

  @override
  String get addByVoice => 'Добавить голосом';

  @override
  String get voiceEntryLabel => 'Добавить операцию голосом';

  @override
  String get setupAccountAction => 'Настроить счёт';

  @override
  String monthSummaryTitle(String month) {
    return 'Итоги за $month';
  }

  @override
  String get income => 'Доходы';

  @override
  String get incomeCaption => 'поступило';

  @override
  String get expenses => 'Расходы';

  @override
  String get expensesCaption => 'потрачено';

  @override
  String get netFlow => 'Чистый поток';

  @override
  String get netPositiveCaption => 'в плюсе';

  @override
  String get trendExpensesTitle => 'Расходы';

  @override
  String get trendBalanceTitle => 'Баланс';

  @override
  String get trendUnknownTitle => 'Динамика';

  @override
  String get trendLast7Days => 'последние 7 дней';

  @override
  String get trendLast30Days => 'последние 30 дней';

  @override
  String get trendPeriodUnknown => 'период';

  @override
  String get trend7DaysChip => '7 дней';

  @override
  String get trend30DaysChip => '30 дней';

  @override
  String get detailsAction => 'Подробнее';

  @override
  String get trendEmpty => 'Пока недостаточно данных для графика';

  @override
  String trendSemantics(String title, String amount) {
    return '$title за период, всего $amount';
  }

  @override
  String get amountsHidden => 'суммы скрыты';

  @override
  String goalDueDate(String date) {
    return 'до $date';
  }

  @override
  String goalProgressSummary(String target, String progress) {
    return 'из $target · $progress%';
  }

  @override
  String goalMonthlyContribution(String amount) {
    return 'Нужно откладывать примерно $amount в месяц';
  }

  @override
  String goalSemantics(
    String title,
    String current,
    String target,
    String progress,
  ) {
    return '$title, накоплено $current, цель $target, прогресс $progress процентов, открыть цель';
  }

  @override
  String get upcomingPaymentsTitle => 'Ближайшие платежи';

  @override
  String get allPaymentsAction => 'Все платежи';

  @override
  String get noUpcomingPayments => 'Ближайших платежей нет';

  @override
  String paymentDueDate(String date) {
    return 'до $date';
  }

  @override
  String paymentOverdueDate(String date) {
    return 'просрочен · $date';
  }

  @override
  String paymentDateUnknown(String date) {
    return 'статус уточняется · $date';
  }

  @override
  String paymentSemantics(String title, String due, String amount) {
    return '$title, $due, $amount';
  }

  @override
  String get recentTransactionsTitle => 'Последние операции';

  @override
  String get noRecentTransactions => 'Подтверждённых операций пока нет';

  @override
  String get transactionCategoryUnavailable => 'Без категории';

  @override
  String transactionMetadata(String category, String date) {
    return '$category · $date';
  }

  @override
  String get transactionIncome => 'доход';

  @override
  String get transactionExpense => 'расход';

  @override
  String get transactionTransfer => 'перевод';

  @override
  String get transactionUnknown => 'операция';

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
  String get refreshingTitle => 'Обновляем данные';

  @override
  String get refreshingDescription =>
      'Текущая финансовая картина остаётся доступной.';

  @override
  String get partialDataTitle => 'Часть данных временно недоступна';

  @override
  String get partialDataDescription => 'Доступные разделы продолжают работать.';

  @override
  String get offlineTitle => 'Нет соединения';

  @override
  String offlineDataAsOf(String date, String time) {
    return 'Данные актуальны на $date, $time UTC.';
  }

  @override
  String get refreshFailedTitle => 'Не удалось обновить данные';

  @override
  String get refreshFailedDescription =>
      'Показываем предыдущую финансовую картину.';

  @override
  String get retryAction => 'Повторить';

  @override
  String get fatalErrorTitle => 'Не удалось загрузить данные';

  @override
  String get fatalErrorDescription =>
      'Попробуйте ещё раз. Если ошибка повторится, сообщите код запроса поддержке.';

  @override
  String requestIdLabel(String requestId) {
    return 'Код запроса: $requestId';
  }

  @override
  String get authExpiredTitle => 'Сессия истекла';

  @override
  String get authExpiredDescription => 'Для защиты данных нужно войти снова.';

  @override
  String get signInAgainAction => 'Войти снова';

  @override
  String get sessionExpiredStubTitle => 'Повторный вход';

  @override
  String get sessionExpiredStubDescription =>
      'Экран авторизации будет подключён вместе с настоящей сессией. Финансовые данные не удалены.';

  @override
  String get balanceUnavailable => 'Баланс временно недоступен';

  @override
  String get monthSummaryUnavailable => 'Итоги месяца временно недоступны';

  @override
  String get trendUnavailable => 'График временно недоступен';

  @override
  String get goalNotSelected => 'Главная цель пока не выбрана';

  @override
  String get goalUnavailable =>
      'Раздел целей временно недоступен. Мы уже обновляем данные.';

  @override
  String get paymentsUnavailable => 'Ближайшие платежи временно недоступны';

  @override
  String get transactionsUnavailable =>
      'Последние операции временно недоступны';

  @override
  String get emptyTitle =>
      'Добавьте первую операцию, чтобы увидеть финансовую картину';

  @override
  String get emptyDescription =>
      'Просто скажите, что купили или получили — остальное мы сделаем сами.';

  @override
  String get loadingLabel => 'Загрузка финансовых данных';

  @override
  String get homeTab => 'Главная';

  @override
  String get chatTab => 'Чат';

  @override
  String get analyticsTab => 'Аналитика';

  @override
  String get goalsTab => 'Цели';

  @override
  String get profileTab => 'Профиль';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get backLabel => 'Назад';

  @override
  String get appearanceSection => 'ОФОРМЛЕНИЕ';

  @override
  String get lightTheme => 'Светлая';

  @override
  String get darkTheme => 'Тёмная';

  @override
  String get accentColor => 'Акцентный цвет';

  @override
  String get tealAccent => 'Бирюзовый';

  @override
  String get blueAccent => 'Синий';

  @override
  String get purpleAccent => 'Фиолетовый';

  @override
  String get terracottaAccent => 'Терракотовый';

  @override
  String get generalSection => 'ОБЩИЕ';

  @override
  String get privacySetting => 'Скрывать суммы';

  @override
  String get languageSetting => 'Язык';

  @override
  String get russianLanguage => 'Русский';

  @override
  String get baseCurrencySetting => 'Основная валюта';

  @override
  String get settingsNote => 'Переключение языка пока недоступно.';

  @override
  String get baselineSettingsAction => 'Дата начала учёта';

  @override
  String get baselineSettingsDescription =>
      'Разрешить операции за более ранний период';

  @override
  String get baselineCorrectionTitle => 'Дата начала учёта';

  @override
  String get baselineCorrectionLoading => 'Загружаем настройки счёта';

  @override
  String get baselineCorrectionDescription =>
      'Перенесите дату назад, чтобы добавить более ранние операции. Начальный остаток и валюта не изменятся.';

  @override
  String get baselineCurrentDateLabel => 'Текущая дата начала учёта';

  @override
  String get baselineNewDateLabel => 'Новая дата';

  @override
  String get baselineChooseDateAction => 'Выбрать дату';

  @override
  String get baselineDateRangeHelp =>
      'Можно выбрать только дату раньше текущей даты начала учёта.';

  @override
  String get baselineReviewTitle => 'Проверьте новую дату';

  @override
  String get baselineReviewDescription =>
      'После подтверждения главный экран и месячные итоги будут пересчитаны из авторитетных данных.';

  @override
  String get baselineConfirmAction => 'Подтвердить новую дату';

  @override
  String get baselineSuccessTitle => 'Дата начала учёта изменена';

  @override
  String baselineSuccessDescription(String date) {
    return 'Теперь можно добавлять операции начиная с $date.';
  }

  @override
  String get baselineHomeDelayedDescription =>
      'Дата уже сохранена. Главный экран обновится позже; повторно подтверждать изменение не нужно.';

  @override
  String get baselineDoneAction => 'Готово';

  @override
  String get baselineUnavailableTitle => 'Дату пока нельзя изменить';

  @override
  String get baselineAccountRequired => 'Сначала настройте первый счёт.';

  @override
  String get baselineMinimumDateReached =>
      'Счёт уже начинается с самой ранней поддерживаемой даты.';

  @override
  String get baselineNotEarlierError =>
      'Выберите дату раньше текущей даты начала учёта.';

  @override
  String get baselineFutureError =>
      'Дата начала учёта не может быть позже сегодняшнего дня.';

  @override
  String get baselineAfterOperationError =>
      'Новая дата не может быть позже самой ранней сохранённой операции.';

  @override
  String get baselineLoadFailed => 'Не удалось загрузить настройки счёта.';

  @override
  String get baselineChangeFailed =>
      'Не удалось изменить дату. Финансовые данные не были изменены клиентом.';

  @override
  String get stubDescription =>
      'Раздел будет реализован на следующем этапе. Сейчас это навигационная заглушка.';

  @override
  String get voiceStubTitle => 'Голосовой ввод';

  @override
  String get voiceStubDescription =>
      'Экран записи подготовлен как заглушка. Микрофон и распознавание речи появятся в следующем vertical slice.';

  @override
  String get backHome => 'На главную';

  @override
  String get authLoadingLabel => 'Проверяем защищённую сессию';

  @override
  String get loginTitle => 'Вход';

  @override
  String get loginDescription =>
      'Войдите, чтобы открыть свою финансовую картину.';

  @override
  String get registerTitle => 'Создание аккаунта';

  @override
  String get registerDescription =>
      'Создайте защищённый аккаунт, чтобы начать вести финансы.';

  @override
  String get displayNameField => 'Ваше имя';

  @override
  String get displayNameRequired => 'Укажите имя';

  @override
  String get emailField => 'Электронная почта';

  @override
  String get emailInvalid => 'Введите корректный адрес электронной почты';

  @override
  String get passwordField => 'Пароль';

  @override
  String get confirmPasswordField => 'Повторите пароль';

  @override
  String get passwordRequirements => 'Не менее 12 символов';

  @override
  String get passwordInvalid => 'Пароль должен содержать от 12 до 128 символов';

  @override
  String get passwordsDoNotMatch => 'Пароли не совпадают';

  @override
  String get showPassword => 'Показать пароль';

  @override
  String get hidePassword => 'Скрыть пароль';

  @override
  String get loginAction => 'Войти';

  @override
  String get registerAction => 'Создать аккаунт';

  @override
  String get createAccountAction => 'Нет аккаунта? Создать';

  @override
  String get haveAccountAction => 'Уже есть аккаунт? Войти';

  @override
  String get authSessionExpiredNotice => 'Сессия завершена. Войдите снова.';

  @override
  String get signedOutNotice => 'Вы вышли из аккаунта.';

  @override
  String get invalidCredentialsError =>
      'Не удалось войти. Проверьте почту и пароль.';

  @override
  String get emailInUseError =>
      'Не удалось создать аккаунт. Возможно, эта почта уже используется.';

  @override
  String get authInvalidInputError =>
      'Проверьте введённые данные и попробуйте снова.';

  @override
  String get authThrottledError =>
      'Слишком много попыток. Подождите и попробуйте снова.';

  @override
  String get authOfflineError =>
      'Нет соединения с интернетом. Проверьте сеть и повторите попытку.';

  @override
  String get authTimeoutError => 'Сервер не ответил вовремя. Попробуйте снова.';

  @override
  String get authServiceError =>
      'Сервис входа временно недоступен. Попробуйте позже.';

  @override
  String get authUnexpectedError =>
      'Не удалось завершить вход. Попробуйте снова.';

  @override
  String get authSecureStorageError =>
      'Не удалось открыть защищённое хранилище устройства.';

  @override
  String get accountSection => 'АККАУНТ';

  @override
  String get signOutAction => 'Выйти из аккаунта';

  @override
  String get signOutDialogTitle => 'Выйти из аккаунта?';

  @override
  String get signOutDialogDescription =>
      'Для следующего входа потребуется снова ввести почту и пароль.';

  @override
  String get cancelAction => 'Отмена';

  @override
  String get financeEntryTitle => 'Финансовая операция';

  @override
  String get financeEntryLoading => 'Проверяем финансовый счёт';

  @override
  String get financeEntryLoadFailed => 'Не удалось открыть ввод операции';

  @override
  String get accountSetupTitle => 'Настройте первый счёт';

  @override
  String get accountSetupDescription =>
      'Укажите фактический остаток. Дата начала задаёт самый ранний день, за который можно добавить операцию. Перед сохранением вы проверите данные.';

  @override
  String get accountNameField => 'Название счёта';

  @override
  String get accountNameHint => 'Например, Основной счёт';

  @override
  String get accountNameRequired => 'Укажите название счёта';

  @override
  String get openingBalanceField => 'Начальный остаток';

  @override
  String get openingBalanceHelp =>
      'Это исходный остаток, а не доход или расход.';

  @override
  String get openingBalanceDateField => 'Дата начального остатка';

  @override
  String get canonicalTimezoneLabel => 'Часовой пояс учёта';

  @override
  String get continueToReviewAction => 'Проверить данные';

  @override
  String get accountReviewTitle => 'Проверьте настройки счёта';

  @override
  String get reviewBeforeConfirmDescription =>
      'Финансовые данные сохранятся только после явного подтверждения.';

  @override
  String get confirmFinanceAction => 'Подтвердить и сохранить';

  @override
  String get editAction => 'Изменить';

  @override
  String get accountCreatedNotice =>
      'Счёт подтверждён. Теперь добавьте первую операцию.';

  @override
  String get manualOperationTitle => 'Добавьте операцию вручную';

  @override
  String get manualOperationDescription =>
      'Заполните структурированные поля. Голос и автоматическое распознавание пока не используются.';

  @override
  String get accountLabel => 'Счёт';

  @override
  String get operationExpense => 'Расход';

  @override
  String get operationIncome => 'Доход';

  @override
  String get operationTypeLabel => 'Тип операции';

  @override
  String get operationAmountField => 'Сумма';

  @override
  String get merchantField => 'Место или получатель, необязательно';

  @override
  String get categoryField => 'Категория, необязательно';

  @override
  String get operationDateField => 'Дата операции';

  @override
  String get operationReviewTitle => 'Проверьте операцию';

  @override
  String get addAnotherOperationAction => 'Добавить ещё одну';

  @override
  String get moneyInputInvalid =>
      'Введите корректную сумму, например 1250,50 или -20';

  @override
  String get positiveMoneyInputInvalid =>
      'Введите сумму больше нуля, например 35 или 35,50';

  @override
  String get financeInvalidInput =>
      'Проверьте заполненные поля и попробуйте снова.';

  @override
  String get financeValidationRejected =>
      'Данные не прошли проверку. Проверьте поля перед повторной отправкой.';

  @override
  String get financeDateRejected =>
      'Дата не может быть позже сегодняшнего дня.';

  @override
  String get operationBeforeOpeningDateError =>
      'Дата операции не может быть раньше даты начального остатка.';

  @override
  String get financeAccountUnavailable =>
      'Счёт недоступен для этой операции. Обновите экран и попробуйте снова.';

  @override
  String get financeConflictError =>
      'Команда конфликтует с уже обработанной записью. Измените данные и создайте новое подтверждение.';

  @override
  String get financeOfflineError =>
      'Не удалось связаться с сервером. Проверьте подключение к API и повторите попытку.';

  @override
  String get financeTimeoutError =>
      'Сервер не ответил вовремя. Подтверждение можно безопасно повторить.';

  @override
  String get financeServiceError =>
      'Сервис финансовых операций временно недоступен. Попробуйте снова позже.';

  @override
  String get financeSecurityError =>
      'Не удалось подтвердить безопасное соединение. Проверьте настройки и повторите позже.';

  @override
  String get financeLocalStorageError =>
      'Не удалось надёжно сохранить подтверждение на устройстве. Запрос на сервер не отправлялся. Освободите место или разблокируйте защищённое хранилище и повторите.';

  @override
  String get financeUnexpectedError =>
      'Получен некорректный ответ. Финансовые данные не были изменены клиентом.';

  @override
  String get financeSessionChanged =>
      'Защищённая сессия обновилась. Повторите действие; подтверждение будет отправлено с теми же данными.';

  @override
  String get operationAcceptedTitle => 'Операция сохранена';

  @override
  String get operationAcceptedUpdatingHome =>
      'Операция принята. Ждём новую версию главного экрана.';

  @override
  String get operationAcceptedHomeUpdated =>
      'Главный экран обновлён по новой авторитетной версии.';

  @override
  String get operationAcceptedProjectionDelayed =>
      'Операция уже сохранена, но обновление главного экрана задерживается. Повторно подтверждать её не нужно.';

  @override
  String get operationAcceptedAuthRequired =>
      'Операция уже сохранена, но для обновления главного экрана потребуется снова войти.';

  @override
  String get operationAcceptedSessionChanged =>
      'Операция уже сохранена, но сессия изменилась во время обновления. Откройте главный экран ещё раз.';

  @override
  String get operationAcceptedRefreshFailed =>
      'Операция уже сохранена. Главный экран можно обновить позже.';

  @override
  String get operationQueuedTitle => 'Операция сохранена на устройстве';

  @override
  String get operationQueuedDescription =>
      'Подтверждение защищённо сохранено. Если сервер ещё не принял его, оно не влияет на баланс. Актуальный статус показан на главном экране.';

  @override
  String get operationQueuedAuthDescription =>
      'Подтверждение защищённо сохранено. Для продолжения отправки может понадобиться повторный вход. Актуальный статус показан на главном экране.';

  @override
  String get operationAlreadySyncedTitle => 'Операция уже синхронизирована';

  @override
  String get operationAlreadySyncedDescription =>
      'Сервер подтвердил эту же операцию ранее. Повторная запись не создана.';

  @override
  String get operationAttentionTitle => 'Операция требует проверки';

  @override
  String get operationAttentionConflict =>
      'Сохранённое подтверждение конфликтует с уже обработанной командой и не будет отправляться автоматически.';

  @override
  String get operationAttentionRejected =>
      'Finance Core отклонил подтверждение. Баланс не изменён.';

  @override
  String get operationAttentionSecurity =>
      'Отправка остановлена из-за проверки безопасности. Баланс не изменён.';

  @override
  String get operationAttentionInvalid =>
      'Подтверждение нельзя безопасно отправить автоматически. Баланс не изменён.';

  @override
  String get operationSyncingBannerTitle => 'Отправляем сохранённую операцию';

  @override
  String get operationSyncingBannerDescription =>
      'До подтверждения сервера она не влияет на баланс.';

  @override
  String get operationHomeUpdatingBannerTitle => 'Главный экран обновляется';

  @override
  String get operationHomeUpdatingBannerDescription =>
      'Операция уже сохранена сервером. Баланс обновится после готовности данных; повторно подтверждать её не нужно.';

  @override
  String get operationHomeUpdatingAction => 'Обновить сейчас';

  @override
  String get operationPendingBannerTitle => 'Операция ждёт синхронизации';

  @override
  String get operationPendingBannerDescription =>
      'Она защищённо сохранена на устройстве и пока не влияет на баланс.';

  @override
  String get operationAuthBannerTitle => 'Нужен повторный вход';

  @override
  String get operationAuthBannerDescription =>
      'Сохранённая операция останется на устройстве до безопасной авторизации.';

  @override
  String get operationAttentionBannerTitle => 'Проверьте сохранённую операцию';

  @override
  String get operationAttentionBannerDescription =>
      'Автоматическая отправка остановлена. Баланс не изменён.';

  @override
  String get operationLockedBannerDescription =>
      'Отправка финансовых операций заблокирована после проверки безопасности. Новые подтверждения не будут отправляться автоматически.';

  @override
  String get operationRetryNowAction => 'Повторить отправку';

  @override
  String operationBeforeOpeningDateDetail(String openingDate) {
    return 'Учёт по счёту начинается $openingDate. Операции раньше этой даты записать нельзя. Дату начала можно перенести назад в настройках счёта.';
  }

  @override
  String get plannedCostSettingsAction => 'Запланировать трату';

  @override
  String get plannedCostSettingsDescription => 'Например аренда или подписка';

  @override
  String get plannedCostTitle => 'Планируемая трата';

  @override
  String get plannedCostLoading => 'Загружаем счёт';

  @override
  String get plannedCostDescription =>
      'Планируемая трата не меняет баланс. Она появится в списке предстоящих платежей, пока вы её не подтвердите.';

  @override
  String get plannedCostAccountRequired =>
      'Сначала нужно создать счёт: планируемая трата привязывается к нему.';

  @override
  String get plannedCostTitleLabel => 'Название';

  @override
  String get plannedCostTitleHint => 'Аренда';

  @override
  String get plannedCostAmountLabel => 'Сумма';

  @override
  String get plannedCostDateLabel => 'Дата платежа';

  @override
  String get plannedCostChooseDateAction => 'Выбрать дату';

  @override
  String get plannedCostSubmitAction => 'Запланировать';

  @override
  String get plannedCostRetryAction => 'Повторить';

  @override
  String get plannedCostAcceptedTitle => 'Трата запланирована';

  @override
  String get plannedCostAcceptedDescription =>
      'Она не влияет на баланс и ждёт подтверждения.';

  @override
  String get plannedCostHomePending => 'Обновляем главный экран';

  @override
  String get plannedCostHomeUpdated => 'Главный экран обновлён';

  @override
  String get plannedCostHomeDelayed => 'Главный экран обновится чуть позже';

  @override
  String get plannedCostHomeFailed => 'Не удалось обновить главный экран';

  @override
  String get plannedCostInvalidInput => 'Проверьте название, сумму и дату.';

  @override
  String get plannedCostIssueAccountUnavailable => 'Счёт недоступен.';

  @override
  String get plannedCostIssueCurrencyMismatch =>
      'Валюта не совпадает с валютой счёта.';

  @override
  String get plannedCostIssueUnsupportedCurrency =>
      'Эта валюта пока не поддерживается.';

  @override
  String get plannedCostIssueBeforeBaseline =>
      'Дата раньше начала учёта по счёту. Выберите более позднюю дату.';

  @override
  String get plannedCostGenericFailure => 'Не удалось запланировать трату.';

  @override
  String get plannedCostDoneAction => 'Готово';

  @override
  String get plannedCostListTitle => 'Запланировано';

  @override
  String get plannedCostListEmpty => 'Пока ничего не запланировано.';

  @override
  String get plannedCostCancelAction => 'Отменить';

  @override
  String get plannedCostCancelSemantics => 'Отменить план';

  @override
  String get plannedCostDueLabel => 'Срок';

  @override
  String get plannedCostOverdueLabel => 'Просрочено';

  @override
  String get plannedCostCancelFailure => 'Не удалось отменить план.';

  @override
  String get plannedCostConfirmAction => 'Оплачено';

  @override
  String get plannedCostConfirmSemantics => 'Отметить план оплаченным';

  @override
  String get plannedCostConfirmFailure =>
      'Не удалось записать операцию. План остался в списке — попробуйте ещё раз.';

  @override
  String get plannedCostConfirmHint =>
      '«Оплачено» создаст обычную операцию расхода и уберёт план из списка.';

  @override
  String get savingsGoalTitle => 'Цели';

  @override
  String get savingsGoalLoading => 'Загружаем цели';

  @override
  String get savingsGoalAccountRequired =>
      'Сначала создайте счёт — цель копится в его валюте.';

  @override
  String get savingsGoalGenericFailure =>
      'Не удалось выполнить действие. Попробуйте ещё раз.';

  @override
  String get savingsGoalInvalidInput => 'Проверьте название, сумму и дату.';

  @override
  String get savingsGoalRetryAction => 'Повторить';

  @override
  String get savingsGoalDescription =>
      'Цель показывает, сколько вы уже отложили. Отложенные деньги остаются на счёте: баланс, доходы и расходы не меняются.';

  @override
  String get savingsGoalEmpty => 'Пока нет ни одной цели.';

  @override
  String get savingsGoalCreateAction => 'Новая цель';

  @override
  String get savingsGoalCancelCreateAction => 'Отмена';

  @override
  String get savingsGoalTitleLabel => 'Название';

  @override
  String get savingsGoalTitleHint => 'Отпуск';

  @override
  String get savingsGoalTargetLabel => 'Сколько нужно';

  @override
  String get savingsGoalMonthlyLabel => 'Планирую откладывать в месяц';

  @override
  String get savingsGoalMonthlyHelper =>
      'Необязательно. Это ориентир, а не обязательство.';

  @override
  String get savingsGoalDateLabel => 'К какой дате';

  @override
  String get savingsGoalChooseDateAction => 'Выбрать дату';

  @override
  String get savingsGoalSubmitAction => 'Создать цель';

  @override
  String get savingsGoalContributionLabel => 'Сумма';

  @override
  String get savingsGoalDepositAction => 'Отложить';

  @override
  String get savingsGoalWithdrawAction => 'Забрать';

  @override
  String get savingsGoalCancelAction => 'Отказаться от цели';

  @override
  String get savingsGoalCancelSemantics =>
      'Отказаться от цели и убрать её из списка';

  @override
  String get savingsGoalDepositSemantics =>
      'Отложить указанную сумму на эту цель';

  @override
  String get savingsGoalWithdrawSemantics =>
      'Забрать указанную сумму с этой цели';

  @override
  String get savingsGoalAchievedLabel => 'Цель достигнута';

  @override
  String get savingsGoalIssueAccountUnavailable =>
      'Счёт недоступен. Обновите экран.';

  @override
  String get savingsGoalIssueCurrencyMismatch =>
      'Валюта цели должна совпадать с валютой счёта.';

  @override
  String get savingsGoalIssueUnsupportedCurrency =>
      'Пока поддерживается только EUR.';

  @override
  String get savingsGoalIssueBeforeBaseline =>
      'Дата раньше даты открытия счёта.';

  @override
  String get savingsGoalIssueFutureContribution =>
      'Отложить можно только за сегодня или раньше.';

  @override
  String get savingsGoalIssueNotActive => 'Цель уже закрыта. Обновите экран.';

  @override
  String get savingsGoalIssueWithdrawalTooLarge =>
      'На цели меньше денег, чем вы пытаетесь забрать.';

  @override
  String get categoryPickerNone => 'Без категории';

  @override
  String get categoryPickerOther => 'Другое (ввести текстом)';

  @override
  String get categoryPickerOtherLabel => 'Своя категория';

  @override
  String get categoryPickerLoading => 'Загружаем категории';

  @override
  String get categoryPickerUnavailable =>
      'Список категорий недоступен — впишите название вручную.';

  @override
  String get categorySeedGroceries => 'Продукты';

  @override
  String get categorySeedEatingOut => 'Кафе и рестораны';

  @override
  String get categorySeedTransport => 'Транспорт';

  @override
  String get categorySeedHousing => 'Жильё';

  @override
  String get categorySeedUtilities => 'Связь и интернет';

  @override
  String get categorySeedHealth => 'Здоровье';

  @override
  String get categorySeedClothing => 'Одежда';

  @override
  String get categorySeedEntertainment => 'Развлечения';

  @override
  String get categorySeedEducation => 'Образование';

  @override
  String get categorySeedGiftsOut => 'Подарки';

  @override
  String get categorySeedOtherExpense => 'Прочее';

  @override
  String get categorySeedSalary => 'Зарплата';

  @override
  String get categorySeedFreelance => 'Подработка';

  @override
  String get categorySeedGiftsIn => 'Подарки';

  @override
  String get categorySeedInterest => 'Проценты';

  @override
  String get categorySeedOtherIncome => 'Прочее';

  @override
  String get categoriesSettingsAction => 'Категории';

  @override
  String get categoriesSettingsDescription =>
      'Свои названия для трат и доходов';

  @override
  String get categoriesTitle => 'Категории';

  @override
  String get categoriesExpenseTab => 'Расходы';

  @override
  String get categoriesIncomeTab => 'Доходы';

  @override
  String get categoryAddAction => 'Добавить категорию';

  @override
  String get categoryNameLabel => 'Название';

  @override
  String get categoryCreateAction => 'Создать';

  @override
  String get categorySaveAction => 'Сохранить';

  @override
  String get categoryRenameAction => 'Переименовать';

  @override
  String get categoryHideAction => 'Скрыть';

  @override
  String get categoryRestoreAction => 'Вернуть';

  @override
  String categoryHiddenSection(int count) {
    return 'Скрытые: $count';
  }

  @override
  String get categoryHiddenNote =>
      'Скрытая категория не предлагается при новой записи, но остаётся на прошлых операциях.';

  @override
  String get categoryListEmpty => 'Пока ни одной категории';

  @override
  String get categoryHideDialogTitle => 'Скрыть категорию?';

  @override
  String get categoryHideDialogDescription =>
      'Она исчезнет из списка при новой записи. Прошлые операции останутся в ней, и её можно вернуть.';

  @override
  String get categoryNameTakenError => 'Такое название уже есть';

  @override
  String get categoryArchivedError => 'Категория скрыта — сначала верните её';

  @override
  String get categoryNotFoundError => 'Категория не найдена';

  @override
  String get categoryNameInvalidError => 'Введите название до 100 символов';

  @override
  String get categoryLoadError => 'Не удалось загрузить категории';

  @override
  String get operationCorrectAction => 'Изменить';

  @override
  String get operationRemoveAction => 'Удалить';

  @override
  String get operationCorrectTitle => 'Исправить операцию';

  @override
  String get operationCorrectSave => 'Сохранить';

  @override
  String get operationCorrectedMessage => 'Операция исправлена';

  @override
  String get operationRemovedMessage => 'Операция удалена';

  @override
  String get operationRemoveDialogTitle => 'Удалить операцию?';

  @override
  String get operationRemoveDialogBody =>
      'Она перестанет учитываться в балансе и отчётах. Сама запись сохранится в истории изменений.';

  @override
  String get operationCorrectionFailed =>
      'Не удалось сохранить изменение. Попробуйте ещё раз.';

  @override
  String get operationAlreadyReversedMessage =>
      'Эту операцию уже исправили. Обновите список.';

  @override
  String get operationNotFoundMessage => 'Такой операции больше нет.';

  @override
  String get operationHistoryTitle => 'Все операции';

  @override
  String get operationHistorySettingsAction => 'Все операции';

  @override
  String get operationHistorySettingsDescription =>
      'История записей и что было вписано';

  @override
  String get operationHistoryEmpty => 'Пока ни одной записи';

  @override
  String get operationHistoryMore => 'Показать ещё';

  @override
  String get operationHistoryLoadError => 'Не удалось загрузить операции';

  @override
  String get operationHistoryLoadMoreError =>
      'Не удалось загрузить продолжение';

  @override
  String operationHistoryDate(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get operationDetailDate => 'Дата';

  @override
  String get operationDetailCategory => 'Категория';

  @override
  String get operationDetailMerchant => 'Где';

  @override
  String get operationDetailOriginalText => 'Было вписано';

  @override
  String get operationDetailOriginalTextHint => 'Категорию позже переименовали';

  @override
  String get analyticsExpenseByCategory => 'Расходы по категориям';

  @override
  String get analyticsIncomeByCategory => 'Доходы по категориям';

  @override
  String get analyticsBreakdownEmpty => 'За этот месяц записей нет';

  @override
  String get analyticsLoadError => 'Не удалось посчитать аналитику';

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
  String get profileLoadError => 'Не удалось загрузить профиль';

  @override
  String get profileEmailLabel => 'Почта для входа';

  @override
  String get profileAccountSection => 'СЧЁТ';

  @override
  String get profileTimezoneSetting => 'Часовой пояс';

  @override
  String get profileNoAccount => 'Счёт появится после первой записи';

  @override
  String profileOpeningDateValue(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Сейчас $dateString';
  }

  @override
  String profileVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get entrySentenceField => 'Опишите операцию одной фразой';

  @override
  String get entrySentenceHint => 'Потратил 12,50 на продукты вчера';

  @override
  String get entrySentenceParseAction => 'Разобрать';

  @override
  String get entrySentenceFilled =>
      'Заполнил поля ниже — проверьте и подтвердите.';

  @override
  String get entrySentenceParseError => 'Не удалось разобрать фразу.';

  @override
  String get entrySentenceEmpty =>
      'Напишите фразу покороче или начните с суммы.';

  @override
  String get entrySentenceGapAmount => 'Сумму не нашёл — впишите её.';

  @override
  String get entrySentenceGapAmbiguous =>
      'В фразе несколько чисел — уточните сумму.';

  @override
  String get entrySentenceGapDate => 'Дату не понял — проверьте её.';

  @override
  String get entrySentenceGapCategory => 'Категорию не подобрал — выберите её.';

  @override
  String get entrySentenceGapTransfer =>
      'Это перевод между кошельками, а не доход или трата — поэтому ничего не заполнил.';

  @override
  String get entrySentenceOpenTransfer => 'Открыть перевод';

  @override
  String get categoryKeywordsTitle => 'Слова категории';

  @override
  String get categoryKeywordsAction => 'Слова';

  @override
  String get categoryKeywordsDescription =>
      'Если слово из фразы начинается с одного из этих, операция попадёт в эту категорию. «авто» поймает и «автохимию», «продукт» — и «продуктов».';

  @override
  String get categoryKeywordsEmpty =>
      'Слов пока нет — категория подберётся только по названию.';

  @override
  String get categoryKeywordsField => 'Добавить слово';

  @override
  String get categoryKeywordsAdd => 'Добавить';

  @override
  String categoryKeywordsRemove(String keyword) {
    return 'Убрать слово $keyword';
  }

  @override
  String get categoryKeywordsInvalid =>
      'Слово — от трёх букв или цифр, без пробелов.';

  @override
  String get categoryKeywordsTaken =>
      'Это слово уже ведёт в другую категорию. Уберите его там.';

  @override
  String get categoryKeywordsArchived =>
      'Скрытая категория не участвует в подборе.';

  @override
  String get categoryKeywordsLoadError => 'Не удалось загрузить слова';

  @override
  String get categoryKeywordsSaveError => 'Не удалось сохранить слово';

  @override
  String get analyticsPeriod7Days => '7 дней';

  @override
  String get analyticsPeriodMonth => 'Месяц';

  @override
  String get analyticsPeriodQuarter => 'Квартал';

  @override
  String get analyticsPeriodYear => 'Год';

  @override
  String get analyticsPeriodCustom => 'Свой период';

  @override
  String get analyticsPeriodLabel => 'Период';

  @override
  String get analyticsBalanceTitle => 'Баланс';

  @override
  String analyticsBalanceFromTo(String opening, String closing) {
    return '$opening → $closing';
  }

  @override
  String analyticsBalanceChange(String change) {
    return 'за период $change';
  }

  @override
  String get analyticsNoSpending => 'За этот период трат не было';

  @override
  String analyticsPreviousAmount(String amount) {
    return 'было $amount';
  }

  @override
  String analyticsWindowRange(String from, String to) {
    return '$from — $to';
  }

  @override
  String analyticsComparedWith(String from, String to) {
    return 'в сравнении с $from — $to';
  }

  @override
  String get plannedCostIssueCategoryUnavailable =>
      'Эта категория недоступна. Выберите другую.';

  @override
  String get plannedCostRepeatToggle => 'Повторять каждый месяц';

  @override
  String get plannedCostRepeatDayLabel => 'День месяца';

  @override
  String get plannedCostRepeatLastDay => 'Последний день месяца';

  @override
  String get plannedCostRepeatShortMonthHint =>
      'В коротких месяцах платёж сдвинется на последний день: 31 января, 28 февраля, 31 марта.';

  @override
  String get plannedCostRepeatFirstDatesTitle => 'Ближайшие даты';

  @override
  String get plannedCostRecurrenceListTitle => 'Повторяется';

  @override
  String get plannedCostRecurrenceListEmpty => 'Повторяющихся трат пока нет.';

  @override
  String plannedCostRecurrenceMonthlyOnDay(int day) {
    return 'Каждый месяц, $day числа';
  }

  @override
  String get plannedCostRecurrenceMonthlyLastDay =>
      'Каждый месяц, последний день';

  @override
  String get plannedCostRecurrenceEndAction => 'Закончить';

  @override
  String get plannedCostRecurrenceEndDialogTitle => 'Закончить серию?';

  @override
  String get plannedCostRecurrenceEndDialogBody =>
      'Новые платежи создаваться не будут. Будущие запланированные платежи из этой серии отменятся, а уже наступившие останутся — их нужно подтвердить или пропустить.';

  @override
  String plannedCostRecurrenceEndedMessage(int count) {
    return 'Серия закончена. Отменено будущих платежей: $count';
  }

  @override
  String get plannedCostSkipAction => 'Пропустить';

  @override
  String get plannedCostSkipHint =>
      '«Пропустить» убирает один платёж, серия продолжится.';

  @override
  String get plannedCostRecurrenceAcceptedTitle =>
      'Повторяющаяся трата записана';

  @override
  String get plannedCostRecurrenceAcceptedDescription =>
      'Платежи будут появляться сами. Это прогноз: баланс он не меняет.';

  @override
  String get plannedCostRecurrenceFailure =>
      'Не удалось изменить повторяющуюся трату.';

  @override
  String get appUpdateCheckAction => 'Проверить обновления';

  @override
  String get appUpdateCheckDescription =>
      'Спросить сервер, вышла ли новая версия';

  @override
  String get appUpdateChecking => 'Проверяем…';

  @override
  String get appUpdateUpToDate => 'У вас последняя версия.';

  @override
  String appUpdateAvailable(String version, String size) {
    return 'Доступна версия $version, $size';
  }

  @override
  String get appUpdateNotesLabel => 'Что нового';

  @override
  String get appUpdateDownloadAction => 'Скачать и установить';

  @override
  String appUpdateDownloading(int percent) {
    return 'Скачиваем… $percent%';
  }

  @override
  String get accountExportAction => 'Выгрузить мои данные';

  @override
  String get accountExportDescription =>
      'Полный файл со всеми данными и таблица операций для Excel';

  @override
  String get accountExportPreparing => 'Готовлю файлы…';

  @override
  String get accountExportFailedUnreachable =>
      'Не удалось связаться с сервером. Проверьте интернет и попробуйте ещё раз.';

  @override
  String get accountExportFailedUnavailable =>
      'Сервер не смог подготовить выгрузку. Попробуйте позже.';

  @override
  String get accountExportFailedAuthentication =>
      'Сессия закончилась — войдите снова.';

  @override
  String get accountExportFailedShare =>
      'Файлы готовы, но окно «Поделиться» не открылось.';

  @override
  String get accountExportFailedStorage =>
      'Не удалось записать файлы на телефон.';

  @override
  String get accountDeletionAction => 'Удалить аккаунт';

  @override
  String get accountDeletionActionDescription =>
      'Через 7 дней. Передумали — просто войдите снова';

  @override
  String get accountDeletionTitle => 'Удаление аккаунта';

  @override
  String get accountDeletionHeadline => 'Аккаунт удалится через 7 дней';

  @override
  String get accountDeletionWhat =>
      'Удалится всё: кошельки, операции, переводы, категории, планы, бюджеты и цели. Вернуть их потом будет нельзя.';

  @override
  String get accountDeletionSignedOut =>
      'Вы сразу выйдете на всех устройствах. Если передумаете — войдите в течение 7 дней, и удаление отменится.';

  @override
  String get accountDeletionBackups =>
      'В резервных копиях сервера данные хранятся ещё до 14 дней, потом исчезают и оттуда.';

  @override
  String get accountDeletionExportFirst => 'Сначала выгрузить мои данные';

  @override
  String accountDeletionUnsent(int count) {
    return 'Операций на этом телефоне, ещё не дошедших до сервера: $count. Их нет в выгрузке, и они пропадут вместе с аккаунтом. Лучше дождаться отправки.';
  }

  @override
  String get accountDeletionPasswordLabel => 'Пароль';

  @override
  String get accountDeletionPasswordHelp =>
      'Тот же, которым вы входите. Нужен, чтобы удалить аккаунт мог только его владелец.';

  @override
  String get accountDeletionPasswordRejected => 'Неверный пароль';

  @override
  String get accountDeletionSubmit => 'Удалить аккаунт';

  @override
  String get accountDeletionConfirmTitle => 'Удалить аккаунт?';

  @override
  String get accountDeletionConfirmBody =>
      'Вы выйдете на всех устройствах. Через 7 дней все данные будут удалены, если вы не войдёте раньше.';

  @override
  String get accountDeletionConfirmCancel => 'Отмена';

  @override
  String get accountDeletionConfirmAccept => 'Удалить';

  @override
  String get accountDeletionUnreachable =>
      'Не удалось связаться с сервером. Ничего не удалено — проверьте интернет и попробуйте ещё раз.';

  @override
  String get accountDeletionUnavailable =>
      'Сервер не смог принять запрос. Ничего не удалено — попробуйте позже.';

  @override
  String get accountDeletionAuthentication =>
      'Сессия закончилась — войдите снова. Ничего не удалено.';

  @override
  String accountDeletionScheduledNotice(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Аккаунт будет удалён $dateString. Чтобы отменить удаление, просто войдите до этого дня.';
  }

  @override
  String get accountDeletionScheduledNoticeUndated =>
      'Аккаунт будет удалён через 7 дней. Чтобы отменить удаление, просто войдите до этого срока.';

  @override
  String get accountDeletionCancelled =>
      'Удаление аккаунта отменено — вы вошли, и все данные на месте.';

  @override
  String get appUpdateHandedToInstaller =>
      'Файл скачан и проверен. Подтвердите установку в системном окне — Android ставит обновление сам, и это занимает до минуты. Скачивать заново не нужно: файл сейчас нужен установщику.';

  @override
  String get appUpdateOpenInstallerAction => 'Открыть окно установки снова';

  @override
  String get appUpdateNeedsPermission =>
      'Android просит разрешить установку из этого приложения. Это делается один раз.';

  @override
  String get appUpdatePermissionAction => 'Открыть настройки';

  @override
  String get appUpdateFailedUnreachable =>
      'Сервер недоступен. Попробуйте позже.';

  @override
  String get appUpdateFailedServer => 'Сервер не смог ответить про обновления.';

  @override
  String get appUpdateFailedCorrupted =>
      'Файл скачался повреждённым и удалён. Попробуйте ещё раз.';

  @override
  String get appUpdateFailedInstaller =>
      'Не удалось открыть установщик Android.';

  @override
  String get appUpdateFailedAuth => 'Нужно войти заново.';

  @override
  String get appUpdateRetryAction => 'Повторить';

  @override
  String appUpdateMegabytes(String megabytes) {
    return '$megabytes МБ';
  }

  @override
  String get notificationsQuietLabel => 'Уведомления';

  @override
  String get notificationsEmpty => 'Ничего, что требует внимания.';

  @override
  String get notificationsEmptyHint =>
      'Здесь появятся напоминания о платежах и новые версии приложения.';

  @override
  String notificationUpdateTitle(String version) {
    return 'Доступна версия $version';
  }

  @override
  String get notificationUpdateBody => 'Обновить можно в профиле.';

  @override
  String get notificationUpdateAction => 'Открыть профиль';

  @override
  String notificationPaymentOverdueTitle(String title) {
    return 'Просрочен платёж: $title';
  }

  @override
  String notificationPaymentDueSoonTitle(String title) {
    return 'Скоро платёж: $title';
  }

  @override
  String notificationPaymentBody(String date, String amount) {
    return '$date, $amount';
  }

  @override
  String get notificationPaymentAction => 'Открыть запланированные';

  @override
  String get budgetsTitle => 'Бюджеты';

  @override
  String get budgetsSettingsAction => 'Бюджеты';

  @override
  String get budgetsSettingsDescription => 'Месячные лимиты и сколько осталось';

  @override
  String budgetsPeriod(String from, String to) {
    return '$from — $to';
  }

  @override
  String get budgetsOverallTitle => 'Все траты';

  @override
  String get budgetsEmpty => 'Лимитов пока нет.';

  @override
  String get budgetsEmptyHint =>
      'Поставьте месячный лимит на категорию или сразу на все траты.';

  @override
  String budgetsSpentOfLimit(String spent, String limit) {
    return 'Потрачено $spent из $limit';
  }

  @override
  String budgetsRemaining(String amount) {
    return 'Осталось $amount';
  }

  @override
  String budgetsOverspentBy(String amount) {
    return 'Перерасход $amount';
  }

  @override
  String budgetsPlanned(String amount) {
    return 'Ещё запланировано $amount';
  }

  @override
  String get budgetsAddAction => 'Поставить лимит';

  @override
  String get budgetsRemoveAction => 'Снять';

  @override
  String get budgetsRemoveDialogTitle => 'Снять лимит?';

  @override
  String get budgetsRemoveDialogBody =>
      'Трата останется, перестанет считаться только лимит. Поставить новый можно в любой момент.';

  @override
  String get budgetsCategoryLabel => 'На что';

  @override
  String get budgetsLimitLabel => 'Лимит в месяц';

  @override
  String get budgetsSaveAction => 'Сохранить';

  @override
  String get budgetsLoadError => 'Не удалось загрузить бюджеты.';

  @override
  String get budgetsWriteError => 'Не удалось сохранить лимит.';

  @override
  String get budgetsNoCategoriesLeft => 'Для всех категорий лимиты уже стоят.';

  @override
  String get budgetsAccountRequired => 'Сначала создайте счёт.';

  @override
  String get timezoneTitle => 'Часовой пояс учёта';

  @override
  String timezoneCurrent(String zone) {
    return 'Сейчас $zone';
  }

  @override
  String get timezoneExplanation =>
      'Здесь решается, где проходит граница дня и месяца. Уже записанные операции остаются на своих датах — меняется только то, что считается «сегодня» и «этот месяц».';

  @override
  String get timezoneSearchField => 'Поиск города или зоны';

  @override
  String get timezoneDeviceSection => 'ПОЯС ТЕЛЕФОНА';

  @override
  String get timezoneAllSection => 'ВСЕ ПОЯСА';

  @override
  String get timezoneNothingFound => 'Ничего не найдено';

  @override
  String timezoneConfirmTitle(String zone) {
    return 'Перенести учёт в $zone?';
  }

  @override
  String get timezoneConfirmBody =>
      'Суммы и даты уже записанных операций не изменятся. По-новому будут считаться только «сегодня» и границы месяца.';

  @override
  String get timezoneConfirmAction => 'Перенести';

  @override
  String timezoneCorrected(String zone) {
    return 'Учёт ведётся в $zone';
  }

  @override
  String get timezoneUnchangedError => 'Учёт уже ведётся в этом поясе.';

  @override
  String get timezoneBehindOperationsError =>
      'В этом поясе последняя запись оказалась бы в будущем, и её сумма пропала бы из баланса до завтра. Выберите пояс восточнее или попробуйте позже.';

  @override
  String get timezoneWriteError => 'Не удалось изменить часовой пояс.';

  @override
  String get timezoneLoadError => 'Не удалось загрузить счёт.';

  @override
  String get timezoneAccountRequired => 'Сначала создайте счёт.';

  @override
  String get timezoneSettingsDescription => 'Где проходит граница дня и месяца';

  @override
  String get entrySentenceGapCurrency =>
      'Валюту не разобрал — впишите сумму сами.';

  @override
  String entrySentenceCurrencyMismatch(String parsed, String account) {
    return 'Сумма в $parsed, а счёт в $account — не подставил её.';
  }

  @override
  String get otherWalletsTitle => 'ДРУГИЕ КОШЕЛЬКИ';

  @override
  String get transferTitle => 'Перевод между счетами';

  @override
  String get transferSettingsAction => 'Перевод между счетами';

  @override
  String get transferSettingsDescription =>
      'Переложить деньги из одного кошелька в другой';

  @override
  String get transferFromField => 'Откуда';

  @override
  String get transferToField => 'Куда';

  @override
  String get transferFromAmountField => 'Сколько ушло';

  @override
  String get transferToAmountField => 'Сколько пришло';

  @override
  String get transferDateField => 'Когда';

  @override
  String transferRateLabel(String from, String rate, String to) {
    return 'Курс: 1 $from = $rate $to';
  }

  @override
  String get transferRateHint =>
      'Курс не берётся из интернета — он следует из двух сумм, которые вы ввели.';

  @override
  String get transferReviewAction => 'Продолжить';

  @override
  String get transferConfirmAction => 'Перевести';

  @override
  String get transferEditAction => 'Изменить';

  @override
  String get transferAcceptedTitle => 'Перевод записан';

  @override
  String transferAcceptedBody(String fromAmount, String toAmount) {
    return '$fromAmount → $toAmount';
  }

  @override
  String get transferSecondWalletRequired =>
      'Для перевода нужен второй кошелёк в другой валюте.';

  @override
  String get transferLoadError => 'Не удалось загрузить счета.';

  @override
  String get transferWriteError => 'Не удалось выполнить перевод.';

  @override
  String get transferSameWalletError => 'Выберите два разных кошелька.';

  @override
  String get transferIssueWalletUnavailable => 'Кошелёк недоступен.';

  @override
  String get transferIssueCurrencyMismatch =>
      'Валюта суммы не совпадает с валютой кошелька.';

  @override
  String get transferIssueBeforeBaseline =>
      'Деньги не могли уйти раньше, чем кошелёк появился.';

  @override
  String get transferIssueFutureDate => 'Дата перевода в будущем.';

  @override
  String get transferIssueConfirmationBeforeCapture =>
      'Подтверждение раньше самой записи.';

  @override
  String get walletTitle => 'Новый кошелёк';

  @override
  String get walletSettingsAction => 'Открыть кошелёк';

  @override
  String get walletSettingsDescription =>
      'Счёт в другой валюте — деньги не конвертируются';

  @override
  String get walletNameField => 'Название';

  @override
  String get walletCurrencyField => 'Валюта';

  @override
  String get walletOpeningBalanceField => 'Сколько сейчас на нём';

  @override
  String get walletOpeningDateField => 'С какого числа';

  @override
  String get walletCurrencySearch => 'Поиск валюты';

  @override
  String get walletCurrencyHeld => 'Уже есть';

  @override
  String get walletExplanation =>
      'Деньги между кошельками не конвертируются. Каждый живёт в своей валюте, а перевод записывается двумя суммами.';

  @override
  String get walletReviewAction => 'Продолжить';

  @override
  String get walletConfirmAction => 'Открыть';

  @override
  String get walletOpenedTitle => 'Кошелёк открыт';

  @override
  String get walletAccountRequired => 'Сначала создайте основной счёт.';

  @override
  String get walletLoadError => 'Не удалось загрузить счета.';

  @override
  String get walletWriteError => 'Не удалось открыть кошелёк.';

  @override
  String get operationWalletField => 'Кошелёк';
}
