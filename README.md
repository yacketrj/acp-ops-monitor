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
| `check-upstream-prs.sh` | Track PRs across repos, notify on merges |
| `validate-and-report.sh` | Fork sync, rebase, mergeability, CI validation |
| `notify-discord.sh` | Post events to Discord webhook |

## Cron

Runs hourly via `crontab -l`:
```
0 * * * * bash ~/acp-ops-monitor/check-upstream-prs.sh >> /tmp/acp-cron.log 2>&1; bash ~/acp-ops-monitor/validate-and-report.sh >> /tmp/acp-cron.log 2>&1
```
