# SOC 2 Compliance — Arrakis Control Panel

This directory contains SOC 2 control documentation, policies, evidence, and runbooks for the ACP ecosystem.

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

## Audit Schedule

| Type | Frequency | Next Due |
|---|---|---|
| Access Review | Quarterly | 2026-09-30 |
| Backup Verification | Monthly | 2026-08-19 |
| Vulnerability Scan | Continuous | Ongoing |
| Log Review | Monthly | 2026-08-19 |
| Full Audit | Annually | 2027-07-19 |
