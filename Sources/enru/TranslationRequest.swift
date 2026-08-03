import Foundation

enum TranslationDirection: Hashable {
    case russianToEnglish
    case englishToRussian
}

/// A single unit of work handed to a translation session.
/// `id` is monotonically increasing so results that arrive after a newer job was
/// dispatched can be recognised as stale and dropped.
struct TranslationJob: Identifiable, Sendable {
    let id: Int
    let text: String
    let direction: TranslationDirection
}
