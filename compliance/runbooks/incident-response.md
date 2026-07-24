# Incident Response — acp-ops-monitor

## Real Precedent: 2026-07-22 Destructive Fork Reset

See the README's [Incident History](../../README.md#incident-history)
section for the full root-cause writeup. This runbook exists so a future
incident of the same *class* (an automation script performing an
irreversible-feeling git operation based on a wrong read of repo state) has
a documented response procedure, not just a documented postmortem.

## Detection

- Discord notification from `validate-and-report.sh` reporting an unexpected
  `❌` line (merge/rebase conflict, CI failure) is the primary detection
  signal.
- Absence of expected recent commits on a fork's `main` after a known PR
  merge is the detection signal for a *reset*-class incident specifically —
  check `git log origin/main` against the PR's expected merge commit.
- `/tmp/acp-cron.log` contains the full stdout/stderr of every hourly run
  and is the first place to check for what the automation actually did.

## Response Steps

1. **Stop the cron job immediately** — comment out or remove the crontab
   line (`crontab -e`) so the automation cannot repeat the destructive
   action on its next hourly run while you investigate.
2. **Identify what was lost.** For a reset-class incident: compare the
   fork's current `origin/main` SHA against the GitHub PR history
   (`gh pr list --state merged`) to find merged PRs whose commits are no
   longer reachable from `origin/main`.
3. **Recover via fast-forward, not a fresh reset.** If the lost commits are
   still reachable (e.g. via `git reflog`, or because the PR's merge commit
   still exists on GitHub even though the local branch pointer moved), fast
   forward `origin/main` back to include them:
   ```bash
   git fetch origin
   git checkout main
   git merge --ff-only <last-known-good-sha>
   git push origin main --force-with-lease
   ```
   Never use `--force` without `--with-lease` during recovery — a second
   automated or manual push racing with your recovery could otherwise
   compound the damage.
4. **Fix the root cause before re-enabling cron.** Do not re-enable the
   cron job until the specific logic that caused the incident has a
   regression test proving the bad behavior no longer occurs (see
   `tests/sync-direction.bats` for the pattern used after the 2026-07-22
   incident).
5. **Re-enable cron and monitor the next 2-3 runs closely** (check
   `/tmp/acp-cron.log` after each) before trusting it to run fully
   unattended again.

## Post-Incident

- Add a dedicated regression test reproducing the exact failure scenario
  (not just a general-purpose test of the surrounding logic).
- Update this runbook and the README's Incident History section with the
  new incident's details, even if the root cause turns out to be
  substantially the same as a prior incident — the *reproduction case* is
  what has permanent value, not just the general root-cause description.
- If the incident involved a force-push, consider whether branch protection
  rules should be tightened to prevent force-push to `main` on the affected
  repo entirely, at the cost of this automation needing a non-force-push
  recovery path.
