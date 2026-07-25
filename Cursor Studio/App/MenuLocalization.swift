import AppKit

@MainActor
enum MenuLocalization {
    static func apply() {
        guard AppLanguage.selected != .system,
              let mainMenu = NSApplication.shared.mainMenu else {
            return
        }
        let mapping = AppLanguage.selected.resolved == .russian
            ? englishToRussian
            : russianToEnglish
        localize(mainMenu, using: mapping)
    }

    private static func localize(
        _ menu: NSMenu,
        using mapping: [String: String]
    ) {
        for item in menu.items {
            if let localized = mapping[item.title] {
                item.title = localized
                item.submenu?.title = localized
            }
            if let submenu = item.submenu {
                localize(submenu, using: mapping)
            }
        }
    }

    private static let englishToRussian: [String: String] = [
        "File": "Файл",
        "Edit": "Правка",
        "View": "Вид",
        "Window": "Окно",
        "Help": "Справка",
        "About Cursor Studio": "О программе Cursor Studio",
        "Settings…": "Настройки…",
        "Services": "Службы",
        "Hide Cursor Studio": "Скрыть Cursor Studio",
        "Hide Others": "Скрыть остальные",
        "Show All": "Показать все",
        "Quit Cursor Studio": "Завершить Cursor Studio",
        "New Window": "Новое окно",
        "Close": "Закрыть",
        "Undo": "Отменить",
        "Redo": "Повторить",
        "Cut": "Вырезать",
        "Copy": "Копировать",
        "Paste": "Вставить",
        "Paste and Match Style": "Вставить и согласовать стиль",
        "Delete": "Удалить",
        "Select All": "Выбрать всё",
        "Find": "Найти",
        "Find…": "Найти…",
        "Find Next": "Найти далее",
        "Find Previous": "Найти ранее",
        "Use Selection for Find": "Использовать выделенное для поиска",
        "Jump to Selection": "Перейти к выделенному",
        "Spelling and Grammar": "Правописание и грамматика",
        "Substitutions": "Подстановки",
        "Transformations": "Преобразования",
        "Speech": "Речь",
        "Start Dictation…": "Начать диктовку…",
        "Emoji & Symbols": "Эмодзи и символы",
        "Show Sidebar": "Показать боковую панель",
        "Hide Sidebar": "Скрыть боковую панель",
        "Customize Toolbar…": "Настроить панель инструментов…",
        "Enter Full Screen": "Перейти в полноэкранный режим",
        "Exit Full Screen": "Выйти из полноэкранного режима",
        "Minimize": "Свернуть",
        "Zoom": "Масштабировать",
        "Bring All to Front": "Все окна — на передний план",
        "Cursor Studio Help": "Справка Cursor Studio",
    ]

    private static let russianToEnglish: [String: String] = Dictionary(
        uniqueKeysWithValues: englishToRussian.map { ($0.value, $0.key) }
    )
}
