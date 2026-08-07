# PATH EVM Localnet Rehearsal

This walkthrough is a hands-on rehearsal to learn the Solidity stack:

- `PulseAuction` (pricing + sale flow)
- `PathPulseAdapter` (auction -> PATH NFT bridge)
- `PathNFT` (ERC-721 + movement progression)

## 0) Start from a clean localnet

Terminal A:

```bash
cd evm
npm run node
```

If a previous node is already running on `127.0.0.1:8546`, stop it and start a fresh one so token IDs and epoch counters are predictable.

## 1) Deploy and sanity check

Terminal B:

```bash
cd evm
npm run deploy:local:eth
npm run smoke:local:eth
npm run serial:bids:local:eth
npm run scenario:local:eth
```

Expected:

- Deployment file written to `evm/deployments/localhost-eth.json`
- Smoke bid succeeds and mints token `1`
- Scenario report in `evm/deployments/reports/localhost-path-cascade-eth-report.json` has `"allChecksPass": true`

## 1.5) Export frontend handoff

After deployment, export the local devnet FE release. The frontend should consume this OPS
handoff instead of hard-coded local addresses.

```bash
npm run ops:export:local-fe-release -- --rpc-url http://127.0.0.1:8546 --force
```

Expected output:

- `artifacts/devnet/current/fe-release/protocol-release.devnet.json`
- `artifacts/devnet/current/fe-release/addresses.devnet.json`
- `artifacts/devnet/current/fe-release/abi/PulseAuction.json`
- `artifacts/devnet/current/fe-release/env.devnet.example`

## 2) Open interactive console

```bash
cd evm
npx hardhat console --network localhost
```

Paste this to load contracts:

```js
const fs = await import("node:fs/promises");
const d = JSON.parse(await fs.readFile("deployments/localhost-eth.json", "utf8"));
const [deployer, buyer] = await ethers.getSigners();

const auction = await ethers.getContractAt("PulseAuction", d.contracts.pulseAuction);
const adapter = await ethers.getContractAt("PathPulseAdapter", d.contracts.pathPulseAdapter);
const nft = await ethers.getContractAt("PathNFT", d.contracts.pathNft);
```

Read wiring/config:

```js
await auction.getConfig();      // open, genesis, floor, k, pts
await auction.getState();       // epoch, start, anchor, floor, curveActive
await adapter.getConfig();      // auction + PATH NFT addresses
await adapter.getAuthorizedAuction(); // explicit auction getter
await adapter.getPathNftTarget();     // explicit PATH NFT getter
await adapter.tokenBase();      // public token id base
await adapter.epochBase();      // auction epoch base
await nft.name();               // PATH
await nft.symbol();             // PATH
await nft.SPARK_BASE();         // 1000000000000000
await nft.getReservedCap();     // Spark quota supplied in deploy calldata
await nft.getReservedRemaining(); // available, unallocated Spark slots
await nft.getReservedPending(); // slots held by active invitations
await nft.sparkClaimDuration(); // Spark self-claim window in seconds
```

## 3) Run one live auction sale

```js
const epochBefore = BigInt((await auction.epochIndex()).toString());
const tokenBase = BigInt((await adapter.tokenBase()).toString());
const epochBase = BigInt((await adapter.epochBase()).toString());
const expectedTokenId = tokenBase + ((BigInt(epochBefore) + 1n) - epochBase);
const ask = await auction.getCurrentPrice();
const tx = await auction.connect(buyer).bid(ask, { value: ask });
await tx.wait();

await nft.ownerOf(expectedTokenId); // buyer owns latest minted token
await auction.epochIndex();     // increments by 1

// coupling invariant (configured in adapter):
// tokenId = tokenBase + (epochIndex - epochBase)
const epoch = BigInt((await auction.epochIndex()).toString());
tokenBase + (epoch - epochBase) === expectedTokenId;
```

## 4) Observe the cascade curve

Wait 30 seconds and bid again:

```js
await network.provider.send("evm_increaseTime", [30]);
await network.provider.send("evm_mine");

const ask2 = await auction.getCurrentPrice();
const tx2 = await auction.connect(buyer).bid(ask2, { value: ask2 });
await tx2.wait();

await auction.getState();       // check new anchor/floor/epoch
```

You should see `epochIndex` keep increasing and price/floor evolve after each sale.

## 4.5) Optional Spark pass mint check

If the deployment used a non-zero Spark quota, grant the reserved role, create
a named invitation, then have the recipient confirm the name and self-mint one
permanently locked Spark PATH:

```js
const RESERVED_ROLE = await nft.RESERVED_ROLE();
await (await nft.grantRole(RESERVED_ROLE, deployer.address)).wait();
const sparkName = "Alice";
await (await nft.allowSparker(buyer.address, sparkName)).wait();
await nft.getSparkInvitation(buyer.address); // [expiresAt, "Alice"]
const expectedNameHash = ethers.keccak256(ethers.toUtf8Bytes(sparkName));
const sparkId = await nft.connect(buyer).mintSparker.staticCall(expectedNameHash, "0x");
await (await nft.connect(buyer).mintSparker(expectedNameHash, "0x")).wait();
await nft.ownerOf(sparkId);
await nft.isSparker(sparkId);   // true
await nft.locked(sparkId);      // true (ERC-5192)
await nft.sparkName(sparkId);   // Alice
```

## 5) Exercise movement progression in PathNFT

The canonical deploy already configured and froze all movements. Local rehearsal
uses the deployer account as the movement executor:

```js
const THOUGHT = await nft.MOVEMENT_THOUGHT();
const WILL = await nft.MOVEMENT_WILL();
const AWA = await nft.MOVEMENT_AWA();

await nft.getMovementQuota(THOUGHT);       // 1
await nft.getMovementQuota(WILL);          // 10
await nft.getMovementQuota(AWA);           // 1
await nft.getAuthorizedMinter(THOUGHT);    // deployer.address on local rehearsal
await nft.isMovementFrozen(THOUGHT);       // true
```

Use the PATH minted by the smoke bid and sign its owner-only consume authorization:

```js
const pathId = 1n;
const typeHash = ethers.id(
  "ConsumeAuthorization(address pathNft,uint256 chainId,uint256 pathId,bytes32 movement,address claimer,address executor,uint256 permissionEpoch,uint256 nonce,uint256 deadline)"
);

async function consume(movement) {
  const chainId = (await ethers.provider.getNetwork()).chainId;
  const permissionEpoch = await nft.getPermissionEpoch(pathId);
  const nonce = await nft.getConsumeNonce(buyer.address);
  const deadline = BigInt((await ethers.provider.getBlock("latest")).timestamp) + 3600n;
  const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
    ["bytes32", "address", "uint256", "uint256", "bytes32", "address", "address", "uint256", "uint256", "uint256"],
    [typeHash, await nft.getAddress(), chainId, pathId, movement, buyer.address, deployer.address, permissionEpoch, nonce, deadline]
  );
  const signature = await buyer.signMessage(ethers.getBytes(ethers.keccak256(encoded)));
  return nft.connect(deployer).consumeUnit(pathId, movement, buyer.address, deadline, signature);
}

await (await consume(THOUGHT)).wait();
await nft.getStage(pathId);       // 1 (WILL)
await nft.getStageMinted(pathId); // 0
```

Try a wrong-order consume to see guardrails:

```js
await consume(AWA);
// expected custom error: BadMovementOrder()
```

## 6) Quick failure-mode checks

```js
await adapter.settle(buyer.address, 1, "0x");              // expected revert: ONLY_AUCTION
await auction.connect(buyer).bid(1n, { value: 1n });       // expected revert: ASK_ABOVE_MAX_PRICE
```

## 7) Reset and repeat

Stop the local node, restart it, then rerun section 1 to rehearse again from genesis state.
