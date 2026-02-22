# AGENTS.md — downstream usage guide

This file is for agent operators working in downstream repos that consume this template via subtree or submodule.

## Purpose
- The template repo is the source of truth for ops‑lanes docs, policies, schemas, and examples.
- Downstream repos should **consume** it, not edit it in place.

## Ops Agent Response Contract (MUST)

Many agent runners auto-load only the downstream repo's root `AGENTS.md`. Since this template is often vendored under a subtree path, downstream repos must copy/paste the snippet below into their repo root `AGENTS.md` so agents actually load it:

- `docs/snippets/root-AGENTS-ops-agent-contract.md`

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

Rule: never present `PROPOSED` as `VERIFIED`.

## Where it lives in downstream repos
- Subtree (current default): `opsec-ops-lanes-template/`
- Submodule (optional): `ops-template/` or another stable path

## What agents may do in downstream repos
- Reference template docs directly from the subtree path.
- Copy example policy files into `ops/policy/` and edit the copies.
- Create runbooks in `ops/runbooks/`.
- Maintain run artifacts in `artifacts/<network>/...` (commit only what is safe).
- Add local `.env.example` and `.gitignore` entries that keep secrets out of git.

## What agents must not do in downstream repos
- Do not edit files inside the subtree path (`opsec-ops-lanes-template/`) directly.
- Do not commit secrets, keystores, seed phrases, or RPC credentials.
- Do not introduce accounts‑file signing mode. Keystore mode only.
- Do not use LLMs during apply. Only pinned scripts may execute operations.

## How to update the template in a downstream repo
Use one of these methods:

```bash
git subtree pull --prefix opsec-ops-lanes-template https://github.com/inshell-art/opsec-ops-lanes-template.git main --squash
```

```bash
make -f ops/Makefile subtree-update
```

If the repo has a helper script:

```bash
ops/tools/update_ops_template.sh
```

## How to make edits to the template
- Make edits **in the template repo** (`opsec-ops-lanes-template`), then push to `main`.
- Downstream repos should pull updates via subtree or submodule.

## Minimal verification checklist for agents
- Confirm the template subtree path exists.
- Ensure the downstream repo has a local policy copy in `ops/policy/`.
- Check that no secrets are tracked in git.
- Verify that docs used by operators match the template versions.
- Ensure operator-facing guidance includes `docs/agent-trust-model.md`.

## Operator safety reminders
- Keep keystore files and signer metadata paths outside the repo and reference via local env vars.
- Never paste private keys or mnemonics into docs, scripts, or chat logs.
- Do not approve or execute a write without the required checks and approvals.
