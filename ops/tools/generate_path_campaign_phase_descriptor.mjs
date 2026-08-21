#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const args = Object.fromEntries(process.argv.slice(2).reduce((items, item, index, all) => {
  if (item.startsWith("--")) items.push([item.slice(2), all[index + 1]]);
  return items;
}, []));

const phase = args.phase;
const environment = args.environment;
const chainId = Number(args["chain-id"]);
const bundleId = args["bundle-id"];
const output = args.out;
if (!["path-a", "path-b"].includes(phase)
    || !["internal-sepolia", "public-beta-sepolia", "mainnet"].includes(environment)
    || !Number.isSafeInteger(chainId) || chainId < 1
    || !/^[a-z0-9][a-z0-9._-]{0,127}$/.test(bundleId ?? "") || !output) {
  throw new Error("Usage: --phase <path-a|path-b> --environment <internal-sepolia|public-beta-sepolia|mainnet> --chain-id <id> --bundle-id <id> --out <CAMPAIGN-PHASE.json>");
}

const descriptor = {
  schema_version: 1,
  bundle_id: bundleId,
  phase_id: phase,
  environment,
  chain_id: chainId,
  entrypoints: {
    preflight: "bin/preflight",
    execute: "bin/execute",
    postconditions: "bin/postconditions"
  },
  input_receipt_type: phase === "path-a" ? null : "inshell.thought.deployment.receipt.v1",
  output_receipt_type: phase === "path-a"
    ? "inshell.path.phase-a.receipt.v1"
    : "inshell.path.phase-b.final-receipt.v1",
  allowed_environment_variables: ["PATH_CAMPAIGN_PARAMS_FILE"],
  resume_checkpoints: [{
    checkpoint_id: phase === "path-a" ? "path-nft-deployed" : "canonical-action-prefix",
    verifier: "bin/verify-checkpoint",
    entrypoint: "bin/resume"
  }]
};

const resolved = path.resolve(output);
fs.mkdirSync(path.dirname(resolved), { recursive: true });
fs.writeFileSync(resolved, `${JSON.stringify(descriptor, null, 2)}\n`, "utf8");
console.log(resolved);
