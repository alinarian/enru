import Foundation

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

    private var latestJobID = 0
    private var debounceTask: Task<Void, Never>?
    private var queues: [TranslationDirection: AsyncStream<TranslationJob>.Continuation] = [:]
    private var lastDispatched: (text: String, direction: TranslationDirection)?

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
        let direction: TranslationDirection = LanguageDetector.detect(text) == .russian
            ? .russianToEnglish
            : .englishToRussian

        if let last = lastDispatched, last.text == text, last.direction == direction, errorMessage == nil {
            return
        }

        latestJobID += 1
        lastDispatched = (text, direction)
        errorMessage = nil
        isLoading = true

        guard let queue = queues[direction] else {
            isLoading = false
            errorMessage = "Translation isn't available yet."
            lastDispatched = nil
            return
        }
        queue.yield(TranslationJob(id: latestJobID, text: text, direction: direction))
    }
}
