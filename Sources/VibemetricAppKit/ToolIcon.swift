import SwiftUI
import VibemetricCore

/// Original publisher artwork, bundled locally so showing history never needs a network request.
struct ToolIcon: View {
    let tool: AgentTool
    @Environment(\.textScale) private var scale

    var body: some View {
        Image(nsImage: tool == .claudeCode ? Self.claude : Self.codex)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 26 * scale, height: 26 * scale)
            .accessibilityHidden(true)
    }

    private static let claude = image("claude-code")
    private static let codex = image("codex")

    private static func image(_ name: String) -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Brand"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing bundled tool artwork: \(name)")
        }
        return image
    }
}
