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
| `validate-and-report.sh` | Fork sync, rebase, mergeability, CI validation, and failed-systemd-unit detection (added 2026-07-25, closing a real gap where `dune-awakening-db-backup.service` had been silently failing daily since at least 2026-07-23 and was only found via manual `systemctl --failed` audit) |
| `notify-discord.sh` | Post events to Discord webhook. `~/.local/bin/notify-discord.sh` (what `validate-and-report.sh`'s `$NOTIFY` actually invokes) is a symlink to this file -- edit here, never the deployed path directly. |

## State Caches

Both PR tracking and release-tag tracking are stateful (diff-based, to notify only on real transitions, never on every hourly run):

- `~/.cache/acp-pr-states.json` — last-seen status per repo+PR-number
- `~/.cache/acp-upstream-release-states.json` — last-seen latest release tag per upstream repo (only `Red-Blink/*` repos are checked here; `yacketrj/*` repos aren't forks and have no separate "upstream release" concept beyond their own PR-merge tracking above)

Deleting a cache file resets its baseline — the next run will silently re-establish a baseline without notifying (by design, so a fresh deploy of this monitor doesn't fire a false "new" notification for every pre-existing PR/release).

## Host-Level Monitoring

`validate-and-report.sh` also checks `systemctl --failed` on every run (not stateful/diff-based like the PR/release trackers above — reports every run while any unit remains failed, since a stuck-failed unit is a persistent problem worth repeating until fixed). This covers real systemd services/timers this project depends on running on this host, notably:

- `discord-bot.service` — the live Arrakis Control Panel Discord bot (`Restart=always`)
- `dune-awakening-db-backup.timer` / `.service` — daily game-server database backup

## Secrets

- `~/.config/acp-ops-monitor/dev-webhook-url.txt` — Discord webhook URL for `notify-discord.sh` (or set `DISCORD_DEV_WEBHOOK_URL` instead). Chosen deliberately as a stable, non-project location: an earlier version of this file lived inside a project working directory that was later deleted during an unrelated cleanup, silently breaking all Discord notifications until found and fixed (2026-07-25). Not committed to git (gitignored).

## Cron

Runs hourly via `crontab -l`:
```
0 * * * * bash ~/acp-ops-monitor/check-upstream-prs.sh >> /tmp/acp-cron.log 2>&1; bash ~/acp-ops-monitor/validate-and-report.sh >> /tmp/acp-cron.log 2>&1
```
