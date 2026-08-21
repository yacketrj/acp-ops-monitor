#!/usr/bin/env bash
# lib/ci-health.sh — Shared CI-health check, used by both
# check-upstream-prs.sh and validate-and-report.sh.
#
# This logic previously existed inline, duplicated, in both scripts (each
# with its own copy of "gh run list --branch main --limit 1, check
# conclusion"). Extracted for the same reason lib/sync-direction.sh was:
# a real bug lived in the duplicated version and would otherwise have
# needed fixing twice. Two real bugs, found together on 2026-08-21:
#
# 1. `gh run list --branch main --limit 1` picks whichever *workflow*
#    happens to be chronologically newest, not necessarily the one
#    containing the real security jobs. Confirmed directly on
#    dune-awakening-selfhost-docker: the same push triggers CI/CodeQL/
#    Semgrep/etc, and `--limit 1` returned a CodeQL run (no security jobs
#    at all) while the CI workflow's own `security-checks` job, run
#    moments earlier on the same commit, was invisible to the old check.
#    Fixed by using the commit's aggregated check-runs (GET
#    /repos/{repo}/commits/{ref}/check-runs) instead, which covers every
#    workflow's jobs for one exact commit in a single call.
#
# 2. This monitor's own CI-health check was blind to a job reporting
#    "success" while its real work silently never ran -- exactly the bug
#    found the same day in dune-awakening-selfhost-docker's
#    security-checks job (gitleaks/trivy binaries missing, script fails
#    open, job still concludes "success"). Fixed by additionally fetching
#    the log of any successful security-related job and checking for
#    known fail-open markers.

# Markers a security-scanning CI job prints when it fails OPEN instead of
# failing closed -- i.e. it reports the *job* as "success" while the
# actual scanner never ran (missing binary, license gate, etc).
# Deliberately broad (case-insensitive, no tool name hardcoded) so a
# *new* silently-skipped tool trips this too, not just the two that have
# already been found (gitleaks, trivy).
CI_HEALTH_SILENT_SKIP_MARKERS='SKIP: .* (is )?not installed|missing .*license'

# Pure function: does this log text contain a fail-open marker? Takes
# the log content on stdin. No network calls -- unit-testable in
# isolation (see tests/ci-health.bats).
ci_health_log_has_silent_skip() {
  grep -qEi "$CI_HEALTH_SILENT_SKIP_MARKERS"
}

# Given a repo and a ref (e.g. "main"), fetch every check-run for that
# commit whose name looks security-related and that reported success,
# and check its log for a fail-open marker. Echoes one job name per
# affected job (nothing if none found). Best effort -- log fetches can
# be sizable, so this only runs for jobs that already reported "success"
# (a job that failed outright doesn't need this check, its problem is
# already visible via the conclusion field alone).
ci_health_find_silent_skips() {
  local repo="$1" ref="$2"
  local jobs_json
  jobs_json=$(timeout 30 gh api "repos/$repo/commits/$ref/check-runs" --jq '[.check_runs[] | select(.conclusion == "success") | select(.name | test("secur|scan|gitleaks|trivy|semgrep"; "i")) | {id, name}]' 2>/dev/null || echo "[]")
  echo "$jobs_json" | python3 -c '
import json, sys
for j in json.load(sys.stdin):
    print(str(j["id"]) + "\t" + str(j["name"]))
' 2>/dev/null | while IFS=$'\t' read -r job_id job_name; do
    [ -n "$job_id" ] || continue
    local log
    log=$(timeout 30 gh api "repos/$repo/actions/jobs/$job_id/logs" 2>/dev/null || echo "")
    if echo "$log" | ci_health_log_has_silent_skip; then
      echo "$job_name"
    fi
  done
}

# Main entry point. Prints a colored one-line (or multi-line, if a
# silent skip is found) status to stdout and increments the caller's
# $ISSUES on any problem (failure or silent-skip warning). Requires
# GREEN/RED/YELLOW/NC and ISSUES to already be set in the caller's
# scope (both scripts already define these).
#
# Returns 0 if clean, 1 if a problem was found (failure or warning) --
# callers that build a Discord report string (validate-and-report.sh)
# can use this to decide whether to append a line, without this
# function needing to know about that caller-specific $REPORT variable.
check_ci_health() {
  local repo="$1" label="$2"
  local repo_name
  repo_name=$(echo "$repo" | cut -d'/' -f2)

  local check_runs_json
  check_runs_json=$(timeout 30 gh api "repos/$repo/commits/main/check-runs" --jq '[.check_runs[] | {name, conclusion}]' 2>/dev/null || echo "[]")
  local total
  total=$(echo "$check_runs_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
  if [ "$total" = "0" ]; then
    echo -e "  ${YELLOW}SKIP:${NC} $label ($repo_name) — no CI runs found for HEAD"
    return 0
  fi

  local any_failed
  any_failed=$(echo "$check_runs_json" | python3 -c '
import json, sys
bad = {"failure", "timed_out", "cancelled", "action_required"}
runs = json.load(sys.stdin)
print("yes" if any(r["conclusion"] in bad for r in runs) else "no")
' 2>/dev/null || echo "no")

  if [ "$any_failed" = "yes" ]; then
    echo -e "  ${RED}FAIL:${NC} $label ($repo_name) — latest CI: failure"
    ISSUES=$((ISSUES + 1))
    return 1
  fi

  local skipped_jobs
  skipped_jobs=$(ci_health_find_silent_skips "$repo" "main")
  if [ -n "$skipped_jobs" ]; then
    echo -e "  ${YELLOW}WARN:${NC} $label ($repo_name) — CI: success, but a scanner may have silently skipped:"
    echo "$skipped_jobs" | while read -r j; do echo "         - $j"; done
    ISSUES=$((ISSUES + 1))
    return 1
  fi

  echo -e "  ${GREEN}OK:${NC} $label ($repo_name) — CI: success"
  return 0
}
