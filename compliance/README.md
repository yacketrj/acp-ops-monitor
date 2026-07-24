# SOC 2 Compliance — acp-ops-monitor

This directory contains SOC 2 alignment documentation, policies, evidence,
and runbooks scoped to **this repo's own automation** (PR tracking, fork
sync, CI validation, Discord notifications). It is not a certification
claim — see
[Arrakis-Control-Panel's SOC 2 Alignment Notes](https://github.com/yacketrj/Arrakis-Control-Panel/blob/main/docs/soc2-alignment.md)
for the ecosystem-wide compliance posture this repo's evidence feeds into.

## Structure

| Directory | Purpose |
|---|---|
| `controls/` | SOC 2 control matrix and mappings |
| `policies/` | Security and operational policies |
| `evidence/` | Audit evidence collection |
| `runbooks/` | Incident response and recovery procedures |
| `audit/` | Audit reports and findings |

## Controls

See `controls/soc2-matrix.md` for the full control matrix with status and evidence links.

## Policies

- [Threat Model](policies/threat-model.md)
- [Data Classification](policies/data-classification.md)
- [Access Review](policies/access-review.md)
- [Log Retention](policies/log-retention.md)
- [Data Retention](policies/data-retention.md)

## Runbooks

- [Incident Response](runbooks/incident-response.md)
- [Backup & Recovery](runbooks/backup-recovery.md)
- [Rollback](runbooks/rollback.md)
- [Data Deletion](runbooks/data-deletion.md)

## Evidence & Audit

- [Evidence Index](evidence/README.md)
- [Audit Reports](audit/README.md)

## Audit Schedule

| Type | Frequency | Next Due |
|---|---|---|
| Access Review | Quarterly | 2026-09-30 |
| Backup Verification | Monthly | 2026-08-19 |
| Vulnerability Scan | Continuous | Ongoing |
| Log Review | Monthly | 2026-08-19 |
| Full Audit | Annually | 2027-07-19 |
