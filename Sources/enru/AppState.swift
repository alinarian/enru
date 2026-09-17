import Foundation
import Translation

/// Holds the popup's UI state and drives debounced, auto-detected translation.
///
/// Apple's Translation framework only vends a `TranslationSession` from inside a SwiftUI
/// `.translationTask`, so this class never touches a session directly. Instead it owns one
/// job queue per translation direction; the view runs a long-lived loop per direction that
/// pulls jobs off the queue and reports results back here.
///
/// Queues rather than published request objects: delivery must not depend on SwiftUI
/// noticing a state change, and each queue keeps only the newest job so a burst of
/// keystrokes can never back up behind stale work.
@MainActor
final class AppState: ObservableObject {
    /// On-device translation returns in tens of milliseconds, so a short debounce still
    /// avoids redundant work while feeling immediate.
    static let debounceInterval = Duration.milliseconds(400)

    /// A single edit that grows the text by at least this much is a paste, not typing.
    private static let pasteThreshold = 10

    private static let inputLanguageKey = "Languages.input"
    private static let outputLanguageKey = "Languages.output"

    @Published var inputText: String = "" {
        didSet {
            guard inputText != oldValue else { return }
            inputChanged(from: oldValue, to: inputText)
        }
    }

    @Published private(set) var outputText: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isPreparingModel: Bool = false
    @Published private(set) var errorMessage: String? = nil
    @Published var focusToken: Int = 0

    /// The languages translated between. Changing it restarts the sessions (the view
    /// derives its configurations from this) and re-translates whatever is typed.
    @Published private(set) var languagePair: LanguagePair

    /// Everything the on-device Translation framework can translate, sorted by display
    /// name. Empty until the asynchronous query completes (or if it fails).
    @Published private(set) var availableLanguages: [Locale.Language] = []

    private var latestJobID = 0
    private var debounceTask: Task<Void, Never>?
    private var queues: [TranslationDirection: AsyncStream<TranslationJob>.Continuation] = [:]
    private var lastDispatched: (text: String, direction: TranslationDirection)?
    /// Text waiting for a session that hasn't registered its queue yet — the popup's
    /// first show, or the moment after the language pair changed.
    private var pendingText: String?

    init() {
        languagePair = Self.loadLanguagePair()
        Task { await loadAvailableLanguages() }
    }

    // MARK: - Languages

    func setInputLanguage(_ language: Locale.Language) {
        // Picking the other side's language reads as "swap", not "translate X to X".
        let pair = language == languagePair.output
            ? languagePair.swapped
            : LanguagePair(input: language, output: languagePair.output)
        apply(pair)
    }

    func setOutputLanguage(_ language: Locale.Language) {
        let pair = language == languagePair.input
            ? languagePair.swapped
            : LanguagePair(input: languagePair.input, output: language)
        apply(pair)
    }

    func swapLanguages() {
        apply(languagePair.swapped)
    }

    /// Human-readable name for a language, in the user's own locale ("Russian",
    /// "English (UK)", "Chinese (Taiwan)").
    nonisolated static func displayName(for language: Locale.Language) -> String {
        let identifier = language.minimalIdentifier
        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private func apply(_ pair: LanguagePair) {
        guard pair != languagePair else { return }
        languagePair = pair
        UserDefaults.standard.set(pair.input.minimalIdentifier, forKey: Self.inputLanguageKey)
        UserDefaults.standard.set(pair.output.minimalIdentifier, forKey: Self.outputLanguageKey)

        // The view is about to replace both sessions. Finish the old queues so the
        // outgoing loops stop cleanly, and orphan anything still in flight.
        debounceTask?.cancel()
        latestJobID += 1
        for queue in queues.values {
            queue.finish()
        }
        queues.removeAll()
        lastDispatched = nil
        pendingText = nil
        errorMessage = nil

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            outputText = ""
            isLoading = false
        } else {
            dispatch(trimmed)
        }
    }

    private static func loadLanguagePair() -> LanguagePair {
        let defaults = UserDefaults.standard
        var pair = LanguagePair.default
        if let input = defaults.string(forKey: inputLanguageKey) {
            pair.input = Locale.Language(identifier: input)
        }
        if let output = defaults.string(forKey: outputLanguageKey) {
            pair.output = Locale.Language(identifier: output)
        }
        return pair.input == pair.output ? .default : pair
    }

    private func loadAvailableLanguages() async {
        let languages = await LanguageAvailability().supportedLanguages
        guard !languages.isEmpty else { return }
        availableLanguages = languages.sorted {
            Self.displayName(for: $0).localizedStandardCompare(Self.displayName(for: $1)) == .orderedAscending
        }

        // Stored and default identifiers are minimal ("en", "ru") while the framework
        // lists regional variants ("en-US", "ru-RU"). Snap onto the listed entries so the
        // pickers show a selection and sessions use exactly what the framework offers.
        let resolved = LanguagePair(
            input: resolve(languagePair.input) ?? languagePair.input,
            output: resolve(languagePair.output) ?? languagePair.output
        )
        if resolved.input != resolved.output {
            apply(resolved)
        }
    }

    /// Finds the listed language matching `language`: the same entry, else the same
    /// language once likely script and region are filled in, else the same language code.
    private func resolve(_ language: Locale.Language) -> Locale.Language? {
        if availableLanguages.contains(language) { return language }
        if let match = availableLanguages.first(where: { $0.maximalIdentifier == language.maximalIdentifier }) {
            return match
        }
        guard let code = language.languageCode else { return nil }
        return availableLanguages.first { $0.languageCode == code }
    }

    // MARK: - Session plumbing

    /// Registers a consumer for `direction` and returns its job queue.
    /// Any previous consumer for that direction is finished, so a session restart
    /// (view reappearing, session recreated after an error) replaces it cleanly.
    func jobStream(for direction: TranslationDirection) -> AsyncStream<TranslationJob> {
        queues[direction]?.finish()
        let (stream, continuation) = AsyncStream.makeStream(
            of: TranslationJob.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        queues[direction] = continuation
        if let pendingText {
            dispatch(pendingText)
        } else if let last = lastDispatched, last.direction == direction, isLoading {
            // The job went to the previous consumer after it had died (a session that
            // errored and is being replaced); it would otherwise never be answered.
            lastDispatched = nil
            dispatch(last.text)
        }
        return stream
    }

    func isCurrent(_ job: TranslationJob) -> Bool {
        job.id == latestJobID
    }

    func setPreparingModel(_ preparing: Bool) {
        isPreparingModel = preparing
    }

    func receive(_ text: String, for job: TranslationJob) {
        guard isCurrent(job) else { return }
        outputText = text
        errorMessage = nil
        isLoading = false
    }

    func receive(failure: Error, for job: TranslationJob) {
        guard isCurrent(job) else { return }
        guard !(failure is CancellationError) else { return }
        outputText = ""
        errorMessage = failure.localizedDescription
        isLoading = false
        lastDispatched = nil
    }

    // MARK: - Popup lifecycle

    func resetForShow() {
        debounceTask?.cancel()
        latestJobID += 1 // orphan anything still in flight
        inputText = ""
        outputText = ""
        errorMessage = nil
        isLoading = false
        lastDispatched = nil
        pendingText = nil
    }

    func focusInput() {
        focusToken += 1
    }

    // MARK: - Debounce & dispatch

    private func inputChanged(from oldText: String, to newText: String) {
        debounceTask?.cancel()

        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            latestJobID += 1
            outputText = ""
            errorMessage = nil
            isLoading = false
            lastDispatched = nil
            pendingText = nil
            return
        }

        let isPaste = newText.count - oldText.count >= Self.pasteThreshold
        debounceTask = Task { [weak self] in
            if !isPaste {
                try? await Task.sleep(for: Self.debounceInterval)
                guard !Task.isCancelled else { return }
            }
            self?.dispatch(trimmed)
        }
    }

    private func dispatch(_ text: String) {
        let pair = languagePair
        let detected = LanguageDetector.detect(text, among: [pair.input, pair.output])
        let direction: TranslationDirection = detected == pair.output ? .reverse : .forward

        if let last = lastDispatched, last.text == text, last.direction == direction, errorMessage == nil {
            return
        }

        errorMessage = nil
        isLoading = true

        guard let queue = queues[direction] else {
            // No session for this direction yet (first show, or the language pair just
            // changed and SwiftUI is still starting the new sessions). Hold the text and
            // hand it over as soon as the session registers its queue.
            pendingText = text
            lastDispatched = nil
            return
        }

        latestJobID += 1
        lastDispatched = (text, direction)
        pendingText = nil
        queue.yield(TranslationJob(id: latestJobID, text: text, direction: direction))
    }
}
