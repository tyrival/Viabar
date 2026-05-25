import Foundation

enum AppLocalization {
    static func string(_ key: String, language: EffectiveAppLanguage) -> String {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return key }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(
        _ key: String,
        language: EffectiveAppLanguage,
        _ arguments: CVarArg...
    ) -> String {
        String(format: string(key, language: language), locale: language.locale, arguments: arguments)
    }
}
