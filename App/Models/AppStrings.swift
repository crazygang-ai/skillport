import Foundation
import SwiftUI

public struct AppStrings: Equatable, Sendable {
    public let localeIdentifier: String

    public init(localeIdentifier: String) {
        self.localeIdentifier = SettingsModel.normalizedLocale(localeIdentifier)
    }

    public static func current(defaults: UserDefaults = .standard) -> AppStrings {
        let rawLocale =
            (defaults.array(forKey: SettingsModel.appleLanguagesKey) as? [String])?.first
            ?? Locale.current.identifier
        return AppStrings(localeIdentifier: rawLocale)
    }

    public var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    public func callAsFunction(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: .main, locale: locale)
    }
}

private struct AppStringsEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppStrings(localeIdentifier: Locale.current.identifier)
}

extension EnvironmentValues {
    var appStrings: AppStrings {
        get { self[AppStringsEnvironmentKey.self] }
        set { self[AppStringsEnvironmentKey.self] = newValue }
    }
}
