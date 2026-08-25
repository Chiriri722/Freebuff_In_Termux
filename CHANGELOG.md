# Changelog

All notable changes to this project are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases use Semantic Versioning.

## [Unreleased]

### Added

- Session-scoped login URL bridge with private permissions and atomic consume.
- Structured PRoot command execution, identifier validation, lifecycle manager, strict JSON doctor, and release gates.
- Architecture-aware Node.js download with official SHA-256 verification.
- Installer-owned runtime markers and manifest-preserved Node/FreeBuff archive checksums.
- Bounded programmatic output, AbortSignal cancellation, timeout escalation, and Linux process-group cleanup.
- ShellCheck, shfmt, Bats, npm payload, workflow pinning, and release-contract CI gates.
- Durable multi-file installer transactions with hard-exit recovery and failpoint tests.
- Exact npm payload allowlisting, clean-consumer installation smoke, and executable release preflight checks.

### Changed

- Installers use canonical wrapper/bridge files, pinned dependencies, atomic managed-file replacement, and rollback.
- Shared storage bind is disabled by default and requires explicit opt-in.
- PRoot-Distro v5 execution uses `list --quiet` and `--isolated --shared-home`; rootfs OCI images are digest-pinned.
- The shell wrapper launches PRoot in a dedicated `setsid` process group and escalates termination after a bounded grace period.
- The install manifest is schema 2 and records the validated PRoot image digest.
- The npm package publishes only runtime/operator artifacts through explicit ESM exports and a files allowlist.
- Runtime pointers are project-owned under `/opt/freebuff-termux`; installers no longer create global `/usr/local/bin` links.
- Release evidence records the tested runtime commit and is committed as the only change before tagging.
- CI and releases execute the real installer hard-crash recovery contract in an isolated root filesystem.
- Installer integration covers every transactional failpoint under both SIGKILL recovery and SIGTERM rollback.

### Security

- Remote installation rejects branches and verifies full commits or checksummed Release artifacts.
- Authentication URLs are no longer written to a fixed shared file or printed by default.
- Global Termux package upgrades and shell-interpolated user arguments were removed.
- Host probes no longer evaluate command or HOME strings through a shell.
- GitHub Actions dependencies are pinned to immutable commit SHAs.
- Existing managed paths and hashes are validated before repair, update, uninstall, or replacement.
- FreeBuff npm tarballs are SHA-512 verified before installation.
- Pre-existing runtime roots are rejected unless manifest-owned or marked with the exact expected archive digest.
- Login bridge session paths use a traversal-safe exact pattern instead of a slash-matching shell glob.
- Final release archives are structurally validated and checked against an independently captured SHA-256 before upload.

### Fixed

- An early SIGTERM arriving after PGID publication but before the wrapper's main wait now follows the same bounded TERM-to-KILL cleanup path instead of hanging indefinitely.
