import AppKit
import SwiftUI

struct AssistantView: View {
    @EnvironmentObject private var engine: AssistantEngine
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if engine.isAvailable {
                conversation
                Divider()
                composer
            } else {
                unavailableNotice
            }
        }
    }

    // MARK: - Kopfzeile

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Assistenz").font(Theme.Font.pageTitle)
                Text("Fragen zu deinen Daten – das Modell läuft lokal auf diesem Mac.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            if !engine.messages.isEmpty {
                Button("Neues Gespräch") { engine.clear() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Verlauf

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if engine.messages.isEmpty {
                        welcome
                    } else {
                        ForEach(engine.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    // Ankerpunkt, damit neue Antworten sichtbar bleiben.
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: engine.messages.last?.text) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: engine.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Card(title: "Wobei kann ich helfen?",
                 subtitle: "Ich kenne deine erfasste App-Nutzung, die Produktivitätsauswertung, deine Termine und Aufgaben.") {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(engine.suggestions, id: \.self) { suggestion in
                        Button {
                            engine.send(suggestion)
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.Palette.accent)
                                Text(suggestion)
                                    .font(Theme.Font.body)
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .background(Theme.Palette.hairline.opacity(0.5),
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Auch Vergleiche sind möglich, etwa „Vergleiche Chrome und Notion über die letzten 7 Tage“.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    // MARK: - Eingabe

    private var composer: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("Frag etwas zu deinem Dashboard …", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit(submit)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline))

            Button(action: submit) {
                Image(systemName: engine.isResponding ? "ellipsis" : "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || engine.isResponding)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .onAppear { inputFocused = true }
    }

    private func submit() {
        let text = draft
        draft = ""
        engine.send(text)
    }

    // MARK: - Nicht verfügbar

    private var unavailableNotice: some View {
        VStack {
            Spacer()
            Card(title: "Assistenz nicht verfügbar") {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(engine.unavailable?.message ?? "")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Erneut prüfen") { engine.refreshAvailability() }
                        Button("Systemeinstellungen öffnen") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.link)
                    }
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: 460)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Sprechblase. Fragen rechts und getönt, Antworten links und ruhig.
private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9))
                        Text("Assistenz")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Theme.Palette.textTertiary)
                }

                Group {
                    if message.text.isEmpty && message.isStreaming {
                        ThinkingIndicator()
                    } else {
                        MarkdownText(message.text)
                    }
                }
                .foregroundStyle(foreground)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs + 1)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(message.role == .assistant ? Theme.Palette.hairline : .clear)
                )

                ForEach(message.charts) { spec in
                    ChartCard(spec: spec)
                        .frame(maxWidth: 560)
                }

                if message.chartUnavailable {
                    Label("Dafür kann ich keine Darstellung zeichnen.",
                          systemImage: "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                if message.chartWasFallback {
                    Label("Direkt aus den Aufzeichnungen gezeichnet.", systemImage: "checkmark.seal")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                if let correction = message.chartCorrection {
                    Label(correction, systemImage: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.accent)
                }

                actionReceipts

                if message.unverifiedClaim {
                    Label("Die Antwort behauptet eine Änderung, es wurde aber nichts geändert. Bitte noch einmal ausdrücklich formulieren.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.unproductive)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, 3)
                        .background(Theme.Palette.unproductive.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                }

                if message.contextWasReset {
                    Label("Der Gesprächsverlauf war voll und wurde geleert.",
                          systemImage: "arrow.counterclockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var actionReceipts: some View {
        if !message.actions.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(message.actions) { action in
                    ActionReceipt(action: action, message: message)
                }
            }
            .padding(.top, 2)
        }
    }

    private var background: Color {
        switch message.role {
        case .user:      return Theme.Palette.accent
        case .assistant: return message.failed ? Theme.Palette.unproductive.opacity(0.10) : Theme.Palette.card
        }
    }

    private var foreground: Color {
        switch message.role {
        case .user:      return .white
        case .assistant: return message.failed ? Theme.Palette.unproductive : Theme.Palette.textPrimary
        }
    }
}

/// Drei Punkte, solange das Modell noch nichts geschrieben hat.
private struct ThinkingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.Palette.textTertiary)
                    .frame(width: 5, height: 5)
                    .opacity(0.35 + 0.65 * max(0, cos(phase - Double(index) * 0.7)))
            }
        }
        .frame(height: 16)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}


/// Stellt die Antwort des Modells dar. Es antwortet in Markdown, teils mit
/// Aufzählungen – `Text` allein würde die Sternchen stehen lassen. Deshalb
/// zeilenweise: Listenzeichen werden zu echten Aufzählungspunkten, der Rest
/// der Zeile wird inline ausgewertet (fett, kursiv, Code).
struct MarkdownText: View {
    private let lines: [Line]  // fileprivate erweitert, siehe unten

    fileprivate struct Line: Identifiable {
        let id = UUID()
        let text: AttributedString
        let indent: Int
        let isBullet: Bool
        let isBlank: Bool
    }

    init(_ raw: String) {
        lines = raw.components(separatedBy: .newlines).map(Line.init(raw:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(lines) { line in
                if line.isBlank {
                    Spacer().frame(height: 3)
                } else if line.isBullet {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(Theme.Palette.textTertiary)
                        Text(line.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(line.indent) * 12)
                } else {
                    Text(line.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(Theme.Font.body)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension MarkdownText.Line {
    init(raw: String) {
        let indentWidth = raw.prefix { $0 == " " || $0 == "\t" }.count
        var body = raw.trimmingCharacters(in: .whitespaces)

        var bullet = false
        for marker in ["* ", "- ", "• ", "+ "] where body.hasPrefix(marker) {
            body.removeFirst(marker.count)
            bullet = true
            break
        }
        // Überschriften wie „## Titel“ tragen im Chat nichts bei.
        while body.hasPrefix("#") { body.removeFirst() }
        body = body.trimmingCharacters(in: .whitespaces)

        let parsed = (try? AttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(body)

        self.init(text: parsed,
                  indent: bullet ? min(indentWidth / 2, 3) : 0,
                  isBullet: bullet,
                  isBlank: body.isEmpty)
    }
}


/// Beleg über eine tatsächlich vorgenommene Änderung.
///
/// Das Modell kann behaupten, etwas eingetragen zu haben. Diese Zeile
/// erscheint nur, wenn die Änderung wirklich stattgefunden hat – und bietet
/// an, sie zurückzunehmen.
private struct ActionReceipt: View {
    let action: AssistantAction
    let message: ChatMessage

    @EnvironmentObject private var engine: AssistantEngine

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: action.undone ? "arrow.uturn.backward.circle.fill" : action.kind.symbol)
                .font(.system(size: 10))
                .foregroundStyle(action.undone ? Theme.Palette.textTertiary : action.kind.color)

            Text(action.text)
                .font(.system(size: 11))
                .foregroundStyle(action.undone ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
                .strikethrough(action.undone, color: Theme.Palette.textTertiary)
                .lineLimit(2)

            if action.undone {
                Text("zurückgenommen")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else if action.undo != nil {
                Button("Rückgängig") { engine.undo(action, in: message) }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, 3)
        .background(Theme.Palette.hairline.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }
}
