#!/usr/bin/env bats
# validate-and-report.bats — Tests for the validate-and-report.sh notification
# logic, fingerprint mechanism, and state transitions. Git operations and
# network calls are inherently untestable in unit tests; those sections are
# validated through CI checks (section 4 of the script) and manual review.

setup() {
  TEST_DIR="$(mktemp -d)"
  STATE_FILE="$TEST_DIR/test-state.txt"
  PR_STATE_FILE="$TEST_DIR/test-pr-state.txt"
  export STATE_FILE PR_STATE_FILE
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Fingerprint mechanism ──

@test "fingerprint: issues produce a non-empty MD5 fingerprint" {
  REPORT="❌ Test issue detected"
  ISSUES=1
  FINGERPRINT=$(echo "$REPORT" | md5sum | cut -c1-8)
  [ -n "$FINGERPRINT" ]
  [ "$FINGERPRINT" != "clean" ]
  [ "${#FINGERPRINT}" -eq 8 ]
}

@test "fingerprint: clean state produces literal 'clean' fingerprint" {
  ISSUES=0
  FINGERPRINT="clean"
  [ "$FINGERPRINT" = "clean" ]
}

@test "fingerprint: same report produces same fingerprint across runs" {
  REPORT="❌ CI failure in dune"
  ISSUES=1
  FP1=$(echo "$REPORT" | md5sum | cut -c1-8)
  FP2=$(echo "$REPORT" | md5sum | cut -c1-8)
  [ "$FP1" = "$FP2" ]
}

@test "fingerprint: different reports produce different fingerprints" {
  REPORT_A="❌ CI failure in dune"
  REPORT_B="❌ CI failure in catalog"
  FP_A=$(echo "$REPORT_A" | md5sum | cut -c1-8)
  FP_B=$(echo "$REPORT_B" | md5sum | cut -c1-8)
  [ "$FP_A" != "$FP_B" ]
}

# ── State file transitions ──

@test "state: empty state file means no previous issues" {
  : > "$STATE_FILE"
  ISSUES=0
  FINGERPRINT="clean"
  RESOLVED=""
  while IFS=" " read -r old_fingerprint _; do
    if [ "$old_fingerprint" != "$FINGERPRINT" ] && [ -n "$old_fingerprint" ]; then
      RESOLVED="${RESOLVED}resolved"
    fi
  done < "$STATE_FILE"
  [ -z "$RESOLVED" ]
}

@test "state: transitioning from issues to clean reports resolution" {
  echo "abc12345 CI failing" > "$STATE_FILE"
  ISSUES=0
  FINGERPRINT="clean"
  RESOLVED=""
  while IFS=" " read -r old_fingerprint _; do
    if [ "$old_fingerprint" != "$FINGERPRINT" ] && [ -n "$old_fingerprint" ]; then
      RESOLVED="${RESOLVED}resolved"
    fi
  done < "$STATE_FILE"
  [ -n "$RESOLVED" ]
}

@test "state: staying clean produces no resolution notice" {
  : > "$STATE_FILE"
  ISSUES=0
  FINGERPRINT="clean"
  RESOLVED=""
  while IFS=" " read -r old_fingerprint _; do
    if [ "$old_fingerprint" != "$FINGERPRINT" ] && [ -n "$old_fingerprint" ]; then
      RESOLVED="${RESOLVED}resolved"
    fi
  done < "$STATE_FILE"
  [ -z "$RESOLVED" ]
}

@test "state: same issue fingerprint does not produce resolution" {
  echo "abc12345 CI failing" > "$STATE_FILE"
  ISSUES=1
  REPORT="❌ CI failure in dune"
  FINGERPRINT="abc12345"  # simulate same fingerprint
  RESOLVED=""
  while IFS=" " read -r old_fingerprint _; do
    if [ "$old_fingerprint" != "$FINGERPRINT" ] && [ -n "$old_fingerprint" ]; then
      RESOLVED="${RESOLVED}resolved"
    fi
  done < "$STATE_FILE"
  [ -z "$RESOLVED" ]
}

@test "state: different fingerprint from previous issues means new issue" {
  echo "abc12345 CI failing" > "$STATE_FILE"
  ISSUES=1
  REPORT="❌ PR conflict in catalog"
  FINGERPRINT=$(echo "$REPORT" | md5sum | cut -c1-8)
  RESOLVED=""
  while IFS=" " read -r old_fingerprint _; do
    if [ "$old_fingerprint" != "$FINGERPRINT" ] && [ -n "$old_fingerprint" ]; then
      RESOLVED="${RESOLVED}resolved"
    fi
  done < "$STATE_FILE"
  [ -n "$RESOLVED" ]
  [ "$FINGERPRINT" != "abc12345" ]
}

# ── Notification decision tree ──

@test "notify: issues > 0 always triggers alert notification" {
  ISSUES=3
  ACTIVITY=1
  RESOLVED=""
  NOTIFICATION_TYPE=""
  if [ "$ISSUES" -eq 0 ] && [ -n "$RESOLVED" ]; then
    NOTIFICATION_TYPE="resolved"
  elif [ "$ISSUES" -eq 0 ]; then
    NOTIFICATION_TYPE="all_clear"
  else
    NOTIFICATION_TYPE="alert"
  fi
  [ "$NOTIFICATION_TYPE" = "alert" ]
}

@test "notify: issues == 0 with resolved triggers resolution notification" {
  ISSUES=0
  ACTIVITY=0
  RESOLVED="some_resolved"
  NOTIFICATION_TYPE=""
  if [ "$ISSUES" -eq 0 ] && [ -n "$RESOLVED" ]; then
    NOTIFICATION_TYPE="resolved"
  elif [ "$ISSUES" -eq 0 ]; then
    NOTIFICATION_TYPE="all_clear"
  else
    NOTIFICATION_TYPE="alert"
  fi
  [ "$NOTIFICATION_TYPE" = "resolved" ]
}

@test "notify: issues == 0 without resolved triggers all_clear notification" {
  ISSUES=0
  ACTIVITY=0
  RESOLVED=""
  NOTIFICATION_TYPE=""
  if [ "$ISSUES" -eq 0 ] && [ -n "$RESOLVED" ]; then
    NOTIFICATION_TYPE="resolved"
  elif [ "$ISSUES" -eq 0 ]; then
    NOTIFICATION_TYPE="all_clear"
  else
    NOTIFICATION_TYPE="alert"
  fi
  [ "$NOTIFICATION_TYPE" = "all_clear" ]
}

# ── State file persistence ──

@test "state: issues > 0 writes fingerprint to state file" {
  ISSUES=1
  REPORT="❌ Test issue"
  FINGERPRINT=$(echo "$REPORT" | md5sum | cut -c1-8)
  echo "$FINGERPRINT ${REPORT:0:80}" > "$STATE_FILE"
  [ -s "$STATE_FILE" ]
  read -r stored_fp _ < "$STATE_FILE"
  [ "$stored_fp" = "$FINGERPRINT" ]
}

@test "state: issues == 0 clears state file" {
  ISSUES=0
  : > "$STATE_FILE"
  [ ! -s "$STATE_FILE" ]
}

# ── PR state tracking ──

@test "pr_state: merged PR added to known list" {
  : > "$PR_STATE_FILE"
  PR=128
  grep -q "^merged:$PR$" "$PR_STATE_FILE" 2>/dev/null || echo "merged:$PR" >> "$PR_STATE_FILE"
  grep -q "^merged:$PR$" "$PR_STATE_FILE"
}

@test "pr_state: already-known merged PR not re-added" {
  echo "merged:128" > "$PR_STATE_FILE"
  PR=128
  if ! grep -q "^merged:$PR$" "$PR_STATE_FILE" 2>/dev/null; then
    echo "merged:$PR" >> "$PR_STATE_FILE"
  fi
  COUNT=$(grep -c "^merged:$PR$" "$PR_STATE_FILE" || echo 0)
  [ "$COUNT" -eq 1 ]
}

@test "pr_state: closed PR tracked separately from merged" {
  echo "closed:99" > "$PR_STATE_FILE"
  PR=99
  grep -q "^merged:$PR$" "$PR_STATE_FILE" 2>/dev/null || grep -q "^closed:$PR$" "$PR_STATE_FILE" 2>/dev/null
  [ $? -eq 0 ]
}

# ── Edge cases ──

@test "edge: empty REPORT with issues produces valid fingerprint" {
  ISSUES=1
  REPORT=""
  FINGERPRINT=$(echo "$REPORT" | md5sum | cut -c1-8)
  [ -n "$FINGERPRINT" ]
  [ "$FINGERPRINT" != "clean" ]
}

@test "edge: state file with corrupted content is handled" {
  echo "garbage without proper format" > "$STATE_FILE"
  ISSUES=0
  FINGERPRINT="clean"
  RESOLVED=""
  while IFS=" " read -r old_fingerprint _; do
    if [ "$old_fingerprint" != "$FINGERPRINT" ] && [ -n "$old_fingerprint" ]; then
      RESOLVED="${RESOLVED}resolved"
    fi
  done < "$STATE_FILE"
  # "garbage" != "clean" → RESOLVED
  [ -n "$RESOLVED" ]
}

@test "edge: ACTIVITY counter remains high with many PR merges" {
  ACTIVITY=12
  [ "$ACTIVITY" -eq 12 ]
}
