# Data Retention — acp-ops-monitor

This repo processes no user data and stores no data beyond the operational
state files documented in [`data-classification.md`](data-classification.md)
and [`log-retention.md`](log-retention.md). There is no data-retention
obligation beyond the disk-hygiene concerns already tracked there (unbounded
growth of `/tmp/acp-cron.log` and `/tmp/acp-known-prs.txt`).

If this system is ever extended to store data with actual retention
requirements (e.g. a persistent database instead of flat cache files), this
document must be updated before that change ships — not after.
