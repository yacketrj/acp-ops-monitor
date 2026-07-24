# Data Classification — acp-ops-monitor

| Category | Present in this repo? | Notes |
|---|---|---|
| PII | No | This system processes PR metadata, git refs, and CI status only. |
| Secrets/credentials | No (in the repo itself) | `gh` auth tokens and the Discord webhook URL are runtime environment/local-file state, never committed. Enforced by `.gitignore`, Gitleaks, ggshield, and Trivy's secret scanner in both pre-commit and CI. |
| Public repository metadata | Yes | PR titles, numbers, URLs, merge timestamps, CI conclusion states — all already public on GitHub for public repos, or visible to the authenticated operator for private ones. |
| Application/business data | No | This repo has no database and no data layer. |

## Local State Files (Not Committed)

These are operational cache/state, not classified data, but are documented
here for completeness since they persist across cron runs:

| File | Purpose | Sensitivity |
|---|---|---|
| `~/.cache/acp-pr-states.json` | Last-seen PR state per repo, to detect OPEN→MERGED transitions | None — same public PR metadata as above |
| `/tmp/acp-known-prs.txt` | Dedup log of already-notified merged/closed PR numbers | None |
| `/tmp/acp-issue-state.txt` | Fingerprint of the last reported issue set, to detect resolution | None |
| `/tmp/acp-cron.log` | Combined stdout/stderr of both cron jobs | Low — could reveal internal file paths (`$HOME`-relative) in error output; not treated as secret but also not intended for wide distribution |

None of these require encryption at rest given their content, but see
[`log-retention.md`](log-retention.md) for their retention/rotation posture
(currently unbounded — tracked as a gap).
