import Foundation
import NaturalLanguage

/// Decides which of the two configured languages a piece of text is written in.
///
/// Uses the system language recogniser constrained to just the two candidates, so
/// it works for any pair — same-script pairs like English/French included — without
/// hard-coding script ranges.
enum LanguageDetector {
    /// Returns the member of `candidates` that `text` is most likely written in, or
    /// `nil` when the recogniser has no opinion or cannot tell the candidates apart
    /// (for example English (US) vs. English (UK), which share one recogniser language).
    static func detect(_ text: String, among candidates: [Locale.Language]) -> Locale.Language? {
        let tagged = candidates.compactMap { language in
            recognizerLanguage(for: language).map { (language: language, tag: $0) }
        }
        let tags = Set(tagged.map(\.tag))
        guard tags.count == tagged.count, tags.count > 1 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Array(tags)
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        return tagged.first { $0.tag == dominant }?.language
    }

    /// Maps a Translation-framework language onto the recogniser's vocabulary, which
    /// uses bare language codes except for Chinese, where the script disambiguates.
    private static func recognizerLanguage(for language: Locale.Language) -> NLLanguage? {
        guard let code = language.languageCode?.identifier else { return nil }
        if code == "zh", let script = language.script?.identifier {
            return NLLanguage(rawValue: "zh-\(script)")
        }
        return NLLanguage(rawValue: code)
    }
}
