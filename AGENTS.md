# Focus Project Instructions
# FOCUS — Strict Rules

## Scope & Diff Discipline
- Read ONLY the files explicitly mentioned by the user or directly required for the specific error. Never scan the whole repository.
- Make minimal, surgical edits only. Do NOT refactor, rename, reformat, or touch unrelated files.
- Before editing more than 2 files, explain the root cause in 3–5 bullet points and wait for approval.
- Never run broad searches across the codebase unless asked.

## Swift & iOS Build Rules
- Target: iOS, Swift 6 strict concurrency (`@MainActor` for UI/ViewModels, `Sendable` compliance, no `DispatchQueue.main.async` workarounds).
- No third-party dependencies unless explicitly approved.
- Keep `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `ASSETCATALOG_COMPILER_APPICON_NAME`, and `-sdk iphoneos` intact in `project.yml` and CI workflows.
## Environment
- Development is performed on Windows.
- macOS and Xcode are unavailable locally.
- Never run xcodebuild locally.
- Builds, tests and IPA exports run through GitHub Actions.
- Project generation uses XcodeGen and project.yml.

## Token Efficiency
- Inspect only files relevant to the current task.
- Never scan the entire repository without a concrete reason.
- Use targeted search before opening files.
- Do not reread files already inspected unless they changed.
- Avoid repeating project summaries.
- Keep answers concise.
- Make minimal surgical edits.
- Never refactor unrelated code.
- Never generate multiple alternative implementations unless requested.
- Do not retry failed commands blindly.
- Inspect the exact error before attempting a fix.
- Stop when the task is complete.

## Workflow
1. Understand the task.
2. Inspect the minimum necessary files.
3. State a short plan for non-trivial changes.
4. Implement the smallest solution.
5. Inspect the diff.
6. Run relevant tests or validation.
7. Report changed files and results.

## Git Safety
- Never commit automatically.
- Never push automatically.
- Never reset, force push, or discard user changes.
- Ask before destructive operations.
- Preserve unrelated working-tree changes.

## Focus Architecture
- iOS 17+
- Swift 6
- SwiftUI
- SwiftData
- UserNotifications
- Strict concurrency enabled
- Bundle ID: com.placeholder.focus

## Swift Rules
- Respect Swift 6 strict concurrency.
- Prefer existing architectural patterns.
- Do not introduce dependencies without approval.
- Do not duplicate existing services.
- Avoid unnecessary abstractions.
- Keep Domain independent from UI.
- Check existing protocols before creating new ones.

## Notifications
- Preserve the T0, T+10, T+20, T+30 sequence.
- Maximum 4 notifications per task.
- Respect the global notification budget.
- SEEN must cancel remaining notifications.
- Never bypass existing scheduling rules.

## Recurring Tasks
- Preserve template/instance separation.
- Reset idempotently using local date YYYY-MM-DD.
- Account for timezone changes and DST.

## UI
- Preserve existing gestures and UX invariants.
- Long press completes tasks.
- Left swipe deletes with Undo.
- Right swipe snoozes for 30 minutes.

## CI
- CI is the source of truth for compilation and tests.
- Never claim code builds without CI confirmation.
- Check workflow logs when a build fails.
- Fix the smallest relevant issue.

## Reporting
After each task, report:
- What changed
- Files touched
- Tests performed
- CI status, if available
- Any remaining risks