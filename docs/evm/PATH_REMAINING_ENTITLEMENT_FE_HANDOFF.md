# PATH Remaining Entitlement FE Handoff

## Status

This handoff describes the owner-only movement permission model and the current
Spark award flow. It supersedes the v0.4.2 consume-signing and Spark APIs. The
`consumeUnit` Solidity function arguments are unchanged, but its signed message
now includes `permissionEpoch`; old signing code will produce
`BadConsumeAuthorization()`. PATH-specific failures are typed custom errors in
the new ABI. The Spark ABI is breaking and requires a new `PathNFT`
deployment.

Import a new ABI/artifact release containing `getPermissionEpoch(pathId)`, the
`PermissionEpochAdvanced` event, ERC-5192 `locked(tokenId)`, and the named Spark
invitation functions before deploying this frontend behavior. Network addresses
must still come from the verified deployment release for the target chain.

## Product Rule

A secondary buyer of a regular PATH receives that token's current progress and
remaining movement entitlement. Transfer never resets or duplicates quota.

- Regular PATH remains ERC-721 transferable.
- Spark PATH is a permanent non-transferable ERC-5192 award.
- Both regular and Spark PATH carry the same movement quota and owner-only
  consume rights.
- Only the current `ownerOf(pathId)` can authorize movement consumption.
- ERC-721 approvals authorize regular PATH transfer, not movement use. An
  approval cannot bypass a Spark token's lock.
- Every successful non-mint regular PATH transfer increments the token's
  permission epoch.
- Previously minted movement tokens remain with their existing owners.
- A complete regular PATH may still transfer, but has zero remaining
  entitlement. A complete Spark remains locked.

## Authoritative Reads

For each PATH token, read:

```text
ownerOf(pathId)
getStage(pathId)
getStageMinted(pathId)
getMovementQuota(MOVEMENT_THOUGHT)
getMovementQuota(MOVEMENT_WILL)
getMovementQuota(MOVEMENT_AWA)
getPermissionEpoch(pathId)
getConsumeNonce(owner)
isSparker(pathId)
locked(pathId)
```

For a Spark token, also read `sparkName(pathId)`. It returns the immutable
issuer-supplied name. For regular PATH it returns an empty string. `locked`
reverts for a nonexistent token, returns `false` for regular PATH, and returns
`true` for Spark.

Movement constants are available from `MOVEMENT_THOUGHT()`, `MOVEMENT_WILL()`,
and `MOVEMENT_AWA()`. Do not hard-code their byte representation when the ABI is
available.

The stable marketplace traits remain `Stage`, `THOUGHT`, `WILL`, and `AWA`.
They report minted progress. Do not add a new on-chain metadata trait merely for
the frontend's remaining-entitlement presentation.

## Derive Remaining Entitlement

Stages are `0 = THOUGHT`, `1 = WILL`, `2 = AWA`, and `3 = COMPLETE`.
`getStageMinted(pathId)` is the minted count within the current stage.

```ts
type Quotas = { thought: bigint; will: bigint; awa: bigint };

export function derivePathEntitlement(
  stage: bigint,
  stageMinted: bigint,
  quota: Quotas
) {
  const minted: Quotas = { thought: 0n, will: 0n, awa: 0n };

  if (stage === 0n) {
    minted.thought = stageMinted;
  } else if (stage === 1n) {
    minted.thought = quota.thought;
    minted.will = stageMinted;
  } else if (stage === 2n) {
    minted.thought = quota.thought;
    minted.will = quota.will;
    minted.awa = stageMinted;
  } else if (stage >= 3n) {
    minted.thought = quota.thought;
    minted.will = quota.will;
    minted.awa = quota.awa;
  }

  return {
    minted,
    remaining: {
      thought: quota.thought - minted.thought,
      will: quota.will - minted.will,
      awa: quota.awa - minted.awa
    }
  };
}
```

Render a clearly named `Remaining entitlement` block on token details, listing,
purchase confirmation, and owner action views. Each movement row should show
`remaining of quota`, for example:

```text
Remaining entitlement
THOUGHT  0 of 1 remaining
WILL     6 of 10 remaining
AWA      1 of 1 remaining
```

For compact cards, use a factual summary such as `6 WILL + 1 AWA remaining`.
Do not present a partially consumed PATH as fresh inventory. Purchase confirmation
must also state that movement tokens minted before the sale are not included.

Read owner, stage, current-stage count, quotas, and permission epoch against one
block (for example, one multicall or a shared `blockTag`). Re-read the complete
snapshot immediately before purchase confirmation. If owner, epoch, or progress
changed, discard the old quote and require the buyer to review the new remaining
entitlement.

The contract term is `quota`; `remaining entitlement` is the frontend's plain
language for `quota - minted`. It is derived state, not an additional on-chain
counter or metadata trait.

For Spark, show the same remaining-entitlement block on token detail and owner
action views, but replace sale controls with factual status:

```text
Spark award
Name  Alice
Transferability  Permanently locked
Remaining entitlement
THOUGHT  0 of 1 remaining
WILL     6 of 10 remaining
AWA      1 of 1 remaining
```

Do not show list, buy, transfer, or operator-transfer actions for Spark. The
current Spark owner may still authorize movement consumption.

## Owner Eligibility

```ts
const canAuthorize =
  connectedAccount !== undefined &&
  connectedAccount.toLowerCase() === owner.toLowerCase();
```

`getApproved(pathId)` and `isApprovedForAll(owner, account)` must not influence
`canAuthorize`. An approved marketplace or custody operator can transfer PATH
only when it is a regular token; the operator cannot authorize THOUGHT, WILL,
or AWA consumption and cannot transfer a locked Spark.

## Spark Invitation And Claim

An invitation holds one deploy-time reserved slot immediately. Treat these
reads as authoritative issuer capacity:

```text
getReservedCap()        total lifetime Spark cap
getReservedRemaining()  available, unallocated slots
getReservedPending()    slots held by invitations
```

The minted count is derived as:

```ts
const minted = reservedCap - reservedRemaining - reservedPending;
```

Issuer flow:

1. Require the connected account to have `RESERVED_ROLE`.
2. Collect recipient address and exact display name.
3. Validate the name locally, then call `allowSparker(recipient, name)`.
4. Read `getSparkInvitation(recipient)` and show the stored name and expiry.
5. The issuer may call `revokeSparker(recipient)` to cancel and return its slot.

Name validation must match the contract: 1-31 ASCII bytes, characters `0x20`
through `0x7e`, excluding quote (`"`) and backslash (`\`), with no leading or
trailing spaces. Do not silently trim, normalize, alter case, or replace
characters. The issuer-supplied value becomes permanent after claim.

Invitee flow:

```ts
import { keccak256, toUtf8Bytes } from "ethers";

const [expiresAt, name] = await pathNft.getSparkInvitation(account);
if (expiresAt === 0n) throw new Error("No active Spark invitation");

// Show the exact name and expiry and require explicit confirmation.
const expectedNameHash = keccak256(toUtf8Bytes(name));
const sparkId = await pathNft
  .connect(signer)
  .mintSparker.staticCall(expectedNameHash, "0x");
const tx = await pathNft.connect(signer).mintSparker(expectedNameHash, "0x");
await tx.wait();
```

The recipient wallet pays claim gas. A claim is valid through the exact
`expiresAt` timestamp and invalid after it. Passing the hash prevents a stale
page from claiming after an invitation has been revoked, expired, or reissued
with a different name.

On the current artifact, a local Hardhat measurement uses `104,076` gas for
`allowSparker` and `129,183` gas for `mintSparker`; the one-time role grant uses
`51,316` gas. These are reference measurements, not transaction limits. The
claim page must call
`pathNft.connect(signer).mintSparker.estimateGas(expectedNameHash, "0x")`
against the target network and let the wallet determine current fee pricing.
Reproduce the reference rows with `npm run evm:estimate:deploy:cost`.

Expired invitations do not release capacity automatically. Any account may call
`releaseExpiredSparker(recipient)` after expiry. Issuer pages should expose a
cleanup action; indexers or a keeper may also submit it. A fresh
`allowSparker(recipient, name)` call atomically releases that recipient's old
expired invitation before reserving the replacement.

Subscribe to:

- `SparkerAllowed(recipient, expiresAt)`: refetch invitation and capacity.
- `SparkerInvitationReleased(recipient)`: clear invitation and refetch capacity.
- `SparkerMinted(recipient, tokenId)`: clear invitation and open the token.
- `Locked(tokenId)`: mark the minted Spark permanently non-transferable.

Expected Spark errors:

- `InvalidSparkName`: name violates the exact byte rules.
- `NoReservedSparkAvailable`: no unallocated slot exists.
- `SparkInvitationMissing`: recipient has no invitation.
- `SparkInvitationActive`: expiry cleanup was attempted too early.
- `SparkInvitationExpired`: claim was submitted after expiry.
- `SparkNameMismatch`: active name changed or the invitee confirmed stale text.
- `SparkSoulbound`: a Spark transfer was attempted.
- `ZeroSparkRecipient`: issuer supplied the zero address.

## Marketplace Presentation

Spark and regular PATH remain in the same contract and marketplace collection.
The Spark mint emits the normal ERC-721 `Transfer` event plus ERC-5192
`Locked(tokenId)`. `tokenURI.name` is `PATH Spark #<serial>: <name>` for Spark,
where `serial = tokenId - SPARK_BASE + 1` is rendered as an unpadded decimal.
The full ERC-721 token ID remains unchanged in `tokenURI.token`. The image and
`Stage`, `THOUGHT`, `WILL`, and `AWA` traits remain identical to regular PATH
behavior. `Spark` and `Name` are deliberately not traits.

Marketplace support for ERC-5192 varies. The contract itself rejects every
Spark transfer even if an external marketplace fails to label it correctly.
The project frontend must use `isSparker` and `locked` and must never infer
transferability from marketplace UI alone.

## Signed Consume Authorization

PATH uses an EIP-191 signed struct hash, not EIP-712 typed data. Use the exact
type string and field order below:

```ts
import {
  AbiCoder,
  getBytes,
  id,
  keccak256,
  type Signer
} from "ethers";

const CONSUME_AUTHORIZATION_TYPE =
  "ConsumeAuthorization(address pathNft,uint256 chainId,uint256 pathId,bytes32 movement,address claimer,address executor,uint256 permissionEpoch,uint256 nonce,uint256 deadline)";

export async function signPathConsume({
  signer,
  pathNft,
  chainId,
  pathId,
  movement,
  executor,
  permissionEpoch,
  nonce,
  deadline
}: {
  signer: Signer;
  pathNft: string;
  chainId: bigint;
  pathId: bigint;
  movement: string;
  executor: string;
  permissionEpoch: bigint;
  nonce: bigint;
  deadline: bigint;
}) {
  const claimer = await signer.getAddress();
  const encoded = AbiCoder.defaultAbiCoder().encode(
    [
      "bytes32",
      "address",
      "uint256",
      "uint256",
      "bytes32",
      "address",
      "address",
      "uint256",
      "uint256",
      "uint256"
    ],
    [
      id(CONSUME_AUTHORIZATION_TYPE),
      pathNft,
      chainId,
      pathId,
      movement,
      claimer,
      executor,
      permissionEpoch,
      nonce,
      deadline
    ]
  );

  return signer.signMessage(getBytes(keccak256(encoded)));
}
```

Before signing, verify that `claimer === ownerOf(pathId)`, read the latest
permission epoch and owner nonce, and resolve `executor` from
`getAuthorizedMinter(movement)`. The movement contract calls:

```text
consumeUnit(pathId, movement, owner, deadline, signature)
```

Any account may relay the transaction to the movement contract, but only the
current PATH owner's signature is valid.

## Refresh and Invalidation

Subscribe to or index these events:

- `Transfer`: refetch owner, progress, permission epoch, Spark classification,
  and lock status.
- `PermissionEpochAdvanced`: discard every cached or pending signature for that
  `pathId` and refetch the epoch.
- `MovementConsumed`: refetch progress and remaining entitlement.
- `MetadataUpdate`: refresh marketplace-style metadata and artwork.
- `BatchMetadataUpdate`: invalidate cached metadata for the collection after a
  movement configuration change.
- `Locked` / `Unlocked`: record ERC-5192 transferability at mint time.

Also clear pending authorization when the connected account, chain, PATH
address, movement executor, or deadline changes. Read the epoch again
immediately before signing; never persist consume signatures as reusable user
credentials.

Expected errors:

- `NotOwner`: signer/claimer is not the current PATH owner.
- `BadConsumeAuthorization`: stale epoch, nonce, executor, chain, PATH address, or bad
  signature.
- `ConsumeAuthorizationExpired`: deadline has passed.
- `BadMovementOrder`: requested movement is not the current stage.
- `QuotaExhausted`: current movement has no remaining entitlement.

## Secondary-Market Acceptance

The frontend implementation is complete when:

1. Remaining entitlement is visible before purchase and is derived from live
   contract reads.
2. A transfer immediately changes `canAuthorize` from seller to buyer.
3. Transfer does not change displayed minted or remaining counts.
4. Approved operators cannot access movement actions.
5. Pending signatures are cleared when the permission epoch changes.
6. Previously minted movement tokens remain displayed under their existing
   owners and are not presented as children transferred with PATH.
7. Purchase confirmation revalidates one same-block entitlement snapshot and
   refuses to proceed with stale progress, epoch, or ownership.
8. Spark cards and details show the immutable name, `Permanently locked`, and
   remaining entitlement, with no sale or transfer controls.
9. Issuer capacity distinguishes available and pending slots and cannot invite
   when available capacity is zero.
10. Invitees see and explicitly confirm the exact stored name and expiry before
    the wallet submits `mintSparker(expectedNameHash, data)`.
11. Expiry cleanup and issuer revoke immediately refetch invitation and capacity
    state; stale invitation pages cannot claim a replacement name.
