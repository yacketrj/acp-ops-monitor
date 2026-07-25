# ACP Ops Monitor

Hourly cron jobs for monitoring ACP repositories: PR tracking, fork sync, CI validation, and Discord notifications.

## Monitored Repos

- `Red-Blink/dune-awakening-selfhost-docker` (Core)
- `Red-Blink/dune-docker-addons` (Catalog)
- `yacketrj/dune-ops-observability-addon` (Addon)
- `yacketrj/dune-docker-addons` (Catalog)
- `yacketrj/dune-awakening-selfhost-discordbot` (DiscordBot)
- `yacketrj/acp-landing` (Landing)

## Scripts

| Script | Purpose |
|--------|---------|
| `check-upstream-prs.sh` | Track PRs across repos, notify on merges; also tracks real upstream release tags on `Red-Blink/*` repos and notifies once when a new tag first appears (added 2026-07-25, closing a real gap where an upstream release went undetected by this monitor and was only found manually during unrelated work) |
| `validate-and-report.sh` | Fork sync, rebase, mergeability, CI validation |
| `notify-discord.sh` | Post events to Discord webhook |

## State Caches

Both PR tracking and release-tag tracking are stateful (diff-based, to notify only on real transitions, never on every hourly run):

- `~/.cache/acp-pr-states.json` — last-seen status per repo+PR-number
- `~/.cache/acp-upstream-release-states.json` — last-seen latest release tag per upstream repo (only `Red-Blink/*` repos are checked here; `yacketrj/*` repos aren't forks and have no separate "upstream release" concept beyond their own PR-merge tracking above)

Deleting a cache file resets its baseline — the next run will silently re-establish a baseline without notifying (by design, so a fresh deploy of this monitor doesn't fire a false "new" notification for every pre-existing PR/release).

## Cron

Runs hourly via `crontab -l`:
```
0 * * * * bash ~/acp-ops-monitor/check-upstream-prs.sh >> /tmp/acp-cron.log 2>&1; bash ~/acp-ops-monitor/validate-and-report.sh >> /tmp/acp-cron.log 2>&1
```
