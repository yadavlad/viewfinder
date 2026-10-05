# Dev Rules
- Native only: SwiftUI + Apple frameworks. No third-party packages.
- Lean: smallest working solution. No abstractions, no extra features.
- Plan first: before editing, state a short plan (files + what changes), then proceed.
- Never edit .pbxproj or Info.plist; tell me to change settings in Xcode instead.
- Verify by building: xcodebuild -scheme Viewfinder -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
- Fix build errors yourself before reporting back.
- Be terse. No explanations unless asked.

# Git Rules
- One task = one small PR. Never merge your own PR.
- Stay inside the task. No unrequested refactors, renames, or formatting.
- Ask first before changing dependencies, CI, build/signing config, or deleting files.
- Never commit secrets or large binaries. Never touch tags or releases.
- Run build + tests before opening a PR. In the PR, say what changed, how it was tested, and what needs on-device testing.
- If unclear, stop and ask.
