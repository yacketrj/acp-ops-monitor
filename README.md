# ACP Ops Monitor

Hourly cron jobs for monitoring the Dune Awakening ACP ecosystem: upstream PR
tracking, fork sync (with a hard safety guard against destructive resets),
CI validation, and Discord notifications.

## Monitored Repos

| Repo | Role | Checked by |
|---|---|---|
| `Red-Blink/dune-awakening-selfhost-docker` | Upstream Core | fork-sync source of truth |
| `yacketrj/dune-awakening-selfhost-docker` | Core fork | sync, PR mergeability, CI status |
| `Red-Blink/dune-docker-addons` | Upstream Catalog | PR mergeability |
| `yacketrj/dune-docker-addons` | Catalog fork | fork sync, CI status |
| `yacketrj/dune-ops-observability-addon` | Addon | PR tracking, CI status |
| `yacketrj/Arrakis-Control-Panel` | Discord bot (formerly `dune-awakening-selfhost-discordbot`) | PR tracking, CI status |
| `yacketrj/acp-landing` | Landing site | PR tracking, CI status |

## Scripts

| Script | Purpose |
|--------|---------|
| `check-upstream-prs.sh` | Track open/merged PRs across repos, notify Discord on OPEN→MERGED transitions, check CI status |
| `validate-and-report.sh` | Fork sync (core + catalog), PR rebase, mergeability checks, CI failure detection, Discord summary |
| `notify-discord.sh` | Post a formatted embed to a Discord webhook |
| `lib/sync-direction.sh` | Shared, unit-tested logic deciding whether a fork is safe to fast-forward-reset onto upstream — see [Incident History](#incident-history) |
| `install.sh` | Idempotent prerequisite check + `notify-discord.sh` install; prints the crontab line to add |

## Setup

```bash
git clone https://github.com/yacketrj/acp-ops-monitor.git ~/acp-ops-monitor
bash ~/acp-ops-monitor/install.sh
```

`install.sh` checks for `git`/`gh`/`bash`, verifies `gh auth status`,
installs `notify-discord.sh` to `~/.local/bin`, checks that the core fork
clone exists with an `upstream` remote configured, and prints the crontab
line to add. It does **not** modify your crontab automatically — paste the
printed line into `crontab -e` yourself after reviewing it.

### Prerequisites

- `git`, `gh` (authenticated: `gh auth login`), `bash`
- A local clone of the core fork with both `origin` and `upstream` remotes
  configured, at `~/dune-awakening-selfhost-docker` (override with
  `ACP_CORE_DIR`)
- Optionally, a local clone of the catalog fork at
  `~/dune-docker-addon/dune-docker-addons` (override with `ACP_CATALOG_DIR`;
  `validate-and-report.sh` skips this check gracefully if absent)
- A Discord webhook URL, provided via the `DISCORD_DEV_WEBHOOK_URL`
  environment variable (**cron does not read your shell's rc files** — set
  this directly in the crontab entry, as `install.sh` prints)

## Cron

Runs hourly. `install.sh` prints the exact line for your machine; it looks
like:

```
DISCORD_DEV_WEBHOOK_URL=https://discord.com/api/webhooks/REDACTED
0 * * * * bash ~/acp-ops-monitor/check-upstream-prs.sh >> /tmp/acp-cron.log 2>&1; bash ~/acp-ops-monitor/validate-and-report.sh >> /tmp/acp-cron.log 2>&1
```

## Testing

Shell logic that decides whether to run a destructive git operation
(`git reset --hard` + force-push) is extracted into `lib/sync-direction.sh`
and covered by a [bats](https://github.com/bats-core/bats-core) test suite:

```bash
sudo apt-get install -y bats   # or: brew install bats-core
bats tests/
```

CI runs this suite automatically on every push/PR (see `.github/workflows/ci.yml`).

## Incident History

On 2026-07-22, the fork-sync logic in `validate-and-report.sh` triggered a
`git reset --hard upstream/main` + force-push against the core fork's `main`
branch **three separate times in one day**, each time discarding a PR that
had just been merged (`#103`, `#104`, `#108`). The root cause: the original
condition only checked whether `upstream/main`'s SHA differed from
`origin/main`'s SHA — it did not check *direction*. That check fires
identically whether the fork is genuinely behind upstream, genuinely ahead
(has fork-local merged work upstream doesn't have yet), or has diverged.
Combined with an unconditional reset+force-push, any state other than
"already in sync" that wasn't "purely behind" got silently destroyed.

Fixed in PR [#7](https://github.com/yacketrj/acp-ops-monitor/pull/7) by
computing both `ahead` and `behind` commit counts and only treating the
"purely behind, nothing of its own to lose" case as sync-eligible. That fix
initially lived only as an inline comment next to duplicated logic in two
places (core fork sync, catalog fork sync) with no test coverage of its own
— the same class of bug could have been silently reintroduced by any future
edit. This was subsequently extracted into `lib/sync-direction.sh` with a
dedicated `bats` regression suite (`tests/sync-direction.bats`) that
explicitly reproduces the incident scenario (fork ahead by exactly one
merged commit, upstream unchanged) as a permanent test case.

## Compliance & Security Docs

- [`compliance/README.md`](compliance/README.md) — SOC 2 control tracking status for this repo
- [`docs/security-checklist.md`](docs/security-checklist.md) — pre-submission security checklist template, adapted for this ecosystem's Discord bot/adapter work
