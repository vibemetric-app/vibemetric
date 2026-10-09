import SwiftUI
import VibemetricCore

/// Vibemetric → Settings… (⌘,), shown in the main window. Scoring engine and notes, daily score, Pro, and startup.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AutoSettings.enabledKey) private var autoEnabled = true
    @AppStorage(AutoSettings.minuteKey) private var autoMinute = AutoSchedule.defaultMinuteOfDay
    @AppStorage(AutoSettings.skipIdleKey) private var skipWhenIdle = true
    @AppStorage(Notifier.enabledKey) private var notifyWhenScored = true
    @Environment(\.textScale) private var scale
    @State private var openAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").scaledFont(22, weight: .semibold).foregroundStyle(Theme.ink)

                SettingsSection("Engine and Model", systemImage: "gauge.with.dots.needle.67percent",
                                footer: "Applies to your first assessment, every manual score, and daily automatic scores.") {
                    AssessmentEnginePicker(compact: true)
                }

                SettingsSection("Notes to LLM", systemImage: "text.bubble") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Added to every assessment. Tell the scorer which projects or records to focus on or leave out. For example:")
                        Text("• “I want it to score only the following projects: TradeKing, FishFinder.”")
                        Text("• “The demo-skill sessions on Sept 28 were only a test; leave them out.”")
                        Text("Notes can’t ask for a particular score.")
                    }
                    .scaledFont(12)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    NotesEditor()
                }

                SettingsSection("Schedule", systemImage: "clock",
                                footer: "Runs while Vibemetric is open. If your Mac is asleep at that time, it runs when the Mac wakes. Each run uses your selected scoring engine’s account, so skipping idle days saves usage.") {
                    FieldRow("Daily") {
                        HStack(spacing: 10) {
                            Toggle("", isOn: $autoEnabled).toggleStyle(.switch).labelsHidden()
                            Text("Score automatically every day").scaledFont(13).foregroundStyle(Theme.ink)
                        }
                    }
                    FieldRow("Time") { TimeField(minuteOfDay: $autoMinute) }
                        .disabled(!autoEnabled)
                        .opacity(autoEnabled ? 1 : 0.5)
                    FieldRow("Idle days") {
                        HStack(spacing: 10) {
                            Toggle("", isOn: $skipWhenIdle).toggleStyle(.switch).labelsHidden()
                            Text("Skip when there are no new sessions").scaledFont(13).foregroundStyle(Theme.ink)
                        }
                    }
                    .disabled(!autoEnabled)
                    .opacity(autoEnabled ? 1 : 0.5)
                    if autoEnabled, let next = AutoSchedule(enabled: true, minuteOfDay: autoMinute).next(after: Date()) {
                        FieldRow("Next") { Text(RelativeDate.format(next)).scaledFont(13).foregroundStyle(Theme.ink) }
                    }
                    if let status = model.lastAutoStatus {
                        FieldRow("Last") { Text(status).scaledFont(13).foregroundStyle(Theme.ink) }
                    }
                }

                ForEach(Extensions.settingsSections.indices, id: \.self) { Extensions.settingsSections[$0]() }

                SettingsSection("General", systemImage: "gearshape",
                                footer: "Notifications show your new score and what changed; if they don't appear, allow Vibemetric in System Settings → Notifications. Opening at login keeps the daily score running.") {
                    FieldRow("Alerts") {
                        HStack(spacing: 10) {
                            Toggle("", isOn: $notifyWhenScored).toggleStyle(.switch).labelsHidden()
                            Text("Notify me when scoring finishes").scaledFont(13).foregroundStyle(Theme.ink)
                        }
                    }
                    FieldRow("Startup") {
                        HStack(spacing: 10) {
                            Toggle("", isOn: $openAtLogin).toggleStyle(.switch).labelsHidden()
                                .onChange(of: openAtLogin) { _, wanted in
                                    do {
                                        try LaunchAtLogin.set(wanted)
                                        loginError = nil
                                    } catch {
                                        loginError = error.localizedDescription
                                        openAtLogin = LaunchAtLogin.isEnabled
                                    }
                                }
                            Text("Open Vibemetric at login").scaledFont(13).foregroundStyle(Theme.ink)
                        }
                    }
                    if let loginError {
                        Text(loginError).scaledFont(12).foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { openAtLogin = LaunchAtLogin.isEnabled }
    }
}

/// One settings section in a rounded box: icon and title, a rule, the controls, then a short explanation.
public struct SettingsSection<Content: View>: View {
    var title: String
    var systemImage: String
    var footer: String?
    @ViewBuilder var content: Content

    public init(_ title: String, systemImage: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .scaledFont(16, weight: .semibold)
                .foregroundStyle(Theme.ink)
            Rectangle().fill(Theme.rule).frame(height: 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) { content }
            if let footer {
                Text(footer)
                    .scaledFont(11)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.rule))
    }
}

/// The Engine, Model and Account layout: a fixed-width label, then the value or control next to it.
public struct FieldRow<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content
    @Environment(\.textScale) private var scale

    public init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label).scaledFont(13, weight: .medium).foregroundStyle(Theme.ink)
                .frame(width: 80 * scale, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34 * scale)
    }
}

/// The notes passed to every assessment, shared by Settings and the "Run my score" screen.
struct NotesEditor: View {
    @AppStorage(AppModel.instructionsKey) private var instructions = ""

    var body: some View {
        TextEditor(text: $instructions)
            .scaledFont(13)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 110)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rule))
            .accessibilityLabel("Notes to LLM")
            .onChange(of: instructions) { _, text in
                if text.count > AssessmentOptions.maxInstructionsLength {
                    instructions = String(text.prefix(AssessmentOptions.maxInstructionsLength))
                }
            }
    }
}

/// The daily time as one field the same size as the others: hour, minute, and AM/PM menus.
struct TimeField: View {
    @Binding var minuteOfDay: Int
    @Environment(\.textScale) private var scale

    private var hour24: Int { minuteOfDay / 60 }
    private var minute: Int { minuteOfDay % 60 }
    private var isPM: Bool { hour24 >= 12 }
    private var hour12: Int { hour24 % 12 == 0 ? 12 : hour24 % 12 }

    private func set(hour12 h: Int? = nil, minute m: Int? = nil, pm: Bool? = nil) {
        let h12 = h ?? hour12, pmValue = pm ?? isPM
        let h24 = (h12 % 12) + (pmValue ? 12 : 0)
        minuteOfDay = h24 * 60 + (m ?? minute)
    }

    var body: some View {
        // Five-minute steps, plus the current minute if it's in between (e.g. 12:31).
        let minutes = Array(Set(Array(stride(from: 0, to: 60, by: 5)) + [minute])).sorted()
        HStack(spacing: 0) {
            part(String(hour12), width: 52) { ForEach(1...12, id: \.self) { h in Button("\(h)") { set(hour12: h) } } }
            Text(":").scaledFont(13).foregroundStyle(Theme.muted)
            part(String(format: "%02d", minute), width: 52) {
                ForEach(minutes, id: \.self) { m in Button(String(format: "%02d", m)) { set(minute: m) } }
            }
            part(isPM ? "PM" : "AM", width: 60) {
                Button("AM") { set(pm: false) }
                Button("PM") { set(pm: true) }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 34 * scale)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.rule))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily score time")
    }

    private func part<Items: View>(_ value: String, width: CGFloat, @ViewBuilder items: () -> Items) -> some View {
        Menu { items() } label: {
            HStack(spacing: 4) {
                Text(value).scaledFont(13).foregroundStyle(Theme.ink).monospacedDigit()
                Image(systemName: "chevron.down").scaledFont(9, weight: .semibold).foregroundStyle(Theme.muted)
            }
            .frame(width: width * scale, height: 34 * scale)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// Buttons at the same height and shape as the fields next to them.
public struct FieldButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.textScale) private var scale
    @Environment(\.isEnabled) private var isEnabled

    public init(prominent: Bool = false, destructive: Bool = false) {
        self.prominent = prominent
        self.destructive = destructive
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(13, weight: prominent ? .semibold : .regular)
            .foregroundStyle(prominent ? Color.white : destructive ? Theme.color(for: .bottleneck) : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 34 * scale)
            .background(prominent ? Theme.accent : Theme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(prominent ? Color.clear : Theme.rule))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}
