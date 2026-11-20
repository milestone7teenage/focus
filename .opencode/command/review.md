---
description: Review current changes for bugs and regressions
---

Review the current changes in Focus.

Inspect the git diff and relevant surrounding code only.

Look for:
- Bugs
- Swift 6 concurrency violations
- Data loss risks
- Notification scheduling regressions
- Recurring-task reset bugs
- Timezone or DST issues
- UX invariant violations
- Missing tests

Rules:
- Do not edit files.
- Do not refactor.
- Do not report stylistic preferences as bugs.
- Prioritize findings by severity.
- Include file and line references where possible.
- If no meaningful issues are found, say so.