# Changelog

## 0.6.0 (2026-10-28)

- A new header runs across the whole window, with larger My scores and Team tabs in the middle and the copy, export and Settings buttons at the right. The sidebar's General and Categories tabs match its look.
- Official app: Teams. Sign in with Google, make a team with Vibemetric Pro, and invite teammates by email. An invitation shows up as a card on the Team tab, where one click accepts it. Each member picks which score to share, and a shared score shows the same Summary and category lines as their own result.
- Official app: choose the name your teammates see, when you sign in or later in Settings → Account.
- Official app: Settings has an Account section for Google sign-in and a separate Vibemetric Pro section for your plan and Pro key.

## 0.5.2 (2026-10-27)

- A result's categories can be shown as a radar chart: switch between Text and Radar next to "Details" (formerly "Focus on these next"). The chart shows all 10 categories, with the previous score as a dashed outline. Click a category's name to open its quick lines and full details in a panel over the chart. Vibemetric remembers which view you picked.

## 0.5.1 (2026-10-26)

- The Summary and each category's quick lines are short and plain again: one everyday sentence each, without tool or project names. Any line that still comes back long is rewritten shorter before the result is shown.

## 0.5.0 (2026-10-25)

- Each category in a new score shows two quick lines under its name: what works, with a green check, and what holds it back, with an amber mark. Results scored before this version keep their single line.
- Official app: a deep dive opens in three tabs, Problem, Fix and Root cause, like a category's details. The problem reads as a short story (what you wanted, what you did, what happened, what you keep dealing with) under a highlighted summary, and the prompt to make the fix sits in its own panel, always shown, with a larger Copy button.

## 0.4.16 (2026-10-25)

- Automatic scores can run on the days you choose, not only every day: pick days such as every Monday, or Monday and Wednesday, in Settings → Schedule. "Next" shows the day and time of the next score, such as "Tomorrow 2:00pm" or "Wednesday 2:00pm".

## 0.4.15 (2026-10-25)

- New scores open with a Summary: 4 to 6 plain-language points, what you do well first, then what holds you back, written so anyone can follow them. Results scored before this version keep "What you're doing well".

## 0.4.14 (2026-10-25)

- Scoring rubric 5. Each category now lists the habits behind its score, like "Changes are checked in the real flow". Each habit is marked Yes, Partly, Not yet, or Not enough evidence, with a real example from your sessions, and a count when enough tasks were read. Missing evidence never lowers a score, and a score change names the new evidence behind it. Because the rubric changed, your next score starts a new baseline.
- Opening a category shows tabs: Problem, Solution, Your habits, and Strengths. Go deeper sits below them.
- Scores finish in about two minutes. The card is written in parts at the same time, which reuse the work already read instead of paying for it again.
- Scoring keeps going if your Mac sleeps partway through.
- Official app: Go deeper stands out more, with a sparkle icon and an outline.

## 0.4.13 (2026-10-22)

- "What you're doing well" shows its points in a rounded card that matches the category list, with a green dot for each point and more space between lines.

## 0.4.12 (2026-10-22)

- "Focus on these next" lists every category in one card. Each row has a ring filled to the score, the category's name with its issue underneath, and a chevron. Click a row to see the full explanation and the fix.

## 0.4.11 (2026-10-22)

- Each engine in the Engine switch says whether it's ready: Ready, Not installed, Not signed in, or Can't start. When the selected engine can't score, Vibemetric says what's missing and gives the Terminal command to fix it, with a Copy button. If you have the Claude desktop app but not Claude Code's `claude` command, it says so plainly.
- On a new install, Vibemetric uses whichever engine works. Once you've picked or used one, it keeps your choice.
- Category boxes have a new layout: the name and score centered on top, the issue and the fix side by side, and a "See details" bar at the bottom that opens the full explanation.

## 0.4.10 (2026-10-22)

- The top of a result shows only its date, and in place of the band label, how much the score changed since your previous one (for example "↑ 7 since Oct 21"). "Few sessions were examined" moves into "About this score".
- The toolbar keeps the same buttons in the same place on every screen; the export buttons are greyed out when no result is open.
- The past results and deep dives lists no longer have a heading, so a click there no longer folds the list.

## 0.4.9 (2026-10-22)

- Each category box shows its score as dots and "6/10" on the right of its banner, in place of the icon.
- New scores write "What you're doing well" and each box's issue and fix as plain, complete sentences, without shorthand.

## 0.4.8 (2026-10-22)

- A simpler result screen: your score, what you're doing well, and one box per category with its score, a one-line issue and a one-line fix. Click a box to see the full explanation, evidence and steps. New scores write these short lines; older results use their existing text.

## 0.4.7 (2026-10-22)

- ⌘W closes the main window and leaves the menu bar panel open, even when the panel is in front. Esc or a click elsewhere still closes the panel.

## 0.4.6 (2026-10-20)

- The sidebar keeps its width when you make the window smaller: the score card narrows instead, and the window stops shrinking once the card reaches its minimum. The sidebar never gets narrower than its minimum and can be dragged much wider than before.

## 0.4.5 (2026-10-20)

- Details page: each category in "All 10 categories" starts with its own icon in a round badge (black in light mode, white in dark mode). The verdict under each name is a single line, and the question each category answers is no longer shown.

## 0.4.4 (2026-10-20)

- Scores judge the habits you use now: a habit you've since corrected no longer counts against you.
- Score cards explain each problem more clearly: what you set out to do, what you and the AI each did, and what was left for you to handle. Each solution says who changes what, and why that fixes the problem.
- Official app: after you apply a deep dive's fix with its copied request, the report shows the verified result, with what changed, how it was checked, and an "Applied" tag. Later scores can take that verified change into account.
- Official app: a deep dive's web research only looks up the setup instructions for the tools it recommends.

## 0.4.3 (2026-10-19)

- Scoring (rubric 4): running with a permission-bypass mode no longer costs a point. Security is scored only on the restrictions, hooks, isolation and checks your records show. Because the rules changed, your next score starts a new baseline instead of being compared with older scores. Older results keep the deduction they were scored with.

## 0.4.2 (2026-10-19)

- Official app: a deep dive now sees your earlier deep dives, up to ten from the same score and ten in the same category from other scores, so running one again finds a different bottleneck instead of repeating the last one.

## 0.4.1 (2026-10-18)

- While scoring, a progress bar shows the percentage and the stage: preparing, reading sessions ("23 of 70"), then writing your score. The menu bar and the sidebar show the percentage too.
- Scores finish within about 8 minutes, even with a long history. The scorer reads about 70 sessions in full: every session since your last score first, then the most telling ones for each category, then a spread across projects and dates. Counts and patterns still cover every session.
- If a score is still reading at 6.5 minutes, Vibemetric asks it to stop and write the card from what it has read, instead of running until it times out. The card's scope notes when that happened.
- The "low coverage" note compares the sessions read against that 70-session target.

## 0.4.0 (2026-10-18)

- Official app: anonymous usage counts (installs, app opens, and each assessment's engine, model, session count, duration and score) help decide what to fix next. No transcripts, prompts, notes, paths or project names are sent. Turn it off in Settings → Usage Data.
- Details page: Issues and each category's Problem now list only problems. What you already do well in a category appears in its own "What's working" box above the Problem. Applies to new scores; older results show as before.
- Faster scans for long histories: Vibemetric keeps a small summary of each session (counts, signals and token use, no conversation text beyond a short title) and parses only transcripts that are new or have changed. Scores still cover your whole history, and the evidence the scorer reads is unchanged.
- Each score scans again first, so a manual score includes sessions from since the app opened, not only since the last daily score.
- Scoring with token usage no longer reads every transcript a second time.
- Less memory while Vibemetric sits in the menu bar: full session timelines are read only for the sessions picked as evidence.
- `vibemetric scan` and `pack` take `--home DIR` and `--cache FILE`; `pack` also writes `usage.tsv` and `model-settings.md`, like the app.

## 0.3.5 (2026-10-16)

- Scoring: permission bypass now affects Security only through its 1-point deduction, and not following last time's suggestion no longer lowers a score by itself.

## 0.3.4 (2026-10-16)

- Details page: the fixes are headed "Issues (1/9)" instead of "Problems".
- Official app: under each Solution, a "Go deeper" panel says what a deep dive adds (the root cause with examples from your sessions, a step-by-step fix for your projects, and a ready-to-paste prompt) next to Run deep dive. Once a category has a deep dive on that score, it shows "View your deep dive" with a small "Run again".

## 0.3.3 (2026-10-16)

- Every problem's Solution is now a plain bullet list, laid out like Problem: what to change and where, how to try it on your next task, and how you'll know it worked. New scores write these steps for every category below 10; older scores show the one-line fix.
- The Prompt and Steps tabs are gone, and every problem card has the same plain border.
- Official app: deep dives focus on one bottleneck: where you're stuck, why, the fix with text to copy, what to do next time, and the sessions behind it. Cause details fold away, with animation that respects Reduce Motion.
- Official app: up to five deep dives can run at once.
- Official app: "Run deep dive again" on the same score asks first, since it reads the same saved evidence; score again to see the effect of your changes.

## 0.3.2 (2026-10-15)

- Details page: the fixes are headed "Problems (1/9)", with larger previous and next arrows right beside the heading. Section titles are larger and bolder.
- Menu bar: the popover has a nearly solid background, so its text stays readable over busy windows.
- Official app: "Run deep dive" opens the Categories tab and shows the deep dive's live progress there, with elapsed time, Cancel and a log of what the engine reads.
- Official app: the deep dive key sheet leads with "Get Pro: 7-day free trial", with the key field below for people who already have one.

## 0.3.1 (2026-10-14)

- Each fix in "What to fix" can take an optional module's action under its Solution; the official app shows "Run deep dive" there.
- Official app: without Pro, "Run deep dive" asks for an API key or links to Pro instead of jumping to Settings, and starts the deep dive once a key is added.

## 0.3.0 (2026-10-14)

- Every fix and category shows two parts: **Problem**, as short bullets with the sessions it comes from, and **Solution**, with the fix in one line and Prompt and Steps tabs.
- The summary at the top of the score is smaller and, on new scores, written as 2–3 plain-language bullets.
- Menu bar: two problems, each with its fix, and the full problem sentence instead of a count.
- Main window: what to fix is a carousel, with the next fix showing at the edge.
- New scores describe problems in plain words: what happened, how often and what it cost, without jargon or praise mixed in.

## 0.2.0 (2026-10-13)

- Vibemetric is open source under the MIT license. This repository has the complete free app.
- Builds from source have no Pro features and don't check for updates. The official app from vibemetric.app keeps both.
- Optional modules attach through the plug-in points in `Sources/VibemetricAppKit/Extensions.swift`.
- Menu bar: the most urgent fix comes first, with the score as a small line below it.
- Score details are easier to read: short fields and a new General layout.
- Score explanations use month-day dates and name the real projects the evidence comes from.
- Recommendation tables stay intact in narrow windows.
- Scanning uses less memory: each transcript's temporary objects are freed as soon as it's read.

Versions before 0.2.0 were released from a private repository. Their history is not in this repository.
