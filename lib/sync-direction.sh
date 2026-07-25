#!/usr/bin/env bash
# lib/sync-direction.sh — Shared, testable logic for deciding whether a fork's
# main branch is safe to fast-forward-reset onto upstream/main.
#
# This logic previously existed inline, duplicated, in validate-and-report.sh
# for both the core fork and the catalog fork. It caused three destructive
# `git reset --hard` + force-push events against merged work in a single day
# (2026-07-22) because the original version only checked "does origin/main's
# SHA differ from upstream/main's SHA" without checking *direction* — it
# fired identically whether the fork was genuinely behind, genuinely ahead
# (with local merged work upstream doesn't have yet), or diverged.
#
# Extracting this into a single, unit-tested function ensures the fix has
# real regression coverage (see tests/sync-direction.bats) instead of living
# only as a comment next to the code, as it did immediately after the
# original incident fix (PR #7).

# sync_decision <ahead_count> <behind_count>
#
# Arguments are pre-computed by the caller via:
#   ahead_count  = git rev-list upstream/main..origin/main --count
#   behind_count = git rev-list origin/main..upstream/main --count
#
# This function takes counts rather than shelling out to git itself so it
# can be unit tested with bats without needing real git repos/remotes.
#
# Output (single word on stdout):
#   sync    - origin/main is a strict, pure ancestor of upstream/main
#             (genuinely behind only, nothing of its own to lose) — safe to
#             fast-forward / reset onto upstream/main.
#   diverged - origin/main has commits upstream/main lacks (ahead or
#              diverged) — NEVER reset; this the exact case that caused the
#              destructive incident this function exists to prevent.
#   equal   - both refs point at the same commit — nothing to do.
sync_decision() {
  local ahead_count="$1"
  local behind_count="$2"

  if ! [[ "$ahead_count" =~ ^[0-9]+$ ]] || ! [[ "$behind_count" =~ ^[0-9]+$ ]]; then
    echo "invalid" >&2
    return 2
  fi

  if [ "$ahead_count" -eq 0 ] && [ "$behind_count" -eq 0 ]; then
    echo "equal"
    return 0
  fi

  if [ "$ahead_count" -eq 0 ] && [ "$behind_count" -gt 0 ]; then
    echo "sync"
    return 0
  fi

  # ahead_count > 0 (ahead-only or diverged, i.e. behind_count may be 0 or
  # >0 too) — origin/main has local commits upstream/main does not have.
  # This must NEVER trigger a reset.
  echo "diverged"
  return 0
}

# is_safe_to_reset <ahead_count> <behind_count>
#
# Convenience boolean wrapper: returns 0 (true) only when sync_decision
# would say "sync". Intended for direct use in an `if` condition, e.g.:
#   if is_safe_to_reset "$AHEAD" "$BEHIND"; then git reset --hard upstream/main; fi
is_safe_to_reset() {
  local decision
  decision="$(sync_decision "$1" "$2")"
  [ "$decision" = "sync" ]
}

# Allow this file to be executed directly for a quick manual check:
#   ./lib/sync-direction.sh 0 5   -> sync
#   ./lib/sync-direction.sh 2 0   -> diverged
#   ./lib/sync-direction.sh 0 0   -> equal
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  sync_decision "${1:?ahead_count required}" "${2:?behind_count required}"
fi
