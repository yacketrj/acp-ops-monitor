# Log Retention — acp-ops-monitor

## Current State (Honest Assessment)

| Log/state file | Location | Current retention | Gap |
|---|---|---|---|
| Cron combined output | `/tmp/acp-cron.log` | Unbounded — appended to (`>>`) forever, never rotated | `/tmp` may be cleared on reboot depending on OS config, giving *unintentional* rotation, but this is not a designed retention policy |
| PR-merge dedup state | `~/.cache/acp-pr-states.json` | Overwritten each run (not append-only) | None — this one self-bounds correctly |
| Known-PR dedup log | `/tmp/acp-known-prs.txt` | Unbounded — appended to (`>>`) forever | Grows by one line per newly-observed merged/closed PR, forever; never rotated or pruned |
| Issue-state fingerprint | `/tmp/acp-issue-state.txt` | Overwritten each run | None — self-bounds correctly |

## Policy

- Cron output logs (`/tmp/acp-cron.log`) should be rotated to prevent
  unbounded growth. **Tracked gap, not yet automated** — until a `logrotate`
  config or equivalent is added, operators should periodically truncate this
  file manually (`: > /tmp/acp-cron.log`) or rely on `/tmp` being cleared on
  reboot, which is not a guaranteed mechanism on all systems.
- The known-PR dedup file (`/tmp/acp-known-prs.txt`) grows unbounded but at
  a low rate (one line per merged/closed PR ever observed across two
  repos). This is a real but low-severity gap — see `check-upstream-prs.sh`'s
  cache file for a better pattern (single JSON object, overwritten each run,
  not appended) that the dedup file should eventually be migrated to.
- No log contains secrets or PII (see `data-classification.md`), so retention
  here is a disk-hygiene concern, not a compliance-driven deletion
  requirement.

## Planned Resolution

Migrate `/tmp/acp-known-prs.txt`'s append-only text format to the same
single-JSON-object-overwritten-each-run pattern already used successfully by
`check-upstream-prs.sh`'s `~/.cache/acp-pr-states.json` cache. This removes
the unbounded-growth gap entirely rather than adding a rotation policy on
top of a growing file.
