import SwiftUI
import Translation

struct ContentView: View {
    @ObservedObject var appState: AppState

    @FocusState private var inputFocused: Bool

    // Each configuration is created once and never mutated, so `.translationTask` starts
    // exactly one session per direction and keeps it alive for the life of the popup.
    // Recreating a configuration per keystroke is what makes translations silently stop:
    // two configurations for the same language pair compare equal, so SwiftUI sees no
    // change and never re-runs the task.
    @State private var russianToEnglish: TranslationSession.Configuration?
    @State private var englishToRussian: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("type…", text: $appState.inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                .focused($inputFocused)

            ScrollView {
                HStack(alignment: .top, spacing: 6) {
                    if appState.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    if let error = appState.errorMessage {
                        Text(error).foregroundStyle(.red)
                    } else if appState.isPreparingModel {
                        Text("Preparing language model…").foregroundStyle(.secondary)
                    } else {
                        // Keep the previous translation on screen while the next one runs
                        // so the panel doesn't flash empty on every keystroke.
                        Text(appState.outputText)
                            .foregroundStyle(.primary)
                            .opacity(appState.isLoading ? 0.4 : 1)
                    }
                    Spacer()
                }
                .font(.system(size: 14))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.25)))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: appState.focusToken) { _, _ in
            inputFocused = true
        }
        .onAppear {
            inputFocused = true
            if russianToEnglish == nil {
                russianToEnglish = .init(
                    source: Locale.Language(identifier: "ru"),
                    target: Locale.Language(identifier: "en")
                )
            }
            if englishToRussian == nil {
                englishToRussian = .init(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "ru")
                )
            }
        }
        .translationTask(russianToEnglish) { session in
            await runSession(session, for: .russianToEnglish)
        }
        .translationTask(englishToRussian) { session in
            await runSession(session, for: .englishToRussian)
        }
    }

    /// Drains this direction's job queue for as long as the session is alive.
    @MainActor
    private func runSession(_ session: TranslationSession, for direction: TranslationDirection) async {
        var prepared = false

        for await job in appState.jobStream(for: direction) {
            guard appState.isCurrent(job) else { continue }
            do {
                if !prepared {
                    appState.setPreparingModel(true)
                    try await session.prepareTranslation()
                    appState.setPreparingModel(false)
                    prepared = true
                }
                let response = try await session.translate(job.text)
                appState.receive(response.targetText, for: job)
            } catch {
                appState.setPreparingModel(false)
                appState.receive(failure: error, for: job)
                // A session that has failed once may stay unusable; invalidating the
                // configuration makes SwiftUI hand this loop a fresh session.
                invalidateConfiguration(for: direction)
                return
            }
        }
    }

    private func invalidateConfiguration(for direction: TranslationDirection) {
        switch direction {
        case .russianToEnglish: russianToEnglish?.invalidate()
        case .englishToRussian: englishToRussian?.invalidate()
        }
    }
}

/// NSVisualEffectView bridge for the native macOS vibrancy/blur background.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
