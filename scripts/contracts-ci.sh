#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FORGE="$(bash scripts/find-forge.sh)"

"$FORGE" fmt --check
"$FORGE" build --sizes --deny warnings
export FOUNDRY_PROFILE=ci
# WSL only forwards selected Linux variables to Windows executables.
export WSLENV="${WSLENV:+${WSLENV}:}FOUNDRY_PROFILE"
"$FORGE" test --deny warnings
