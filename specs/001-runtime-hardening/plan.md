# Implementation plan

1. Install pinned upstream Codex integration and establish this specification.
2. Link F033–F041 to Linear; verify read-only Sentry prerequisites.
3. Reconcile independent boundary investigation before runtime edits.
4. Add failing tests; fix installer entrypoints, validation and CWD guards.
5. Fix stdin, guest URL mapping and process ownership with Linux regressions.
6. Run focused gates and obtain an independent postpatch review.
7. Run all host gates and update findings, tasks and integration state with evidence.

Keep argument transport positional, integrity pins static and URLs redacted. Resolve
runtime pointers in the guest namespace. Preserve Windows child-close behavior.
The installed PowerShell Spec-kit scripts support Windows development; product
scripts and Linux regressions use Bash. Set `SPECIFY_FEATURE_DIRECTORY=specs/001-runtime-hardening`
to resolve this spec while on `main`.
