import Foundation

/// Which way a job travels between the two configured languages.
enum TranslationDirection: Hashable, CaseIterable {
    /// Input language → output language. The default.
    case forward
    /// Output language → input language, used when the typed text is detected
    /// to be in the output language.
    case reverse
}

/// The two languages the popup translates between.
///
/// `input` is what the user normally types and `output` what they want to read, but
/// direction is still auto-detected per job: text recognised as the output language
/// is translated back into the input language.
struct LanguagePair: Equatable {
    var input: Locale.Language
    var output: Locale.Language

    static let `default` = LanguagePair(
        input: Locale.Language(identifier: "en"),
        output: Locale.Language(identifier: "ru")
    )

    var swapped: LanguagePair {
        LanguagePair(input: output, output: input)
    }

    func source(for direction: TranslationDirection) -> Locale.Language {
        direction == .forward ? input : output
    }

    func target(for direction: TranslationDirection) -> Locale.Language {
        direction == .forward ? output : input
    }
}

/// A single unit of work handed to a translation session.
/// `id` is monotonically increasing so results that arrive after a newer job was
/// dispatched can be recognised as stale and dropped.
struct TranslationJob: Identifiable, Sendable {
    let id: Int
    let text: String
    let direction: TranslationDirection
}
