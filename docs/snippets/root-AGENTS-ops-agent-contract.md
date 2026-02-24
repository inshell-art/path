## Ops Agent Response Contract (MUST)

This section applies to any agent interacting with ops steps/tools in this repo.

### Trigger rule (unambiguous)
If the user:
- asks to run any ops tool/step (`ops/tools/*.sh`, `make -C ops ...`, or workflow steps like `bundle`, `verify`, `approve`, `apply`, `postconditions`), or
- asks what happened / what a step does / what was run / to show output for any ops step,
then the agent response MUST be in this order:
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
- Use minimal/compact response by default.
- Expand only when the user asks (for example: `expand evidence`).
- Do not paste long command output dumps unless asked.

Rules:
- Never present `PROPOSED` as `VERIFIED`.
- If you did not run a command, say so and provide expected output (do not claim observed output).

### Short example (required order)
`Minimal Evidence Pack`
- `Claim:` `VERIFIED` bundle check passed.
- `Source:` `ops/tools/verify_bundle.sh`, repo pin `<sha>`.
- `Reproduce:` `NETWORK=devnet RUN_ID=<id> ops/tools/verify_bundle.sh`.
- `Output:` observed `Bundle verified ...`, exit `0`.
- `Files:` read `bundles/devnet/<id>/*`, produced none.
- `Stop:` missing manifest/hash mismatch/commit mismatch.
- `Limits:` does not prove semantic safety.

`Common Answer`
- Verify step succeeded for `RUN_ID=<id>`.
