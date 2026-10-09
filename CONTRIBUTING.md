# Contributing to Vibemetric

Thank you for your help. This file tells you how to build, test and send a change.

## Build and test

You need macOS 14 or later and Xcode 15.3 or later (Swift 5.10+).

```bash
swift build
swift test
swift run VibemetricApp        # run the app from source
./scripts/build-app.sh         # build/Vibemetric.app and build/Vibemetric.dmg
```

`swift test` uses fixture CLIs. It never calls Claude Code or Codex and never spends model usage. The live tests in the README are optional.

You never need the `Pro/` folder. It holds the private module of the official app, and git ignores it.

## Pull requests

1. Open an issue first for a large change, so we can agree on the approach.
2. Make your branch from `develop`, and open the pull request into `develop`.
3. Keep one topic in each pull request. Add or update tests for changed behavior.
4. Make sure that `swift build` and `swift test` pass. CI runs both on each pull request.
5. Never put real session transcripts, project names, keys or personal data in code, tests or screenshots. Use fictional data.

## Plug-in points

The plug-in points in `Sources/VibemetricAppKit/Extensions.swift` are a stable interface: the official app's Pro module uses them. Open an issue to discuss a change to them before you send a pull request. Describe new plug-in points by where they attach, not by a specific feature.

## Developer Certificate of Origin (DCO)

Each commit must have a `Signed-off-by` line. With this line, you certify the [Developer Certificate of Origin](https://developercertificate.org): you wrote the change, or you have the right to submit it under the MIT license.

```bash
git commit -s -m "Your message"
```

The `-s` option adds the line with the name and email from your git configuration. CI rejects a pull request that has a commit without it. To add the line to earlier commits on your branch, run `git rebase --signoff develop` and push again.

## Name and logo

The code is MIT-licensed, but the Vibemetric name and logo are not. If you publish a fork, use a different name and icon.
