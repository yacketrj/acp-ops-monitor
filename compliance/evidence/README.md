# Evidence — acp-ops-monitor

Evidence supporting the control matrix in
[`../controls/soc2-matrix.md`](../controls/soc2-matrix.md) is primarily
**directly inspectable in this repo**, not collected into static snapshots
here, since the underlying artifacts (CI workflow runs, test results,
pre-commit config) are already durable and versioned:

| Control | Live evidence location |
|---|---|
| Destructive-operation safety logic tested | `tests/sync-direction.bats`, run in [CI](https://github.com/yacketrj/acp-ops-monitor/actions/workflows/ci.yml) on every push/PR |
| Secret scanning | CI workflow run logs (Gitleaks step); local `.pre-commit-config.yaml` (Gitleaks, ggshield, Trivy secrets) |
| SAST | CI workflow run logs (Semgrep step) |
| Dependency updates | [Dependabot PR history](https://github.com/yacketrj/acp-ops-monitor/pulls?q=is%3Apr+label%3Aci-cd) |

If a future formal audit requires point-in-time snapshots (e.g. a PDF export
of a specific CI run's logs), save them into this directory named
`YYYY-MM-DD-<control-area>.md` or similar, rather than replacing this
live-evidence-pointer approach for day-to-day tracking.
