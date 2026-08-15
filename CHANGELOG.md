# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added (2026-08-15)

- **Diverged-fork threshold/alert**: `validate-and-report.sh`'s "diverged"
  branch (ahead-of-and/or-behind upstream) previously reported "OK, by
  design" forever, for any amount of divergence, with no alert. Now files
  a real GitHub issue (state-file deduped, same pattern as release
  detection) whenever the fork is genuinely behind upstream AND that
  behind-count has grown since the last report — catching real,
  unreconciled upstream work (e.g. a maintainer's follow-up fix on a PR
  this fork already got merged) instead of silently accumulating it.
  8 new bats tests.

### Fixed (2026-08-15)

- **Stale host paths**: `CORE_DIR`/`CATALOG_DIR` defaults (in both
  `validate-and-report.sh` and `install.sh`) still pointed at the original
  WSL box's directory layout (`~/projects/dune/...`); this account's repos
  now live at `~/projects/repos/...` on the current host. Both scripts'
  `set -euo pipefail` meant the entire monitor aborted immediately on
  every run since the host move — combined with no crontab ever having
  been installed on the new host either, this monitor had not actually
  run at all since the migration. Now correctly defaults to the real
  current path and still honors `ACP_CORE_DIR`/`ACP_CATALOG_DIR`
  overrides for future host moves.
- **Hardcoded `/home/darkdante/...` paths** (6 occurrences across
  `validate-and-report.sh` and `install.sh`'s printed crontab line):
  `darkdante` was the old WSL box's real username; this account runs as
  `root` on the current host. Replaced with `${HOME}` throughout, matching
  `check-upstream-prs.sh`'s own already-correct convention.
- **SC2168 shellcheck error** (`local` used outside a function) in
  `validate-and-report.sh` — a real, pre-existing error, not just a
  warning, that had been failing this repo's own CI on `main` since at
  least 2026-08-10.

### Added (2026-08-10)

- **Upstream test drift detection** in `validate-and-report.sh` (section 6b).
  Compares Core fork tests against upstream, reports new/diverged tests.
- **Dead-man's switch**: timestamp check warns if monitor hasn't run in >90 min.
- **Network timeouts**: 60s on `gh pr/release`, 30s on `gh run`, 10s on `gh auth`.
- **State pruning**: state files older than 30 days auto-deleted.
- **20 bats tests** for `validate-and-report.sh` notification logic.

### Fixed (2026-08-10)

- **Hourly "All Clear" spam**: suppressed identical clean-state notifications.
  Now only sends on transition from issues→clean.
- **Log location**: moved from world-readable `/tmp` to `~/.cache/` (mode 700).
- **State files**: moved from `/tmp` to `~/.cache/`.
- **GH_TOKEN pre-flight**: scripts exit with clear error if unauthenticated.
- **Flock locking**: prevents concurrent cron runs.
- **install.sh paths**: updated to 2026-07-25 directory layout.

### Added (2026-07-25)

- Home directory structure-lint integration in `validate-and-report.sh` (section 6).
- Failed systemd unit detection (section 5).
- CI failure detection across all 7 monitored repos.
- PR mergeability checks for Core and Catalog forks.
- Catalog fork sync with same safety guards as Core fork.
- `sync_decision()` extraction into `lib/sync-direction.sh` with bats test suite.
- Discord webhook restoration and notification infrastructure.
