#!/usr/bin/env bash
set -euo pipefail

npm --prefix evm run estimate:deploy:cost
