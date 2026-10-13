import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case zhHans
    case zh
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L10n.t("settings.language.system")
        case .zhHans: return "简体中文"
        case .zh: return "繁體中文"
        case .en: return "English"
        }
    }

    /// The language actually used for data and UI strings.
    var resolved: AppLanguage {
        if self != .system { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh-Hans")
            || preferred.hasPrefix("zh-CN")
            || preferred.hasPrefix("zh-SG")
            || preferred.hasPrefix("zh-MY") {
            return .zhHans
        }
        if preferred.hasPrefix("zh") { return .zh }
        return .en
    }

    /// Whether the resolved language displays Chinese text.
    var isChinese: Bool {
        let language = resolved
        return language == .zh || language == .zhHans
    }

    /// BCP-47-ish code used for data name lookups.
    var localeCode: String {
        switch resolved {
        case .zhHans: return "zh-Hans"
        case .zh: return "zh-Hant"
        default: return "en"
        }
    }

    var locale: Locale {
        switch resolved {
        case .zhHans: return Locale(identifier: "zh_Hans_CN")
        case .zh: return Locale(identifier: "zh_Hant_HK")
        case .en: return Locale(identifier: "en")
        default: return Locale.current
        }
    }

    /// Strings table code, or nil to use the system default.
    var bundleCode: String? {
        switch resolved {
        case .zhHans: return "zh-Hans"
        case .zh: return "zh-Hant"
        case .en: return "en"
        default: return nil
        }
    }
}

enum EtaFormat: String, CaseIterable, Identifiable, Sendable {
    case diff
    case exact
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diff: return L10n.t("settings.etaFormat.diff")
        case .exact: return L10n.t("settings.etaFormat.exact")
        case .mixed: return L10n.t("settings.etaFormat.mixed")
        }
    }
}

extension AppLanguage {
    /// Mirror of the user setting, updated by `AppSettings`, safe to read from any thread.
    nonisolated(unsafe) static var current: AppLanguage = .system
}

enum L10n {
    static func t(_ key: String) -> String {
        guard let code = AppLanguage.current.bundleCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return String(localized: String.LocalizationValue(key))
        }
        return String(localized: String.LocalizationValue(key), bundle: bundle)
    }

    /// Language actually used for data display.
    static var language: AppLanguage { AppLanguage.current.resolved }

    /// Converts Traditional Chinese data text for the current display language.
    static func display(_ text: String) -> String {
        language == .zhHans ? ChineseConverter.simplified(text) : text
    }
}

/// Region-aware clock. The active `TransitProvider` injects its time zone at
/// app start, so all date math follows the region being served.
enum RegionClock {
    nonisolated(unsafe) static var timeZone: TimeZone = TimeZone(identifier: "Asia/Hong_Kong")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static var cachedFormatters: [DateFormatter] = []
    private static var cachedTimeZone: TimeZone?

    private static func formatters() -> [DateFormatter] {
        if cachedTimeZone != timeZone || cachedFormatters.isEmpty {
            cachedFormatters = ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mmZ", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"].map { format in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone
                formatter.dateFormat = format
                return formatter
            }
            cachedTimeZone = timeZone
        }
        return cachedFormatters
    }

    static func date(fromISO string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        for formatter in formatters() {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    static func isoString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter.string(from: date)
    }

    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func timeString(_ iso: String) -> String {
        guard let date = date(fromISO: iso) else {
            return iso.count >= 16 ? String(iso.dropFirst(11).prefix(5)) : iso
        }
        return timeString(date)
    }

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    /// Weekday index following the data convention: 0 = Sunday ... 6 = Saturday.
    static func weekdayIndex(_ date: Date = Date()) -> Int {
        let components = calendar.dateComponents([.weekday], from: date)
        return (components.weekday ?? 1) - 1
    }
}
