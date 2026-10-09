import Foundation
import Testing
@testable import VibemetricAppKit

struct ReasonFormatTests {
    @Test func bulletLabelsBecomeBold() {
        #expect(ReviewMarkdown.boldLabel("Demo web: CLAUDE.md has no run commands") == "**Demo web:** CLAUDE.md has no run commands")
        #expect(ReviewMarkdown.boldLabel("**Acme backend:** 501 lines") == "**Acme backend:** 501 lines")
        #expect(ReviewMarkdown.boldLabel("No colon in this bullet") == "No colon in this bullet")
        #expect(ReviewMarkdown.boldLabel("See https://example.com: a link") == "See https://example.com: a link")
        #expect(ReviewMarkdown.boldLabel("A label that is much too long to be a heading for one bullet: text").hasPrefix("A label"))
    }
}

struct TableLayoutTests {
    @Test func onlyRanksKeepTheNarrowFirstColumn() {
        #expect(ReviewMarkdown.isRank("1"))
        #expect(ReviewMarkdown.isRank("#2"))
        #expect(ReviewMarkdown.isRank("3."))
        #expect(!ReviewMarkdown.isRank("Claude Code main · Opus 5"))
        #expect(!ReviewMarkdown.isRank("Light"))
    }

    @Test func reviewMarkdownKeepsBlocksAndInlineMeaning() throws {
        let source = """
        **Start with `guard`.**

        | Priority | Skill | Why | When |
        | --- | --- | --- | --- |
        | 1 | [guard](https://skills.sh/repo/guard) | Check a \\| b | Before changes |

        ### Install

        ```sh
        npx skills add repo/skills --skill guard
        ```

        ### Try this first

        ```text
        $guard Check the boundary. Report the result.
        ```
        """
        let blocks = ReviewBlock.parse(source)
        #expect(blocks.count == 6)
        #expect(blocks[1] == .table(headers: ["Priority", "Skill", "Why", "When"], rows: [
            ["1", "[guard](https://skills.sh/repo/guard)", "Check a \\| b", "Before changes"]
        ]))
        #expect(blocks[3] == .code("npx skills add repo/skills --skill guard"))
        #expect(blocks[5] == .code("$guard Check the boundary. Report the result."))
        let inline = markdown("**First** use [`guard`](https://skills.sh/repo/guard)")
        #expect(String(inline.characters) == "First use guard")
        #expect(inline.runs.contains { $0.link == URL(string: "https://skills.sh/repo/guard") })
        #expect(inline.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(ReviewBlock.parse("- **[guard](https://skills.sh/test/guard)** — Keeps execution bounded.") == [.bullet("**[guard](https://skills.sh/test/guard)** — Keeps execution bounded.")])
        #expect(ReviewBlock.parse("Legacy review\nwith plain text") == [.paragraph("Legacy review\nwith plain text")])
        #expect(ReviewBlock.parse("````text\n$guard ``` literal\n````") == [.code("$guard ``` literal")])
    }
}
