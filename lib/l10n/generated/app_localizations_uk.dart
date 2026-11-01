// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'Мої фінанси';

  @override
  String get greetingMorningNeutral => 'Доброго ранку';

  @override
  String get greetingDayNeutral => 'Добрий день';

  @override
  String get greetingEveningNeutral => 'Добрий вечір';

  @override
  String get greetingNightNeutral => 'Доброї ночі';

  @override
  String greetingMorning(String userName) {
    return 'Доброго ранку, $userName';
  }

  @override
  String greetingDay(String userName) {
    return 'Добрий день, $userName';
  }

  @override
  String greetingEvening(String userName) {
    return 'Добрий вечір, $userName';
  }

  @override
  String greetingNight(String userName) {
    return 'Доброї ночі, $userName';
  }

  @override
  String get notificationsLabel => 'Сповіщення, є нові';

  @override
  String get notificationsTitle => 'Сповіщення';

  @override
  String get notificationsStubDescription =>
      'Центр сповіщень буде підключено на наступному етапі.';

  @override
  String get openSettingsLabel => 'Відкрити налаштування';

  @override
  String get balanceTitle => 'Баланс';

  @override
  String get hideAmounts => 'Приховати суми';

  @override
  String get showAmounts => 'Показати суми';

  @override
  String get monthDelta => 'за місяць';

  @override
  String get balanceDeltaUnavailable => 'Динаміка за місяць недоступна';

  @override
  String get addBySentence => 'Записати фразою';

  @override
  String get sentenceEntryLabel => 'Записати операцію однією фразою';

  @override
  String get addByVoice => 'Додати голосом';

  @override
  String get voiceEntryLabel => 'Додати операцію голосом';

  @override
  String get typeBySentence => 'Написати фразою';

  @override
  String get voicePrompt => 'Скажіть, наприклад: «витратив 12,50 на продукти»';

  @override
  String get voiceNothingHeard => 'Нічого не розчув. Спробуйте ще раз.';

  @override
  String get voiceNeedsNetwork =>
      'Розпізнаванню мовлення потрібен інтернет або завантажена українська мова в налаштуваннях голосового введення.';

  @override
  String get voiceUnavailable =>
      'На цьому телефоні немає розпізнавання мовлення. Можна написати фразою.';

  @override
  String get voiceFailed => 'Не вдалося розпізнати мовлення. Спробуйте ще раз.';

  @override
  String get voiceTypeInsteadAction => 'Написати';

  @override
  String get setupAccountAction => 'Налаштувати рахунок';

  @override
  String monthSummaryTitle(String month) {
    return 'Підсумки за $month';
  }

  @override
  String get income => 'Доходи';

  @override
  String get incomeCaption => 'надійшло';

  @override
  String get expenses => 'Витрати';

  @override
  String get expensesCaption => 'витрачено';

  @override
  String get netFlow => 'Чистий потік';

  @override
  String get netPositiveCaption => 'у плюсі';

  @override
  String get trendExpensesTitle => 'Витрати';

  @override
  String get trendBalanceTitle => 'Баланс';

  @override
  String get trendUnknownTitle => 'Динаміка';

  @override
  String get trendLast7Days => 'останні 7 днів';

  @override
  String get trendLast30Days => 'останні 30 днів';

  @override
  String get trendPeriodUnknown => 'період';

  @override
  String get trend7DaysChip => '7 днів';

  @override
  String get trend30DaysChip => '30 днів';

  @override
  String get detailsAction => 'Детальніше';

  @override
  String get trendEmpty => 'Поки замало даних для графіка';

  @override
  String trendSemantics(String title, String amount) {
    return '$title за період, усього $amount';
  }

  @override
  String get amountsHidden => 'суми приховано';

  @override
  String goalDueDate(String date) {
    return 'до $date';
  }

  @override
  String goalProgressSummary(String target, String progress) {
    return 'з $target · $progress%';
  }

  @override
  String goalMonthlyContribution(String amount) {
    return 'Потрібно відкладати приблизно $amount на місяць';
  }

  @override
  String goalSemantics(
    String title,
    String current,
    String target,
    String progress,
  ) {
    return '$title, накопичено $current, ціль $target, прогрес $progress відсотків, відкрити ціль';
  }

  @override
  String get upcomingPaymentsTitle => 'Найближчі платежі';

  @override
  String get allPaymentsAction => 'Усі платежі';

  @override
  String get noUpcomingPayments => 'Найближчих платежів немає';

  @override
  String paymentDueDate(String date) {
    return 'до $date';
  }

  @override
  String paymentOverdueDate(String date) {
    return 'прострочено · $date';
  }

  @override
  String paymentDateUnknown(String date) {
    return 'статус уточнюється · $date';
  }

  @override
  String paymentSemantics(String title, String due, String amount) {
    return '$title, $due, $amount';
  }

  @override
  String get recentTransactionsTitle => 'Останні операції';

  @override
  String get noRecentTransactions => 'Підтверджених операцій поки немає';

  @override
  String get transactionCategoryUnavailable => 'Без категорії';

  @override
  String transactionMetadata(String category, String date) {
    return '$category · $date';
  }

  @override
  String get transactionIncome => 'дохід';

  @override
  String get transactionExpense => 'витрата';

  @override
  String get transactionTransfer => 'переказ';

  @override
  String get transactionUnknown => 'операція';

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
  String get refreshingTitle => 'Оновлюємо дані';

  @override
  String get refreshingDescription =>
      'Поточна фінансова картина залишається доступною.';

  @override
  String get partialDataTitle => 'Частина даних тимчасово недоступна';

  @override
  String get partialDataDescription =>
      'Доступні розділи продовжують працювати.';

  @override
  String get offlineTitle => 'Немає з’єднання';

  @override
  String offlineDataAsOf(String date, String time) {
    return 'Дані актуальні на $date, $time UTC.';
  }

  @override
  String get refreshFailedTitle => 'Не вдалося оновити дані';

  @override
  String get refreshFailedDescription =>
      'Показуємо попередню фінансову картину.';

  @override
  String get retryAction => 'Повторити';

  @override
  String get fatalErrorTitle => 'Не вдалося завантажити дані';

  @override
  String get fatalErrorDescription =>
      'Спробуйте ще раз. Якщо помилка повториться, повідомте код запиту в підтримку.';

  @override
  String requestIdLabel(String requestId) {
    return 'Код запиту: $requestId';
  }

  @override
  String get authExpiredTitle => 'Сеанс завершився';

  @override
  String get authExpiredDescription =>
      'Для захисту даних потрібно ввійти знову.';

  @override
  String get signInAgainAction => 'Увійти знову';

  @override
  String get sessionExpiredStubTitle => 'Повторний вхід';

  @override
  String get sessionExpiredStubDescription =>
      'Екран авторизації буде підключено разом зі справжнім сеансом. Фінансові дані не видалено.';

  @override
  String get balanceUnavailable => 'Баланс тимчасово недоступний';

  @override
  String get monthSummaryUnavailable => 'Підсумки місяця тимчасово недоступні';

  @override
  String get trendUnavailable => 'Графік тимчасово недоступний';

  @override
  String get goalNotSelected => 'Головну ціль поки не вибрано';

  @override
  String get goalUnavailable =>
      'Розділ цілей тимчасово недоступний. Ми вже оновлюємо дані.';

  @override
  String get paymentsUnavailable => 'Найближчі платежі тимчасово недоступні';

  @override
  String get transactionsUnavailable => 'Останні операції тимчасово недоступні';

  @override
  String get emptyTitle =>
      'Додайте першу операцію, щоб побачити фінансову картину';

  @override
  String get emptyDescription =>
      'Просто скажіть, що купили або отримали — решту ми зробимо самі.';

  @override
  String get loadingLabel => 'Завантаження фінансових даних';

  @override
  String get homeTab => 'Головна';

  @override
  String get chatTab => 'Чат';

  @override
  String get analyticsTab => 'Аналітика';

  @override
  String get goalsTab => 'Цілі';

  @override
  String get profileTab => 'Профіль';

  @override
  String get settingsTitle => 'Налаштування';

  @override
  String get backLabel => 'Назад';

  @override
  String get appearanceSection => 'ОФОРМЛЕННЯ';

  @override
  String get lightTheme => 'Світла';

  @override
  String get darkTheme => 'Темна';

  @override
  String get accentColor => 'Акцентний колір';

  @override
  String get tealAccent => 'Бірюзовий';

  @override
  String get blueAccent => 'Синій';

  @override
  String get purpleAccent => 'Фіолетовий';

  @override
  String get terracottaAccent => 'Теракотовий';

  @override
  String get generalSection => 'ЗАГАЛЬНІ';

  @override
  String get privacySetting => 'Приховувати суми';

  @override
  String get languageSetting => 'Мова';

  @override
  String get baseCurrencySetting => 'Основна валюта';

  @override
  String get baselineSettingsAction => 'Дата початку обліку';

  @override
  String get baselineSettingsDescription =>
      'Дозволити операції за раніший період';

  @override
  String get baselineCorrectionTitle => 'Дата початку обліку';

  @override
  String get baselineCorrectionLoading => 'Завантажуємо налаштування рахунку';

  @override
  String get baselineCorrectionDescription =>
      'Перенесіть дату назад, щоб додати раніші операції. Початковий залишок і валюта не зміняться.';

  @override
  String get baselineCurrentDateLabel => 'Поточна дата початку обліку';

  @override
  String get baselineNewDateLabel => 'Нова дата';

  @override
  String get baselineChooseDateAction => 'Вибрати дату';

  @override
  String get baselineDateRangeHelp =>
      'Можна вибрати лише дату, ранішу за поточну дату початку обліку.';

  @override
  String get baselineReviewTitle => 'Перевірте нову дату';

  @override
  String get baselineReviewDescription =>
      'Після підтвердження головний екран і місячні підсумки буде перераховано з авторитетних даних.';

  @override
  String get baselineConfirmAction => 'Підтвердити нову дату';

  @override
  String get baselineSuccessTitle => 'Дату початку обліку змінено';

  @override
  String baselineSuccessDescription(String date) {
    return 'Тепер можна додавати операції від $date.';
  }

  @override
  String get baselineHomeDelayedDescription =>
      'Дату вже збережено. Головний екран оновиться пізніше; повторно підтверджувати зміну не потрібно.';

  @override
  String get baselineDoneAction => 'Готово';

  @override
  String get baselineUnavailableTitle => 'Дату поки не можна змінити';

  @override
  String get baselineAccountRequired => 'Спочатку налаштуйте перший рахунок.';

  @override
  String get baselineMinimumDateReached =>
      'Рахунок уже починається з найранішої підтримуваної дати.';

  @override
  String get baselineNotEarlierError =>
      'Виберіть дату, ранішу за поточну дату початку обліку.';

  @override
  String get baselineFutureError =>
      'Дата початку обліку не може бути пізнішою за сьогоднішній день.';

  @override
  String get baselineAfterOperationError =>
      'Нова дата не може бути пізнішою за найранішу збережену операцію.';

  @override
  String get baselineLoadFailed =>
      'Не вдалося завантажити налаштування рахунку.';

  @override
  String get baselineChangeFailed =>
      'Не вдалося змінити дату. Клієнт не змінював фінансові дані.';

  @override
  String get stubDescription =>
      'Розділ буде реалізовано на наступному етапі. Зараз це навігаційна заглушка.';

  @override
  String get voiceStubTitle => 'Голосове введення';

  @override
  String get voiceStubDescription =>
      'Екран запису підготовлено як заглушку. Мікрофон і розпізнавання мовлення з’являться в наступному vertical slice.';

  @override
  String get backHome => 'На головну';

  @override
  String get authLoadingLabel => 'Перевіряємо захищений сеанс';

  @override
  String get loginTitle => 'Вхід';

  @override
  String get loginDescription =>
      'Увійдіть, щоб відкрити свою фінансову картину.';

  @override
  String get registerTitle => 'Створення акаунта';

  @override
  String get registerDescription =>
      'Створіть захищений акаунт, щоб почати вести фінанси.';

  @override
  String get displayNameField => 'Ваше ім’я';

  @override
  String get displayNameRequired => 'Вкажіть ім’я';

  @override
  String get emailField => 'Електронна пошта';

  @override
  String get emailInvalid => 'Введіть правильну адресу електронної пошти';

  @override
  String get passwordField => 'Пароль';

  @override
  String get confirmPasswordField => 'Повторіть пароль';

  @override
  String get passwordRequirements => 'Щонайменше 12 символів';

  @override
  String get passwordInvalid => 'Пароль має містити від 12 до 128 символів';

  @override
  String get passwordsDoNotMatch => 'Паролі не збігаються';

  @override
  String get showPassword => 'Показати пароль';

  @override
  String get hidePassword => 'Приховати пароль';

  @override
  String get loginAction => 'Увійти';

  @override
  String get registerAction => 'Створити акаунт';

  @override
  String get createAccountAction => 'Немає акаунта? Створити';

  @override
  String get haveAccountAction => 'Уже є акаунт? Увійти';

  @override
  String get authSessionExpiredNotice => 'Сеанс завершено. Увійдіть знову.';

  @override
  String get signedOutNotice => 'Ви вийшли з акаунта.';

  @override
  String get invalidCredentialsError =>
      'Не вдалося ввійти. Перевірте пошту й пароль.';

  @override
  String get emailInUseError =>
      'Не вдалося створити акаунт. Можливо, ця пошта вже використовується.';

  @override
  String get authInvalidInputError =>
      'Перевірте введені дані та спробуйте знову.';

  @override
  String get authThrottledError =>
      'Забагато спроб. Зачекайте й спробуйте знову.';

  @override
  String get authOfflineError =>
      'Немає з’єднання з інтернетом. Перевірте мережу й повторіть спробу.';

  @override
  String get authTimeoutError => 'Сервер не відповів вчасно. Спробуйте знову.';

  @override
  String get authServiceError =>
      'Сервіс входу тимчасово недоступний. Спробуйте пізніше.';

  @override
  String get authUnexpectedError =>
      'Не вдалося завершити вхід. Спробуйте знову.';

  @override
  String get authSecureStorageError =>
      'Не вдалося відкрити захищене сховище пристрою.';

  @override
  String get accountSection => 'АКАУНТ';

  @override
  String get signOutAction => 'Вийти з акаунта';

  @override
  String get signOutDialogTitle => 'Вийти з акаунта?';

  @override
  String get signOutDialogDescription =>
      'Для наступного входу потрібно буде знову ввести пошту й пароль.';

  @override
  String get cancelAction => 'Скасувати';

  @override
  String get financeEntryTitle => 'Фінансова операція';

  @override
  String get financeEntryLoading => 'Перевіряємо фінансовий рахунок';

  @override
  String get financeEntryLoadFailed => 'Не вдалося відкрити введення операції';

  @override
  String get accountSetupTitle => 'Налаштуйте перший рахунок';

  @override
  String get accountSetupDescription =>
      'Вкажіть фактичний залишок. Дата початку задає найраніший день, за який можна додати операцію. Перед збереженням ви перевірите дані.';

  @override
  String get accountNameField => 'Назва рахунку';

  @override
  String get accountNameHint => 'Наприклад, Основний рахунок';

  @override
  String get accountNameRequired => 'Вкажіть назву рахунку';

  @override
  String get accountCurrencyRequired => 'Оберіть валюту';

  @override
  String get accountCurrencyHelp =>
      'Потім валюту цього рахунку не змінити. Для інших валют можна буде відкрити окремі гаманці.';

  @override
  String get openingBalanceField => 'Початковий залишок';

  @override
  String get openingBalanceHelp =>
      'Це вихідний залишок, а не дохід чи витрата.';

  @override
  String get openingBalanceDateField => 'Дата початкового залишку';

  @override
  String get canonicalTimezoneLabel => 'Часовий пояс обліку';

  @override
  String get continueToReviewAction => 'Перевірити дані';

  @override
  String get accountReviewTitle => 'Перевірте налаштування рахунку';

  @override
  String get reviewBeforeConfirmDescription =>
      'Фінансові дані збережуться лише після явного підтвердження.';

  @override
  String get confirmFinanceAction => 'Підтвердити й зберегти';

  @override
  String get editAction => 'Змінити';

  @override
  String get accountCreatedNotice =>
      'Рахунок підтверджено. Тепер додайте першу операцію.';

  @override
  String get manualOperationTitle => 'Додайте операцію вручну';

  @override
  String get manualOperationDescription =>
      'Заповніть структуровані поля. Голос і автоматичне розпізнавання поки не використовуються.';

  @override
  String get accountLabel => 'Рахунок';

  @override
  String get operationExpense => 'Витрата';

  @override
  String get operationIncome => 'Дохід';

  @override
  String get operationTypeLabel => 'Тип операції';

  @override
  String get operationAmountField => 'Сума';

  @override
  String get merchantField => 'Місце чи отримувач, необов’язково';

  @override
  String get categoryField => 'Категорія, необов’язково';

  @override
  String get operationDateField => 'Дата операції';

  @override
  String get operationReviewTitle => 'Перевірте операцію';

  @override
  String get addAnotherOperationAction => 'Додати ще одну';

  @override
  String get moneyInputInvalid =>
      'Введіть правильну суму, наприклад 1250,50 або -20';

  @override
  String get positiveMoneyInputInvalid =>
      'Введіть суму, більшу за нуль, наприклад 35 або 35,50';

  @override
  String get financeInvalidInput =>
      'Перевірте заповнені поля та спробуйте знову.';

  @override
  String get financeValidationRejected =>
      'Дані не пройшли перевірку. Перевірте поля перед повторним надсиланням.';

  @override
  String get financeDateRejected =>
      'Дата не може бути пізнішою за сьогоднішній день.';

  @override
  String get operationBeforeOpeningDateError =>
      'Дата операції не може бути ранішою за дату початкового залишку.';

  @override
  String get financeAccountUnavailable =>
      'Рахунок недоступний для цієї операції. Оновіть екран і спробуйте знову.';

  @override
  String get financeConflictError =>
      'Команда конфліктує з уже обробленим записом. Змініть дані та створіть нове підтвердження.';

  @override
  String get financeOfflineError =>
      'Не вдалося зв’язатися із сервером. Перевірте підключення до API та повторіть спробу.';

  @override
  String get financeTimeoutError =>
      'Сервер не відповів вчасно. Підтвердження можна безпечно повторити.';

  @override
  String get financeServiceError =>
      'Сервіс фінансових операцій тимчасово недоступний. Спробуйте знову пізніше.';

  @override
  String get financeSecurityError =>
      'Не вдалося підтвердити безпечне з’єднання. Перевірте налаштування й повторіть пізніше.';

  @override
  String get financeLocalStorageError =>
      'Не вдалося надійно зберегти підтвердження на пристрої. Запит на сервер не надсилався. Звільніть місце або розблокуйте захищене сховище й повторіть.';

  @override
  String get financeUnexpectedError =>
      'Отримано некоректну відповідь. Клієнт не змінював фінансові дані.';

  @override
  String get financeSessionChanged =>
      'Захищений сеанс оновився. Повторіть дію; підтвердження буде надіслано з тими самими даними.';

  @override
  String get operationAcceptedTitle => 'Операцію збережено';

  @override
  String get operationAcceptedUpdatingHome =>
      'Операцію прийнято. Чекаємо на нову версію головного екрана.';

  @override
  String get operationAcceptedHomeUpdated =>
      'Головний екран оновлено за новою авторитетною версією.';

  @override
  String get operationAcceptedProjectionDelayed =>
      'Операцію вже збережено, але оновлення головного екрана затримується. Повторно підтверджувати її не потрібно.';

  @override
  String get operationAcceptedAuthRequired =>
      'Операцію вже збережено, але для оновлення головного екрана потрібно буде знову ввійти.';

  @override
  String get operationAcceptedSessionChanged =>
      'Операцію вже збережено, але сеанс змінився під час оновлення. Відкрийте головний екран ще раз.';

  @override
  String get operationAcceptedRefreshFailed =>
      'Операцію вже збережено. Головний екран можна оновити пізніше.';

  @override
  String get operationQueuedTitle => 'Операцію збережено на пристрої';

  @override
  String get operationQueuedDescription =>
      'Підтвердження збережено в захищеному вигляді. Якщо сервер ще не прийняв його, воно не впливає на баланс. Актуальний статус показано на головному екрані.';

  @override
  String get operationQueuedAuthDescription =>
      'Підтвердження збережено в захищеному вигляді. Для продовження надсилання може знадобитися повторний вхід. Актуальний статус показано на головному екрані.';

  @override
  String get operationAlreadySyncedTitle => 'Операцію вже синхронізовано';

  @override
  String get operationAlreadySyncedDescription =>
      'Сервер підтвердив цю саму операцію раніше. Повторний запис не створено.';

  @override
  String get operationAttentionTitle => 'Операція потребує перевірки';

  @override
  String get operationAttentionConflict =>
      'Збережене підтвердження конфліктує з уже обробленою командою і не надсилатиметься автоматично.';

  @override
  String get operationAttentionRejected =>
      'Finance Core відхилив підтвердження. Баланс не змінено.';

  @override
  String get operationAttentionSecurity =>
      'Надсилання зупинено через перевірку безпеки. Баланс не змінено.';

  @override
  String get operationAttentionInvalid =>
      'Підтвердження не можна безпечно надіслати автоматично. Баланс не змінено.';

  @override
  String get operationSyncingBannerTitle => 'Надсилаємо збережену операцію';

  @override
  String get operationSyncingBannerDescription =>
      'До підтвердження сервером вона не впливає на баланс.';

  @override
  String get operationHomeUpdatingBannerTitle => 'Головний екран оновлюється';

  @override
  String get operationHomeUpdatingBannerDescription =>
      'Сервер уже зберіг операцію. Баланс оновиться, щойно дані будуть готові; повторно підтверджувати її не потрібно.';

  @override
  String get operationHomeUpdatingAction => 'Оновити зараз';

  @override
  String get operationPendingBannerTitle => 'Операція чекає на синхронізацію';

  @override
  String get operationPendingBannerDescription =>
      'Її збережено на пристрої в захищеному вигляді, і поки вона не впливає на баланс.';

  @override
  String get operationAuthBannerTitle => 'Потрібен повторний вхід';

  @override
  String get operationAuthBannerDescription =>
      'Збережена операція залишиться на пристрої до безпечної авторизації.';

  @override
  String get operationAttentionBannerTitle => 'Перевірте збережену операцію';

  @override
  String get operationAttentionBannerDescription =>
      'Автоматичне надсилання зупинено. Баланс не змінено.';

  @override
  String get operationLockedBannerDescription =>
      'Надсилання фінансових операцій заблоковано після перевірки безпеки. Нові підтвердження не надсилатимуться автоматично.';

  @override
  String get operationRetryNowAction => 'Повторити надсилання';

  @override
  String operationBeforeOpeningDateDetail(String openingDate) {
    return 'Облік рахунку починається $openingDate. Операції, раніші за цю дату, записати не можна. Дату початку можна перенести назад у налаштуваннях рахунку.';
  }

  @override
  String get plannedCostSettingsAction => 'Запланувати витрату';

  @override
  String get plannedCostSettingsDescription => 'Наприклад, оренда або підписка';

  @override
  String get plannedCostTitle => 'Запланована витрата';

  @override
  String get plannedCostLoading => 'Завантажуємо рахунок';

  @override
  String get plannedCostDescription =>
      'Запланована витрата не змінює баланс. Вона буде в списку майбутніх платежів, доки ви її не підтвердите.';

  @override
  String get plannedCostAccountRequired =>
      'Спочатку потрібно створити рахунок: запланована витрата прив’язується до нього.';

  @override
  String get plannedCostTitleLabel => 'Назва';

  @override
  String get plannedCostTitleHint => 'Оренда';

  @override
  String get plannedCostAmountLabel => 'Сума';

  @override
  String get plannedCostDateLabel => 'Дата платежу';

  @override
  String get plannedCostChooseDateAction => 'Вибрати дату';

  @override
  String get plannedCostSubmitAction => 'Запланувати';

  @override
  String get plannedCostRetryAction => 'Повторити';

  @override
  String get plannedCostAcceptedTitle => 'Витрату заплановано';

  @override
  String get plannedCostAcceptedDescription =>
      'Вона не впливає на баланс і чекає на підтвердження.';

  @override
  String get plannedCostHomePending => 'Оновлюємо головний екран';

  @override
  String get plannedCostHomeUpdated => 'Головний екран оновлено';

  @override
  String get plannedCostHomeDelayed => 'Головний екран оновиться трохи пізніше';

  @override
  String get plannedCostHomeFailed => 'Не вдалося оновити головний екран';

  @override
  String get plannedCostInvalidInput => 'Перевірте назву, суму й дату.';

  @override
  String get plannedCostIssueAccountUnavailable => 'Рахунок недоступний.';

  @override
  String get plannedCostIssueCurrencyMismatch =>
      'Валюта не збігається з валютою рахунку.';

  @override
  String get plannedCostIssueUnsupportedCurrency =>
      'Ця валюта поки не підтримується.';

  @override
  String get plannedCostIssueBeforeBaseline =>
      'Дата раніша за початок обліку цього рахунку. Виберіть пізнішу дату.';

  @override
  String get plannedCostGenericFailure => 'Не вдалося запланувати витрату.';

  @override
  String get plannedCostDoneAction => 'Готово';

  @override
  String get plannedCostListTitle => 'Заплановано';

  @override
  String get plannedCostListEmpty => 'Поки нічого не заплановано.';

  @override
  String get plannedCostCancelAction => 'Скасувати';

  @override
  String get plannedCostCancelSemantics => 'Скасувати план';

  @override
  String get plannedCostDueLabel => 'Термін';

  @override
  String get plannedCostOverdueLabel => 'Прострочено';

  @override
  String get plannedCostCancelFailure => 'Не вдалося скасувати план.';

  @override
  String get plannedCostConfirmAction => 'Оплачено';

  @override
  String get plannedCostConfirmSemantics => 'Позначити план оплаченим';

  @override
  String get plannedCostConfirmFailure =>
      'Не вдалося записати операцію. План залишився в списку — спробуйте ще раз.';

  @override
  String get plannedCostConfirmHint =>
      '«Оплачено» створить звичайну операцію витрати й прибере план зі списку.';

  @override
  String get savingsGoalTitle => 'Цілі';

  @override
  String get savingsGoalLoading => 'Завантажуємо цілі';

  @override
  String get savingsGoalAccountRequired =>
      'Спочатку створіть рахунок — ціль накопичується в його валюті.';

  @override
  String get savingsGoalGenericFailure =>
      'Не вдалося виконати дію. Спробуйте ще раз.';

  @override
  String get savingsGoalInvalidInput => 'Перевірте назву, суму й дату.';

  @override
  String get savingsGoalRetryAction => 'Повторити';

  @override
  String get savingsGoalDescription =>
      'Ціль показує, скільки ви вже відклали. Відкладені гроші залишаються на рахунку: баланс, доходи й витрати не змінюються.';

  @override
  String get savingsGoalEmpty => 'Поки немає жодної цілі.';

  @override
  String get savingsGoalCreateAction => 'Нова ціль';

  @override
  String get savingsGoalCancelCreateAction => 'Скасувати';

  @override
  String get savingsGoalTitleLabel => 'Назва';

  @override
  String get savingsGoalTitleHint => 'Відпустка';

  @override
  String get savingsGoalTargetLabel => 'Скільки потрібно';

  @override
  String get savingsGoalMonthlyLabel => 'Планую відкладати на місяць';

  @override
  String get savingsGoalMonthlyHelper =>
      'Необов’язково. Це орієнтир, а не зобов’язання.';

  @override
  String get savingsGoalDateLabel => 'До якої дати';

  @override
  String get savingsGoalChooseDateAction => 'Вибрати дату';

  @override
  String get savingsGoalSubmitAction => 'Створити ціль';

  @override
  String get savingsGoalContributionLabel => 'Сума';

  @override
  String get savingsGoalDepositAction => 'Відкласти';

  @override
  String get savingsGoalWithdrawAction => 'Забрати';

  @override
  String get savingsGoalCancelAction => 'Відмовитися від цілі';

  @override
  String get savingsGoalCancelSemantics =>
      'Відмовитися від цілі й прибрати її зі списку';

  @override
  String get savingsGoalDepositSemantics => 'Відкласти вказану суму на цю ціль';

  @override
  String get savingsGoalWithdrawSemantics => 'Забрати вказану суму з цієї цілі';

  @override
  String get savingsGoalAchievedLabel => 'Ціль досягнуто';

  @override
  String get savingsGoalIssueAccountUnavailable =>
      'Рахунок недоступний. Оновіть екран.';

  @override
  String get savingsGoalIssueCurrencyMismatch =>
      'Валюта цілі має збігатися з валютою рахунку.';

  @override
  String get savingsGoalIssueUnsupportedCurrency =>
      'Ця валюта поки не підтримується.';

  @override
  String get savingsGoalIssueBeforeBaseline =>
      'Дата раніша за дату відкриття рахунку.';

  @override
  String get savingsGoalIssueFutureContribution =>
      'Відкласти можна лише за сьогодні або раніше.';

  @override
  String get savingsGoalIssueNotActive => 'Ціль уже закрито. Оновіть екран.';

  @override
  String get savingsGoalIssueWithdrawalTooLarge =>
      'На цілі менше грошей, ніж ви намагаєтеся забрати.';

  @override
  String get categoryPickerNone => 'Без категорії';

  @override
  String get categoryPickerOther => 'Інше (ввести текстом)';

  @override
  String get categoryPickerOtherLabel => 'Своя категорія';

  @override
  String get categoryPickerLoading => 'Завантажуємо категорії';

  @override
  String get categoryPickerUnavailable =>
      'Список категорій недоступний — впишіть назву вручну.';

  @override
  String get categorySeedGroceries => 'Продукти';

  @override
  String get categorySeedEatingOut => 'Кафе й ресторани';

  @override
  String get categorySeedTransport => 'Транспорт';

  @override
  String get categorySeedHousing => 'Житло';

  @override
  String get categorySeedUtilities => 'Зв’язок та інтернет';

  @override
  String get categorySeedHealth => 'Здоров’я';

  @override
  String get categorySeedClothing => 'Одяг';

  @override
  String get categorySeedEntertainment => 'Розваги';

  @override
  String get categorySeedEducation => 'Освіта';

  @override
  String get categorySeedGiftsOut => 'Подарунки';

  @override
  String get categorySeedOtherExpense => 'Інше';

  @override
  String get categorySeedSalary => 'Зарплата';

  @override
  String get categorySeedFreelance => 'Підробіток';

  @override
  String get categorySeedGiftsIn => 'Подарунки';

  @override
  String get categorySeedInterest => 'Відсотки';

  @override
  String get categorySeedOtherIncome => 'Інше';

  @override
  String get categoriesSettingsAction => 'Категорії';

  @override
  String get categoriesSettingsDescription => 'Свої назви для витрат і доходів';

  @override
  String get categoriesTitle => 'Категорії';

  @override
  String get categoriesExpenseTab => 'Витрати';

  @override
  String get categoriesIncomeTab => 'Доходи';

  @override
  String get categoryAddAction => 'Додати категорію';

  @override
  String get categoryNameLabel => 'Назва';

  @override
  String get categoryCreateAction => 'Створити';

  @override
  String get categorySaveAction => 'Зберегти';

  @override
  String get categoryRenameAction => 'Перейменувати';

  @override
  String get categoryHideAction => 'Приховати';

  @override
  String get categoryRestoreAction => 'Повернути';

  @override
  String categoryHiddenSection(int count) {
    return 'Приховані: $count';
  }

  @override
  String get categoryHiddenNote =>
      'Прихована категорія не пропонується під час нового запису, але залишається на минулих операціях.';

  @override
  String get categoryListEmpty => 'Поки жодної категорії';

  @override
  String get categoryHideDialogTitle => 'Приховати категорію?';

  @override
  String get categoryHideDialogDescription =>
      'Вона зникне зі списку під час нового запису. Минулі операції залишаться в ній, і її можна повернути.';

  @override
  String get categoryNameTakenError => 'Така назва вже є';

  @override
  String get categoryArchivedError =>
      'Категорію приховано — спочатку поверніть її';

  @override
  String get categoryNotFoundError => 'Категорію не знайдено';

  @override
  String get categoryNameInvalidError => 'Введіть назву до 100 символів';

  @override
  String get categoryLoadError => 'Не вдалося завантажити категорії';

  @override
  String get operationCorrectAction => 'Змінити';

  @override
  String get operationRemoveAction => 'Видалити';

  @override
  String get operationCorrectTitle => 'Виправити операцію';

  @override
  String get operationCorrectSave => 'Зберегти';

  @override
  String get operationCorrectedMessage => 'Операцію виправлено';

  @override
  String get operationRemovedMessage => 'Операцію видалено';

  @override
  String get operationRemoveDialogTitle => 'Видалити операцію?';

  @override
  String get operationRemoveDialogBody =>
      'Вона перестане враховуватися в балансі й звітах. Сам запис збережеться в історії змін.';

  @override
  String get operationCorrectionFailed =>
      'Не вдалося зберегти зміну. Спробуйте ще раз.';

  @override
  String get operationAlreadyReversedMessage =>
      'Цю операцію вже виправили. Оновіть список.';

  @override
  String get operationNotFoundMessage => 'Такої операції більше немає.';

  @override
  String get operationHistoryTitle => 'Усі операції';

  @override
  String get operationHistorySettingsAction => 'Усі операції';

  @override
  String get operationHistorySettingsDescription =>
      'Історія записів і що було вписано';

  @override
  String get operationHistoryEmpty => 'Поки жодного запису';

  @override
  String get operationHistoryMore => 'Показати ще';

  @override
  String get operationHistoryLoadError => 'Не вдалося завантажити операції';

  @override
  String get operationHistoryLoadMoreError =>
      'Не вдалося завантажити продовження';

  @override
  String operationHistoryDate(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get operationDetailDate => 'Дата';

  @override
  String get operationDetailCategory => 'Категорія';

  @override
  String get operationDetailMerchant => 'Де';

  @override
  String get operationDetailOriginalText => 'Було вписано';

  @override
  String get operationDetailOriginalTextHint =>
      'Категорію пізніше перейменували';

  @override
  String get analyticsExpenseByCategory => 'Витрати за категоріями';

  @override
  String get analyticsIncomeByCategory => 'Доходи за категоріями';

  @override
  String get analyticsBreakdownEmpty => 'За цей місяць записів немає';

  @override
  String get analyticsLoadError => 'Не вдалося порахувати аналітику';

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
  String get profileLoadError => 'Не вдалося завантажити профіль';

  @override
  String get profileEmailLabel => 'Пошта для входу';

  @override
  String get profileAccountSection => 'РАХУНОК';

  @override
  String get profileTimezoneSetting => 'Часовий пояс';

  @override
  String get profileNoAccount => 'Рахунок з’явиться після першого запису';

  @override
  String profileOpeningDateValue(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Зараз $dateString';
  }

  @override
  String profileVersion(String version) {
    return 'Версія $version';
  }

  @override
  String get entrySentenceField => 'Опишіть операцію однією фразою';

  @override
  String get entrySentenceHint => 'Витратив 12,50 на продукти вчора';

  @override
  String get entrySentenceParseAction => 'Розібрати';

  @override
  String get entrySentenceFilled =>
      'Заповнив поля нижче — перевірте й підтвердьте.';

  @override
  String get entrySentenceParseError => 'Не вдалося розібрати фразу.';

  @override
  String get entrySentenceEmpty =>
      'Напишіть коротшу фразу або почніть із суми.';

  @override
  String get entrySentenceGapAmount => 'Суму не знайшов — впишіть її.';

  @override
  String get entrySentenceGapAmbiguous =>
      'У фразі кілька чисел — уточніть суму.';

  @override
  String get entrySentenceGapDate => 'Дату не зрозумів — перевірте її.';

  @override
  String get entrySentenceGapCategory => 'Категорію не підібрав — виберіть її.';

  @override
  String get entrySentenceGapTransfer =>
      'Це переказ між гаманцями, а не дохід чи витрата — тому нічого не заповнив.';

  @override
  String get entrySentenceOpenTransfer => 'Відкрити переказ';

  @override
  String get categoryKeywordsTitle => 'Слова категорії';

  @override
  String get categoryKeywordsAction => 'Слова';

  @override
  String get categoryKeywordsDescription =>
      'Якщо слово з фрази починається з одного з цих, операція потрапить у цю категорію. «авто» спіймає і «автохімію», «продукт» — і «продуктів».';

  @override
  String get categoryKeywordsEmpty =>
      'Слів поки немає — категорія підбереться лише за назвою.';

  @override
  String get categoryKeywordsField => 'Додати слово';

  @override
  String get categoryKeywordsAdd => 'Додати';

  @override
  String categoryKeywordsRemove(String keyword) {
    return 'Прибрати слово $keyword';
  }

  @override
  String get categoryKeywordsInvalid =>
      'Слово — від трьох літер або цифр, без пробілів.';

  @override
  String get categoryKeywordsTaken =>
      'Це слово вже веде в іншу категорію. Приберіть його там.';

  @override
  String get categoryKeywordsArchived =>
      'Прихована категорія не бере участі в підборі.';

  @override
  String get categoryKeywordsLoadError => 'Не вдалося завантажити слова';

  @override
  String get categoryKeywordsSaveError => 'Не вдалося зберегти слово';

  @override
  String get analyticsPeriod7Days => '7 днів';

  @override
  String get analyticsPeriodMonth => 'Місяць';

  @override
  String get analyticsPeriodQuarter => 'Квартал';

  @override
  String get analyticsPeriodYear => 'Рік';

  @override
  String get analyticsPeriodCustom => 'Свій період';

  @override
  String get analyticsPeriodLabel => 'Період';

  @override
  String get analyticsBalanceTitle => 'Баланс';

  @override
  String analyticsBalanceFromTo(String opening, String closing) {
    return '$opening → $closing';
  }

  @override
  String analyticsBalanceChange(String change) {
    return 'за період $change';
  }

  @override
  String get analyticsNoSpending => 'За цей період витрат не було';

  @override
  String analyticsPreviousAmount(String amount) {
    return 'було $amount';
  }

  @override
  String analyticsWindowRange(String from, String to) {
    return '$from — $to';
  }

  @override
  String analyticsComparedWith(String from, String to) {
    return 'порівняно з $from — $to';
  }

  @override
  String get plannedCostIssueCategoryUnavailable =>
      'Ця категорія недоступна. Виберіть іншу.';

  @override
  String get plannedCostRepeatToggle => 'Повторювати щомісяця';

  @override
  String get plannedCostRepeatDayLabel => 'День місяця';

  @override
  String get plannedCostRepeatLastDay => 'Останній день місяця';

  @override
  String get plannedCostRepeatShortMonthHint =>
      'У коротких місяцях платіж зсунеться на останній день: 31 січня, 28 лютого, 31 березня.';

  @override
  String get plannedCostRepeatFirstDatesTitle => 'Найближчі дати';

  @override
  String get plannedCostRecurrenceListTitle => 'Повторюється';

  @override
  String get plannedCostRecurrenceListEmpty =>
      'Повторюваних витрат поки немає.';

  @override
  String plannedCostRecurrenceMonthlyOnDay(int day) {
    return 'Щомісяця, $day числа';
  }

  @override
  String get plannedCostRecurrenceMonthlyLastDay => 'Щомісяця, останній день';

  @override
  String get plannedCostRecurrenceEndAction => 'Завершити';

  @override
  String get plannedCostRecurrenceEndDialogTitle => 'Завершити серію?';

  @override
  String get plannedCostRecurrenceEndDialogBody =>
      'Нові платежі не створюватимуться. Майбутні заплановані платежі з цієї серії скасуються, а ті, що вже настали, залишаться — їх потрібно підтвердити або пропустити.';

  @override
  String plannedCostRecurrenceEndedMessage(int count) {
    return 'Серію завершено. Скасовано майбутніх платежів: $count';
  }

  @override
  String get plannedCostSkipAction => 'Пропустити';

  @override
  String get plannedCostSkipHint =>
      '«Пропустити» прибирає один платіж, серія продовжиться.';

  @override
  String get plannedCostRecurrenceAcceptedTitle =>
      'Повторювану витрату записано';

  @override
  String get plannedCostRecurrenceAcceptedDescription =>
      'Платежі з’являтимуться самі. Це прогноз: баланс він не змінює.';

  @override
  String get plannedCostRecurrenceFailure =>
      'Не вдалося змінити повторювану витрату.';

  @override
  String get appUpdateCheckAction => 'Перевірити оновлення';

  @override
  String get appUpdateCheckDescription =>
      'Запитати сервер, чи вийшла нова версія';

  @override
  String get appUpdateChecking => 'Перевіряємо…';

  @override
  String get appUpdateUpToDate => 'У вас остання версія.';

  @override
  String appUpdateAvailable(String version, String size) {
    return 'Доступна версія $version, $size';
  }

  @override
  String get appUpdateNotesLabel => 'Що нового';

  @override
  String get appUpdateDownloadAction => 'Завантажити та встановити';

  @override
  String appUpdateDownloading(int percent) {
    return 'Завантажуємо… $percent%';
  }

  @override
  String get accountExportAction => 'Експортувати мої дані';

  @override
  String get accountExportDescription =>
      'Повний файл з усіма даними й таблиця операцій для Excel';

  @override
  String get accountExportPreparing => 'Готую файли…';

  @override
  String get accountExportFailedUnreachable =>
      'Не вдалося зв’язатися із сервером. Перевірте інтернет і спробуйте ще раз.';

  @override
  String get accountExportFailedUnavailable =>
      'Сервер не зміг підготувати експорт. Спробуйте пізніше.';

  @override
  String get accountExportFailedAuthentication =>
      'Сеанс завершився — увійдіть знову.';

  @override
  String get accountExportFailedShare =>
      'Файли готові, але вікно «Поділитися» не відкрилося.';

  @override
  String get accountExportFailedStorage =>
      'Не вдалося записати файли на телефон.';

  @override
  String get accountDeletionAction => 'Видалити акаунт';

  @override
  String get accountDeletionActionDescription =>
      'Через 7 днів. Передумали — просто увійдіть знову';

  @override
  String get accountDeletionTitle => 'Видалення акаунта';

  @override
  String get accountDeletionHeadline => 'Акаунт буде видалено через 7 днів';

  @override
  String get accountDeletionWhat =>
      'Буде видалено все: гаманці, операції, перекази, категорії, плани, бюджети й цілі. Повернути їх потім буде неможливо.';

  @override
  String get accountDeletionSignedOut =>
      'Ви одразу вийдете на всіх пристроях. Якщо передумаєте — увійдіть протягом 7 днів, і видалення скасується.';

  @override
  String get accountDeletionBackups =>
      'У резервних копіях сервера дані зберігаються ще до 14 днів, потім зникають і звідти.';

  @override
  String get accountDeletionExportFirst => 'Спершу експортувати мої дані';

  @override
  String accountDeletionUnsent(int count) {
    return 'Операцій на цьому телефоні, які ще не дійшли до сервера: $count. Їх немає в експорті, і вони зникнуть разом з акаунтом. Краще дочекатися надсилання.';
  }

  @override
  String get accountDeletionPasswordLabel => 'Пароль';

  @override
  String get accountDeletionPasswordHelp =>
      'Той самий, яким ви входите. Потрібен, щоб видалити акаунт міг лише його власник.';

  @override
  String get accountDeletionPasswordRejected => 'Неправильний пароль';

  @override
  String get accountDeletionSubmit => 'Видалити акаунт';

  @override
  String get accountDeletionConfirmTitle => 'Видалити акаунт?';

  @override
  String get accountDeletionConfirmBody =>
      'Ви вийдете на всіх пристроях. Через 7 днів усі дані буде видалено, якщо ви не ввійдете раніше.';

  @override
  String get accountDeletionConfirmCancel => 'Скасувати';

  @override
  String get accountDeletionConfirmAccept => 'Видалити';

  @override
  String get accountDeletionUnreachable =>
      'Не вдалося зв’язатися із сервером. Нічого не видалено — перевірте інтернет і спробуйте ще раз.';

  @override
  String get accountDeletionUnavailable =>
      'Сервер не зміг прийняти запит. Нічого не видалено — спробуйте пізніше.';

  @override
  String get accountDeletionAuthentication =>
      'Сеанс завершився — увійдіть знову. Нічого не видалено.';

  @override
  String accountDeletionScheduledNotice(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Акаунт буде видалено $dateString. Щоб скасувати видалення, просто увійдіть до цього дня.';
  }

  @override
  String get accountDeletionScheduledNoticeUndated =>
      'Акаунт буде видалено через 7 днів. Щоб скасувати видалення, просто увійдіть до цього терміну.';

  @override
  String get accountDeletionCancelled =>
      'Видалення акаунта скасовано — ви ввійшли, і всі дані на місці.';

  @override
  String get appUpdateHandedToInstaller =>
      'Файл завантажено й перевірено. Підтвердьте встановлення в системному вікні — Android встановлює оновлення сам, і це займає до хвилини. Завантажувати заново не потрібно: файл зараз потрібен інсталятору.';

  @override
  String get appUpdateOpenInstallerAction =>
      'Відкрити вікно встановлення знову';

  @override
  String get appUpdateNeedsPermission =>
      'Android просить дозволити встановлення із цього застосунку. Це робиться один раз.';

  @override
  String get appUpdatePermissionAction => 'Відкрити налаштування';

  @override
  String get appUpdateFailedUnreachable =>
      'Сервер недоступний. Спробуйте пізніше.';

  @override
  String get appUpdateFailedServer =>
      'Сервер не зміг відповісти про оновлення.';

  @override
  String get appUpdateFailedCorrupted =>
      'Файл завантажився пошкодженим і його видалено. Спробуйте ще раз.';

  @override
  String get appUpdateFailedInstaller =>
      'Не вдалося відкрити інсталятор Android.';

  @override
  String get appUpdateFailedAuth => 'Потрібно ввійти заново.';

  @override
  String get appUpdateRetryAction => 'Повторити';

  @override
  String appUpdateMegabytes(String megabytes) {
    return '$megabytes МБ';
  }

  @override
  String get notificationsQuietLabel => 'Сповіщення';

  @override
  String get notificationsEmpty => 'Нічого, що потребує уваги.';

  @override
  String get notificationsEmptyHint =>
      'Тут з’являтимуться нагадування про платежі й нові версії застосунку.';

  @override
  String notificationUpdateTitle(String version) {
    return 'Доступна версія $version';
  }

  @override
  String get notificationUpdateBody => 'Оновити можна в профілі.';

  @override
  String get notificationUpdateAction => 'Відкрити профіль';

  @override
  String notificationPaymentOverdueTitle(String title) {
    return 'Прострочено платіж: $title';
  }

  @override
  String notificationPaymentDueSoonTitle(String title) {
    return 'Скоро платіж: $title';
  }

  @override
  String notificationPaymentBody(String date, String amount) {
    return '$date, $amount';
  }

  @override
  String get notificationPaymentAction => 'Відкрити заплановані';

  @override
  String get budgetsTitle => 'Бюджети';

  @override
  String get budgetsSettingsAction => 'Бюджети';

  @override
  String get budgetsSettingsDescription =>
      'Місячні ліміти й скільки залишилося';

  @override
  String budgetsPeriod(String from, String to) {
    return '$from — $to';
  }

  @override
  String get budgetsOverallTitle => 'Усі витрати';

  @override
  String get budgetsEmpty => 'Лімітів поки немає.';

  @override
  String get budgetsEmptyHint =>
      'Встановіть місячний ліміт на категорію або одразу на всі витрати.';

  @override
  String budgetsSpentOfLimit(String spent, String limit) {
    return 'Витрачено $spent з $limit';
  }

  @override
  String budgetsRemaining(String amount) {
    return 'Залишилося $amount';
  }

  @override
  String budgetsOverspentBy(String amount) {
    return 'Перевитрата $amount';
  }

  @override
  String budgetsPlanned(String amount) {
    return 'Ще заплановано $amount';
  }

  @override
  String get budgetsAddAction => 'Встановити ліміт';

  @override
  String get budgetsRemoveAction => 'Зняти';

  @override
  String get budgetsRemoveDialogTitle => 'Зняти ліміт?';

  @override
  String get budgetsRemoveDialogBody =>
      'Витрата залишиться, перестане рахуватися лише ліміт. Встановити новий можна будь-коли.';

  @override
  String get budgetsCategoryLabel => 'На що';

  @override
  String get budgetsLimitLabel => 'Ліміт на місяць';

  @override
  String get budgetsSaveAction => 'Зберегти';

  @override
  String get budgetsLoadError => 'Не вдалося завантажити бюджети.';

  @override
  String get budgetsWriteError => 'Не вдалося зберегти ліміт.';

  @override
  String get budgetsNoCategoriesLeft =>
      'Для всіх категорій ліміти вже встановлено.';

  @override
  String get budgetsAccountRequired => 'Спочатку створіть рахунок.';

  @override
  String get timezoneTitle => 'Часовий пояс обліку';

  @override
  String timezoneCurrent(String zone) {
    return 'Зараз $zone';
  }

  @override
  String get timezoneExplanation =>
      'Тут вирішується, де проходить межа дня й місяця. Уже записані операції залишаються на своїх датах — змінюється лише те, що вважається «сьогодні» й «цей місяць».';

  @override
  String get timezoneSearchField => 'Пошук міста або зони';

  @override
  String get timezoneDeviceSection => 'ПОЯС ТЕЛЕФОНА';

  @override
  String get timezoneAllSection => 'УСІ ПОЯСИ';

  @override
  String get timezoneNothingFound => 'Нічого не знайдено';

  @override
  String timezoneConfirmTitle(String zone) {
    return 'Перенести облік у $zone?';
  }

  @override
  String get timezoneConfirmBody =>
      'Суми й дати вже записаних операцій не зміняться. По-новому рахуватимуться лише «сьогодні» й межі місяця.';

  @override
  String get timezoneConfirmAction => 'Перенести';

  @override
  String timezoneCorrected(String zone) {
    return 'Облік ведеться в $zone';
  }

  @override
  String get timezoneUnchangedError => 'Облік уже ведеться в цьому поясі.';

  @override
  String get timezoneBehindOperationsError =>
      'У цьому поясі останній запис опинився б у майбутньому, і його сума зникла б із балансу до завтра. Виберіть пояс східніше або спробуйте пізніше.';

  @override
  String get timezoneWriteError => 'Не вдалося змінити часовий пояс.';

  @override
  String get timezoneLoadError => 'Не вдалося завантажити рахунок.';

  @override
  String get timezoneAccountRequired => 'Спочатку створіть рахунок.';

  @override
  String get timezoneSettingsDescription => 'Де проходить межа дня й місяця';

  @override
  String get entrySentenceGapCurrency =>
      'Валюту не розібрав — впишіть суму самі.';

  @override
  String entrySentenceCurrencyMismatch(String parsed, String account) {
    return 'Сума в $parsed, а рахунок у $account — не підставив її.';
  }

  @override
  String get otherWalletsTitle => 'ІНШІ ГАМАНЦІ';

  @override
  String get transferTitle => 'Переказ між рахунками';

  @override
  String get transferSettingsAction => 'Переказ між рахунками';

  @override
  String get transferSettingsDescription =>
      'Перекласти гроші з одного гаманця в інший';

  @override
  String get transferFromField => 'Звідки';

  @override
  String get transferToField => 'Куди';

  @override
  String get transferFromAmountField => 'Скільки пішло';

  @override
  String get transferToAmountField => 'Скільки прийшло';

  @override
  String get transferDateField => 'Коли';

  @override
  String transferRateLabel(String from, String rate, String to) {
    return 'Курс: 1 $from = $rate $to';
  }

  @override
  String get transferRateHint =>
      'Курс не береться з інтернету — він випливає з двох сум, які ви ввели.';

  @override
  String get transferReviewAction => 'Продовжити';

  @override
  String get transferConfirmAction => 'Переказати';

  @override
  String get transferEditAction => 'Змінити';

  @override
  String get transferAcceptedTitle => 'Переказ записано';

  @override
  String transferAcceptedBody(String fromAmount, String toAmount) {
    return '$fromAmount → $toAmount';
  }

  @override
  String get transferSecondWalletRequired =>
      'Для переказу потрібен другий гаманець в іншій валюті.';

  @override
  String get transferLoadError => 'Не вдалося завантажити рахунки.';

  @override
  String get transferWriteError => 'Не вдалося виконати переказ.';

  @override
  String get transferSameWalletError => 'Виберіть два різні гаманці.';

  @override
  String get transferIssueWalletUnavailable => 'Гаманець недоступний.';

  @override
  String get transferIssueCurrencyMismatch =>
      'Валюта суми не збігається з валютою гаманця.';

  @override
  String get transferIssueBeforeBaseline =>
      'Гроші не могли піти раніше, ніж з’явився гаманець.';

  @override
  String get transferIssueFutureDate => 'Дата переказу в майбутньому.';

  @override
  String get transferIssueConfirmationBeforeCapture =>
      'Підтвердження раніше за сам запис.';

  @override
  String get walletTitle => 'Новий гаманець';

  @override
  String get walletSettingsAction => 'Відкрити гаманець';

  @override
  String get walletSettingsDescription =>
      'Рахунок в іншій валюті — гроші не конвертуються';

  @override
  String get walletNameField => 'Назва';

  @override
  String get walletCurrencyField => 'Валюта';

  @override
  String get walletOpeningBalanceField => 'Скільки зараз на ньому';

  @override
  String get walletOpeningDateField => 'З якого числа';

  @override
  String get walletCurrencySearch => 'Пошук валюти';

  @override
  String get walletCurrencyHeld => 'Уже є';

  @override
  String get walletExplanation =>
      'Гроші між гаманцями не конвертуються. Кожен живе у своїй валюті, а переказ записується двома сумами.';

  @override
  String get walletReviewAction => 'Продовжити';

  @override
  String get walletConfirmAction => 'Відкрити';

  @override
  String get walletOpenedTitle => 'Гаманець відкрито';

  @override
  String get walletAccountRequired => 'Спочатку створіть основний рахунок.';

  @override
  String get walletLoadError => 'Не вдалося завантажити рахунки.';

  @override
  String get walletWriteError => 'Не вдалося відкрити гаманець.';

  @override
  String get operationWalletField => 'Гаманець';

  @override
  String get spokenSentenceKept =>
      'Фразу збережено на телефоні. Коли з’явиться інтернет, вона чекатиме на розбір тут і на головній — до 30 днів.';

  @override
  String get spokenSentenceNotKept =>
      'Цю фразу не вдалося зберегти. Скажіть її знову, коли з’явиться інтернет.';

  @override
  String entrySentenceSaidAt(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat(
      'd MMMM, HH:mm',
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return 'Сказано $dateString — дати рахуються від цього моменту';
  }

  @override
  String waitingPhrasesTitle(int count) {
    return 'Чекають на розбір: $count';
  }

  @override
  String get waitingPhrasesDescription =>
      'Сказано без інтернету. Натисніть фразу, щоб розібрати її; після розбору вона видаляється з телефона.';

  @override
  String get waitingPhraseHidden => 'Фразу приховано';

  @override
  String waitingPhraseSaidAt(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat(
      'd MMMM, HH:mm',
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return 'Сказано $dateString';
  }

  @override
  String get waitingPhraseForget => 'Видалити фразу';

  @override
  String get waitingPhrasesNoticeDescription =>
      'Сказано без інтернету — натисніть, щоб розібрати';

  @override
  String waitingPhrasesNoticeLabel(int count) {
    return 'Фрази, сказані без інтернету, чекають на розбір: $count. Відкрити';
  }

  @override
  String get languageFollowPhone => 'Як на телефоні';

  @override
  String get languageSettingDescription => 'Екрани й голосове введення';

  @override
  String currencyName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'EUR': 'Євро',
      'USD': 'Долар США',
      'UAH': 'Гривня',
      'GBP': 'Фунт стерлінгів',
      'PLN': 'Злотий',
      'CHF': 'Швейцарський франк',
      'CZK': 'Чеська крона',
      'SEK': 'Шведська крона',
      'NOK': 'Норвезька крона',
      'DKK': 'Данська крона',
      'HUF': 'Форинт',
      'RON': 'Румунський лей',
      'BGN': 'Болгарський лев',
      'RSD': 'Сербський динар',
      'ALL': 'Албанський лек',
      'MKD': 'Македонський денар',
      'BAM': 'Конвертована марка',
      'TRY': 'Турецька ліра',
      'MDL': 'Молдовський лей',
      'RUB': 'Російський рубль',
      'BYN': 'Білоруський рубль',
      'GEL': 'Ларі',
      'AMD': 'Вірменський драм',
      'AZN': 'Азербайджанський манат',
      'KZT': 'Теньге',
      'UZS': 'Узбецький сум',
      'KGS': 'Киргизький сом',
      'ILS': 'Шекель',
      'AED': 'Дирхам ОАЕ',
      'EGP': 'Єгипетський фунт',
      'INR': 'Індійська рупія',
      'CNY': 'Юань',
      'JPY': 'Єна',
      'KRW': 'Вона',
      'THB': 'Бат',
      'VND': 'Донг',
      'IDR': 'Індонезійська рупія',
      'SGD': 'Сінгапурський долар',
      'HKD': 'Гонконгський долар',
      'AUD': 'Австралійський долар',
      'NZD': 'Новозеландський долар',
      'CAD': 'Канадський долар',
      'MXN': 'Мексиканське песо',
      'BRL': 'Бразильський реал',
      'ARS': 'Аргентинське песо',
      'CLP': 'Чилійське песо',
      'ZAR': 'Південноафриканський ранд',
      'MAD': 'Марокканський дирхам',
      'TND': 'Туніський динар',
      'ISK': 'Ісландська крона',
      'other': '$code',
    });
    return '$_temp0';
  }

  @override
  String timezoneCity(String zone) {
    String _temp0 = intl.Intl.selectLogic(zone, {
      'Europe_Lisbon': 'Лісабон',
      'Europe_Dublin': 'Дублін',
      'Europe_London': 'Лондон',
      'Atlantic_Canary': 'Канарські острови',
      'Europe_Madrid': 'Мадрид',
      'Europe_Paris': 'Париж',
      'Europe_Brussels': 'Брюссель',
      'Europe_Amsterdam': 'Амстердам',
      'Europe_Berlin': 'Берлін',
      'Europe_Zurich': 'Цюрих',
      'Europe_Vienna': 'Відень',
      'Europe_Prague': 'Прага',
      'Europe_Rome': 'Рим',
      'Europe_Warsaw': 'Варшава',
      'Europe_Budapest': 'Будапешт',
      'Europe_Stockholm': 'Стокгольм',
      'Europe_Oslo': 'Осло',
      'Europe_Copenhagen': 'Копенгаген',
      'Europe_Belgrade': 'Белград',
      'Europe_Zagreb': 'Загреб',
      'Europe_Ljubljana': 'Любляна',
      'Europe_Bratislava': 'Братислава',
      'Europe_Athens': 'Афіни',
      'Europe_Bucharest': 'Бухарест',
      'Europe_Sofia': 'Софія',
      'Europe_Helsinki': 'Гельсінкі',
      'Europe_Tallinn': 'Таллінн',
      'Europe_Riga': 'Рига',
      'Europe_Vilnius': 'Вільнюс',
      'Europe_Kyiv': 'Київ',
      'Europe_Chisinau': 'Кишинів',
      'Europe_Minsk': 'Мінськ',
      'Europe_Istanbul': 'Стамбул',
      'Europe_Moscow': 'Москва',
      'Asia_Tbilisi': 'Тбілісі',
      'Asia_Yerevan': 'Єреван',
      'Asia_Baku': 'Баку',
      'Asia_Nicosia': 'Нікосія',
      'Asia_Jerusalem': 'Єрусалим',
      'Asia_Dubai': 'Дубай',
      'Asia_Tashkent': 'Ташкент',
      'Asia_Almaty': 'Алмати',
      'Asia_Bishkek': 'Бішкек',
      'Asia_Bangkok': 'Бангкок',
      'Asia_Singapore': 'Сінгапур',
      'Asia_Hong_Kong': 'Гонконг',
      'Asia_Shanghai': 'Шанхай',
      'Asia_Seoul': 'Сеул',
      'Asia_Tokyo': 'Токіо',
      'Australia_Perth': 'Перт',
      'Australia_Sydney': 'Сідней',
      'Pacific_Auckland': 'Окленд',
      'Africa_Cairo': 'Каїр',
      'Africa_Johannesburg': 'Йоганнесбург',
      'America_Sao_Paulo': 'Сан-Паулу',
      'America_Argentina_Buenos_Aires': 'Буенос-Айрес',
      'America_New_York': 'Нью-Йорк',
      'America_Toronto': 'Торонто',
      'America_Chicago': 'Чикаго',
      'America_Denver': 'Денвер',
      'America_Los_Angeles': 'Лос-Анджелес',
      'America_Mexico_City': 'Мехіко',
      'other': 'UTC',
    });
    return '$_temp0';
  }
}
