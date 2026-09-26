# Runtime and installer boundary hardening

Status: host implementation complete; device acceptance pending.
Baseline: `979bb2b8230d68c68e86e7a69e6305c82b74ead1`.

The 2026-09-08 review found nine defects. Fix them without changing the public
TypeScript API or enabling runtime telemetry.

## Requirements

- F033: verified installer/bootstrap scripts run from checkout and release artifacts
  without executable mode. Hash validation precedes execution.
- F034: the shell wrapper preserves piped and terminal stdin.
- F035: isolated PRoot exposes a private guest-visible URL queue. The actual bridge
  accepts that location, rejects other paths and preserves URL redaction.
- F036: all three launch paths stop on missing guest CWD; valid paths and positional
  arguments retain their exact values.
- F037: timeout, abort, output overflow and forwarded host signals terminate owned
  process groups even when the direct child exits before a descendant.
- F038: normal wrapper completion cleans up surviving owned descendants.
- F039: doctor rejects each invalid manifest field independently in both output modes.
- F040: doctor checks actual runtime pointers, recognizes guest-absolute links and
  reports missing or incorrect pointers as degraded.
- F041: checksum tests allow provenance comments and prove tampered archives are
  rejected before extraction or execution.

## Acceptance evidence

Focused tests first reproduce each defect and then pass with the patch. Required
host gates: build, lint, formatting, Jest, shell syntax, ShellCheck, shfmt, actionlint,
Bats and package-consumer smoke. Linux process tests run on Linux. Actual Android
PTY restoration and isolated PRoot browser delivery remain separate device checks.

## Integrations

Use upstream Spec-kit v1.0.0 Codex skills, finding-level Linear issues, independent
Codex Security boundary/review checks, and read-only Sentry triage when configured.
Never commit credentials or put raw Sentry event payloads in issues.
