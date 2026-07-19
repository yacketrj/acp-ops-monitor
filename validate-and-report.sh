#!/usr/bin/env bash
# validate-and-report.sh — Hourly fork sync, PR rebase, mergeability, and CI validation.
# Auto-syncs core fork main with upstream, rebases open PR branches, and reports issues to Discord.
#
# Usage: bash validate-and-report.sh

set -euo pipefail

NOTIFY="${HOME}/.local/bin/notify-discord.sh"
CORE_DIR="${HOME}/dune-awakening-selfhost-docker"
CATALOG_DIR="${HOME}/dune-docker-addon/dune-docker-addons"
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
ORIGIN_MAIN=$(git rev-parse origin/main 2>/dev/null || echo "")

if [ "$UPSTREAM" != "$ORIGIN_MAIN" ]; then
  BEHIND=$(git rev-list origin/main..upstream/main --count 2>/dev/null || echo "?")
  echo "  SYNC: core fork $BEHIND commits behind — syncing main..."

  # Save current branch and working tree
  CURRENT_BRANCH=$(git branch --show-current)
  STASHED=false
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    git stash -u -m "auto-sync-${TODAY}" 2>/dev/null && STASHED=true
  fi

  # Sync main with upstream
  git checkout main 2>/dev/null || git checkout -b main upstream/main
  git reset --hard upstream/main 2>/dev/null
  git push origin main --force-with-lease --no-verify 2>&1 | tail -1

  echo -e "  ${GREEN}OK:${NC} main synced with upstream ($(echo $UPSTREAM | cut -c1-7))"

  # ─── Sync integration/discord with upstream/main using merge ───
  echo -n "  integration/discord: "
  if git show-ref --verify --quiet "refs/remotes/origin/integration/discord" || git show-ref --verify --quiet "refs/heads/integration/discord"; then
    git checkout integration/discord 2>/dev/null || true
    if git merge upstream/main --no-edit 2>/dev/null; then
      git push origin integration/discord --force-with-lease --no-verify 2>&1 | tail -1
      echo -e "${GREEN}merged${NC}"
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
      git push origin "$branch" --force-with-lease --no-verify 2>&1 | tail -1
      echo -e "${GREEN}rebased${NC}"
    else
      git rebase --abort 2>/dev/null || true
      echo -e "${RED}CONFLICT${NC}"
      REPORT="${REPORT}\n❌ PR branch \`$branch\` has merge conflicts with upstream/main"
      ISSUES=$((ISSUES + 1))
    fi
  done

  # ─── Sync active feature branches (modified in last 30 days) ───
  echo "  Syncing active feature branches..."

  ACTIVE_BRANCHES=$(git for-each-ref --sort=-committerdate --format='%(refname:short) %(committerdate:short)' refs/heads/feature/ refs/heads/fix/ 2>/dev/null | awk -v cutoff=$(date -d '30 days ago' +%Y-%m-%d) '$2 >= cutoff {print $1}' || echo "")

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
          git push origin "$branch" --force-with-lease --no-verify 2>&1 | tail -1
          echo -e "${GREEN}synced${NC}"
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
else
  echo -e "  ${GREEN}OK:${NC} core fork synced ($(echo $UPSTREAM | cut -c1-7))"
fi

# ─── 2. Catalog fork sync ───
echo "--- 2. Catalog fork sync ---"
if [ -d "$CATALOG_DIR" ]; then
  cd "$CATALOG_DIR"
  git fetch upstream main --quiet 2>/dev/null || true
  git fetch origin main --quiet 2>/dev/null || true
  CAT_UP=$(git rev-parse upstream/main 2>/dev/null || echo "")
  CAT_OR=$(git rev-parse origin/main 2>/dev/null || echo "")
  if [ -n "$CAT_UP" ] && [ -n "$CAT_OR" ] && [ "$CAT_UP" != "$CAT_OR" ]; then
    BEHIND=$(git rev-list origin/main..upstream/main --count 2>/dev/null || echo "?")
    echo "  SYNC: catalog fork $BEHIND commits behind — syncing..."
    git checkout main 2>/dev/null || true
    git reset --hard upstream/main 2>/dev/null
    git push origin main --force-with-lease --no-verify 2>&1 | tail -1
    echo -e "  ${GREEN}OK:${NC} catalog synced"
  else
    echo -e "  ${GREEN}OK:${NC} catalog fork synced"
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
PR_STATE_FILE="/tmp/acp-known-prs.txt"
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
echo "--- 4. CI failures ---"
for r in yacketrj/dune-awakening-selfhost-docker yacketrj/dune-ops-observability-addon yacketrj/dune-docker-addons yacketrj/Arrakis-Control-Panel yacketrj/acp-landing; do
  LATEST=$(gh run list --repo "$r" --branch main --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null || echo "")
  REPO_NAME=$(echo "$r" | cut -d'/' -f2)
  if [ "$LATEST" = "failure" ]; then
    echo -e "  ${RED}FAIL:${NC} $REPO_NAME — latest CI: failure"
    REPORT="${REPORT}\n⚠️ **$REPO_NAME** — latest CI \`failure\` needs resolution"
    ISSUES=$((ISSUES + 1))
  else
    echo -e "  ${GREEN}OK:${NC} $REPO_NAME — clean"
  fi
done

# ─── 5. Summary + Issue Tracking ───
STATE_FILE="/tmp/acp-issue-state.txt"
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
while IFS=" " read -r old_fingerprint old_report_short; do
  if [ "$old_fingerprint" != "$FINGERPRINT" ] && [ -n "$old_fingerprint" ]; then
    RESOLVED="${RESOLVED}✅ Issue \`${old_fingerprint}\` resolved\n"
  fi
done < "$STATE_FILE"

# Update state file
if [ "$ISSUES" -gt 0 ]; then
  echo "$FINGERPRINT ${REPORT:0:80}" > "$STATE_FILE"
else
  > "$STATE_FILE"
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
  echo -e "${GREEN}All checks passed.${NC} $ACTIVITY new PR events. Sending status update."
  if [ -x "$NOTIFY" ]; then
    bash "$NOTIFY" deploy \
      "✅ ACP Validation — All Clear" \
      "Core fork synced. All PRs MERGEABLE. CI clean. $ACTIVITY PR events detected." \
      "" 5763719 >/dev/null 2>&1 || true
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
