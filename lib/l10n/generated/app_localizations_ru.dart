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
  String get totalBalance => 'Общий баланс';

  @override
  String get hideAmounts => 'Скрыть суммы';

  @override
  String get showAmounts => 'Показать суммы';

  @override
  String get monthDelta => 'за месяц';

  @override
  String get activeAccounts => 'Все активные счета';

  @override
  String get addByVoice => 'Добавить голосом';

  @override
  String get voiceEntryLabel => 'Добавить операцию голосом';

  @override
  String get monthSummaryTitle => 'Итоги июля';

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
  String get settingsNote => 'Настройки языка и валюты пока демонстрационные.';

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
}
