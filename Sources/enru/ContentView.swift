import SwiftUI
import Translation

struct ContentView: View {
    @ObservedObject var appState: AppState

    @FocusState private var inputFocused: Bool

    // One configuration per direction, rebuilt only when the language pair changes, so
    // `.translationTask` starts exactly one session per direction and keeps it alive
    // until the languages change. Recreating a configuration per keystroke is what makes
    // translations silently stop: two configurations for the same language pair compare
    // equal, so SwiftUI sees no change and never re-runs the task.
    @State private var forward: TranslationSession.Configuration?
    @State private var reverse: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            languageBar

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
        .onChange(of: appState.languagePair) { _, pair in
            syncConfigurations(with: pair)
            inputFocused = true
        }
        .onAppear {
            inputFocused = true
            syncConfigurations(with: appState.languagePair)
        }
        .translationTask(forward) { session in
            await runSession(session, for: .forward)
        }
        .translationTask(reverse) { session in
            await runSession(session, for: .reverse)
        }
    }

    // MARK: - Language selection

    private var languageBar: some View {
        HStack(spacing: 2) {
            languagePicker(
                label: "Input language",
                selection: Binding(
                    get: { appState.languagePair.input },
                    set: { appState.setInputLanguage($0) }
                )
            )

            Button {
                appState.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .help("Swap languages")

            languagePicker(
                label: "Output language",
                selection: Binding(
                    get: { appState.languagePair.output },
                    set: { appState.setOutputLanguage($0) }
                )
            )

            Spacer(minLength: 0)
        }
        .controlSize(.small)
        .foregroundStyle(.secondary)
    }

    private func languagePicker(label: String, selection: Binding<Locale.Language>) -> some View {
        Picker(label, selection: selection) {
            ForEach(languageOptions(including: selection.wrappedValue), id: \.self) { language in
                Text(AppState.displayName(for: language)).tag(language)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help(label)
    }

    /// The framework's supported languages, with the current selection prepended if it
    /// isn't among them (before the list has loaded, or for a stored language that is no
    /// longer offered) so the picker always has a valid selection to show.
    private func languageOptions(including selection: Locale.Language) -> [Locale.Language] {
        let languages = appState.availableLanguages
        return languages.contains(selection) ? languages : [selection] + languages
    }

    // MARK: - Sessions

    /// Points both configurations at `pair`, touching only those whose languages differ:
    /// every assignment restarts that direction's session.
    private func syncConfigurations(with pair: LanguagePair) {
        if forward?.source != pair.input || forward?.target != pair.output {
            forward = .init(source: pair.input, target: pair.output)
        }
        if reverse?.source != pair.output || reverse?.target != pair.input {
            reverse = .init(source: pair.output, target: pair.input)
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
        case .forward: forward?.invalidate()
        case .reverse: reverse?.invalidate()
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
