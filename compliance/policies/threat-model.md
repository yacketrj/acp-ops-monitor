# Threat Model — acp-ops-monitor

## What This System Does

Hourly, unattended bash scripts that: (1) track PR state across several
GitHub repos, (2) sync a fork's `main` branch onto its upstream when
genuinely behind, (3) rebase open PR branches, (4) check CI status, and (5)
post summaries to a Discord webhook.

## Assets

| Asset | Why it matters |
|---|---|
| `gh` CLI credentials (via `gh auth login`) | Can read/write PRs, branches, and repo metadata across every repo the authenticated account has access to |
| Local git clones with `origin` push access | Force-push capability against real, shared branches |
| Discord webhook URL | Can post arbitrary messages to a real Discord channel if leaked |

## Trust Boundaries

- **Cron → GitHub API**: the scripts run unattended and unsupervised. There
  is no human in the loop approving each `git push --force-with-lease` or
  `gh pr` mutation. This is the single largest trust boundary in the system.
- **GitHub API → local filesystem**: PR lists, CI status, and mergeability
  come from `gh`/GitHub and are trusted without independent verification —
  acceptable here because the blast radius of a wrong read is "an
  inaccurate Discord message," not data loss.
- **Local filesystem → destructive git operation**: this is the boundary
  that failed in the 2026-07-22 incident (see README's Incident History).
  Any logic between "read git state" and "run `git reset --hard` + force
  push" must be conservative-by-default: when in doubt, do nothing and
  report, never guess and act.

## Threats Considered

| Threat | STRIDE Category | Mitigation |
|---|---|---|
| Ambiguous/misread git state triggers a destructive reset against merged work | Tampering (self-inflicted, not adversarial, but the impact is identical) | `lib/sync-direction.sh`'s explicit three-way decision (`sync` / `diverged` / `equal`), tested in `tests/sync-direction.bats` |
| A compromised or maliciously-updated third-party GitHub Action runs with repo-write-adjacent permissions | Elevation of Privilege | Pin actions to specific versions/SHAs (see Known Gaps in `compliance/controls/soc2-matrix.md`) |
| Leaked Discord webhook URL used to spam or impersonate the ACP bot in the real channel | Spoofing / Information Disclosure | Webhook URL never committed (`.gitignore`, Gitleaks, ggshield, Trivy secret scanning); read from env var or a gitignored local file only |
| Cron job silently fails and nobody notices (no notification sent because the failure happened *before* the notification step) | Denial of Service (of the monitoring function itself, not the monitored systems) | `set -euo pipefail` fails fast; `>> /tmp/acp-cron.log 2>&1` preserves output for manual inspection — **tracked gap:** no automated alert-on-cron-failure exists yet (the monitor doesn't monitor itself) |
| A future edit reintroduces the direction-blind sync bug | Tampering (regression) | Extracted into a single shared, tested function (`lib/sync-direction.sh`) used by both the core-fork and catalog-fork sync paths, rather than duplicated inline logic that could drift independently |

## Non-Threats (Explicitly Out of Scope)

- PII/user-data exposure — this system processes no user data.
- Payment/financial data — not applicable.
- Multi-tenant isolation — single-operator system, not a shared service.
