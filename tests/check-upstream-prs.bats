#!/usr/bin/env bats
# tests/check-upstream-prs.bats — Coverage for check-upstream-prs.sh's
# OPEN->MERGED state-transition detection and Discord notification trigger,
# using mocked `gh` and `notify-discord.sh` binaries so no real network
# access or GitHub credentials are required.
#
# Also covers the 2026-07-24 refactor from per-PR python3 subprocess calls
# to a single-call associative-array state merge (see the REFACTOR comment
# in check-upstream-prs.sh) — these tests exist specifically to prove that
# refactor didn't change observable behavior.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../check-upstream-prs.sh"
  TEST_BIN_DIR="$(mktemp -d)"
  TEST_HOME="$(mktemp -d)"
  NOTIFY_LOG="$(mktemp)"

  # Mock notify-discord.sh: records every invocation's args instead of
  # posting to a real webhook.
  mkdir -p "${TEST_HOME}/.local/bin"
  cat > "${TEST_HOME}/.local/bin/notify-discord.sh" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "${NOTIFY_LOG}"
exit 0
EOF
  chmod +x "${TEST_HOME}/.local/bin/notify-discord.sh"

  export ACP_NOTIFY_BIN="${TEST_HOME}/.local/bin/notify-discord.sh"
  export ACP_PR_STATE_CACHE="${TEST_HOME}/.cache/acp-pr-states.json"
  export HOME="${TEST_HOME}"
  export PATH="${TEST_BIN_DIR}:${PATH}"
}

teardown() {
  rm -rf "${TEST_BIN_DIR}" "${TEST_HOME}" "${NOTIFY_LOG}"
}

# Writes a mock `gh` binary that returns canned JSON for specific
# `pr list`/`run list` invocations, keyed by a simple case match on args.
mock_gh() {
  local script="$1"
  cat > "${TEST_BIN_DIR}/gh" <<EOF
#!/usr/bin/env bash
$script
EOF
  chmod +x "${TEST_BIN_DIR}/gh"
}

@test "PR seen as OPEN then MERGED on a later run triggers exactly one notification" {
  # Run 1: PR #42 is open.
  mock_gh '
if [[ "$*" == *"--state open"* ]]; then
  echo -e "42\tTest PR\thttps://github.com/x/y/pull/42"
elif [[ "$*" == *"--state merged"* ]]; then
  echo -n ""
elif [[ "$*" == *"run list"* ]]; then
  echo "success"
fi
'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$NOTIFY_LOG" ]

  # Run 2: same PR #42 now shows up as merged; open list is empty.
  mock_gh '
if [[ "$*" == *"--state open"* ]]; then
  echo -n ""
elif [[ "$*" == *"--state merged"* ]]; then
  echo -e "42\tTest PR\thttps://github.com/x/y/pull/42\t2026-07-24T00:00:00Z"
elif [[ "$*" == *"run list"* ]]; then
  echo "success"
fi
'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -s "$NOTIFY_LOG" ]
  grep -q "upstream-pr-merged" "$NOTIFY_LOG"
  grep -q "PR #42 Merged" "$NOTIFY_LOG"
}

@test "PR already known as MERGED does not re-notify on a subsequent run" {
  mock_gh '
if [[ "$*" == *"--state open"* ]]; then
  echo -n ""
elif [[ "$*" == *"--state merged"* ]]; then
  echo -e "7\tAlready merged\thttps://github.com/x/y/pull/7\t2026-07-20T00:00:00Z"
elif [[ "$*" == *"run list"* ]]; then
  echo "success"
fi
'
  # First sighting of PR #7 as merged, with no prior OPEN state recorded for
  # it (old_val is UNKNOWN, not OPEN) — no notification should fire, since
  # the transition detection specifically requires OPEN->MERGED, not
  # UNKNOWN->MERGED. This models a PR that was already merged before this
  # script ever ran once (e.g. the very first run after installing this
  # monitor on a repo with existing merged PR history).
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$NOTIFY_LOG" ]

  # Run again — state cache now has key=MERGED from the previous run, so
  # still no notification (still not a fresh OPEN->MERGED transition).
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$NOTIFY_LOG" ]
}

@test "PR that never transitions through OPEN in a prior run is not notified when first seen merged" {
  mock_gh '
if [[ "$*" == *"--state open"* ]]; then
  echo -n ""
elif [[ "$*" == *"--state merged"* ]]; then
  echo -e "99\tOut of nowhere\thttps://github.com/x/y/pull/99\t2026-07-24T00:00:00Z"
elif [[ "$*" == *"run list"* ]]; then
  echo "success"
fi
'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$NOTIFY_LOG" ]
}

@test "state cache file is valid JSON after a run" {
  mock_gh '
if [[ "$*" == *"--state open"* ]]; then
  echo -e "1\tA\thttps://a"
elif [[ "$*" == *"--state merged"* ]]; then
  echo -n ""
elif [[ "$*" == *"run list"* ]]; then
  echo "success"
fi
'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$ACP_PR_STATE_CACHE" ]
  python3 -c "import json; json.load(open('${ACP_PR_STATE_CACHE}'))"
}

@test "CI failure on any monitored repo produces a non-zero exit code" {
  mock_gh '
if [[ "$*" == *"--state open"* ]] || [[ "$*" == *"--state merged"* ]]; then
  echo -n ""
elif [[ "$*" == *"run list"* ]]; then
  echo "failure"
fi
'
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CI issue(s) found"* ]]
}

@test "all-clean run (no open/merged PRs, all CI success) exits 0" {
  mock_gh '
if [[ "$*" == *"--state open"* ]] || [[ "$*" == *"--state merged"* ]]; then
  echo -n ""
elif [[ "$*" == *"run list"* ]]; then
  echo "success"
fi
'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All checks passed"* ]]
}
