#!/usr/bin/env python3
import argparse
import asyncio
import json
from pathlib import Path

import aiohttp
from starknet_py.common import create_casm_class
from starknet_py.hash.casm_class_hash import compute_casm_class_hash
from starknet_py.net.account.account import Account
from starknet_py.net.full_node_client import FullNodeClient
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.net.signer.stark_curve_signer import KeyPair


def load_account(accounts_file: Path, namespace: str, name: str) -> dict:
    data = json.loads(accounts_file.read_text())
    try:
        return data[namespace][name]
    except KeyError as exc:
        raise SystemExit(
            f"Account {name} not found in {accounts_file} namespace {namespace}"
        ) from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Declare Sierra class via v3 tx")
    parser.add_argument("--rpc", required=True)
    parser.add_argument("--accounts-file", required=True)
    parser.add_argument("--namespace", default="alpha-sepolia")
    parser.add_argument("--account", required=True)
    parser.add_argument("--sierra", required=True)
    parser.add_argument("--casm", required=True)
    parser.add_argument("--chain", default="sepolia")
    return parser.parse_args()


def chain_id(chain: str) -> int:
    if chain.lower() == "sepolia":
        return StarknetChainId.SEPOLIA
    if chain.lower() == "mainnet":
        return StarknetChainId.MAINNET
    raise SystemExit(f"Unsupported chain: {chain}")


async def main() -> None:
    args = parse_args()

    accounts_file = Path(args.accounts_file).expanduser()
    acct = load_account(accounts_file, args.namespace, args.account)
    address = int(acct["address"], 16)
    priv = int(acct["private_key"], 16)
    pub = int(acct["public_key"], 16)

    sierra = Path(args.sierra).read_text()
    casm_raw = json.loads(Path(args.casm).read_text())
    casm_raw.setdefault("pythonic_hints", [])
    casm = json.dumps(casm_raw)
    casm_class = create_casm_class(casm)
    compiled_class_hash = compute_casm_class_hash(casm_class)

    connector = aiohttp.TCPConnector(ssl=False)
    async with aiohttp.ClientSession(connector=connector) as session:
        client = FullNodeClient(node_url=args.rpc, session=session)
        key_pair = KeyPair(private_key=priv, public_key=pub)
        account = Account(
            address=address,
            client=client,
            key_pair=key_pair,
            chain=chain_id(args.chain),
        )

        declare_tx = await account.sign_declare_v3(
            compiled_contract=sierra,
            compiled_class_hash=compiled_class_hash,
            auto_estimate=True,
        )
        resp = await client.declare(declare_tx)

    print(
        json.dumps(
            {"class_hash": hex(resp.class_hash), "tx_hash": hex(resp.transaction_hash)}
        )
    )


if __name__ == "__main__":
    asyncio.run(main())
