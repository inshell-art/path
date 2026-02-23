# PATH EVM Localnet Rehearsal

This walkthrough is a hands-on rehearsal to learn the Solidity stack:

- `PulseAuction` (pricing + sale flow)
- `PathMinterAdapter` (auction -> minter bridge)
- `PathMinter` (public + reserved ID policy)
- `PathNFT` (ERC-721 + movement progression)

## 0) Start from a clean localnet

Terminal A:

```bash
cd evm
npm run node
```

If a previous node is already running on `127.0.0.1:8545`, stop it and start a fresh one so token IDs and epoch counters are predictable.

## 1) Deploy and sanity check

Terminal B:

```bash
cd evm
npm run deploy:local:eth
npm run smoke:local:eth
npm run scenario:local:eth
```

Expected:

- Deployment file written to `evm/deployments/localhost-eth.json`
- Smoke bid succeeds and mints token `0`
- Scenario report in `evm/deployments/reports/localhost-path-cascade-eth-report.json` has `"allChecksPass": true`

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
const adapter = await ethers.getContractAt("PathMinterAdapter", d.contracts.pathMinterAdapter);
const minter = await ethers.getContractAt("PathMinter", d.contracts.pathMinter);
const nft = await ethers.getContractAt("PathNFT", d.contracts.pathNft);
```

Read wiring/config:

```js
await auction.getConfig();      // open, genesis, floor, k, pts
await auction.getState();       // epoch, start, anchor, floor, curveActive
await adapter.getConfig();      // auction + minter addresses
await minter.pathNft();         // should point at PathNFT
await minter.nextId();          // next public token id
await nft.name();               // PATH NFT
await nft.symbol();             // PATH
```

## 3) Run one live auction sale

```js
const ask = await auction.getCurrentPrice();
const tx = await auction.connect(buyer).bid(ask, { value: ask });
await tx.wait();

await minter.nextId();          // increments by 1
await nft.ownerOf((await minter.nextId()) - 1n); // buyer owns latest minted token
await auction.epochIndex();     // increments by 1
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

## 5) Exercise movement progression in PathNFT

Deploy a movement minter helper and configure movements:

```js
const MF = await ethers.getContractFactory("MockMovementMinter");
const mover = await MF.deploy();
await mover.waitForDeployment();

const THOUGHT = ethers.encodeBytes32String("THOUGHT");
const WILL = ethers.encodeBytes32String("WILL");
const AWA = ethers.encodeBytes32String("AWA");

await (await nft.setMovementConfig(THOUGHT, await mover.getAddress(), 2)).wait();
await (await nft.setMovementConfig(WILL, await mover.getAddress(), 2)).wait();
await (await nft.setMovementConfig(AWA, await mover.getAddress(), 1)).wait();
```

Mint a direct training token and consume movements in order:

```js
const MINTER_ROLE = await nft.MINTER_ROLE();
await (await nft.grantRole(MINTER_ROLE, deployer.address)).wait();

const trainingId = 9001n;
await (await nft.safeMint(buyer.address, trainingId, "0x")).wait();

await (await mover.connect(buyer).consume(await nft.getAddress(), trainingId, THOUGHT, buyer.address)).wait();
await nft.getStage(trainingId);       // still 0 (quota 2)
await nft.getStageMinted(trainingId); // 1

await (await mover.connect(buyer).consume(await nft.getAddress(), trainingId, THOUGHT, buyer.address)).wait();
await nft.getStage(trainingId);       // now 1
await nft.getStageMinted(trainingId); // reset to 0
```

Try a wrong-order consume to see guardrails:

```js
await mover.connect(buyer).consume(await nft.getAddress(), trainingId, AWA, buyer.address);
// expected revert: BAD_MOVEMENT_ORDER
```

## 6) Exercise reserved minting policy

Grant reserved role and mint a sparker:

```js
const RESERVED_ROLE = await minter.RESERVED_ROLE();
await (await minter.grantRole(RESERVED_ROLE, deployer.address)).wait();

await (await minter.mintSparker(buyer.address, "0x")).wait();
await minter.getReservedRemaining();
```

Reserved IDs are minted from a very high range (`2^256 - 2`, decreasing), not from the public sequence.

## 7) Quick failure-mode checks

```js
await adapter.settle(buyer.address, "0x");                 // expected revert: ONLY_AUCTION
await auction.connect(buyer).bid(1n, { value: 1n });       // expected revert: ASK_ABOVE_MAX_PRICE
```

## 8) Reset and repeat

Stop the local node, restart it, then rerun section 1 to rehearse again from genesis state.
