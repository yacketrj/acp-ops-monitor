# Access Review — acp-ops-monitor

## Access Inventory

| Access | Grantee | Scope | Review Cadence |
|---|---|---|---|
| GitHub repo write/force-push (via local clone + `origin` remote) | Operator running the cron jobs | Core fork, catalog fork | Quarterly (see `compliance/README.md`'s Audit Schedule) |
| `gh` CLI authentication | Operator running the cron jobs | Whatever the authenticated GitHub account can access | Quarterly |
| Discord webhook (post-only) | Anyone with the webhook URL | Single channel, post-only (webhooks cannot read channel history or manage the server) | On rotation/suspected leak |
| GitHub Actions `secrets.GITHUB_TOKEN` | CI workflows in this repo | Repo-scoped, `contents: read` + `security-events: write` per `.github/workflows/ci.yml`'s `permissions:` block | Reviewed whenever workflow permissions change |

## Review Checklist (Quarterly)

- [ ] Confirm the operator account's `gh auth status` token has not been
      over-scoped beyond what these scripts need (PR read/write, repo
      read, branch push).
- [ ] Confirm the Discord webhook URL has not been accidentally logged,
      committed, or pasted into a public channel/issue.
- [ ] Confirm `.github/workflows/*.yml`'s `permissions:` blocks are still
      least-privilege (currently `contents: read` + `security-events:
      write` for the security-scanning workflow; no workflow requests
      `contents: write` or `pull-requests: write`, matching the fact that
      the automation's actual mutating operations happen via local `git`/`gh`
      CLI credentials outside of CI, not via a workflow's own token).
- [ ] Confirm no new script has been added that requests broader access
      than it needs (e.g. a new script reusing `NOTIFY`'s webhook for an
      unrelated purpose without review).

## Revocation Procedure

If the operator's `gh` credentials or the Discord webhook are compromised:

1. Revoke/regenerate immediately: `gh auth logout` then re-authenticate
   with a fresh token; regenerate the Discord webhook URL from the Discord
   channel's integration settings (this invalidates the old URL instantly).
2. Update the `DISCORD_DEV_WEBHOOK_URL` value wherever it's configured for
   cron (see README's Setup section — it is **not** stored in this repo).
3. Re-run `bash install.sh` to re-verify prerequisites after credential
   rotation.
