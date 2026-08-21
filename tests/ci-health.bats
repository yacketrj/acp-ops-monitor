#!/usr/bin/env bats
# ci-health.bats — Tests for lib/ci-health.sh's pure log-marker matcher.
# The rest of ci-health.sh shells out to `gh api` and is validated
# through live CI runs and manual review instead (same convention as
# validate-and-report.bats — see that file's header comment), since
# real network calls aren't unit-testable in a meaningful way here.

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source "$SCRIPT_DIR/lib/ci-health.sh"
}

@test "ci_health_log_has_silent_skip: detects gitleaks skip marker" {
  echo "== Gitleaks changed-file scan ==
SKIP: gitleaks is not installed." | ci_health_log_has_silent_skip
}

@test "ci_health_log_has_silent_skip: detects trivy skip marker" {
  echo "== Trivy filesystem scan ==
SKIP: trivy is not installed." | ci_health_log_has_silent_skip
}

@test "ci_health_log_has_silent_skip: detects a missing-license marker" {
  echo "[Project-Arrakis] is an organization. License key is required.
missing gitleaks license. Go grab one at gitleaks.io" | ci_health_log_has_silent_skip
}

@test "ci_health_log_has_silent_skip: does not flag a clean scan log" {
  result=0
  echo "== Gitleaks changed-file scan ==
Gitleaks changed-file scan passed.
== Trivy filesystem scan ==
Running Trivy against: .security-reports/pr-files
Security checks completed." | ci_health_log_has_silent_skip || result=$?
  [ "$result" -eq 1 ]
}

@test "ci_health_log_has_silent_skip: does not flag unrelated log content mentioning 'skip'" {
  result=0
  echo "note: skipping alert-relay-token auto-provision test: file already exists" | ci_health_log_has_silent_skip || result=$?
  [ "$result" -eq 1 ]
}

@test "ci_health_log_has_silent_skip: is case-insensitive" {
  echo "skip: GitLeaks Is NOT Installed" | ci_health_log_has_silent_skip
}
