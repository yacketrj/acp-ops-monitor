#!/usr/bin/env bash
# validate-and-report.sh — Hourly fork sync, PR rebase, mergeability, and CI validation.
# Auto-syncs core fork main with upstream, rebases open PR branches, and reports issues to Discord.
# Pre-flight: verify GitHub authentication
if ! gh auth status >/dev/null 2>&1; then
  echo "FATAL: gh not authenticated. Set GH_TOKEN." >&2
  exit 1
fi

#
# Usage: bash validate-and-report.sh

set -euo pipefail

# BUG FIX (2026-07-25): sync_decision() (used below to safely gate the
# fork-sync fast-forward) was extracted into lib/sync-direction.sh with
# real unit test coverage, but this script never actually sourced that
# file -- every invocation failed immediately with
# "sync_decision: command not found" the moment it reached the first
# call site. Found while rebasing an unrelated path-fix commit onto
# this change and running the script to verify.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/sync-direction.sh
source "$SCRIPT_DIR/lib/sync-direction.sh"

NOTIFY="${HOME}/.local/bin/notify-discord.sh"
# Updated 2026-07-25: repos moved under ~/projects/<workstream>/ as part
# of a home-directory reorganization (basenames preserved).
CORE_DIR="${HOME}/projects/dune/dune-awakening-selfhost-docker"
CATALOG_DIR="${HOME}/projects/dune/dune-docker-addons"
TODAY="$(date +%Y-%m-%d)"
ISSUES=0
ACTIVITY=0
REPORT=""
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo "=== ACP Validation ($(date +%H:%M)) ==="

# ─── 1. Core fork: sync main with upstream ───
echo "--- 1. Core fork sync ---"
cd "$CORE_DIR"

git fetch upstream main --quiet 2>/dev/null || true
git fetch origin --quiet 2>/dev/null || true

UPSTREAM=$(git rev-parse upstream/main)

# BUG FIX (2026-07-23): the original unconditional
# `if [ "$UPSTREAM" != "$ORIGIN_MAIN" ]` below does not check *direction* —
# it fires identically whether origin/main is genuinely behind upstream, OR
# origin/main is AHEAD (has fork-local merged work upstream doesn't have
# yet), OR the two have diverged. Combined with the unconditional
# `git reset --hard upstream/main` + force-push a few lines down, this
# silently destroyed three merged PRs on this fork's main in a single day
# (#103, #104, #108) — each time a PR merged into origin/main, the very
# next hourly run saw a SHA mismatch and reset origin/main straight back to
# upstream/main, discarding the merge with no warning. Fast-forwarding a
# genuinely-behind fork is safe; resetting an ahead-or-diverged fork is
# not. Only treat this as a sync-needed case when upstream/main is NOT
# already reachable from origin/main's history AND origin/main has no
# commits of its own that upstream/main lacks (i.e. origin/main is a pure
# ancestor of upstream/main — the fork is strictly, only behind).
#
# BUG FIX (2026-07-25): the AHEAD_OF_UPSTREAM=0 guard above is necessary
# but not sufficient. It only asks "is origin/main ahead of upstream/main
# *right now*" -- but the actual destructive operation on the next line
# was `git reset --hard upstream/main`, which throws away any commit on
# origin/main that ISN'T reachable from upstream/main, REGARDLESS of
# whether the guard's snapshot-in-time check happened to read AHEAD=0.
# This fork now permanently carries real, fork-only history (incident
# reports, PR merges that will never be upstreamed, etc.) on every real
# commit going forward -- there is no longer a safe moment to blindly
# reset this repo's main to a third-party ref, only a safe moment to
# FAST-FORWARD it. Confirmed via reflog forensics on 2026-07-25 that this
# exact reset call (or a manual reproduction of the same command pattern)
# did in fact wipe a local checkout of main back to upstream/main's raw
# tip, discarding 26 real, already-pushed fork commits from the local
# working copy (origin/main on GitHub was thankfully unaffected, since
# the destructive command ran before this fix, on a checkout that hadn't
# been re-pushed yet -- but the force-push on the very next line would
# have made that loss permanent and remote if it had run one line later).
# Replaced `git reset --hard upstream/main` with `git merge --ff-only
# upstream/main`: identical outcome when genuinely, purely behind (the
# only case this guard is meant to allow), but merge --ff-only REFUSES to
# run at all the instant local history has diverged even slightly --
# it fails loudly and non-destructively instead of silently discarding
# commits, which is the correct failure mode for an unattended hourly
# cron job touching a repo's main branch.
AHEAD_OF_UPSTREAM=$(git rev-list upstream/main..origin/main --count 2>/dev/null || echo "0")
BEHIND=$(git rev-list origin/main..upstream/main --count 2>/dev/null || echo "0")
SYNC_STATUS="$(sync_decision "$AHEAD_OF_UPSTREAM" "$BEHIND")"

if [ "$SYNC_STATUS" = "sync" ]; then
  echo "  SYNC: core fork $BEHIND commits behind — syncing main..."

  # Save current branch and working tree
  CURRENT_BRANCH=$(git branch --show-current)
  STASHED=false
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    git stash -u -m "auto-sync-${TODAY}" 2>/dev/null && STASHED=true
  fi

  # Sync main with upstream -- fast-forward only, never reset --hard (see
  # 2026-07-25 fix note above). If this fails, main has real local history
  # upstream doesn't have and this sync is correctly aborted rather than
  # destroying it.
  git checkout main 2>/dev/null || git checkout -b main upstream/main
  if git merge --ff-only upstream/main 2>/dev/null; then
    # BUG FIX (2026-07-25): --no-verify removed. This is the actual sync
    # of this fork's real, permanent main branch -- exactly the kind of
    # consequential push this project's own security-first standard
    # (real gate suite: ggshield, gitleaks, trivy, semgrep, npm audit,
    # artifact-guard, web build) is applied to everywhere else, including
    # every manual push made this session. A merge --ff-only can only
    # ever fast-forward main to a real, already-published upstream
    # commit -- it can't introduce anything the gate would have a
    # legitimate reason to block that upstream's own CI didn't already
    # accept -- but running the gate anyway costs little and catches the
    # case where this fork's own environment (not upstream's) has a
    # problem (e.g. a locally-modified dependency, a stale lockfile).
    # PIPESTATUS captured explicitly so a real gate failure is detected
    # rather than swallowed by the `tail` pipe.
    PUSH_OUT="$(git push origin main 2>&1)"
    PUSH_RC="${PIPESTATUS[0]:-$?}"
    echo "$PUSH_OUT" | tail -3
    if [ "$PUSH_RC" -eq 0 ]; then
      echo -e "  ${GREEN}OK:${NC} main synced with upstream ($(echo $UPSTREAM | cut -c1-7))"
    else
      echo -e "  ${RED}PUSH BLOCKED (gate failure):${NC} main was fast-forwarded locally but the push was blocked — investigate manually, local and origin/main are now out of sync"
      REPORT="${REPORT}\n❌ Core fork main push blocked by pre-push gate after fast-forwarding to upstream — local/origin now diverge, needs manual attention"
      ISSUES=$((ISSUES + 1))
    fi
  else
    echo -e "  ${RED}ABORTED:${NC} main has local history that would be lost by a fast-forward — not syncing. Investigate manually."
    REPORT="${REPORT}\n❌ Core fork main could not be fast-forwarded to upstream (local-only history present) — manual sync needed"
    ISSUES=$((ISSUES + 1))
  fi

  # ─── Sync integration/discord with upstream/main using merge ───
  echo -n "  integration/discord: "
  if git show-ref --verify --quiet "refs/remotes/origin/integration/discord" || git show-ref --verify --quiet "refs/heads/integration/discord"; then
    git checkout integration/discord 2>/dev/null || true
    if git merge upstream/main --no-edit 2>/dev/null; then
      # BUG FIX (2026-07-25): --no-verify here silently skipped the real
      # security/quality gate suite (ggshield, gitleaks, trivy, semgrep,
      # npm audit, artifact-guard, web build) on every automated push this
      # unattended hourly cron job makes -- an inconsistent, unreported
      # weakening of the same standard applied everywhere else in this
      # project. The gate script is fully non-interactive and
      # deterministic (verified: no prompts, clean pass/fail exit codes),
      # so there is no hang risk from running it unattended. If the gate
      # genuinely fails after a rebase/merge (e.g. a real test regression
      # introduced upstream), that should be reported as a real issue for
      # a human to look at, not silently bypassed.
      # Piping through `tail` would otherwise swallow git push's real exit
      # code (the pipeline's status becomes tail's, which is always 0) --
      # capture PIPESTATUS explicitly so a gate failure is actually
      # detected instead of always reporting success.
      PUSH_OUT="$(git push origin integration/discord --force-with-lease 2>&1)"
      PUSH_RC="${PIPESTATUS[0]:-$?}"
      echo "$PUSH_OUT" | tail -3
      if [ "$PUSH_RC" -eq 0 ]; then
        echo -e "${GREEN}merged${NC}"
      else
        echo -e "${RED}PUSH BLOCKED (gate failure)${NC}"
        REPORT="${REPORT}\n❌ integration/discord push blocked by pre-push gate after merging upstream/main — investigate manually"
        ISSUES=$((ISSUES + 1))
      fi
    else
      git merge --abort 2>/dev/null || true
      echo -e "${RED}CONFLICT${NC}"
      REPORT="${REPORT}\n❌ integration/discord has merge conflicts with upstream/main"
      ISSUES=$((ISSUES + 1))
    fi
  else
    echo "skipped (no branch)"
  fi

  # ─── Rebase all open PR branches on updated main ───
  echo "  Rebasing open PR branches..."

  OPEN_PRS=$(gh pr list --repo Red-Blink/dune-awakening-selfhost-docker --author yacketrj --state open --json headRefName --jq '.[].headRefName' 2>/dev/null || echo "")

  for branch in $OPEN_PRS; do
    echo -n "    $branch: "
    if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      echo "skipped (no remote)"
      continue
    fi

    git checkout "$branch" 2>/dev/null || { echo "failed (checkout)"; continue; }

    if git rebase upstream/main 2>/dev/null; then
      # BUG FIX (2026-07-25): --no-verify removed. A rebase can
      # legitimately introduce a real regression relative to a PR
      # branch's last-known-good state (e.g. upstream changed something
      # this branch's own tests didn't account for) -- that's real,
      # actionable information a human reviewing this PR needs to see,
      # not something to silently push past. Calculated call: still
      # push-and-report rather than blocking the whole sync run over one
      # branch, since this is WIP that hasn't merged anywhere yet and a
      # blocked push here has no destructive consequence -- just report
      # it clearly so it doesn't go unnoticed.
      PUSH_OUT="$(git push origin "$branch" --force-with-lease 2>&1)"
      PUSH_RC="${PIPESTATUS[0]:-$?}"
      echo "$PUSH_OUT" | tail -3
      if [ "$PUSH_RC" -eq 0 ]; then
        echo -e "${GREEN}rebased${NC}"
      else
        echo -e "${RED}PUSH BLOCKED (gate failure)${NC}"
        REPORT="${REPORT}\n❌ PR branch \`$branch\` rebased onto upstream/main but push was blocked by pre-push gate — rebase result not yet on origin, investigate manually"
        ISSUES=$((ISSUES + 1))
      fi
    else
      git rebase --abort 2>/dev/null || true
      echo -e "${RED}CONFLICT${NC}"
      REPORT="${REPORT}\n❌ PR branch \`$branch\` has merge conflicts with upstream/main"
      ISSUES=$((ISSUES + 1))
    fi
  done

  # ─── Sync active feature branches (modified in last 30 days) ───
  echo "  Syncing active feature branches..."

  CUTOFF_DATE="$(date -d '30 days ago' +%Y-%m-%d)"
  ACTIVE_BRANCHES=$(git for-each-ref --sort=-committerdate --format='%(refname:short) %(committerdate:short)' refs/heads/feature/ refs/heads/fix/ 2>/dev/null | awk -v cutoff="$CUTOFF_DATE" '$2 >= cutoff {print $1}' || echo "")

  if [ -n "$ACTIVE_BRANCHES" ]; then
    echo "    Found $(echo "$ACTIVE_BRANCHES" | wc -l) active branches"

    for branch in $ACTIVE_BRANCHES; do
      echo -n "    $branch: "

      # Skip if already on this branch
      if [ "$(git branch --show-current)" = "$branch" ]; then
        echo "skipped (current branch)"
        continue
      fi

      # Check if branch exists
      if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        echo "skipped (no local branch)"
        continue
      fi

      # Checkout and rebase
      if git checkout "$branch" 2>/dev/null; then
        if git rebase upstream/main 2>/dev/null; then
          # BUG FIX (2026-07-25): --no-verify removed, same calculated
          # reasoning as the PR-branch sync above -- this is WIP that
          # hasn't merged anywhere, so a blocked push is non-destructive,
          # but a real gate failure introduced by the rebase is genuinely
          # actionable information worth surfacing, not silently
          # bypassing.
          PUSH_OUT="$(git push origin "$branch" --force-with-lease 2>&1)"
          PUSH_RC="${PIPESTATUS[0]:-$?}"
          echo "$PUSH_OUT" | tail -3
          if [ "$PUSH_RC" -eq 0 ]; then
            echo -e "${GREEN}synced${NC}"
          else
            echo -e "${RED}PUSH BLOCKED (gate failure)${NC}"
            REPORT="${REPORT}\n❌ $branch rebased onto upstream/main but push was blocked by pre-push gate — investigate manually"
            ISSUES=$((ISSUES + 1))
          fi
        else
          git rebase --abort 2>/dev/null || true
          echo -e "${RED}CONFLICT${NC}"
          REPORT="${REPORT}\n❌ $branch has rebase conflicts with upstream/main"
          ISSUES=$((ISSUES + 1))
        fi
      else
        echo "failed (checkout)"
      fi
    done
  else
    echo "    No active branches found"
  fi

  # ─── Clean up stale merged PR branches ───
  echo -n "  Cleaning merged branches: "
  MERGED_BRANCHES=$(gh pr list --repo Red-Blink/dune-awakening-selfhost-docker --author yacketrj --state merged --limit 20 --json headRefName --jq '.[].headRefName' 2>/dev/null || echo "")
  CLEANED=0
  for branch in $MERGED_BRANCHES; do
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      git push origin --delete "$branch" 2>/dev/null && CLEANED=$((CLEANED + 1)) || true
    fi
    git branch -D "$branch" 2>/dev/null || true
  done
  echo "$CLEANED removed"

  # Restore previous state
  if [ "$STASHED" = true ]; then
    git checkout "$CURRENT_BRANCH" 2>/dev/null || true
    git stash pop 2>/dev/null || true
  elif [ "$CURRENT_BRANCH" != "main" ]; then
    git checkout "$CURRENT_BRANCH" 2>/dev/null || git checkout integration/discord 2>/dev/null || true
  fi
elif [ "$SYNC_STATUS" = "diverged" ]; then
  # origin/main is AHEAD of or has DIVERGED from upstream/main (has
  # fork-local merged work upstream doesn't have) — this is expected and
  # healthy, NOT an error condition, and must never trigger a reset. This
  # is the exact case that caused the 2026-07-22 incidents when the old
  # logic didn't distinguish it from "genuinely behind" — see
  # lib/sync-direction.sh and tests/sync-direction.bats.
  echo -e "  ${GREEN}OK:${NC} core fork main is ahead of/diverged from upstream by design (local merges not yet upstreamed) — not syncing"
else
  echo -e "  ${GREEN}OK:${NC} core fork synced ($(echo "$UPSTREAM" | cut -c1-7))"
fi

# ─── 2. Catalog fork sync ───
echo "--- 2. Catalog fork sync ---"
if [ -d "$CATALOG_DIR" ]; then
  cd "$CATALOG_DIR"
  git fetch upstream main --quiet 2>/dev/null || true
  git fetch origin main --quiet 2>/dev/null || true
  CAT_UP=$(git rev-parse upstream/main 2>/dev/null || echo "")
  CAT_OR=$(git rev-parse origin/main 2>/dev/null || echo "")
  # Same direction-blind bug as the core fork sync above — fixed the same
  # way: only sync when origin/main is a strict, pure ancestor of
  # upstream/main (genuinely behind, nothing of its own to lose). ALSO
  # fixed the same second bug (2026-07-25): reset --hard was replaced
  # with merge --ff-only so a timing-window false-positive on the AHEAD
  # check above fails safely instead of destructively — see the detailed
  # fix note on the core-fork-sync block above for the real incident this
  # was found from.
  CAT_AHEAD=$(git rev-list upstream/main..origin/main --count 2>/dev/null || echo "0")
  if [ -n "$CAT_UP" ] && [ -n "$CAT_OR" ] && [ "$CAT_UP" != "$CAT_OR" ] && [ "$CAT_AHEAD" = "0" ]; then
    BEHIND=$(git rev-list origin/main..upstream/main --count 2>/dev/null || echo "?")
    echo "  SYNC: catalog fork $BEHIND commits behind — syncing..."
    git checkout main 2>/dev/null || true
    if git merge --ff-only upstream/main 2>/dev/null; then
      # BUG FIX (2026-07-25): --no-verify removed, same reasoning as the
      # core-fork main sync above -- this is a real, consequential push
      # to this fork's real main, not disposable WIP.
      PUSH_OUT="$(git push origin main 2>&1)"
      PUSH_RC="${PIPESTATUS[0]:-$?}"
      echo "$PUSH_OUT" | tail -3
      if [ "$PUSH_RC" -eq 0 ]; then
        echo -e "  ${GREEN}OK:${NC} catalog synced"
      else
        echo -e "  ${RED}PUSH BLOCKED (gate failure):${NC} catalog main was fast-forwarded locally but the push was blocked — investigate manually"
        REPORT="${REPORT}\n❌ Catalog fork main push blocked by pre-push gate after fast-forwarding to upstream — local/origin now diverge, needs manual attention"
        ISSUES=$((ISSUES + 1))
      fi
    else
      # BUG FIX (2026-07-25): this branch previously fell through to an
      # unconditional "OK: catalog synced" message right after reporting
      # ABORTED above it -- a real, separate bug that misreported failure
      # as success. Now correctly does NOT print the success message.
      echo -e "  ${RED}ABORTED:${NC} catalog main has local history that would be lost by a fast-forward — not syncing."
      REPORT="${REPORT}\n❌ Catalog fork main could not be fast-forwarded to upstream (local-only history present) — manual sync needed"
      ISSUES=$((ISSUES + 1))
    fi
  elif [ -n "$CAT_UP" ] && [ -n "$CAT_OR" ] && [ "$CAT_UP" != "$CAT_OR" ]; then
    echo -e "  ${GREEN}OK:${NC} catalog fork main is ahead of/diverged from upstream by design — not syncing"
  elif [ -n "$CAT_UP" ] && [ -n "$CAT_OR" ] && [ "$CAT_UP" = "$CAT_OR" ]; then
    # BUG FIX (2026-07-25): this case (both refs resolved and already
    # equal, i.e. genuinely fully synced) previously fell through to the
    # generic "remotes not configured" message below, which is
    # misleading -- upstream and origin were both reachable and
    # identical, not unconfigured.
    echo -e "  ${GREEN}OK:${NC} catalog fork already synced ($(echo "$CAT_UP" | cut -c1-7))"
  else
    echo -e "  ${YELLOW}SKIP:${NC} catalog fork remotes not configured"
  fi
else
  echo "  SKIP: catalog dir not found"
fi

# ─── 3. PR mergeability check ───
echo "--- 3. PR mergeability ---"
check_prs() {
  local repo="$1" label="$2"
  while IFS=$'\t' read -r pr title mergeable; do
    if [ "$mergeable" = "MERGEABLE" ]; then
      echo -e "  ${GREEN}OK:${NC} PR #$pr ($label) — MERGEABLE"
    else
      echo -e "  ${RED}FAIL:${NC} PR #$pr ($label) — $mergeable"
      REPORT="${REPORT}\n❌ PR #$pr ($label) — **$mergeable** — $title"
      ISSUES=$((ISSUES + 1))
    fi
  done < <(gh pr list --repo "$repo" --author yacketrj --state open --json number,title,mergeable --jq '.[] | "\(.number)\t\(.title)\t\(.mergeable)"' 2>/dev/null)
}
check_prs "Red-Blink/dune-awakening-selfhost-docker" "Core"
check_prs "Red-Blink/dune-docker-addons" "Catalog"

# ─── 3b. Recently merged/closed PRs ───
echo "--- 3b. Recent PR activity ---"
PR_STATE_FILE="/home/darkdante/.cache/acp-ops-monitor/known-prs.txt"
touch "$PR_STATE_FILE"

CORE_DIR_PR="${CORE_DIR}"
cd "$CORE_DIR_PR" 2>/dev/null || true

while IFS=$'\t' read -r pr title mergedAt; do
  if ! grep -q "^merged:$pr$" "$PR_STATE_FILE" 2>/dev/null; then
    echo -e "  ${GREEN}NEW MERGED:${NC} PR #$pr (Core) — $title"
    REPORT="${REPORT}\n✅ PR #$pr (Core) merged — $title"
    ACTIVITY=$((ACTIVITY + 1))
    echo "merged:$pr" >> "$PR_STATE_FILE"
  else
    echo -e "  ${GREEN}OK:${NC} PR #$pr (Core) — merged $mergedAt"
  fi
done < <(gh pr list --repo Red-Blink/dune-awakening-selfhost-docker --author yacketrj --state merged --limit 10 --json number,title,mergedAt --jq '.[] | "\(.number)\t\(.title)\t\(.mergedAt)"' 2>/dev/null)

while IFS=$'\t' read -r pr title; do
  if ! grep -q "^merged:$pr$" "$PR_STATE_FILE" 2>/dev/null && ! grep -q "^closed:$pr$" "$PR_STATE_FILE" 2>/dev/null; then
    echo -e "  ${YELLOW}NEW CLOSED:${NC} PR #$pr (Core) — $title"
    REPORT="${REPORT}\n🔒 PR #$pr (Core) closed — $title"
    ACTIVITY=$((ACTIVITY + 1))
    echo "closed:$pr" >> "$PR_STATE_FILE"
  fi
done < <(gh pr list --repo Red-Blink/dune-awakening-selfhost-docker --author yacketrj --state closed --limit 10 --json number,title --jq '.[] | "\(.number)\t\(.title)"' 2>/dev/null)

# ─── 4. CI failure check ───
# Updated 2026-07-25: added acp-ops-monitor (this repo) and tools to the
# checked list -- per ~/README.md's Strict Requirement #1 ("no repo's
# GitHub Actions may be left in a failing state on its default branch"),
# every repo this workstream maintains should be covered here, not just
# the Dune/ACP application repos. Found via this exact gap: this repo's
# own CI had been failing on main for several hours before being noticed
# manually, specifically because this check didn't include itself.
echo "--- 4. CI failures ---"
for r in yacketrj/dune-awakening-selfhost-docker yacketrj/dune-ops-observability-addon yacketrj/dune-docker-addons yacketrj/arrakis-control-panel yacketrj/acp-landing yacketrj/acp-ops-monitor yacketrj/tools; do
  REPO_NAME=$(echo "$r" | cut -d'/' -f2)
  RUN_JSON=$(gh run list --repo "$r" --branch main --limit 1 --json conclusion 2>/dev/null || echo "[]")
  LATEST=$(echo "$RUN_JSON" | jq -r '.[0].conclusion // "none"' 2>/dev/null || echo "none")
  if [ "$LATEST" = "failure" ]; then
    echo -e "  ${RED}FAIL:${NC} $REPO_NAME — latest CI: failure"
    REPORT="${REPORT}\n⚠️ **$REPO_NAME** — latest CI \`failure\` needs resolution"
    ISSUES=$((ISSUES + 1))
  elif [ "$LATEST" = "none" ]; then
    echo -e "  ${YELLOW}SKIP:${NC} $REPO_NAME — no CI runs found (no workflow configured?)"
  else
    echo -e "  ${GREEN}OK:${NC} $REPO_NAME — clean"
  fi
done

# ─── 5. Failed systemd units ───
# Added 2026-07-25: this host runs real, unattended systemd services/timers
# for this project (the live Discord bot, the game-server DB backup timer)
# with no prior monitoring for silent failures. Found and fixed a real
# case of this exact gap during the same cleanup work that added this
# check: dune-awakening-db-backup.service had been failing daily since at
# least 2026-07-23 (WorkingDirectory pointed at a stale, already-deleted
# repo path -- the same class of bug as the auto-update timer fixed
# earlier this session), undetected until a manual `systemctl --failed`
# audit. This section closes that detection gap going forward using the
# same report/issue pattern as the rest of this script, rather than
# relying on a human to remember to check.
echo "--- 5. Failed systemd units ---"
FAILED_UNITS="$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')"
if [ -n "$FAILED_UNITS" ]; then
  while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    echo -e "  ${RED}FAIL:${NC} $unit is in a failed state"
    REPORT="${REPORT}\n⚠️ systemd unit **$unit** is in a failed state — run \`systemctl status $unit\` to investigate"
    ISSUES=$((ISSUES + 1))
  done <<< "$FAILED_UNITS"
else
  echo -e "  ${GREEN}OK:${NC} no failed systemd units"
fi

# ─── 6. Home directory structure ───
# Added 2026-07-25: after a full home-directory reorganization (see
# ~/archive/2026-07-25-reorg-notes.md), wired structure-lint into this
# hourly run so structure drift (a repo moved/duplicated outside
# ~/projects, a basename/slug mismatch, ~/tools falling off $PATH) is
# caught automatically going forward instead of only being noticed
# the next time someone happens to look.
echo "--- 6. Home directory structure ---"
STRUCTURE_LINT="${HOME}/tools/structure-lint"
if [ -x "$STRUCTURE_LINT" ]; then
  STRUCTURE_OUT="$("$STRUCTURE_LINT" 2>&1)"
  STRUCTURE_RC=$?
  if [ "$STRUCTURE_RC" -eq 0 ]; then
    echo -e "  ${GREEN}OK:${NC} structure-lint passed"
  else
    echo -e "  ${RED}FAIL:${NC} structure-lint found $STRUCTURE_RC issue(s)"
    echo "$STRUCTURE_OUT" | grep "FAIL:" | while IFS= read -r line; do
      echo "  $line"
    done
    REPORT="${REPORT}\n⚠️ Home directory structure-lint found $STRUCTURE_RC issue(s) — run \`~/tools/structure-lint\` to investigate"
    ISSUES=$((ISSUES + 1))
  fi
else
  echo -e "  ${YELLOW}SKIP:${NC} ~/tools/structure-lint not found or not executable"
fi

# ─── 7. Summary + Issue Tracking ───
STATE_FILE="/home/darkdante/.cache/acp-ops-monitor/issue-state.txt"
touch "$STATE_FILE"

echo
# Build issue fingerprint from REPORT
if [ "$ISSUES" -gt 0 ]; then
  FINGERPRINT=$(echo "$REPORT" | md5sum | cut -c1-8)
else
  FINGERPRINT="clean"
fi

# Check for resolved issues (were OPEN, now clean or different fingerprint)
RESOLVED=""
while IFS=" " read -r old_fingerprint _old_report_short; do
  if [ "$old_fingerprint" != "$FINGERPRINT" ] && [ -n "$old_fingerprint" ]; then
    RESOLVED="${RESOLVED}✅ Issue \`${old_fingerprint}\` resolved\n"
  fi
done < "$STATE_FILE"

# Update state file
if [ "$ISSUES" -gt 0 ]; then
  echo "$FINGERPRINT ${REPORT:0:80}" > "$STATE_FILE"
else
  : > "$STATE_FILE"
fi

# Send notifications
if [ "$ISSUES" -eq 0 ] && [ -n "$RESOLVED" ]; then
  echo -e "${GREEN}Issues resolved.${NC} $ACTIVITY new PR events. Sending resolution notification."
  if [ -x "$NOTIFY" ]; then
    bash "$NOTIFY" deploy \
      "✅ ACP Validation — Issues Resolved" \
      "All previously detected issues are now resolved. CI clean across all repos. $ACTIVITY PR events detected." \
      "" 5763719 >/dev/null 2>&1 || true
  fi
elif [ "$ISSUES" -eq 0 ]; then
  # Only send "All Clear" when transitioning from issues→clean, NOT when
  # staying clean (suppresses 24 noisy notifications/day). If the previous
  # fingerprint was already "clean", skip — nothing changed.
  local OLD_FINGERPRINT=""
  if [ -f "$STATE_FILE" ]; then
    read -r OLD_FINGERPRINT _ < "$STATE_FILE" 2>/dev/null || true
  fi
  if [ "$OLD_FINGERPRINT" = "clean" ]; then
    echo -e "${GREEN}All checks passed.${NC} $ACTIVITY new PR events. Skipping notification (state unchanged)."
  else
    echo -e "${GREEN}All checks passed.${NC} $ACTIVITY new PR events. Sending status update."
    if [ -x "$NOTIFY" ]; then
      bash "$NOTIFY" deploy \
        "✅ ACP Validation — All Clear" \
        "Core fork synced. All PRs MERGEABLE. CI clean. $ACTIVITY PR events detected." \
        "" 5763719 >/dev/null 2>&1 || true
    fi
  fi
else
  echo -e "${RED}$ISSUES issue(s) found.${NC} $ACTIVITY PR events. Sending Discord notification."
  if [ -x "$NOTIFY" ]; then
    bash "$NOTIFY" deploy \
      "⚠️ ACP Validation — $ISSUES issue(s)" \
      "$REPORT" \
      "" 16744192 >/dev/null 2>&1 || true
  fi
fi
