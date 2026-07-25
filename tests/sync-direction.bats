#!/usr/bin/env bats
# tests/sync-direction.bats — Regression coverage for the fork-sync direction
# logic that caused three destructive `git reset --hard` incidents against
# merged work on 2026-07-22 (see lib/sync-direction.sh for full history).
#
# Run with: bats tests/sync-direction.bats

setup() {
  load_lib() { source "${BATS_TEST_DIRNAME}/../lib/sync-direction.sh"; }
  load_lib
}

@test "genuinely behind (ahead=0, behind>0) is safe to sync" {
  run sync_decision 0 5
  [ "$status" -eq 0 ]
  [ "$output" = "sync" ]
}

@test "genuinely behind by exactly 1 commit is safe to sync" {
  run sync_decision 0 1
  [ "$output" = "sync" ]
}

@test "equal refs (ahead=0, behind=0) report equal, not sync" {
  run sync_decision 0 0
  [ "$output" = "equal" ]
}

@test "ahead only (ahead>0, behind=0) is diverged — must never sync" {
  run sync_decision 3 0
  [ "$output" = "diverged" ]
}

@test "diverged both ways (ahead>0, behind>0) is diverged — must never sync" {
  run sync_decision 2 4
  [ "$output" = "diverged" ]
}

@test "the exact incident scenario: fork ahead by 1 merged PR is never reset" {
  # This reproduces the real 2026-07-22 incident shape: a PR merges into
  # origin/main, putting it exactly 1 commit ahead of upstream/main, with
  # upstream/main having made no new commits in between (behind=0).
  run sync_decision 1 0
  [ "$output" = "diverged" ]
}

@test "is_safe_to_reset returns true only for the sync case" {
  run is_safe_to_reset 0 5
  [ "$status" -eq 0 ]

  run is_safe_to_reset 1 0
  [ "$status" -eq 1 ]

  run is_safe_to_reset 0 0
  [ "$status" -eq 1 ]

  run is_safe_to_reset 2 3
  [ "$status" -eq 1 ]
}

@test "non-numeric ahead_count is rejected" {
  run sync_decision "?" 5
  [ "$status" -eq 2 ]
  [ "$output" = "invalid" ]
}

@test "non-numeric behind_count is rejected (git rev-list ? fallback case)" {
  run sync_decision 0 "?"
  [ "$status" -eq 2 ]
  [ "$output" = "invalid" ]
}

@test "empty string counts are rejected rather than silently treated as zero" {
  run sync_decision "" ""
  [ "$status" -eq 2 ]
}

@test "large behind count (initial clone / long-dormant fork) still syncs safely" {
  run sync_decision 0 500
  [ "$output" = "sync" ]
}

@test "direct CLI invocation matches function behavior" {
  run bash "${BATS_TEST_DIRNAME}/../lib/sync-direction.sh" 0 5
  [ "$output" = "sync" ]

  run bash "${BATS_TEST_DIRNAME}/../lib/sync-direction.sh" 1 0
  [ "$output" = "diverged" ]
}
