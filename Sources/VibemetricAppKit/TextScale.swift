import AppKit
import SwiftUI

/// App-wide text zoom (⌘+ / ⌘- / ⌘0). macOS has no Dynamic Type, so every font in the app
/// goes through `scaledFont`, which multiplies its point size by the current scale.
enum TextScale {
    static let storageKey = "textScale"
    static let steps: [Double] = [0.85, 1, 1.15, 1.3, 1.5, 1.75, 2]

    static func bigger(_ current: Double) -> Double { steps.first { $0 > current + 0.001 } ?? steps.last! }
    static func smaller(_ current: Double) -> Double { steps.last { $0 < current - 0.001 } ?? steps.first! }
}

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    public var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.textScale) private var scale
    var size: CGFloat
    var weight: Font.Weight
    var design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// A system font whose size follows the app's text zoom.
    public func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

/// View-menu items for zooming, plus ⌘= (the unshifted ⌘+ key most people press).
struct TextScaleCommands: Commands {
    @AppStorage(TextScale.storageKey) private var scale = 1.0

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Bigger Text") { scale = TextScale.bigger(scale) }
                .keyboardShortcut("+")
            Button("Smaller Text") { scale = TextScale.smaller(scale) }
                .keyboardShortcut("-")
            Button("Actual Size") { scale = 1 }
                .keyboardShortcut("0")
        }
    }

    /// SwiftUI can't bind one menu item to both ⌘+ and ⌘=, so catch ⌘= here.
    static func installEqualsShortcut() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command, event.charactersIgnoringModifiers == "=" else { return event }
            let defaults = UserDefaults.standard
            let current = defaults.object(forKey: TextScale.storageKey) as? Double ?? 1
            defaults.set(TextScale.bigger(current), forKey: TextScale.storageKey)
            return nil
        }
    }
}
