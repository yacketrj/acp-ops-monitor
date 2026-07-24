# Data Deletion — acp-ops-monitor

This repo stores no user data or PII (see
[`../policies/data-classification.md`](../policies/data-classification.md)),
so there is no user-initiated data-deletion request process to support.

## Deleting Local Operational State

If you need to reset this system's local state entirely (e.g. to force
re-notification of all currently-open PRs, or to clear a corrupted cache
file):

```bash
rm -f ~/.cache/acp-pr-states.json
rm -f /tmp/acp-known-prs.txt
rm -f /tmp/acp-issue-state.txt
rm -f /tmp/acp-cron.log
```

This is safe at any time — none of these files are required for correctness
on the next run; they only suppress duplicate notifications for already-seen
events. Deleting them means the next run may re-notify Discord about
already-known PR merges/closures, but will not cause any destructive git
operation (the destructive-operation safety check in
`lib/sync-direction.sh` is computed fresh from live `git`/`gh` state on
every run, not from these cache files).
