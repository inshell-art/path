import fs from "node:fs";
import { Wallet } from "ethers";

function fail(message) {
  console.error(message);
  process.exit(2);
}

function readSource(sourceValue) {
  if (!sourceValue) {
    fail("KEYSTORE_SOURCE is required");
  }

  if (fs.existsSync(sourceValue) && fs.statSync(sourceValue).isFile()) {
    return {
      json: fs.readFileSync(sourceValue, "utf8"),
      sourceKind: "file"
    };
  }

  return {
    json: sourceValue,
    sourceKind: "inline"
  };
}

function main() {
  const sourceValue = process.env.KEYSTORE_SOURCE ?? "";
  const password = process.env.KEYSTORE_PASSWORD ?? "";
  const expectedAddressRaw = process.env.EXPECTED_ADDRESS ?? "";
  const expectedAddress = expectedAddressRaw.trim().toLowerCase();

  if (!password) {
    fail("KEYSTORE_PASSWORD is required");
  }

  const { json, sourceKind } = readSource(sourceValue);

  let wallet;
  try {
    wallet = Wallet.fromEncryptedJsonSync(json, password);
  } catch (err) {
    fail(`Failed to decrypt keystore: ${err instanceof Error ? err.message : String(err)}`);
  }

  if (expectedAddress && wallet.address.toLowerCase() !== expectedAddress) {
    fail(`Keystore address mismatch: expected ${expectedAddressRaw}, got ${wallet.address}`);
  }

  process.stdout.write(`${wallet.privateKey}\t${wallet.address}\t${sourceKind}\n`);
}

main();
