# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed (2026-08-17)

- **Divergence issue dedupe + auto-close** (#33): the diverged-fork alert
  added 2026-08-15 correctly suppressed same/shrinking-count spam, but a
  *growing* divergence still called `gh issue create` fresh every time
  instead of updating the issue already open for the same underlying,
  unreconciled divergence — confirmed in the wild as 7 separate duplicate
  open issues (#289, #297, #298, #300, #310, #312, #314) describing the
  exact same problem at different snapshots, none of which this script
  ever closed even after the divergence was actually reconciled (#279/#316).
  The state file now stores `BEHIND ISSUE_NUMBER` (space-separated,
  backward-compatible with the old single-number format) instead of just
  `BEHIND`: a growing count now comments on the tracked open issue instead
  of creating a duplicate (falling back to creating a fresh one only if no
  issue is tracked, or the tracked one was closed by someone else in the
  meantime), and the `BEHIND == 0` (resolved) path now auto-closes the
  tracked issue with a resolution comment instead of silently going green
  forever with an open issue nobody ever closes. 9 new bats tests cover the
  state-file format (old/new/empty), the reuse-vs-create branch, and the
  auto-close-on-resolve branch.

### Fixed (2026-08-15, second pass)

- **`gh issue create` crash on a nonexistent `priority:high` label**: three
  call sites in `validate-and-report.sh` (upstream release detection, PR
  conflict filing, and the new diverged-fork alert added earlier the same
  day) applied `priority:high` against `yacketrj/dune-awakening-selfhost-docker`,
  whose real label taxonomy uses `severity:*`, not `priority:*`. `gh issue
  create` fails outright on a nonexistent label, and this call wasn't
  guarded the way most others in this file are — under `set -euo
  pipefail`, this crashed the entire script the moment any of these three
  code paths were reached. Found on the very first real end-to-end run
  after installing the corrected crontab (the upstream-release-detection
  path fired immediately, since v1.3.87 was already released and unknown
  to this monitor's state cache). Fixed to `severity:high`, confirmed
  against the repo's real label list.

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
