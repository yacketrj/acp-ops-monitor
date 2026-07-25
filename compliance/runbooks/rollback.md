# Rollback — acp-ops-monitor

## Rolling Back a Bad Deploy of This Repo's Own Scripts

Since this repo has no running service (it's cron-invoked scripts read
fresh from disk on every hourly run), "rollback" means reverting the
checked-out script files, not restarting a service:

```bash
cd ~/acp-ops-monitor
git log --oneline -10          # find the last known-good commit
git checkout <good-sha> -- .   # or: git revert <bad-sha> for a proper revert commit
```

There is no deployment step beyond `git pull`/`git checkout` on the machine
running cron — no build, no container image, no separate release artifact
to roll back.

## Rolling Back a Bad Fork Sync (Destructive Reset)

See [`incident-response.md`](incident-response.md) for the full recovery
procedure. Summary: fast-forward `origin/main` back to the last-known-good
SHA using `--ff-only` plus `--force-with-lease` (never bare `--force`), then
fix the root cause and add a regression test before re-enabling cron.

## Rolling Back a CI/Branch Protection Change

If a branch protection rule change unexpectedly blocks all merges (e.g. a
required check that can no longer produce a passing result due to an
unrelated CI outage):

```bash
gh api repos/yacketrj/acp-ops-monitor/branches/main/protection \
  --method PUT --input - <<'EOF'
{ ... previous known-good protection JSON ... }
EOF
```

Always fetch and save the current protection settings
(`gh api repos/yacketrj/acp-ops-monitor/branches/main/protection`) before
changing them, so a "previous known-good" JSON blob actually exists to roll
back to.
