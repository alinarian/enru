import Foundation

enum DetectedLanguage {
    case english
    case russian
}

/// Lightweight Cyrillic-vs-Latin heuristic — no NLP dependency needed for two languages.
enum LanguageDetector {
    static func detect(_ text: String) -> DetectedLanguage {
        var cyrillicCount = 0
        var latinCount = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0400...0x04FF: // Cyrillic block
                cyrillicCount += 1
            case 0x0041...0x005A, 0x0061...0x007A: // A-Z, a-z
                latinCount += 1
            default:
                continue
            }
        }

        // Default to English when there's no alphabetic signal at all (e.g. empty/punctuation-only input).
        return cyrillicCount > latinCount ? .russian : .english
    }
}
