# Feature Tweaks Prep Checklist

## Path contracts
- [ ] Confirm target branch and spec docs to apply.
- [ ] Re-sync devnet addresses (PathNFT, PathMinter, PathMinterAdapter, PathLook, PPRF, StepCurve).
- [ ] Re-run unit tests: `./scripts/test-unit.sh`.
- [ ] Re-run full tests if touching auction flow: `./scripts/test-full.sh`.
- [ ] Update `docs/path_pulse_inshell_overview.md` if any wiring or role changes.

## inshell.art UI
- [ ] Pull latest contract addresses (devnet/sepolia) and verify `addresses/*` inputs.
- [ ] Re-run unit tests: `npm run test:unit`.
- [ ] Verify look tab flow with current PathLook deployment.
- [ ] Update `docs/testing.md` if new scripts or views are added.

## Devnet + hand checks
- [ ] Start watchdog + devnet node.
- [ ] Declare + deploy PathLook deps (PPRF, StepCurve).
- [ ] Declare + deploy Path core.
- [ ] Wire roles: PathNFT MINTER_ROLE -> PathMinter, SALES_ROLE -> Adapter, Adapter auction -> PulseAuction.
- [ ] Mint a PATH and validate token_uri + look SVG.
- [ ] Run a bid and confirm mint pipeline.

## Commit hygiene
- [ ] Keep changes scoped by repo.
- [ ] Record test commands used in commit message or PR notes.
