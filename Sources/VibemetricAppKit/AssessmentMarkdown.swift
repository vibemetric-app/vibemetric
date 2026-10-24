import Foundation

/// Keep saved assessments linked to the same pstack sources as new assessments.
func assessmentMarkdown(_ text: String) -> AttributedString {
    let updated = text
        .replacingOccurrences(of: "https://github.com/backnotprop/pstack/blob/main/",
                              with: "https://github.com/cursor/plugins/blob/main/pstack/")
        .replacingOccurrences(of: "https://raw.githubusercontent.com/backnotprop/pstack/main/",
                              with: "https://raw.githubusercontent.com/cursor/plugins/main/pstack/")
        .replacingOccurrences(of: "backnotprop/pstack", with: "pstack")
    return markdown(updated)
}
