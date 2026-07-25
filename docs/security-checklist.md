# Security-First Pre-Submission Checklist (Ecosystem Template)

**Scope note:** `acp-ops-monitor` itself is a set of bash cron scripts with no
application code, so most items below don't apply *to this repo's own
content*. This checklist is kept here as the canonical, portable template
shared across the ACP ecosystem's application repos (`Arrakis-Control-Panel`,
`dune-awakening-selfhost-docker`, `acp-landing`) — each of those repos should
link back to this copy or maintain their own repo-specific version derived
from it, rather than letting copies drift silently out of sync. An earlier
version of this file was copied here verbatim from an application repo and
referenced files (`carePackage.js`, `duneDb.js`, `linkProvider.js`) that only
exist there — those references have been generalized below so this template
is actually portable, not accidentally repo-specific.

## Before Writing Code

- [ ] **Threat model the feature** — What can go wrong? Who benefits from bypassing it?
- [ ] **Identify trust boundaries** — Where does data cross from untrusted to trusted?
- [ ] **Check existing patterns** — How does the target codebase handle similar security concerns already? Find the nearest existing analog before inventing a new pattern.
- [ ] **Verify database/schema assumptions directly** — Don't assume column or field names from memory or documentation; query the actual schema or data access layer.
- [ ] **Review upstream reference implementation** — If upstream has similar functionality, study it first before reimplementing.

## During Implementation

- [ ] **Validate all inputs** — Every parameter from an external source must be validated.
- [ ] **Check identity before action** — Verify the actor owns the resource they're acting on.
- [ ] **Verify resource state** — Don't act on offline/expired/stale state (e.g. offline game characters, expired sessions, superseded data).
- [ ] **Use transactions** — Multi-step write operations must be atomic.
- [ ] **Handle conflicts explicitly** — Don't silently overwrite. Return a clear conflict error, not a silent success.
- [ ] **Inject dependencies** — Prefer dependency injection over direct imports for testability.
- [ ] **Use proper identity/persona resolution** — Never hardcode sender/actor identities; resolve them the same way the rest of the codebase does.
- [ ] **Log security-relevant events** — Record attempts, failures, and conflicts with timestamps.

## Before Submission

- [ ] **Test edge cases** — Offline/expired/duplicate/wrong-identity scenarios.
- [ ] **Test conflict scenarios** — Concurrent/competing claims on the same resource.
- [ ] **Verify RBAC** — Use the most specific capability/permission available, not a broader generic one that happens to also grant access.
- [ ] **Check error messages** — Don't leak internal details (stack traces, internal IDs, infra hostnames). Return user-friendly errors.
- [ ] **Review against this checklist** — Go through every item above.
- [ ] **Peer review** — Have someone else review the security implications.
- [ ] **Compare with upstream** — If submitting to an upstream project, check their recent commits for patterns you may have missed.

## Post-Merge

- [ ] **Monitor for abuse** — Check logs for unusual patterns after release.
- [ ] **Update documentation** — Reflect security requirements in user-facing guides.
- [ ] **Add tests** — Ensure security edge cases are covered in the automated test suite, not just manually verified once.

## Applying This to `acp-ops-monitor` Itself

Although this repo has no application code, the same discipline applies to
its automation:

- **Trust boundary:** every script here has force-push and PR-merge-adjacent
  capability via `gh` and `git` credentials — treat cron-triggered automation
  with the same scrutiny as a production deployment pipeline, not as a
  throwaway convenience script.
- **Validate direction, not just presence** — see
  [`lib/sync-direction.sh`](../lib/sync-direction.sh) and the
  [Incident History](../README.md#incident-history) section of the README
  for a concrete case where an unconditional "state differs" check, without
  checking *which direction* it differs in, caused three destructive resets
  against merged work in a single day.
- **Test the failure-mode logic, not just the happy path** — the
  `tests/sync-direction.bats` suite exists specifically because the original
  incident's root cause had zero test coverage before *or immediately after*
  its first fix attempt.

**Rule:** every feature submission — in this repo or any ACP ecosystem
repo — must pass this checklist. No exceptions.
