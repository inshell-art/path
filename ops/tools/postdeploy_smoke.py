#!/usr/bin/env python3
"""Postdeploy smoke tooling for live PATH buyer-flow checks.

This tool is Dev OS only. It never handles deploy/admin signer material.
It serves a local browser-wallet smoke page and verifies the resulting tx.
"""

from __future__ import annotations

import argparse
import http.server
import json
import os
import shutil
import socketserver
import subprocess
import sys
import textwrap
from datetime import datetime, timezone
from pathlib import Path


ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
SEPOLIA_CHAIN_ID_HEX = "0xaa36a7"
DEFAULT_SEPOLIA_RPC_URL = "https://ethereum-sepolia-rpc.publicnode.com"


class SmokeError(RuntimeError):
    pass


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def run(cmd: list[str], *, cwd: Path | None = None) -> str:
    try:
        completed = subprocess.run(
            cmd,
            cwd=cwd,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as exc:
        raise SmokeError(
            f"command failed ({exc.returncode}): {' '.join(cmd)}\n{exc.stderr.strip()}"
        ) from exc
    return completed.stdout.strip()


def require_cast() -> None:
    if shutil.which("cast") is None:
        raise SmokeError("required tool missing: cast")


def parse_cast_uint(text: str) -> str:
    first = text.strip().split()[0] if text.strip() else ""
    if not first.isdigit():
        raise SmokeError(f"expected uint output from cast, got: {text!r}")
    return first


def normalize_address(value: str) -> str:
    return value.strip().lower()


def history_dir(args: argparse.Namespace) -> Path:
    root = Path(args.history_root).expanduser()
    return root / args.network / "deploy" / args.run_id


def deployment_path(args: argparse.Namespace) -> Path:
    return history_dir(args) / "canonical-artifacts" / f"deployment.{args.network}-eth.json"


def load_deployment(args: argparse.Namespace) -> dict:
    path = deployment_path(args)
    if not path.is_file():
        raise SmokeError(f"deployment artifact not found: {path}")
    return json.loads(path.read_text())


def rpc_url(args: argparse.Namespace) -> str:
    if args.rpc_url:
        return args.rpc_url
    env_name = f"{args.network.upper()}_RPC_URL"
    if os.environ.get(env_name):
        return os.environ[env_name]
    if args.network == "sepolia":
        return DEFAULT_SEPOLIA_RPC_URL
    raise SmokeError(f"set --rpc-url or {env_name}")


def output_dir(args: argparse.Namespace) -> Path:
    if args.output_dir:
        return Path(args.output_dir).expanduser()
    return repo_root() / "output" / "smoke" / args.network / args.run_id


def chain_id_hex(network: str) -> str:
    if network == "sepolia":
        return SEPOLIA_CHAIN_ID_HEX
    raise SmokeError(f"unsupported smoke network: {network}")


def addresses(deployment: dict) -> dict[str, str]:
    contracts = deployment.get("contracts") or {}
    required = {
        "nft": contracts.get("pathNft", ""),
        "minter": contracts.get("pathMinter", ""),
        "auction": contracts.get("pulseAuction", ""),
        "treasury": deployment.get("treasury", ""),
        "payment_token": deployment.get("paymentToken", ""),
    }
    missing = [key for key, value in required.items() if not value]
    if missing:
        raise SmokeError(f"deployment artifact missing address fields: {', '.join(missing)}")
    if normalize_address(required["payment_token"]) != ZERO_ADDRESS:
        raise SmokeError("postdeploy smoke page currently supports native-ETH paymentToken only")
    return required


def cast_call(address: str, sig: str, rpc: str, *args: str) -> str:
    return run(["cast", "call", address, sig, *args, "--rpc-url", rpc])


def cast_balance(address: str, rpc: str) -> str:
    return run(["cast", "balance", address, "--rpc-url", rpc])


def write_baseline(args: argparse.Namespace, deployment: dict, addrs: dict[str, str], out: Path) -> Path:
    require_cast()
    rpc = rpc_url(args)
    buyer_balance = cast_balance(args.buyer, rpc)
    ask = parse_cast_uint(cast_call(addrs["auction"], "getCurrentPrice()(uint256)", rpc))
    epoch = parse_cast_uint(cast_call(addrs["auction"], "epochIndex()(uint256)", rpc))
    next_id = parse_cast_uint(cast_call(addrs["minter"], "nextId()(uint256)", rpc))
    treasury = cast_balance(addrs["treasury"], rpc)
    latest = out / "baseline.env"
    stamped = out / f"baseline.{utc_stamp()}.env"
    contents = "\n".join(
        [
            f"run_id={args.run_id}",
            f"network={args.network}",
            f"buyer={args.buyer}",
            f"auction={addrs['auction']}",
            f"nft={addrs['nft']}",
            f"minter={addrs['minter']}",
            f"treasury={addrs['treasury']}",
            f"ask_before={ask}",
            f"epoch_before={epoch}",
            f"next_id_before={next_id}",
            f"treasury_before={treasury}",
            f"buyer_balance_before={buyer_balance}",
            f"deployment={deployment_path(args)}",
        ]
    ) + "\n"
    latest.write_text(contents)
    stamped.write_text(contents)
    return latest


HTML_TEMPLATE = (
    r"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>PATH __NETWORK__ Smoke: __RUN_ID__</title>
    <style>
      :root {
        color-scheme: light dark;
        font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      }
      body {
        max-width: 1080px;
        margin: 32px auto;
        padding: 0 24px 48px;
        line-height: 1.45;
      }
      button {
        font: inherit;
        padding: 10px 14px;
        margin: 6px 8px 6px 0;
        cursor: pointer;
      }
      button:disabled {
        cursor: not-allowed;
        opacity: 0.6;
      }
      pre {
        border: 1px solid #9995;
        padding: 14px;
        overflow-x: auto;
        white-space: pre-wrap;
        word-break: break-word;
      }
      .warn {
        border-left: 4px solid #c60;
        padding-left: 12px;
      }
    </style>
  </head>
  <body>
    <h1>PATH __NETWORK__ Postdeploy Smoke</h1>
    <p class="warn">
      This is a live wallet-signing smoke. Approve only from the disposable buyer
      <code>__BUYER__</code>. Do not use ADMIN, TREASURY, or deployer wallets.
    </p>

    <h2>Controls</h2>
    <button id="discover">1. Discover Wallets</button>
    <button id="connect" disabled>2. Connect Rabby</button>
    <button id="refresh" disabled>3. Refresh Ask + Simulate</button>
    <button id="send" disabled>4. Send Smoke Bid</button>

    <h2>Status</h2>
    <pre id="status">Idle.</pre>

    <h2>Transaction Preview</h2>
    <pre id="preview">No transaction prepared.</pre>

    <script>
      const RUN_ID = "__RUN_ID__";
      const NETWORK = "__NETWORK__";
      const EXPECTED_BUYER = "__BUYER__";
      const CHAIN_ID = "__CHAIN_ID__";
      const NFT = "__NFT__";
      const MINTER = "__MINTER__";
      const AUCTION = "__AUCTION__";
      const TREASURY = "__TREASURY__";

      const SELECTOR_BID = "0x454a2ab3";
      const SELECTOR_GET_CURRENT_PRICE = "0xeb91d37e";
      const SELECTOR_EPOCH_INDEX = "0x06c106f9";
      const SELECTOR_NEXT_ID = "0x61b8ce8c";

      const statusEl = document.getElementById("status");
      const previewEl = document.getElementById("preview");
      const discoverButton = document.getElementById("discover");
      const connectButton = document.getElementById("connect");
      const refreshButton = document.getElementById("refresh");
      const sendButton = document.getElementById("send");

      let providers = [];
      let provider = null;
      let connectedAccount = null;
      let prepared = null;

      function log(message) {
        statusEl.textContent = `${new Date().toISOString()} ${message}\n\n${statusEl.textContent}`;
      }

      function normalizeAddress(address) {
        return String(address || "").toLowerCase();
      }

      function requireCondition(condition, message) {
        if (!condition) throw new Error(message);
      }

      function quantityHex(value) {
        return `0x${BigInt(value).toString(16)}`;
      }

      function uint256Word(value) {
        return BigInt(value).toString(16).padStart(64, "0");
      }

      function bidCalldata(maxPriceWei) {
        return `${SELECTOR_BID}${uint256Word(maxPriceWei)}`;
      }

      function decodeUint256(hex) {
        return BigInt(hex || "0x0").toString(10);
      }

      async function request(method, params = []) {
        requireCondition(provider, "Wallet provider is not connected.");
        return provider.request({ method, params });
      }

      async function switchNetwork() {
        const chainId = await request("eth_chainId");
        if (chainId === CHAIN_ID) return;
        await request("wallet_switchEthereumChain", [{ chainId: CHAIN_ID }]);
      }

      function pickRabbyProvider() {
        const rabby = providers.find((entry) => /rabby/i.test(entry.info?.name || ""));
        if (rabby) return rabby.provider;
        if (window.rabby) return window.rabby;
        if (window.ethereum?.isRabby) return window.ethereum;
        return null;
      }

      async function discoverProviders() {
        providers = [];
        window.addEventListener("eip6963:announceProvider", (event) => {
          if (!providers.some((entry) => entry.info?.uuid === event.detail.info?.uuid)) {
            providers.push(event.detail);
          }
        });
        window.dispatchEvent(new Event("eip6963:requestProvider"));
        await new Promise((resolve) => setTimeout(resolve, 500));

        provider = pickRabbyProvider();
        if (!provider && window.ethereum) provider = window.ethereum;

        const names = providers.map((entry) => entry.info?.name || "unknown").join(", ") || "none";
        log(`Providers discovered: ${names}`);
        if (provider) {
          log(`Selected provider: ${provider.isRabby ? "Rabby/window.ethereum" : "available provider"}`);
          connectButton.disabled = false;
        } else {
          log("No wallet provider found. Open this page in a browser with Rabby enabled.");
        }
      }

      async function connect() {
        await switchNetwork();
        const accounts = await request("eth_requestAccounts");
        connectedAccount = accounts[0];
        requireCondition(connectedAccount, "No account returned by wallet.");
        requireCondition(
          normalizeAddress(connectedAccount) === normalizeAddress(EXPECTED_BUYER),
          `Wrong account: ${connectedAccount}. Select expected buyer ${EXPECTED_BUYER}.`
        );
        log(`Connected buyer: ${connectedAccount}`);
        refreshButton.disabled = false;
      }

      async function refreshAndSimulate() {
        await switchNetwork();
        requireCondition(
          normalizeAddress(connectedAccount) === normalizeAddress(EXPECTED_BUYER),
          "Connect the expected buyer before simulating."
        );

        const askWei = decodeUint256(await request("eth_call", [{ to: AUCTION, data: SELECTOR_GET_CURRENT_PRICE }, "latest"]));
        const epoch = decodeUint256(await request("eth_call", [{ to: AUCTION, data: SELECTOR_EPOCH_INDEX }, "latest"]));
        const nextId = decodeUint256(await request("eth_call", [{ to: MINTER, data: SELECTOR_NEXT_ID }, "latest"]));
        const data = bidCalldata(askWei);
        const value = quantityHex(askWei);

        requireCondition(data.startsWith(SELECTOR_BID), `Bad selector: ${data.slice(0, 10)}`);
        requireCondition(data.length === 74, `Bad calldata length: ${data.length}, expected 74`);

        const tx = {
          from: connectedAccount,
          to: AUCTION,
          value,
          data,
        };

        const simulated = await request("eth_call", [tx, "latest"]);
        const gasEstimate = await request("eth_estimateGas", [tx]);

        prepared = { runId: RUN_ID, network: NETWORK, askWei, epoch, nextId, tx, simulated, gasEstimate };
        previewEl.textContent = JSON.stringify(prepared, null, 2);
        log("Simulation passed. Transaction is prepared. Check preview before sending.");
        sendButton.disabled = false;
      }

      async function pollTx(txHash) {
        for (let i = 0; i < 40; i += 1) {
          const tx = await request("eth_getTransactionByHash", [txHash]);
          if (tx) return tx;
          await new Promise((resolve) => setTimeout(resolve, 3000));
        }
        throw new Error("Timed out waiting for transaction to appear in RPC.");
      }

      async function send() {
        requireCondition(prepared, "Run Refresh Ask + Simulate first.");
        requireCondition(prepared.tx.data.startsWith(SELECTOR_BID), "Prepared data selector is wrong.");
        requireCondition(prepared.tx.data.length === 74, "Prepared data length is wrong.");

        log("Requesting wallet signature. Approve only if the wallet shows the expected buyer, auction, and value.");
        const txHash = await request("eth_sendTransaction", [prepared.tx]);
        log(`Submitted: ${txHash}`);

        const minedTx = await pollTx(txHash);
        const onChainInput = minedTx.input || minedTx.data || "";
        const expectedInput = prepared.tx.data;
        if (onChainInput.toLowerCase() !== expectedInput.toLowerCase()) {
          previewEl.textContent = JSON.stringify({ txHash, expectedInput, onChainInput, minedTx }, null, 2);
          throw new Error(`Wallet/provider calldata mismatch. Expected ${expectedInput}, got ${onChainInput}`);
        }

        previewEl.textContent = JSON.stringify({ txHash, expectedInput, onChainInput, minedTx }, null, 2);
        log(`Input verified on-chain. TX_HASH=${txHash}`);
      }

      discoverButton.onclick = () => discoverProviders().catch((error) => log(`Discover failed: ${error.message || error}`));
      connectButton.onclick = () => connect().catch((error) => log(`Connect failed: ${error.message || error}`));
      refreshButton.onclick = () => refreshAndSimulate().catch((error) => log(`Simulation failed: ${error.message || error}`));
      sendButton.onclick = () => send().catch((error) => log(`Send failed: ${error.message || error}`));
    </script>
  </body>
</html>
"""
)


def render_page(args: argparse.Namespace, deployment: dict, addrs: dict[str, str], out: Path) -> Path:
    replacements = {
        "__RUN_ID__": args.run_id,
        "__NETWORK__": args.network,
        "__CHAIN_ID__": chain_id_hex(args.network),
        "__BUYER__": args.buyer,
        "__NFT__": addrs["nft"],
        "__MINTER__": addrs["minter"],
        "__AUCTION__": addrs["auction"],
        "__TREASURY__": addrs["treasury"],
    }
    page = HTML_TEMPLATE
    for needle, value in replacements.items():
        page = page.replace(needle, value)
    path = out / "smoke-rabby.html"
    path.write_text(page)
    return path


def serve_command(args: argparse.Namespace) -> int:
    deployment = load_deployment(args)
    addrs = addresses(deployment)
    out = output_dir(args)
    out.mkdir(parents=True, exist_ok=True)
    baseline = write_baseline(args, deployment, addrs, out)
    page = render_page(args, deployment, addrs, out)
    print(f"Baseline written: {baseline}")
    print(f"Smoke page written: {page}")
    print(f"Open: http://127.0.0.1:{args.port}/{page.name}")
    print("Stop this server with Ctrl-C after the wallet flow is complete.")

    class Handler(http.server.SimpleHTTPRequestHandler):
        pass

    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    os.chdir(out)
    with ReusableTCPServer(("127.0.0.1", args.port), Handler) as httpd:
        httpd.serve_forever()
    return 0


def read_baseline(out: Path) -> dict[str, str]:
    path = out / "baseline.env"
    if not path.is_file():
        return {}
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def verify_command(args: argparse.Namespace) -> int:
    require_cast()
    deployment = load_deployment(args)
    addrs = addresses(deployment)
    out = output_dir(args)
    out.mkdir(parents=True, exist_ok=True)
    rpc = rpc_url(args)
    baseline = read_baseline(out)
    token_id = args.token_id or baseline.get("next_id_before")
    epoch_before = baseline.get("epoch_before")
    treasury_before = baseline.get("treasury_before")
    if not token_id:
        raise SmokeError("missing expected token id; pass --token-id or run serve first")

    stamp = utc_stamp()
    receipt_file = out / f"receipt.{stamp}.txt"
    tx_file = out / f"tx.{stamp}.txt"
    post_file = out / f"post.{stamp}.env"

    receipt_text = run(["cast", "receipt", args.tx_hash, "--rpc-url", rpc])
    tx_text = run(["cast", "tx", args.tx_hash, "--rpc-url", rpc])
    receipt_file.write_text(receipt_text + "\n")
    tx_file.write_text(tx_text + "\n")

    owner_after = cast_call(addrs["nft"], "ownerOf(uint256)(address)", rpc, token_id).strip()
    epoch_after = parse_cast_uint(cast_call(addrs["auction"], "epochIndex()(uint256)", rpc))
    next_id_after = parse_cast_uint(cast_call(addrs["minter"], "nextId()(uint256)", rpc))
    treasury_after = cast_balance(addrs["treasury"], rpc)

    receipt_status = ""
    tx_input = ""
    tx_value = ""
    for line in receipt_text.splitlines():
        parts = line.split()
        if parts[:1] == ["status"] and len(parts) >= 2:
            receipt_status = parts[1]
    for line in tx_text.splitlines():
        parts = line.split()
        if parts[:1] == ["input"] and len(parts) >= 2:
            tx_input = parts[1]
        if parts[:1] == ["value"] and len(parts) >= 2:
            tx_value = parts[1]

    checks = {
        "receipt_success": receipt_status == "1",
        "owner_is_buyer": normalize_address(owner_after) == normalize_address(args.buyer),
        "treasury_increased": treasury_before is not None and int(treasury_after) > int(treasury_before),
        "epoch_advanced": epoch_before is not None and int(epoch_after) == int(epoch_before) + 1,
        "tx_calls_bid": tx_input.lower().startswith("0x454a2ab3"),
    }
    status = "pass" if all(checks.values()) else "fail"

    post = {
        "run_id": args.run_id,
        "network": args.network,
        "buyer": args.buyer,
        "tx_hash": args.tx_hash,
        "tx_value": tx_value,
        "tx_input": tx_input,
        "token_id": token_id,
        "receipt_status": receipt_status,
        "owner_after": owner_after,
        "epoch_before": epoch_before or "",
        "epoch_after": epoch_after,
        "next_id_after": next_id_after,
        "treasury_before": treasury_before or "",
        "treasury_after": treasury_after,
        "status": status,
    }
    post_file.write_text("".join(f"{key}={value}\n" for key, value in post.items()))

    note = out / "SMOKE-NOTE.md"
    note.write_text(
        textwrap.dedent(
            f"""\
            # Sepolia Postdeploy Smoke

            Run ID: {args.run_id}
            Buyer: {args.buyer}
            Transaction: {args.tx_hash}
            Expected token id: {token_id}

            Checks:
            - receipt success: {'pass' if checks['receipt_success'] else 'fail'}
            - tx input calls bid(uint256): {'pass' if checks['tx_calls_bid'] else 'fail'}
            - ownerOf(token_id) == buyer: {'pass' if checks['owner_is_buyer'] else 'fail'}
            - treasury balance increased: {'pass' if checks['treasury_increased'] else 'fail'}
            - epoch advanced by one: {'pass' if checks['epoch_advanced'] else 'fail'}

            Result: {status}
            """
        )
    )

    print(post_file.read_text(), end="")
    print(f"SMOKE_STATUS={status.upper()}")
    print(f"SMOKE_NOTE={note}")
    return 0 if status == "pass" else 1


def add_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--network", default=os.environ.get("NETWORK", "sepolia"))
    parser.add_argument("--run-id", default=os.environ.get("RUN_ID", ""))
    parser.add_argument("--buyer", default=os.environ.get("BUYER", ""))
    parser.add_argument(
        "--history-root",
        default=os.environ.get("SIGNING_OS_HISTORY_ROOT", "~/Private/signing-os-history"),
    )
    parser.add_argument("--output-dir", default=os.environ.get("SMOKE_OUTPUT_DIR", ""))
    parser.add_argument("--rpc-url", default=os.environ.get("SEPOLIA_RPC_URL", ""))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    serve = sub.add_parser("serve", help="serve the local Rabby smoke page")
    add_common(serve)
    serve.add_argument("--port", type=int, default=int(os.environ.get("SMOKE_PORT", "9755")))

    verify = sub.add_parser("verify", help="verify a submitted smoke transaction")
    add_common(verify)
    verify.add_argument("--tx-hash", default=os.environ.get("TX_HASH", ""))
    verify.add_argument("--token-id", default=os.environ.get("TOKEN_ID", ""))
    return parser


def validate_args(args: argparse.Namespace) -> None:
    if not args.run_id:
        raise SmokeError("--run-id is required")
    if not args.buyer:
        raise SmokeError("--buyer is required")
    if args.network not in {"sepolia"}:
        raise SmokeError("only sepolia is currently supported")
    if args.command == "verify" and not args.tx_hash:
        raise SmokeError("--tx-hash or TX_HASH is required for verify")


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    validate_args(args)
    try:
        if args.command == "serve":
            return serve_command(args)
        if args.command == "verify":
            return verify_command(args)
        raise SmokeError(f"unknown command: {args.command}")
    except KeyboardInterrupt:
        print("\nStopped.")
        return 130
    except SmokeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
