# FreeBuff Termux Constitution

## Principles

1. Preserve the public API and exact positional argument transport.
2. Verify immutable source/runtime integrity before execution. Fail closed on
   invalid configuration, missing work directories and broken runtime state.
3. Preserve terminal input and private login URLs; clean owned process groups
   on termination without leaving descendants running.
4. Demonstrate defects with behavioral regressions before fixes. Run Linux
   behavior on Linux and distinguish host evidence from real Termux validation.
5. Keep specifications, Linear status and verification evidence consistent.
   Sentry triage is read-only and redacted; secrets stay outside version control.

## Workflow and governance

Use specification → plan → tasks → regression → narrow patch → independent
security review → required gates. Prefer the codebase-memory graph for discovery,
with filesystem fallback for shell/config files or insufficient graph results.
Changes to these principles require a recorded compatibility assessment.
Unavailable external or device checks remain explicitly open.

Version: 1.0.0 | Ratified: 2026-09-08 | Last amended: 2026-09-08
