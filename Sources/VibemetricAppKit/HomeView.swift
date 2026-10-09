import SwiftUI
import VibemetricCore

/// The "Run my score" screen: the same Engine and Model and Notes to LLM boxes as Settings, and Start.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.textScale) private var scale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Run my score").scaledFont(22, weight: .semibold).foregroundStyle(Theme.ink)

                SettingsSection("Engine and Model", systemImage: "gauge.with.dots.needle.67percent") {
                    AssessmentEnginePicker(compact: true, showsDetails: false)
                }

                SettingsSection("Notes to LLM", systemImage: "text.bubble") {
                    NotesEditor()
                }

                if case let .failed(message) = model.phase {
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(Theme.color(for: .bottleneck))
                        .scaledFont(12)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Button {
                    model.startAssessment()
                } label: {
                    HStack(spacing: 8) {
                        if model.isScanning { ProgressView().controlSize(.small) }
                        Text("Start")
                    }
                    .frame(minWidth: 120 * scale)
                }
                .buttonStyle(FieldButtonStyle(prominent: true))
                .disabled(!model.canStartAssessment)
                .accessibilityIdentifier("start-assessment")
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("assessment-home-scroll")
    }
}

struct ScanSummaryView: View {
    let summary: ScanSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.total.formatted())
                    .scaledFont(56, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("history-total")
                Text("sessions")
                    .scaledFont(16)
                    .foregroundStyle(Theme.muted)
            }

            Rectangle().fill(Theme.rule).frame(height: 1).accessibilityHidden(true)

            VStack(spacing: 18) {
                ForEach(AgentTool.allCases, id: \.self) { tool in
                    HStack(spacing: 12) {
                        ToolIcon(tool: tool)
                        Text(tool.rawValue).scaledFont(14)
                        Spacer(minLength: 12)
                        Text((summary.byTool.first { $0.0 == tool }?.1 ?? 0).formatted())
                            .scaledFont(17, weight: .medium)
                            .monospacedDigit()
                    }
                    .foregroundStyle(Theme.ink)
                    .accessibilityElement(children: .combine)
                }
            }

            Rectangle().fill(Theme.rule).frame(height: 1).accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 16) {
                metadata("folder", "\(summary.projects.formatted()) projects")
                if let range = summary.range {
                    metadata("calendar", Self.dateRange(range))
                }
            }
            .scaledFont(13)
            .foregroundStyle(Theme.muted)

            if summary.total == 0 {
                Text("No sessions found. Use Claude Code or Codex, then rescan your history.")
                    .scaledFont(12)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("history-summary")
    }

    private func metadata(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon).frame(width: 26).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func dateRange(_ range: ClosedRange<Date>) -> String {
        let day = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(Locale(identifier: "en_US"))
        let full = day.year()
        let sameYear = Calendar.current.component(.year, from: range.lowerBound)
            == Calendar.current.component(.year, from: range.upperBound)
        return "\(range.lowerBound.formatted(sameYear ? day : full)) – \(range.upperBound.formatted(full))"
    }
}

private struct AssessmentPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(14, weight: .semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(scheme == .dark ? Color.black.opacity(0.85) : .white)
            .background(fill.opacity(isEnabled ? 1 : 0.45),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .brightness(configuration.isPressed ? -0.06 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var fill: Color {
        scheme == .dark ? Theme.accent : Color(red: 0.79, green: 0.28, blue: 0.11)
    }
}

struct AssessmentSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(12)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundStyle(isEnabled ? Theme.ink : Theme.muted)
            .background(Theme.rule.opacity(configuration.isPressed ? 0.65 : 0.45),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct PrivacyNote: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Theme.rule).frame(height: 1).accessibilityHidden(true)
            Button { expanded.toggle() } label: {
                HStack {
                    SectionLabel(text: "How your data is handled")
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 2)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("privacy-disclosure")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            Text("Original history is read-only. Recognized secrets are removed. Assessment evidence is sent to the selected provider. Each result keeps its evidence on this Mac until you delete the result.")
                .fixedSize(horizontal: false, vertical: true)
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    bullet("doc.text.magnifyingglass", "Vibemetric builds a short digest on this Mac and removes keys, tokens, and database URLs it recognizes.")
                    bullet("terminal", "Your selected engine sends assessment evidence to Anthropic or OpenAI using your own account. The engine saves the scoring session in its own history; Vibemetric leaves it out of later scores.")
                    bullet("lock", (["Vibemetric’s server never receives your transcripts."] + Extensions.privacyNotes).joined(separator: " "))
                }
                .padding(.top, 4)
            }
        }
        .scaledFont(12)
        .foregroundStyle(Theme.muted)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).frame(width: 16).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
