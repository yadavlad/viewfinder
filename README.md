# Rules
- Native only: SwiftUI + Apple frameworks. No third-party packages.
- Lean: smallest working solution. No abstractions, no extra features.
- Plan first: before editing, state a short plan (files + what changes), then proceed.
- Never edit .pbxproj or Info.plist; tell me to change settings in Xcode instead.
- Verify by building: xcodebuild -scheme Viewfinder -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
- Fix build errors yourself before reporting back.
- Be terse. No explanations unless asked.
