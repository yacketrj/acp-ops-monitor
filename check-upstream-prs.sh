#!/usr/bin/env bash
# check-upstream-prs.sh — Track all yacketrj upstream PRs across both repos.
# Only notifies Discord on PR merge events. Logs status locally.
#
# Usage: bash check-upstream-prs.sh

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
NOTIFY="${ACP_NOTIFY_BIN:-${HOME}/.local/bin/notify-discord.sh}"
CACHE="${ACP_PR_STATE_CACHE:-${HOME}/.cache/acp-pr-states.json}"
ISSUES=0

echo "=== Upstream PR Status ($(date +%H:%M)) ==="

mkdir -p "$(dirname "$CACHE")"
[ -f "$CACHE" ] && OLD_STATE_JSON="$(cat "$CACHE")" || OLD_STATE_JSON="{}"

# REFACTOR (2026-07-24): the original version called `python3 -c` once PER
# PR to read from OLD_STATE_JSON and once PER PR to merge into NEW_STATE_JSON
# — O(n) subprocess spawns for what should be O(1) reads/writes. Refactored
# to: (1) do a single python3 call up front to flatten OLD_STATE_JSON into a
# bash associative array for O(1) in-process lookups, and (2) accumulate new
# state entries into a second associative array, serialized to JSON with a
# single python3 call at the very end. This is both faster (fewer process
# spawns under `set -e` + subshell overhead) and more robust (no risk of a
# mid-loop python3 failure silently dropping a state update via the `||
# echo "$NEW_STATE"` fallback the old version relied on).
declare -A OLD_STATE
while IFS=$'\t' read -r key val; do
  [ -z "$key" ] && continue
  OLD_STATE["$key"]="$val"
done < <(python3 -c "
import json, sys
d = json.loads(sys.argv[1]) if sys.argv[1] else {}
for k, v in d.items():
    print(f'{k}\t{v}')
" "$OLD_STATE_JSON" 2>/dev/null || true)

declare -A NEW_STATE

check_repo() {
  local repo="$1" label="$2"
  echo "--- $label ($repo) ---"

  # Open PRs — just list, no notification
  while IFS=$'\t' read -r pr title url; do
    [ -z "$pr" ] && continue
    local key="${repo}_${pr}"
    echo -e "  PR #$pr: ${YELLOW}OPEN${NC}  ${title:0:80}"
    NEW_STATE["$key"]="OPEN"
  done < <(gh pr list --repo "$repo" --author yacketrj --state open --json number,title,url --jq '.[] | "\(.number)\t\(.title)\t\(.url)"' 2>/dev/null || true)

  # Recently merged — notify Discord on OPEN→MERGED transition
  while IFS=$'\t' read -r pr title url merged; do
    [ -z "$pr" ] && continue
    local key="${repo}_${pr}"
    local old_val="${OLD_STATE[$key]:-UNKNOWN}"
    if [ "$old_val" = "OPEN" ]; then
      echo -e "  PR #$pr: ${GREEN}MERGED${NC} ($merged) ${title:0:60}"
      if [ -x "$NOTIFY" ]; then
        bash "$NOTIFY" upstream-pr-merged \
          "✅ $label PR #$pr Merged!" \
          "**Title:** $title
**Repo:** $repo
**Merged:** $merged" \
          "$url" >/dev/null 2>&1 || true
      fi
    fi
    NEW_STATE["$key"]="MERGED"
  done < <(gh pr list --repo "$repo" --author yacketrj --state merged --limit 5 --json number,title,url,mergedAt --jq '.[] | "\(.number)\t\(.title)\t\(.url)\t\(.mergedAt)"' 2>/dev/null || true)
}

# Check CI status for all repos
check_ci() {
  local repo="$1" label="$2"
  local latest
  latest=$(gh run list --repo "$repo" --branch main --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null || echo "")
  local repo_name
  repo_name=$(echo "$repo" | cut -d'/' -f2)
  if [ "$latest" = "failure" ]; then
    echo -e "  ${RED}FAIL:${NC} $repo_name — latest CI: failure"
    ISSUES=$((ISSUES + 1))
  elif [ -n "$latest" ]; then
    echo -e "  ${GREEN}OK:${NC} $repo_name — CI: $latest"
  else
    echo -e "  ${YELLOW}SKIP:${NC} $repo_name — no CI runs found"
  fi
}

check_repo "Red-Blink/dune-awakening-selfhost-docker" "Core"
check_repo "Red-Blink/dune-docker-addons" "Catalog"
echo
check_repo "yacketrj/dune-ops-observability-addon" "Addon"
check_repo "yacketrj/Arrakis-Control-Panel" "ACP"
check_repo "yacketrj/acp-landing" "Landing"

echo ""
echo "--- CI Status ---"
check_ci "Red-Blink/dune-awakening-selfhost-docker" "Core"
check_ci "yacketrj/dune-ops-observability-addon" "Addon"
check_ci "yacketrj/dune-docker-addons" "Catalog"
check_ci "yacketrj/Arrakis-Control-Panel" "ACP"
check_ci "yacketrj/acp-landing" "Landing"

# Single python3 call to serialize the final state — see REFACTOR note above.
{
  for key in "${!NEW_STATE[@]}"; do
    printf '%s\t%s\n' "$key" "${NEW_STATE[$key]}"
  done
} | python3 -c "
import json, sys
d = {}
for line in sys.stdin:
    line = line.rstrip('\n')
    if not line:
        continue
    k, v = line.split('\t', 1)
    d[k] = v
print(json.dumps(d))
" > "$CACHE"

if [ "$ISSUES" -gt 0 ]; then
  echo ""
  echo -e "${RED}$ISSUES CI issue(s) found${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}All checks passed${NC}"
