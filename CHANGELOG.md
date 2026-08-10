# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
