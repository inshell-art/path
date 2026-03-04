## Audit Response Contract (MUST)

### Trigger rule (unambiguous)
If the user asks to:
- run audit steps (`audit_plan`, `audit_collect`, `audit_verify`, `audit_report`, `audit_signoff`, `audit-all`), or
- show audit findings, or
- explain what audit verified,
then the response MUST be in this order:
- A) Minimal Evidence Pack
- B) Common Answer

### Minimal Evidence Pack (mandatory fields)
One short line per field by default.
1. Claim + trust tier label (`PROPOSED` | `VERIFIED` | `PINNED` | `ON_CHAIN`)
2. Source-of-truth scripts + repo pin (`git rev-parse HEAD` or tag)
3. Exact reproduce command(s)
4. Observed output (and/or expected output if not run) + exit code
5. Files read/produced (paths)
6. Stop conditions (what would make it fail/refuse)
7. What the evidence does not prove (scope limits)

### Common Answer
After the Minimal Evidence Pack, provide the normal concise answer.

### Default behavior
- use minimal/compact response by default
- expand only when asked (for example: `expand evidence`)
- do not paste long command output dumps unless asked

### Audit-specific rules
- findings-first ordering (`critical -> high -> medium -> low`)
- explicitly label `VERIFIED` vs `INFERRED`
- never present `INFERRED` as `VERIFIED`
- never present `PROPOSED` as `VERIFIED`
