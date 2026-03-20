# `cast` verification discipline for PATH Signing OS

Purpose: verify that the `cast` binary on the Signing OS is acceptable for keystore generation and deploy-side ops before you trust it with real signer material.

This is a discipline document, not a proof of perfect safety.
It reduces supply-chain and operator risk. It does not save you if the Signing OS is already compromised.

## 1. Scope

Use this before:
- first serious Sepolia Signing OS rehearsal
- first mainnet Signing OS use
- any `cast` reinstall / upgrade / machine rebuild
- any change from one Foundry channel/version to another

## 2. Threat model

What this procedure helps against:
- installing a random or modified binary
- accidentally using an unverified nightly/fork build
- operator confusion about which `cast` is actually on `PATH`
- casual misuse of `--unsafe-password`

What it does not solve:
- a fully compromised Signing OS
- malicious hardware / firmware / kernel compromise
- weak randomness inside a compromised machine
- blindly trusting a tool without post-generation checks

## 3. Rules

1. Use the Signing OS only.
2. Verify provenance before generating or importing a real signer.
3. Prefer the official stable Foundry toolchain.
4. Do not use `foundryup --force` casually.
5. Do not use `cast ... --unsafe-password`.
6. Record the exact `cast` version you used for a serious run.
7. If verification fails, stop. Fix it on Dev OS / bootstrap process first.

## 4. Recommended install path

Preferred:
- install Foundry using the official `foundryup` installer
- install the `stable` release

If you need higher assurance than precompiled binaries:
- build Foundry from source from a pinned commit
- install `cast` from that pinned source on the Signing OS

## 5. Binary provenance check

Run these on the Signing OS:

```bash
which cast
cast --version
```

You want to know exactly which binary is on `PATH` and what version/commit it reports.

If `cast` came from `foundryup`, verify its GitHub artifact attestation:

```bash
gh attestation verify --owner foundry-rs "$(which cast)"
```

Pass condition:
- verification succeeds
- build repo is `foundry-rs/foundry`
- signer/workflow match the official Foundry release workflow

Fail condition:
- attestation verify fails
- owner/repo/workflow are not the expected official Foundry ones
- you cannot explain where this binary came from

## 6. Optional stronger path: build from source

If you want stronger assurance than trusting a downloaded binary:

1. clone `foundry-rs/foundry`
2. checkout a pinned commit or stable tag
3. build/install from source
4. record that exact source commit in your operator notes

This reduces trust in precompiled distribution, but it still does not save you from a compromised host.

## 7. Functional smoke test (disposable)

Do a one-time disposable keystore round-trip on the Signing OS before using real signer material.

Create a temporary directory:

```bash
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/testsigner"
chmod 700 "$TMPDIR" "$TMPDIR/testsigner"
```

Generate a disposable keystore with the default hidden prompt:

```bash
cast wallet new "$TMPDIR/testsigner" keystore.json
chmod 600 "$TMPDIR/testsigner/keystore.json"
```

Create a temporary password file only for this disposable smoke test if you need a non-interactive derive step:

```bash
$EDITOR "$TMPDIR/test.password.txt"
chmod 600 "$TMPDIR/test.password.txt"
```

Derive the address twice and compare:

```bash
ADDR1=$(cast wallet address \
  --keystore "$TMPDIR/testsigner/keystore.json" \
  --password-file "$TMPDIR/test.password.txt")

ADDR2=$(cast wallet address \
  --keystore "$TMPDIR/testsigner/keystore.json" \
  --password-file "$TMPDIR/test.password.txt")

printf 'ADDR1=%s\nADDR2=%s\n' "$ADDR1" "$ADDR2"
[ "$ADDR1" = "$ADDR2" ]
```

Pass condition:
- `ADDR1 == ADDR2`
- the keystore file exists and is encrypted JSON
- no raw private key was ever pasted into the shell

Then destroy the disposable material:

```bash
rm -f "$TMPDIR/test.password.txt"
rm -f "$TMPDIR/testsigner/keystore.json"
rmdir "$TMPDIR/testsigner"
rmdir "$TMPDIR"
```

Notes:
- this smoke test is for tool sanity, not for a real signer
- do not reuse this disposable signer for real funds or policy enrollment

## 8. Real signer generation discipline

Only after sections 5 and 7 pass:

```bash
cast wallet new ~/.opsec/sepolia/signers/deploy_sw_a keystore.json
cast wallet new ~/.opsec/mainnet/signers/deploy_sw_a keystore.json
```

Rules:
- hidden password prompt only
- no `--unsafe-password`
- store the keystore under local-only `~/.opsec/...`
- `chmod 600` the keystore
- record the resulting public address
- verify the address matches the intended signer before funding or use

If the current PATH runbook uses password-file mode for later ops:
- create the password file locally on the Signing OS with an editor
- keep it outside the keystore directory
- `chmod 600`

## 9. When to reject the local `cast`

Reject and stop if any of these are true:
- `which cast` points somewhere unexpected
- attestation verification fails
- version/channel is not the one you intended
- disposable smoke test is inconsistent
- the command path requires `--unsafe-password`
- you cannot explain the provenance of the binary currently on `PATH`

## 10. Recording in operator notes

For every serious Sepolia or Mainnet run, record:
- `cast --version`
- `which cast`
- install source (`foundryup stable` or source build)
- whether attestation verification passed
- date of the last disposable smoke test

## 11. Relationship to PATH runbooks

This discipline is compatible with the current PATH model:
- Dev OS and Remote CI do not hold signing secrets
- Signing OS keeps keystore/password material local-only
- real `apply` happens only on the Signing OS
- current runbooks prefer password-file mode over password env for a serious operator machine

This discipline does not replace:
- Signing OS preflight
- bundle verification
- approval discipline
- postconditions
- audit

It is just the bootstrap confidence check for the tool that generates and uses the keystore.
