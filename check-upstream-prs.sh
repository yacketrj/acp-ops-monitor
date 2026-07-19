#!/usr/bin/env bash
# check-upstream-prs.sh — Track all yacketrj upstream PRs across both repos.
# Only notifies Discord on PR merge events. Logs status locally.
#
# Usage: bash check-upstream-prs.sh

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
NOTIFY="${HOME}/.local/bin/notify-discord.sh"
CACHE="${HOME}/.cache/acp-pr-states.json"
ISSUES=0

echo "=== Upstream PR Status ($(date +%H:%M)) ==="

mkdir -p "$(dirname "$CACHE")"
[ -f "$CACHE" ] && OLD_STATE="$(cat "$CACHE")" || OLD_STATE="{}"

# Initialize NEW_STATE as empty JSON object
NEW_STATE="{}"

check_repo() {
  local repo="$1" label="$2"
  echo "--- $label ($repo) ---"

  # Open PRs — just list, no notification
  while IFS=$'\t' read -r pr title url; do
    [ -z "$pr" ] && continue
    local key="${repo}_${pr}"
    echo -e "  PR #$pr: ${YELLOW}OPEN${NC}  ${title:0:80}"
    NEW_STATE=$(echo "$NEW_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); d['$key']='OPEN'; print(json.dumps(d))" 2>/dev/null || echo "$NEW_STATE")
  done < <(gh pr list --repo "$repo" --author yacketrj --state open --json number,title,url --jq '.[] | "\(.number)\t\(.title)\t\(.url)"' 2>/dev/null || true)

  # Recently merged — notify Discord on OPEN→MERGED transition
  while IFS=$'\t' read -r pr title url merged; do
    [ -z "$pr" ] && continue
    local key="${repo}_${pr}"
    local old_val
    old_val="$(echo "$OLD_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$key','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")"
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
    NEW_STATE=$(echo "$NEW_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); d['$key']='MERGED'; print(json.dumps(d))" 2>/dev/null || echo "$NEW_STATE")
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

echo "$NEW_STATE" > "$CACHE"

if [ "$ISSUES" -gt 0 ]; then
  echo ""
  echo -e "${RED}$ISSUES CI issue(s) found${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}All checks passed${NC}"
