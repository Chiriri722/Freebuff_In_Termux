---
status: pending
commit: '<40-character-tested-runtime-commit>'
tested_at: '<ISO-8601 UTC>'
android: '<version>'
termux: '<version and F-Droid/GitHub source>'
proot_distro: '<version>'
architecture: '<aarch64-or-x86_64>'
tester: '<redacted identifier>'
---

# Termux release evidence: `<tag>`

Copy this file to `docs/termux-evidence/vX.Y.Z.md`. Keep `status: pending` until every required check passes on the exact tested runtime `commit` above. Commit this evidence as the only file changed after that tested commit, then place the release tag on the evidence-only commit. Never record tokens, login URLs, credentials, or user absolute paths.

## Environment

```text
termux-info: <redacted output or artifact reference>
dpkg --print-architecture: <value>
proot-distro --version: <value>
git rev-parse HEAD: <40-character SHA>
```

## Required checks

- [ ] Fresh install used the exact commit/tag artifact and all digest/checksum checks passed.
- [ ] `freebuff-termux doctor --json` returned schema 2 without paths, URLs, or tokens.
- [ ] Reinstalling the same ref was idempotent and preserved a sentinel project file.
- [ ] Normal FreeBuff exit preserved its exit code and left no session, watcher, or PRoot process.
- [ ] Ctrl-C and SIGTERM restored the terminal and left no process in the dedicated process group.
- [ ] Login URL opened or copied once, was never recorded here, and its bridge file was removed.
- [ ] Two concurrent sessions did not cross-deliver login URLs.
- [ ] Shared storage was absent by default and worked only after explicit opt-in.
- [ ] A deliberate checksum mismatch stopped before install and preserved managed/user files.
- [ ] `repair`, immutable `update`, and `uninstall` preserved distro runtime, projects, and credentials as documented.

## Results

| Check                       | Result  | Redacted evidence                            |
| --------------------------- | ------- | -------------------------------------------- |
| fresh install / rerun       | pending | `<artifact or log reference>`                |
| normal / Ctrl-C / SIGTERM   | pending | `<exit codes and zero residual PID summary>` |
| URL / concurrent sessions   | pending | `<pass/fail summary only>`                   |
| storage off / opt-in        | pending | `<mount visibility summary>`                 |
| checksum failure / rollback | pending | `<pass/fail summary>`                        |
| repair / update / uninstall | pending | `<preservation summary>`                     |

## Final review

- [ ] The tested runtime commit is an ancestor of the release tag commit.
- [ ] The exact evidence file is the only path changed between those commits.
- [ ] The release tag matches the package version.
- [ ] All rows pass on a supported architecture.
- [ ] Diff contains no secrets or local absolute paths.
- [ ] Set front matter to `status: passed` only after review.
