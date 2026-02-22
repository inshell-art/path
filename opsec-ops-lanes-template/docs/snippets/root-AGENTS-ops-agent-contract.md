## Ops Agent Response Contract (MUST)

This section applies to any agent interacting with ops steps/tools in this repo.

### Trigger rule (unambiguous)
If the user:
- asks to run any ops tool/step (`ops/tools/*.sh`, `make -C ops ...`, or workflow steps like `bundle`, `verify`, `approve`, `apply`, `postconditions`), or
- asks what happened / what a step does / what was run / to show output for any ops step,
then the agent response MUST be in Evidence Pack format.

### Evidence Pack format (mandatory fields)
1. Claim + trust tier label (`PROPOSED` | `VERIFIED` | `PINNED` | `ON_CHAIN`)
2. Source-of-truth scripts + repo pin (`git rev-parse HEAD` or tag)
3. Exact reproduce command(s)
4. Observed output (and/or expected output if not run) + exit code
5. Files read/produced (paths)
6. Stop conditions (what would make it fail/refuse)
7. What the evidence does not prove (scope limits)

Rules:
- Never present `PROPOSED` as `VERIFIED`.
- If you did not run a command, say so and provide expected output (do not claim observed output).
