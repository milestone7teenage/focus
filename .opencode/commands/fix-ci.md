---
description: Diagnose and fix a CI failure with minimal changes
---

Analyze this CI failure.

Rules:
- Use the provided error log first.
- Identify the exact failure, not unrelated warnings.
- Inspect only relevant files.
- Do not scan the entire repository.
- Do not guess when the log is insufficient.
- Explain the root cause briefly.
- Implement the smallest appropriate fix.
- Do not refactor unrelated code.
- Inspect the final diff.
- Run local checks only if available.
- Never claim Xcode tests passed without CI evidence.
- Never commit or push.

CI log / error:

$ARGUMENTS