#!/usr/bin/env bash
set -euo pipefail

npm --prefix evm run serial:bids:local:eth
