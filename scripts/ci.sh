#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FORGE="$(bash scripts/find-forge.sh)"

"$FORGE" fmt --check
"$FORGE" build --deny warnings
FOUNDRY_PROFILE=ci "$FORGE" test --deny warnings
