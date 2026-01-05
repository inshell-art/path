#!/usr/bin/env python3
import argparse
import asyncio
import json
from pathlib import Path

import aiohttp
from starknet_py.hash.selector import get_selector_from_name
from starknet_py.net.account.account import Account
from starknet_py.net.client_models import Call
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


def parse_felt(value: str) -> int:
    value = value.strip()
    return int(value, 0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Invoke via v3 tx")
    parser.add_argument("--rpc", required=True)
    parser.add_argument("--accounts-file", required=True)
    parser.add_argument("--namespace", default="alpha-sepolia")
    parser.add_argument("--account", required=True)
    parser.add_argument("--contract-address", required=True)
    parser.add_argument("--function", required=True)
    parser.add_argument("--calldata", nargs="*", default=[])
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

    calldata = [parse_felt(x) for x in args.calldata]
    call = Call(
        to_addr=parse_felt(args.contract_address),
        selector=get_selector_from_name(args.function),
        calldata=calldata,
    )

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

        invoke_tx = await account.sign_invoke_v3(call, auto_estimate=True)
        resp = await client.send_transaction(invoke_tx)

    print(json.dumps({"tx_hash": hex(resp.transaction_hash)}))


if __name__ == "__main__":
    asyncio.run(main())
