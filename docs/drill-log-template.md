# DRILL-LOG Template

Use this as a public-safe structure only.
Do not put secret text or real operator-sensitive location details in the repo.

## Purpose
`DRILL-LOG` is the mutable log for recurring checks.
It records what was tested, when it was tested, and whether the result matched the structural expectations already defined in `MAP-MAIN`.

Use `MAP-MAIN` for stable structural facts.
Do not duplicate those facts here unless they are needed as non-secret references.

## Fields

```text
SYSTEM=PATH
NETWORK=<sepolia|mainnet>
MAP_MAIN_VERSION=<version reference>

ENTRY=<timestamp or sequence>
DRILL_TYPE=<restore-check|address-check|ops-check|recovery-check>
TARGET_ROLE=<admin|treasury|host>
EXPECTED_REFERENCE=<map-main field reference>
RESULT=<pass|fail>
NOTES=<short non-secret note>
FOLLOW_UP=<none|documented action>
```

## Rules
- keep it mutable and append-oriented
- keep recurring timestamps here, not in `MAP-MAIN`
- keep results short and non-secret
- reference `MAP-MAIN` for stable addresses, paths, and recovery pairing expectations
