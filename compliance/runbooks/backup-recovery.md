# Backup & Recovery — acp-ops-monitor

## What Needs Backup

This repo's own content is fully backed up by GitHub (git history + the
remote repo itself). There is no database, no persistent volume, and no
generated artifact that exists only on the operator's local machine except:

| Item | Backup status | Recovery if lost |
|---|---|---|
| This repo's script content | ✅ Backed up (git remote) | `git clone` |
| Local core/catalog fork clones (`~/dune-awakening-selfhost-docker`, etc.) | ✅ Backed up (they are themselves git clones of GitHub-hosted repos) | Re-clone; no local-only state is required for correctness |
| Discord webhook URL | ❌ Not backed up (secret, intentionally not committed) | Regenerate from Discord channel integration settings; update wherever `DISCORD_DEV_WEBHOOK_URL` is configured for cron |
| Local cache/state files (`~/.cache/acp-pr-states.json`, `/tmp/acp-*`) | ❌ Not backed up (ephemeral by design) | See [`data-deletion.md`](data-deletion.md) — safe to delete and regenerate; only affects duplicate-notification suppression, never correctness |

## Recovery Time Objective

Not applicable in the traditional sense — this system has no availability
SLA. If the machine running cron is lost entirely, recovery is: provision a
new machine, `git clone` this repo plus the monitored fork clones, run
`bash install.sh`, re-add the crontab entry with a fresh
`DISCORD_DEV_WEBHOOK_URL`. No data is at risk of permanent loss in this
scenario because nothing load-bearing lives only on that machine.
