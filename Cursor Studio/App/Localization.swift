import Foundation

nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case russian

    static let defaultsKey = "appLanguage"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: L10n.systemDefault
        case .english: "English"
        case .russian: "Русский"
        }
    }

    static var selected: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }
        return language
    }

    static let runtime = selected.resolved

    var resolved: AppLanguage {
        guard self == .system else { return self }
        return Locale.current.language.languageCode?.identifier == "ru"
            ? .russian
            : .english
    }
}

nonisolated enum L10n {
    private static let launchedLanguage = AppLanguage.runtime

    private static var isRussian: Bool {
        launchedLanguage == .russian
    }

    static func text(_ english: String, _ russian: String) -> String {
        isRussian ? russian : english
    }

    static let ok = text("OK", "ОК")
    static let cancel = text("Cancel", "Отмена")
    static let done = text("Done", "Готово")
    static let retry = text("Retry", "Повторить")
    static let remove = text("Remove", "Удалить")
    static let settings = text("Settings", "Настройки")
    static let active = text("Active", "Активна")
    static let systemDefault = text("System Default", "Как в системе")
    static let english = "English"
    static let russian = "Русский"

    static let noThemeSelected = text("No Theme Selected", "Тема не выбрана")
    static let noThemeSelectedDetail = text(
        "Create a theme to begin importing cursor images.",
        "Создайте тему, чтобы начать импорт изображений курсоров."
    )
    static let createTheme = text("Create Theme", "Создать тему")
    static let addTheme = text("Add Theme", "Добавить тему")
    static let themes = text("Themes", "Темы")
    static let library = text("Library", "Библиотека")
    static let marketplace = text("Marketplace", "Маркетплейс")
    static let importAction = text("Import", "Импортировать")
    static let importTheme = text("Import Theme", "Импортировать тему")
    static let importCursorImage = text(
        "Import Cursor Image…",
        "Импортировать изображение курсора…"
    )
    static let importHelp = text(
        "Import PNG, SVG, Mousecape, or Windows cursor themes",
        "Импортировать PNG, SVG, Mousecape или темы курсоров Windows"
    )
    static let apply = text("Apply", "Применить")
    static let applyTheme = text("Apply Theme", "Применить тему")
    static let applyHelp = text("Apply selected theme", "Применить выбранную тему")
    static let duplicate = text("Duplicate", "Дублировать")
    static let duplicateTheme = text("Duplicate Theme", "Дублировать тему")
    static let duplicateHelp = text(
        "Duplicate selected theme",
        "Создать копию выбранной темы"
    )
    static let restoreMacOSCursor = text(
        "Restore macOS Cursor",
        "Восстановить курсор macOS"
    )
    static let restoreHelp = text(
        "Restore the default macOS cursor",
        "Восстановить стандартный курсор macOS"
    )
    static let delete = text("Delete", "Удалить")
    static let deleteTheme = text("Delete Theme", "Удалить тему")
    static let deleteThemeQuestion = text(
        "Delete this theme?",
        "Удалить эту тему?"
    )
    static let deleteThemeDetail = text(
        "Its copied cursor assets will be removed from Application Support.",
        "Скопированные файлы курсоров будут удалены из Application Support."
    )
    static let themeName = text("Theme name", "Название темы")
    static let activeThemeHelp = text("Active theme", "Активная тема")
    static let configureRolesDetail = text(
        "Configure any subset of roles; missing roles keep the macOS default.",
        "Настройте любые роли; для отсутствующих останется стандартный курсор macOS."
    )
    static let by = text("by", "автор:")
    static let dropPNGHere = text("Drop a PNG here", "Перетащите PNG сюда")
    static let configured = text("configured", "настроен")
    static let notConfigured = text("not configured", "не настроен")
    static let cursorCardAccessibilityHint = text(
        "Select to edit. You can also drop an image, Mousecape theme, or Windows cursor theme here.",
        "Выберите для редактирования. Сюда также можно перетащить изображение, тему Mousecape или тему курсоров Windows."
    )
    static let replacePNG = text("Replace PNG…", "Заменить PNG…")
    static let noCursorImage = text("No Cursor Image", "Нет изображения курсора")
    static let noCursorImageDetail = text(
        "Import a transparent PNG for this cursor role.",
        "Импортируйте PNG с прозрачностью для этой роли курсора."
    )
    static let importPNG = text("Import PNG…", "Импортировать PNG…")
    static let firstFrameUsed = text(
        "The first frame is used.",
        "Используется первый кадр."
    )
    static let hotspot = text("Hotspot", "Активная точка")
    static let hotspotEditor = text(
        "Hotspot editor",
        "Редактор активной точки"
    )
    static let hotspotEditorHint = text(
        "Click the cursor image to set its active point.",
        "Нажмите на изображение курсора, чтобы задать его активную точку."
    )
    static let position = text("Position", "Позиция")
    static let image = text("Image", "Изображение")
    static let approximateActualSize = text(
        "Approximate actual size",
        "Приблизительный реальный размер"
    )
    static let accessibilityScalingDetail = text(
        "The system may scale cursors with Accessibility settings.",
        "Система может масштабировать курсоры согласно настройкам универсального доступа."
    )

    static let reviewMousecapeTheme = text(
        "Review Mousecape Theme",
        "Проверка темы Mousecape"
    )
    static let reviewImportedTheme = text(
        "Review Imported Theme",
        "Проверка импортируемой темы"
    )
    static let mapped = text("Mapped", "Сопоставлено")
    static let unassigned = text("Unassigned", "Не назначено")
    static let missing = text("Missing", "Отсутствует")
    static let animated = text("Animated", "Анимировано")
    static let warnings = text("Warnings", "Предупреждения")
    static let staticFallback = text(
        "Static fallback",
        "Статический вариант"
    )
    static let staticCursor = text("Static", "Статический")
    static let mappedCursorRoles = text(
        "Mapped cursor roles",
        "Сопоставленные роли курсоров"
    )
    static let mousecapeCursor = text("Mousecape cursor", "Курсор Mousecape")
    static let sourceCursor = text("Source cursor", "Исходный курсор")
    static let importedAsStaticFirstFrame = text(
        "Imported as a static first frame",
        "Импортирован как статический первый кадр"
    )
    static let unassignedSourceCursors = text(
        "Unassigned source cursors",
        "Неназначенные исходные курсоры"
    )
    static let unassignedSourceDetail = text(
        "These images and their metadata will be preserved in the theme, but they are not applied until Cursor Studio has a matching role.",
        "Изображения и метаданные будут сохранены в теме, но не будут применяться, пока в Cursor Studio не появится соответствующая роль."
    )
    static let importNotes = text("Import notes", "Примечания к импорту")

    static let privacyAndCompatibility = text(
        "Privacy & Compatibility",
        "Конфиденциальность и совместимость"
    )
    static let privacy = text("Privacy", "Конфиденциальность")
    static let compatibility = text("Compatibility", "Совместимость")
    static let privateLocalThemes = text(
        "Private, local cursor themes for macOS",
        "Локальные и конфиденциальные темы курсоров для macOS"
    )
    static let everythingStaysLocal = text(
        "Everything stays on this Mac",
        "Всё остаётся на этом Mac"
    )
    static let noImagesLeaveMac = text(
        "No cursor images leave your Mac.",
        "Изображения курсоров не покидают ваш Mac."
    )
    static let noAnalytics = text("No analytics", "Без аналитики")
    static let noAnalyticsDetail = text(
        "Cursor Studio does not collect usage or diagnostic data.",
        "Cursor Studio не собирает данные об использовании или диагностике."
    )
    static let noAccount = text("No account", "Без учётной записи")
    static let noAccountDetail = text(
        "No sign-in, cloud service, or network connection is required.",
        "Для локальной библиотеки не нужны вход, облачный сервис или подключение к сети."
    )
    static let privacySummary = text(
        "Cursor Studio works locally on this Mac. Cursor images are uploaded only when you explicitly publish a theme to Marketplace. No analytics are collected.",
        "Cursor Studio работает локально на этом Mac. Изображения курсоров загружаются только при явной публикации темы в Маркетплейсе. Аналитика не собирается."
    )
    static let compatibilityNotice = text(
        "Cursor Studio uses an unsupported private macOS cursor mechanism. Apple may change it in a future macOS release, so compatibility is not guaranteed.",
        "Cursor Studio использует неподдерживаемый закрытый механизм курсоров macOS. Apple может изменить его в будущей версии macOS, поэтому совместимость не гарантируется."
    )
    static let showDiagnosticLog = text(
        "Show Diagnostic Log",
        "Показать журнал диагностики"
    )

    static let settingsGeneral = text("General", "Основные")
    static let settingsCursor = text("Cursor", "Курсор")
    static let settingsMarketplace = text("Marketplace", "Маркетплейс")
    static let settingsAbout = text("About", "О приложении")
    static let language = text("Language", "Язык")
    static let languageRestartRequired = text(
        "Restart Cursor Studio to apply the new language.",
        "Перезапустите Cursor Studio, чтобы применить новый язык."
    )
    static let launchAtLogin = text(
        "Launch at login",
        "Запускать при входе в систему"
    )
    static let keepCursorActive = text(
        "Keep cursor active when the window is closed",
        "Сохранять курсор активным после закрытия окна"
    )
    static let keepCursorActiveAfterAppQuit = text(
        "Keep cursor active after quitting Cursor Studio",
        "Не сбрасывать курсор после выхода из Cursor Studio"
    )
    static let keepCursorActiveAfterAppQuitDetail = text(
        "WindowServer keeps the cursor active after the app exits. Enable “Launch at login” to reapply the theme after restarting your Mac.",
        "После выхода курсор продолжит работать через WindowServer. Включите «Запускать при входе в систему», чтобы тема применялась снова после перезагрузки Mac."
    )
    static let confirmBeforeDeleting = text(
        "Confirm before deleting a theme",
        "Подтверждать удаление темы"
    )
    static let activeTheme = text("Active theme", "Активная тема")
    static let noActiveTheme = text("System cursor", "Системный курсор")
    static let reapplyNow = text("Reapply Now", "Применить снова")
    static let restoreNow = text("Restore Now", "Восстановить")
    static let autoRecoverCursor = text(
        "Recover after sleep and display changes",
        "Восстанавливать после сна и изменений дисплея"
    )
    static let cursorCompatibilityTitle = text(
        "Compatibility & Recovery",
        "Совместимость и восстановление"
    )
    static let marketplaceAccount = text("Account", "Учётная запись")
    static let signIn = text("Sign In", "Войти")
    static let signOut = text("Sign Out", "Выйти")
    static let createAccount = text("Create Account", "Создать аккаунт")
    static let openCreatorCenter = text(
        "Open Creator Center",
        "Открыть кабинет автора"
    )
    static let creatorCenter = text("Creator Center", "Кабинет автора")
    static let marketplaceWelcome = text(
        "Join Cursor Studio Marketplace",
        "Присоединяйтесь к Маркетплейсу Cursor Studio"
    )
    static let accountNeededForPublishing = text(
        "Sign in to manage your public profile and publish cursor themes.",
        "Войдите, чтобы управлять публичным профилем и публиковать темы курсоров."
    )
    static let restoringSession = text(
        "Restoring your session…",
        "Восстановление сеанса…"
    )
    static let email = text("Email", "Электронная почта")
    static let password = text("Password", "Пароль")
    static let creatorHandle = text("Creator handle", "Имя автора")
    static let displayName = text("Display name", "Отображаемое имя")
    static let credentialsHandledBySupabase = text(
        "Authentication is handled by Supabase. Cursor Studio stores session tokens in your Mac keychain.",
        "Авторизация выполняется через Supabase. Cursor Studio хранит токены сеанса в Связке ключей Mac."
    )
    static let profile = text("Profile", "Профиль")
    static let publicProfile = text("Public profile", "Публичный профиль")
    static let bio = text("Bio", "О себе")
    static let saveProfile = text("Save Profile", "Сохранить профиль")
    static let moderatorAccount = text(
        "Marketplace moderator",
        "Модератор Маркетплейса"
    )
    static let publish = text("Publish", "Публикация")
    static let mySubmissions = text("My Submissions", "Мои заявки")
    static let moderation = text("Moderation", "Модерация")
    static let close = text("Close", "Закрыть")
    static let localTheme = text("Local theme", "Локальная тема")
    static let theme = text("Theme", "Тема")
    static let marketplaceListing = text(
        "Marketplace listing",
        "Карточка в Маркетплейсе"
    )
    static let titleEnglish = text(
        "Title in English",
        "Название на английском"
    )
    static let titleRussianOptional = text(
        "Title in Russian (optional)",
        "Название на русском (необязательно)"
    )
    static let descriptionEnglish = text(
        "Description in English",
        "Описание на английском"
    )
    static let descriptionRussianOptional = text(
        "Description in Russian (optional)",
        "Описание на русском (необязательно)"
    )
    static let selectCategory = text(
        "Select a category",
        "Выберите категорию"
    )
    static let semanticVersion = text(
        "Version (for example, 1.0.0)",
        "Версия (например, 1.0.0)"
    )
    static let acceptCreatorGuidelines = text(
        "I confirm that I own the rights to publish this theme",
        "Я подтверждаю, что имею права на публикацию этой темы"
    )
    static let publishUploadNotice = text(
        "Submitting uploads the selected cursor images, generated preview, and package to Supabase for moderation.",
        "При отправке выбранные изображения курсоров, превью и пакет загружаются в Supabase для модерации."
    )
    static let submitForReview = text(
        "Submit for Review",
        "Отправить на проверку"
    )
    static let noMarketplaceCategories = text(
        "No categories are configured. Apply the category seed migration before publishing.",
        "Категории не настроены. Перед публикацией примените миграцию с начальными категориями."
    )
    static let noSubmissions = text("No Submissions", "Заявок пока нет")
    static let noSubmissionsDetail = text(
        "Publish a local theme to send it to Marketplace moderation.",
        "Опубликуйте локальную тему, чтобы отправить её на модерацию Маркетплейса."
    )
    static let refresh = text("Refresh", "Обновить")
    static let reviewQueue = text("Review Queue", "Очередь проверки")
    static let moderationQueueEmpty = text(
        "The moderation queue is empty",
        "Очередь модерации пуста"
    )
    static let review = text("Review", "Проверить")
    static let moderators = text("Moderators", "Модераторы")
    static let moderatorHandle = text(
        "Creator handle",
        "Имя автора"
    )
    static let addModerator = text(
        "Add Moderator",
        "Добавить модератора"
    )
    static let moderationNote = text(
        "Moderation note",
        "Комментарий модератора"
    )
    static let themePreview = text("Theme preview", "Предпросмотр темы")
    static let testThemeOnMac = text(
        "Preview and test",
        "Предпросмотр и тест"
    )
    static let startThemeTest = text(
        "Test on This Mac",
        "Проверить на этом Mac"
    )
    static let stopThemeTest = text("Stop Test", "Завершить тест")
    static let themeTestRequired = text(
        "Apply the validated package temporarily and inspect every cursor before approval.",
        "Временно примените проверенный пакет и осмотрите курсоры перед одобрением."
    )
    static let themeTestActiveDetail = text(
        "The submitted theme is active temporarily. Stop the test to restore your previous cursor.",
        "Отправленная тема временно активна. Завершите тест, чтобы вернуть предыдущий курсор."
    )
    static let preparingThemeTest = text(
        "Preparing moderator preview…",
        "Подготовка предпросмотра для модератора…"
    )
    static let themeTestActive = text(
        "Moderator theme test is active",
        "Тест темы для модератора активен"
    )
    static let themeTestStopped = text(
        "Theme test stopped; previous cursor restored",
        "Тест завершён; предыдущий курсор восстановлен"
    )
    static let themeTestFailed = text(
        "Theme Test Failed",
        "Ошибка теста темы"
    )
    static let themeTestRestoreFailed = text(
        "Couldn’t Restore Cursor After Test",
        "Не удалось восстановить курсор после теста"
    )
    static let reject = text("Reject", "Отклонить")
    static let approve = text("Approve & Publish", "Одобрить и опубликовать")
    static let reviewDraft = text("Draft", "Черновик")
    static let reviewPending = text("In review", "На проверке")
    static let reviewApproved = text("Published", "Опубликовано")
    static let reviewRejected = text("Rejected", "Отклонено")
    static let marketplaceError = text(
        "Marketplace Error",
        "Ошибка Маркетплейса"
    )
    static let marketplaceBackendUnavailable = text(
        "Marketplace backend is not configured.",
        "Серверная часть Маркетплейса не настроена."
    )
    static let authenticationRequired = text(
        "Sign in to continue.",
        "Чтобы продолжить, выполните вход."
    )
    static let invalidCredentials = text(
        "The email or password is incorrect.",
        "Неверный адрес электронной почты или пароль."
    )
    static let emailConfirmationRequired = text(
        "Confirm your email address before signing in.",
        "Подтвердите адрес электронной почты перед входом."
    )
    static let marketplaceInvalidResponse = text(
        "Marketplace returned an invalid response.",
        "Маркетплейс вернул некорректный ответ."
    )
    static let marketplaceInvalidRequest = text(
        "The Marketplace request could not be prepared.",
        "Не удалось подготовить запрос к Маркетплейсу."
    )
    static let keychainUnavailable = text(
        "The session could not be saved in Keychain.",
        "Не удалось сохранить сеанс в Связке ключей."
    )
    static let registrationFieldsInvalid = text(
        "Enter a valid email, a password of at least 8 characters, a 3–32 character handle, and a display name.",
        "Укажите корректную почту, пароль от 8 символов, имя автора длиной 3–32 символа и отображаемое имя."
    )
    static let profileFieldsInvalid = text(
        "Check the creator handle, display name, and bio length.",
        "Проверьте имя автора, отображаемое имя и длину описания."
    )
    static let publicationFieldsInvalid = text(
        "Complete the English title and description and enter a valid semantic version.",
        "Заполните английские название и описание и укажите корректную семантическую версию."
    )
    static let publishThemeNeedsCursor = text(
        "Add at least one cursor before publishing.",
        "Перед публикацией добавьте хотя бы один курсор."
    )
    static let publishThemeNeedsPreview = text(
        "The theme needs a valid PNG preview.",
        "Для темы требуется корректное PNG-превью."
    )
    static let publishOnlyPNG = text(
        "Only single-frame PNG cursor assets can be published.",
        "Можно публиковать только однокадровые PNG-файлы курсоров."
    )
    static let publishPackageCreationFailed = text(
        "The theme package could not be created.",
        "Не удалось создать пакет темы."
    )
    static let storageUploadFailed = text(
        "A Marketplace file could not be uploaded.",
        "Не удалось загрузить файл Маркетплейса."
    )
    static let storageCleanupFailed = text(
        "An incomplete Marketplace upload could not be removed.",
        "Не удалось удалить незавершённую загрузку Маркетплейса."
    )
    static let moderationPackageUnavailable = text(
        "The submitted package could not be downloaded for validation.",
        "Не удалось загрузить отправленный пакет для проверки."
    )
    static let moderationPackageMismatch = text(
        "The package manifest does not match the submitted theme or version.",
        "Манифест пакета не соответствует отправленной теме или версии."
    )
    static let moderatorHandleRequired = text(
        "Enter the creator handle.",
        "Введите имя автора."
    )
    static let signedInSuccessfully = text(
        "Signed in successfully.",
        "Вход выполнен."
    )
    static let accountCreated = text(
        "Account created.",
        "Аккаунт создан."
    )
    static let signedOutSuccessfully = text(
        "Signed out.",
        "Вы вышли из аккаунта."
    )
    static let profileSaved = text(
        "Profile saved.",
        "Профиль сохранён."
    )
    static let themeSubmittedForReview = text(
        "Theme submitted for review.",
        "Тема отправлена на проверку."
    )
    static let themeApproved = text(
        "Theme approved and published.",
        "Тема одобрена и опубликована."
    )
    static let themeRejected = text(
        "Theme rejected.",
        "Тема отклонена."
    )
    static let moderatorAdded = text(
        "Moderator added.",
        "Модератор добавлен."
    )
    static let moderatorRemoved = text(
        "Moderator removed.",
        "Модератор удалён."
    )
    static let notSignedIn = text("Not signed in", "Вход не выполнен")
    static let marketplaceAccountOptional = text(
        "An account is optional and only needed for favorites, reports, and publishing.",
        "Учётная запись необязательна и нужна только для избранного, жалоб и публикации."
    )
    static let automaticUpdates = text(
        "Automatically update installed themes",
        "Автоматически обновлять установленные темы"
    )
    static let contentLanguage = text("Content language", "Язык контента")
    static let verifiedOnly = text(
        "Show verified themes only",
        "Показывать только проверенные темы"
    )
    static let comingAfterBackend = text(
        "Available after the Marketplace backend is configured.",
        "Станет доступно после настройки серверной части Маркетплейса."
    )
    static let showOnboarding = text(
        "Show Welcome Guide",
        "Показать вводное руководство"
    )
    static let version = text("Version", "Версия")
    static let build = text("Build", "Сборка")
    static let macOSRequirement = text("Requires macOS 15 or later", "Требуется macOS 15 или новее")
    static let website = text("Website", "Веб-сайт")
    static let support = text("Support", "Поддержка")
    static let licenses = text("Licenses", "Лицензии")
    static let acknowledgements = text(
        "Open-Source Licenses",
        "Лицензии открытого ПО"
    )
    static let noThirdPartyLibraries = text(
        "Cursor Studio currently includes no third-party runtime libraries.",
        "Сейчас Cursor Studio не включает сторонние библиотеки времени выполнения."
    )
    static let copySuffix = text("Copy", "Копия")

    static let onboardingWelcomeTitle = text(
        "Welcome to Cursor Studio",
        "Добро пожаловать в Cursor Studio"
    )
    static let onboardingWelcomeDetail = text(
        "Create and manage cursor themes while keeping your local library on this Mac.",
        "Создавайте темы курсоров и управляйте ими, сохраняя локальную библиотеку на этом Mac."
    )
    static let onboardingImportTitle = text(
        "Import Your Cursors",
        "Импортируйте курсоры"
    )
    static let onboardingImportDetail = text(
        "Drop transparent PNG files into roles, or import Mousecape and Windows cursor themes.",
        "Перетаскивайте PNG с прозрачностью в роли или импортируйте темы курсоров Mousecape и Windows."
    )
    static let onboardingApplyTitle = text(
        "Apply and Restore Safely",
        "Применяйте и восстанавливайте безопасно"
    )
    static let onboardingApplyDetail = text(
        "Apply a theme with one click. Restore the standard macOS cursor at any time.",
        "Применяйте тему одним нажатием. Стандартный курсор macOS можно вернуть в любой момент."
    )
    static let onboardingMarketplaceTitle = text(
        "Discover Marketplace",
        "Откройте Маркетплейс"
    )
    static let onboardingMarketplaceDetail = text(
        "Browse compatible themes without an account. The local library remains fully available offline.",
        "Просматривайте совместимые темы без учётной записи. Локальная библиотека полностью доступна офлайн."
    )
    static let back = text("Back", "Назад")
    static let next = text("Next", "Далее")
    static let startUsing = text("Start Using Cursor Studio", "Начать работу")
    static let onboardingPage = text("Welcome guide page", "Страница вводного руководства")

    static let searchThemes = text("Search themes", "Поиск тем")
    static let searchLibrary = text(
        "Search library",
        "Поиск в библиотеке"
    )
    static let noMatchingThemes = text(
        "No matching themes",
        "Подходящих тем нет"
    )
    static let featured = text("Featured", "Рекомендуемые")
    static let recent = text("Recent", "Новые")
    static let popular = text("Popular", "Популярные")
    static let allCategories = text("All Categories", "Все категории")
    static let searchResults = text("Search Results", "Результаты поиска")
    static func marketplaceThemeCount(_ count: Int) -> String {
        if isRussian {
            let noun = russianForm(
                count,
                one: "тема",
                few: "темы",
                many: "тем"
            )
            return "\(count) \(noun)"
        }
        return count == 1 ? "1 theme" : "\(count) themes"
    }
    static let verified = text("Verified", "Проверено")
    static let compatible = text("Compatible", "Совместимо")
    static let incompatible = text("Incompatible", "Несовместимо")
    static let compatibilityUnknown = text("Compatibility unknown", "Совместимость неизвестна")
    static let download = text("Download", "Загрузить")
    static let install = text("Install", "Установить")
    static let installed = text("Installed", "Установлено")
    static let installing = text("Installing…", "Установка…")
    static let cancelDownload = text("Cancel Download", "Отменить загрузку")
    static let marketplaceOfflineTitle = text(
        "Marketplace Is Offline",
        "Маркетплейс недоступен"
    )
    static let marketplaceOfflineDetail = text(
        "Cached themes remain available. Check your connection and try again.",
        "Кэшированные темы остаются доступными. Проверьте подключение и повторите попытку."
    )
    static let marketplaceEmptyTitle = text(
        "No Themes Found",
        "Темы не найдены"
    )
    static let marketplaceEmptyDetail = text(
        "Try another search or category.",
        "Попробуйте изменить запрос или категорию."
    )
    static let marketplaceNoPublishedThemesDetail = text(
        "The live catalog has no published themes yet. Submit a theme and approve it in the moderator queue.",
        "В реальном каталоге пока нет опубликованных тем. Отправьте тему и одобрите её в очереди модерации."
    )
    static let marketplaceMockNotice = text(
        "Preview catalog — Supabase is not configured",
        "Демонстрационный каталог — Supabase не настроен"
    )
    static let themeDetails = text("Theme Details", "Сведения о теме")
    static let creator = text("Creator", "Автор")
    static let category = text("Category", "Категория")
    static let downloads = text("Downloads", "Загрузки")
    static let packageValidationFailed = text(
        "The downloaded theme package failed security validation.",
        "Загруженный пакет темы не прошёл проверку безопасности."
    )
    static let marketplaceLoading = text(
        "Loading Marketplace…",
        "Загрузка Маркетплейса…"
    )
    static let marketplaceRetry = text(
        "Couldn’t Load Marketplace",
        "Не удалось загрузить Маркетплейс"
    )
    static let cachedResults = text(
        "Showing cached results",
        "Показаны данные из кэша"
    )
    static let liveCatalog = text(
        "Live catalog",
        "Актуальный каталог"
    )
    static let clearFilters = text(
        "Clear filters",
        "Сбросить фильтры"
    )
    static let viewDetails = text("View Details", "Подробнее")
    static let includedCursors = text("Included cursors", "Курсоры в комплекте")
    static let cursorPackPreview = text(
        "Cursor pack preview",
        "Предпросмотр курсоров из пака"
    )
    static let loadingCursorPreviews = text(
        "Loading and validating cursor previews…",
        "Загрузка и проверка предпросмотра курсоров…"
    )
    static let cursorPreviewUnavailable = text(
        "Cursor previews are unavailable.",
        "Предпросмотр курсоров недоступен."
    )
    static let installComplete = text(
        "Theme installed",
        "Тема установлена"
    )
    static let installationFailed = text(
        "Installation Failed",
        "Ошибка установки"
    )
    static let previewCatalog = text(
        "The built-in preview catalog works offline. Add public Supabase configuration to connect the live catalog.",
        "Встроенный демонстрационный каталог работает офлайн. Добавьте публичную конфигурацию Supabase для подключения реального каталога."
    )
    static let marketplaceSubtitle = text(
        "Discover safe cursor themes, with compatibility shown first.",
        "Находите безопасные темы курсоров — совместимость показана в первую очередь."
    )
    static let sort = text("Sort", "Сортировка")
    static let discover = text("Discover", "Обзор")
    static let marketplaceSidebarDetail = text(
        "Search, preview, and install compatible themes.",
        "Ищите, просматривайте и устанавливайте совместимые темы."
    )

    static let storageUnavailable = text("Storage Unavailable", "Хранилище недоступно")
    static let libraryRecovered = text("Library Recovered", "Библиотека восстановлена")
    static let newThemeCreated = text("New theme created", "Новая тема создана")
    static let couldNotCreateTheme = text("Couldn’t Create Theme", "Не удалось создать тему")
    static let couldNotRenameTheme = text("Couldn’t Rename Theme", "Не удалось переименовать тему")
    static let themeDuplicated = text("Theme duplicated", "Тема дублирована")
    static let couldNotDuplicateTheme = text("Couldn’t Duplicate Theme", "Не удалось дублировать тему")
    static let themeDeleted = text("Theme deleted", "Тема удалена")
    static let couldNotDeleteTheme = text("Couldn’t Delete Theme", "Не удалось удалить тему")
    static let importFailed = text("Import Failed", "Ошибка импорта")
    static let couldNotSaveHotspot = text("Couldn’t Save Hotspot", "Не удалось сохранить активную точку")
    static let couldNotRemoveCursor = text("Couldn’t Remove Cursor", "Не удалось удалить курсор")
    static let restoringCursor = text("Restoring macOS cursor…", "Восстановление курсора macOS…")
    static let cursorRestored = text("macOS cursor restored", "Курсор macOS восстановлен")
    static let restoreFailed = text("Restore failed", "Не удалось восстановить")
    static let restoreFailedTitle = text("Restore Failed", "Ошибка восстановления")
    static let logUnavailable = text("Log Unavailable", "Журнал недоступен")
    static let capeReadyForReview = text("Cape ready for review", "Тема .cape готова к проверке")
    static let capeImportFailed = text("Cape import failed", "Ошибка импорта .cape")
    static let themeReadyForReview = text(
        "Theme ready for review",
        "Тема готова к проверке"
    )
    static let themeImportFailed = text(
        "Theme import failed",
        "Ошибка импорта темы"
    )
    static let restoringAfterEdit = text(
        "Restoring macOS cursor after edit…",
        "Восстановление курсора macOS после изменения…"
    )
    static let couldNotDeactivateTheme = text(
        "Couldn’t Deactivate Theme",
        "Не удалось деактивировать тему"
    )
    static let themeApplied = text("Theme applied", "Тема применена")
    static let applyFailed = text("Apply failed", "Не удалось применить")
    static let applyFailedTitle = text("Apply Failed", "Ошибка применения")
    static let preferenceFailed = text(
        "Couldn’t Change Setting",
        "Не удалось изменить настройку"
    )
    static let untitledTheme = text("Untitled Theme", "Новая тема")
    static let importedCape = text("Imported Cape", "Импортированная тема")
    static let importedWindowsTheme = text(
        "Imported Windows Theme",
        "Импортированная тема Windows"
    )
    static let demoTheme = text("Monochrome Demo", "Монохромная демо-тема")

    static func cursorCount(_ count: Int) -> String {
        if !isRussian {
            return count == 1 ? "\(count) cursor" : "\(count) cursors"
        }
        return "\(count) \(russianForm(count, one: "курсор", few: "курсора", many: "курсоров"))"
    }

    static func cursorCount(_ count: Int, total: Int) -> String {
        text(
            "\(count) of \(total) \(total == 1 ? "cursor" : "cursors")",
            "\(count) из \(total) \(russianForm(total, one: "курсора", few: "курсоров", many: "курсоров"))"
        )
    }

    static func frameCount(_ count: Int) -> String {
        if !isRussian {
            return count == 1 ? "\(count) frame" : "\(count) frames"
        }
        return "\(count) \(russianForm(count, one: "кадр", few: "кадра", many: "кадров"))"
    }

    static func animatedCursorCount(_ count: Int) -> String {
        if !isRussian {
            return count == 1 ? "\(count) animated" : "\(count) animated"
        }
        return "\(count) аним."
    }

    static func staticFallbackCount(_ count: Int) -> String {
        text(
            count == 1 ? "1 static fallback" : "\(count) static fallbacks",
            "\(count) статич."
        )
    }

    static func importNoteCount(_ count: Int) -> String {
        if !isRussian {
            return count == 1 ? "1 import note" : "\(count) import notes"
        }
        return "\(count) \(russianForm(count, one: "примечание", few: "примечания", many: "примечаний")) к импорту"
    }

    static func downloadCount(_ count: Int) -> String {
        if !isRussian {
            return count == 1 ? "1 download" : "\(count) downloads"
        }
        return "\(count) \(russianForm(count, one: "загрузка", few: "загрузки", many: "загрузок"))"
    }

    static func confirmEmail(_ email: String) -> String {
        text(
            "Check \(email) and confirm your address, then sign in.",
            "Проверьте \(email), подтвердите адрес, затем выполните вход."
        )
    }

    static func publishMissingAsset(_ filename: String) -> String {
        text(
            "The cursor asset \(filename) is missing.",
            "Файл курсора \(filename) отсутствует."
        )
    }

    static func marketplaceRequestFailed(_ statusCode: Int) -> String {
        text(
            "Marketplace request failed (HTTP \(statusCode)).",
            "Ошибка запроса к Маркетплейсу (HTTP \(statusCode))."
        )
    }

    static func byAuthor(_ author: String) -> String {
        text("by \(author)", "автор: \(author)")
    }

    static func pixelSize(width: Int, height: Int) -> String {
        "\(width) × \(height) px"
    }

    static func frameDuration(_ seconds: String) -> String {
        text("Frame duration: \(seconds) seconds", "Длительность кадра: \(seconds) с")
    }

    static let livePreview = text("Live preview", "Живой предпросмотр")

    static func animationHelp(frameCount: Int, fallback: Bool) -> String {
        fallback
            ? text(
                "Static fallback for \(frameCount)-frame animation",
                "Статический вариант анимации из \(frameCount) кадров"
            )
            : text(
                "\(frameCount)-frame animation",
                "Анимация из \(frameCount) кадров"
            )
    }

    static func importedRole(_ role: String) -> String {
        text("\(role) imported", "\(role): импорт завершён")
    }

    static func removedRole(_ role: String) -> String {
        text("\(role) removed", "\(role): удалён")
    }

    static func importedRoles(_ count: Int, theme: String) -> String {
        text(
            "Imported \(count) cursor \(count == 1 ? "role" : "roles") from \(theme)",
            "Из темы «\(theme)» импортировано \(count) \(russianForm(count, one: "роль курсора", few: "роли курсоров", many: "ролей курсоров"))"
        )
    }

    static func reading(_ filename: String) -> String {
        text("Reading \(filename)…", "Чтение \(filename)…")
    }

    static func applying(_ theme: String) -> String {
        text("Applying \(theme)…", "Применение темы «\(theme)»…")
    }

    static func themeIsActive(_ theme: String) -> String {
        text("\(theme) is active", "Тема «\(theme)» активна")
    }

    static func cursorAccessibility(role: String, configured: Bool) -> String {
        "\(role), \(configured ? self.configured : self.notConfigured)"
    }

    static func animationFramesHelp(_ count: Int) -> String {
        text(
            "\(count) animation \(count == 1 ? "frame" : "frames")",
            "\(count) \(russianForm(count, one: "кадр", few: "кадра", many: "кадров")) анимации"
        )
    }

    static func settingError(_ reason: String) -> String {
        text("The setting could not be changed. \(reason)", "Не удалось изменить настройку. \(reason)")
    }

    static func roleName(_ role: CursorRole) -> String {
        switch role {
        case .arrow: text("Arrow", "Стрелка")
        case .pointingHand: text("Pointing Hand", "Указующая рука")
        case .iBeam: text("I-Beam", "Текстовый курсор")
        case .crosshair: text("Crosshair", "Перекрестие")
        case .openHand: text("Open Hand", "Открытая рука")
        case .closedHand: text("Closed Hand", "Закрытая рука")
        case .resizeLeftRight: text("Resize Left–Right", "Изменение ширины")
        case .resizeUpDown: text("Resize Up–Down", "Изменение высоты")
        case .resizeDiagonalNWSE: text("Resize NW–SE", "Размер по диагонали СЗ–ЮВ")
        case .resizeDiagonalNESW: text("Resize NE–SW", "Размер по диагонали СВ–ЮЗ")
        case .operationNotAllowed: text("Operation Not Allowed", "Действие запрещено")
        case .help: text("Help", "Справка")
        case .contextualMenu: text("Contextual Menu", "Контекстное меню")
        case .dragCopy: text("Drag Copy", "Перетаскивание с копированием")
        case .dragLink: text("Drag Link", "Перетаскивание ссылки")
        case .progress: text("Progress", "Выполнение")
        case .busy: text("Busy", "Ожидание")
        }
    }

    static func errorDescription(_ error: CursorStudioError) -> String {
        switch error {
        case .unsupportedOS(let version):
            text(
                "This build does not support macOS \(version). Cursor Studio requires macOS 15 or later.",
                "Эта сборка не поддерживает macOS \(version). Для Cursor Studio требуется macOS 15 или новее."
            )
        case .privateAPIUnavailable(let symbol):
            text(
                "The private macOS cursor API “\(symbol)” is unavailable on this system.",
                "Закрытый API курсоров macOS «\(symbol)» недоступен в этой системе."
            )
        case .invalidImage:
            text("That file is not a readable PNG image.", "Этот файл не является читаемым изображением PNG.")
        case .unsupportedSVG:
            text(
                "SVG import is not available in this build. Please export the artwork as a transparent PNG.",
                "Импорт SVG недоступен в этой сборке. Экспортируйте изображение в PNG с прозрачностью."
            )
        case .impossibleHotspot:
            text(
                "The hotspot cannot be placed outside the cursor image.",
                "Активная точка не может находиться за пределами изображения курсора."
            )
        case .missingThemeAsset(let filename):
            text("The theme asset “\(filename)” is missing.", "Файл темы «\(filename)» отсутствует.")
        case .applicationFailed(let reason):
            text("The cursor theme could not be applied. \(reason)", "Не удалось применить тему курсоров. \(reason)")
        case .restorationFailed(let reason):
            text("The macOS cursor could not be restored. \(reason)", "Не удалось восстановить курсор macOS. \(reason)")
        case .corruptedDatabase:
            text(
                "The theme library was damaged. Cursor Studio created a clean library and preserved the damaged file for diagnostics.",
                "Библиотека тем была повреждена. Cursor Studio создала новую библиотеку и сохранила повреждённый файл для диагностики."
            )
        case .filePermission(let path):
            text(
                "Cursor Studio could not read or write “\(path)”. Check file permissions and try again.",
                "Cursor Studio не удалось прочитать или записать «\(path)». Проверьте права доступа и повторите попытку."
            )
        case .themeNotFound:
            text("The selected theme no longer exists.", "Выбранная тема больше не существует.")
        case .emptyTheme:
            text(
                "Add at least one cursor image before applying this theme.",
                "Добавьте хотя бы одно изображение курсора перед применением темы."
            )
        case .invalidCape(let reason):
            text(
                "That file is not a valid Mousecape theme. \(reason)",
                "Этот файл не является корректной темой Mousecape. \(localizedCapeReason(reason))"
            )
        case .unsupportedCapeStructure:
            text(
                "This .cape uses an unsupported archive or property-list structure.",
                "В этом файле .cape используется неподдерживаемая структура архива или property list."
            )
        case .capeMissingCursorEntries:
            text(
                "The .cape does not contain any usable cursor entries.",
                "Файл .cape не содержит пригодных записей курсоров."
            )
        case .corruptedCapeImage(let identifier):
            text(
                "The cursor image for “\(identifier)” is missing or corrupted.",
                "Изображение курсора «\(identifier)» отсутствует или повреждено."
            )
        case .invalidCapeHotspot(let identifier):
            text(
                "The hotspot for “\(identifier)” is outside its image bounds.",
                "Активная точка «\(identifier)» находится за пределами изображения."
            )
        case .unsupportedCapeAnimation(let identifier):
            text(
                "The animation for “\(identifier)” is unsupported; its first frame can still be imported.",
                "Анимация «\(identifier)» не поддерживается; можно импортировать её первый кадр."
            )
        case .invalidWindowsCursor(let reason):
            text(
                "That file is not a valid Windows cursor. \(reason)",
                "Этот файл не является корректным курсором Windows. \(reason)"
            )
        case .invalidWindowsArchive(let reason):
            text(
                "The Windows cursor archive could not be imported. \(reason)",
                "Не удалось импортировать архив курсоров Windows. \(reason)"
            )
        case .windowsThemeMissingCursors:
            text(
                "No usable .cur or .ani files were found in this Windows theme.",
                "В этой теме Windows не найдено пригодных файлов .cur или .ani."
            )
        }
    }

    private static func localizedCapeReason(_ reason: String) -> String {
        switch reason {
        case "The file extension must be .cape.":
            "Расширение файла должно быть .cape."
        case "The file is too large.":
            "Файл слишком большой."
        case "The property list is empty or too large.":
            "Property list пуст или слишком большой."
        case "The property list could not be decoded.":
            "Не удалось декодировать property list."
        case "It contains too many cursor entries.":
            "Файл содержит слишком много записей курсоров."
        default:
            reason
        }
    }

    private static func russianForm(
        _ count: Int,
        one: String,
        few: String,
        many: String
    ) -> String {
        let absolute = abs(count)
        let lastTwo = absolute % 100
        if 11...14 ~= lastTwo { return many }
        switch absolute % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
