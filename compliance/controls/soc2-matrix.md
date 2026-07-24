# SOC 2 Control Matrix — acp-ops-monitor

This repo is a set of bash cron scripts (PR tracking, fork sync, CI checks,
Discord notifications). It holds no user data, no PII, and no payment data.
Its risk surface is narrow but not zero: the scripts run with `gh`/`git`
credentials capable of force-pushing to real repositories on an hourly,
unattended basis. This matrix scopes controls to that actual risk surface
rather than a generic enterprise template.

This is **not a certification claim**. See
[Arrakis-Control-Panel's SOC 2 Alignment Notes](https://github.com/yacketrj/Arrakis-Control-Panel/blob/main/docs/soc2-alignment.md)
for the ecosystem-wide compliance posture this repo contributes evidence to.

| Control Area | Control | Status | Evidence |
|---|---|---|---|
| Security | Destructive git operations gated by direction-aware logic, not raw SHA comparison | ✅ Implemented | `lib/sync-direction.sh`, `tests/sync-direction.bats` |
| Security | Secret scanning (Gitleaks, ggshield, Trivy secrets scanner) on every commit and PR | ✅ Implemented | `.pre-commit-config.yaml`, `.github/workflows/ci.yml` |
| Security | SAST (Semgrep) on every PR | ✅ Implemented | `.github/workflows/ci.yml` |
| Security | No secrets committed to the repo; webhook URLs read from env var or gitignored local file | ✅ Implemented | `.gitignore`, `notify-discord.sh` |
| Security | GitHub Actions pinned to immutable commit SHAs (not floating tags/branches) | ✅ Implemented | `.github/workflows/ci.yml` |
| Availability | Required CI checks (`CI Gate`) must pass before merge | ⚠️ Partial | Workflow exists and consolidated into a single unambiguous `ci-gate` job in `ci.yml` (previously duplicated across two identically-named "CI Gate" workflows); branch protection enforcement tracked as a follow-up — see Known Gaps |
| Availability | Cron job failure does not corrupt repository state (idempotent, safe-to-retry operations) | ✅ Implemented | `lib/sync-direction.sh` guarantees no destructive op fires on an ambiguous or unsafe state |
| Processing Integrity | Shell logic covered by automated tests, not lint-only | ✅ Implemented | `tests/*.bats`, run in CI |
| Processing Integrity | Shell syntax/style linting | ✅ Implemented | ShellCheck in CI |
| Processing Integrity | GitHub Actions workflow linting (catches malformed job dependencies, invalid expressions, missing shell strictness) | ✅ Implemented | `actionlint` in CI, checksum-verified pinned-version binary download |
| Processing Integrity | Markdown documentation linting (catches broken fenced-code blocks, missing language hints, malformed structure) | ✅ Implemented | `markdownlint-cli2` in CI, config at `.markdownlint-cli2.jsonc` |
| Confidentiality | No database, no persistent user-identifying storage | ✅ Implemented | N/A by design — this repo has no data layer |
| Privacy | No PII collected, processed, or transmitted | ✅ Implemented | N/A by design |
| Change Management | All changes go through PR + required CI checks | ✅ Implemented (process) | GitHub PR history |
| Dependency Management | Automated dependency updates (GitHub Actions) | ✅ Implemented | `.github/dependabot.yml` |
| Dependency Management | Software Bill of Materials (SBOM) | ➖ Not applicable | This repo has no package manager, no `package.json`/`requirements.txt`, and ships no built artifact — it is plain bash scripts with only system-tool prerequisites (`git`, `gh`, `python3`), not bundled dependencies. There is no dependency tree to enumerate. Contrast with `Arrakis-Control-Panel`, which does generate a CycloneDX SBOM (`npm run sbom`) because it has a real npm dependency tree and ships versioned release artifacts — that is the correct place for SBOM in this ecosystem, not here. If this repo ever gains a real dependency manifest, this row must be revisited before it ships. |

## Known Gaps (Tracked, Not Hidden)

| Gap | Risk | Planned Resolution |
|---|---|---|
| Branch protection not enabled on `main` despite a required-looking "CI Gate" job | The gate is currently advisory; a direct push or an admin merge can bypass it | Enable branch protection requiring the `CI Gate` status check via `gh api repos/yacketrj/acp-ops-monitor/branches/main/protection` (see `compliance/runbooks/rollback.md` for the manual fallback if this is ever discovered disabled again) |
| No automated alert if the cron job itself fails to run at all (e.g. the host is down, or a crash happens before the notification step) | A silent outage of the monitoring system itself would only be caught by a human noticing the absence of expected hourly Discord messages | Add a dead-man's-switch style external check (e.g. a scheduled GitHub Actions workflow that alerts if no `/tmp/acp-cron.log` update has happened in >2 hours) — not yet implemented |
| `/tmp/acp-known-prs.txt` grows unbounded (append-only, never rotated) | Low-severity disk-hygiene issue, not a security risk (see `compliance/policies/log-retention.md`) | Migrate to the same overwrite-each-run JSON-cache pattern already used by `~/.cache/acp-pr-states.json` |

## Resolved (Previously Tracked Here)

| Former Gap | Resolution |
|---|---|
| `ludeeus/action-shellcheck@master`, `aquasecurity/trivy-action@master`, `gitleaks/gitleaks-action@v3` were floating branch/tag refs, not pinned SHAs | All three pinned to specific, verified commit SHAs in `.github/workflows/ci.yml`, matching the convention already used for `actions/checkout` |
| `returntocorp/semgrep-action` was unmaintained (no commits since Jan 2024; its current home, `semgrep/semgrep-action`, is archived) | Replaced with a direct `semgrep` CLI invocation in CI, matching `.pre-commit-config.yaml`'s local hook exactly — closes the local/CI parity gap this created |
| Two separate workflows were both literally named "CI Gate" (`ci.yml`'s internal job and a standalone `ci-gate.yml`), making branch-protection required-check configuration ambiguous | Consolidated into a single `ci-gate` job inside `ci.yml`; the standalone `ci-gate.yml` (whose only check, `bash -n` syntax validation, was a strict subset of what ShellCheck already covers) was removed |
| `p/bash` semgrep ruleset had been silently removed from Semgrep's public registry (confirmed via the registry API — the ruleset no longer exists at all, not just moved), causing the newly-added direct-CLI semgrep step to fail with an HTTP 404 the first time it actually ran with `--error` enabled | Removed the `p/bash` reference; shell-specific static analysis remains covered by the separate ShellCheck job |
| No GitHub Actions workflow linting — a malformed job dependency or invalid expression would only be caught by a live CI run failing | Added `actionlint` (checksum-verified pinned binary download, not a third-party Action wrapper) as its own CI job and local pre-commit hook |
| No markdown linting — 15 documentation files added during this repo's compliance/docs buildout had zero automated style/correctness checking | Added `markdownlint-cli2` as its own CI job and local pre-commit hook; found and fixed two real issues (a fenced code block with no language hint in `README.md`, missing blank lines around a fence in `compliance/runbooks/incident-response.md`) on first run |
| `lib/sync-direction.sh`'s destructive-reset safety logic had no automated test coverage | Added `tests/sync-direction.bats`, run in CI on every push/PR |

## Sources

- [`compliance/policies/threat-model.md`](../policies/threat-model.md)
- [`compliance/policies/data-classification.md`](../policies/data-classification.md)
- [`compliance/policies/access-review.md`](../policies/access-review.md)
- [`compliance/policies/log-retention.md`](../policies/log-retention.md)
- [`compliance/policies/data-retention.md`](../policies/data-retention.md)
- [`compliance/runbooks/`](../runbooks/)
