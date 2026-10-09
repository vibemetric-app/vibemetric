import SwiftUI
import VibemetricCore

/// Home and Settings edit the same saved engine and per-engine model selections.
struct AssessmentEnginePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.textScale) private var scale
    /// Settings shows simple uniform rows (label, then a control of one fixed size); Home keeps the larger cards.
    var compact = false
    /// Compact only: the model description and installation line. The start screen hides them and
    /// shows the installation line only when the engine isn't ready.
    var showsDetails = true

    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    // MARK: Compact rows (Settings)

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Engine") { engineSegments }
            row("Model") { modelDropdown }
            if showsDetails {
                Text("\(modelHelp) Evidence is sent to \(model.engine.provider) using your \(model.engine.name) sign-in, plan or API credits.")
                    .scaledFont(12)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsDetails || model.installations[model.engine] == nil {
                installation
            }
        }
    }

    private var controlWidth: CGFloat { 320 * scale }
    private var controlHeight: CGFloat { 34 * scale }

    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        FieldRow(label) { control().frame(width: controlWidth, height: controlHeight) }
    }

    /// Two equal halves in one rounded frame; the selected engine is filled.
    private var engineSegments: some View {
        HStack(spacing: 0) {
            ForEach(AssessmentEngine.allCases) { engine in
                let selected = model.engine == engine
                Button { model.engine = engine } label: {
                    Text(engine.name)
                        .scaledFont(13, weight: selected ? .semibold : .regular)
                        .foregroundStyle(selected ? Color.white : Theme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(selected ? Theme.accent : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(engine.name)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("engine-\(engine.rawValue)")
            }
        }
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.rule))
        .disabled(model.isRunning)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scoring engine")
    }

    /// The same frame as the engine control, so the two rows line up.
    private var modelDropdown: some View {
        let choices = model.engine == .claude ? ModelChoice.allCases.map(\.name) : CodexModelChoice.allCases.map(\.name)
        let current = model.engine == .claude ? model.model.name : model.codexModel.name
        return Menu {
            ForEach(choices, id: \.self) { title in
                Button(title) {
                    if model.engine == .claude, let choice = ModelChoice.allCases.first(where: { $0.name == title }) {
                        model.model = choice
                    } else if model.engine == .codex, let choice = CodexModelChoice.allCases.first(where: { $0.name == title }) {
                        model.codexModel = choice
                    }
                }
            }
        } label: {
            HStack {
                Text(current).scaledFont(13).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").scaledFont(11, weight: .semibold).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.rule))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(model.isRunning)
        .accessibilityLabel("Model")
        .accessibilityIdentifier(model.engine == .codex ? "codex-model" : "claude-model")
    }

    // MARK: Full layout (Home)

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose what analyzes your records")
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                engineControl
                Text("Either engine analyzes both histories.")
                    .scaledFont(12)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                // The dropdown sits next to its label rather than spanning the full width under it.
                HStack(spacing: 12) {
                    Text("Model").scaledFont(14).foregroundStyle(Theme.ink)
                    modelMenu.frame(width: 260 * scale)
                    Spacer(minLength: 0)
                }
                Text(modelHelp)
                    .scaledFont(12)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 30 * scale, alignment: .topLeading)
            }

            installation

            Rectangle().fill(Theme.rule).frame(height: 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Uses your \(model.engine.name) sign-in.")
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                Text("Evidence is sent to \(model.engine.provider) and uses your plan or API credits.")
                    .scaledFont(12)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Two option cards with a radio mark, so the current engine is obvious at a glance.
    private var engineControl: some View {
        HStack(spacing: 10) {
            ForEach(AssessmentEngine.allCases) { engine in
                let selected = model.engine == engine
                Button { model.engine = engine } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .scaledFont(16)
                            .foregroundStyle(selected ? Theme.accent : Theme.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.name)
                                .scaledFont(14, weight: .semibold)
                                .foregroundStyle(Theme.ink)
                            Text("by \(engine.provider)")
                                .scaledFont(11)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(selected ? Theme.accent.opacity(0.08) : Theme.card,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : Theme.rule, lineWidth: selected ? 2 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(engine.name)
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("engine-\(engine.rawValue)")
            }
        }
        .disabled(model.isRunning)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scoring engine")
        .accessibilityIdentifier("assessment-engine")
        .onMoveCommand { direction in
            guard !model.isRunning else { return }
            switch direction {
            case .left: model.engine = .claude
            case .right: model.engine = .codex
            default: break
            }
        }
    }

    private var modelMenu: some View {
        ModelPopup(
            choices: model.engine == .claude ? ModelChoice.allCases.map(\.name) : CodexModelChoice.allCases.map(\.name),
            selection: Binding(
                get: { model.engine == .claude ? model.model.name : model.codexModel.name },
                set: { title in
                    if model.engine == .claude, let choice = ModelChoice.allCases.first(where: { $0.name == title }) {
                        model.model = choice
                    } else if model.engine == .codex, let choice = CodexModelChoice.allCases.first(where: { $0.name == title }) {
                        model.codexModel = choice
                    }
                }
            ),
            fontSize: 13 * scale,
            enabled: !model.isRunning,
            identifier: model.engine == .codex ? "codex-model" : "claude-model"
        )
        .frame(height: 34 * scale)
    }

    private var modelHelp: String {
        if model.engine == .codex { return model.codexModel.help }
        return model.model == .standard
            ? "Uses Sonnet for this assessment."
            : "Uses \(model.model.name) for this assessment."
    }

    private var installation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let installation = model.installations[model.engine] {
                    let version = installation.version?
                        .split(whereSeparator: \.isWhitespace)
                        .first(where: { $0.first?.isNumber == true })
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.color(for: .strong))
                        .fixedSize()
                    Text(version.map { "\(model.engine.name) · \($0)" } ?? model.engine.name)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1).truncationMode(.middle)
                        .help(installation.version ?? model.engine.name)
                } else if model.isCheckingEngines {
                    ProgressView().controlSize(.small)
                    Text("Checking installation…").foregroundStyle(Theme.muted)
                } else {
                    Label("Not ready", systemImage: "exclamationmark.circle")
                        .foregroundStyle(Theme.accent)
                    Link("Set up \(model.engine.name)", destination: model.engine.setupURL)
                }
                Spacer(minLength: 0)
                Button {
                    Task { await model.refreshEngines() }
                } label: {
                    HStack(spacing: 5) {
                        if model.isCheckingEngines, model.installations[model.engine] != nil {
                            ProgressView().controlSize(.mini)
                        }
                        Text("Check again")
                    }
                }
                .buttonStyle(AssessmentSecondaryButtonStyle())
                .disabled(model.isCheckingEngines || model.isRunning)
                .accessibilityIdentifier("check-engines")
            }
            .scaledFont(12)

            if let error = model.installationErrors[model.engine] {
                Text(error).scaledFont(12).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A real macOS popup fills the column and keeps native menu and keyboard behavior.
private struct ModelPopup: NSViewRepresentable {
    let choices: [String]
    @Binding var selection: String
    let fontSize: CGFloat
    let enabled: Bool
    let identifier: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectModel(_:))
        button.setAccessibilityLabel("Model")
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        if button.itemTitles != choices {
            button.removeAllItems()
            button.addItems(withTitles: choices)
        }
        button.selectItem(withTitle: selection)
        button.font = .systemFont(ofSize: fontSize)
        button.isEnabled = enabled
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.setAccessibilityIdentifier(identifier)
    }

    final class Coordinator: NSObject {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }

        @objc func selectModel(_ sender: NSPopUpButton) {
            guard let title = sender.selectedItem?.title else { return }
            selection.wrappedValue = title
        }
    }
}
