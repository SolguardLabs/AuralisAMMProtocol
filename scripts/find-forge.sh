#!/usr/bin/env bash
set -euo pipefail

if command -v forge >/dev/null 2>&1; then
  command -v forge
  exit 0
fi

if command -v forge.exe >/dev/null 2>&1; then
  command -v forge.exe
  exit 0
fi

candidates=("$HOME/.foundry/bin/forge" "$HOME/.foundry/bin/forge.exe")
if [[ -n "${USERPROFILE:-}" ]] && command -v cygpath >/dev/null 2>&1; then
  windows_home="$(cygpath -u "$USERPROFILE")"
  candidates+=("$windows_home/.foundry/bin/forge.exe")
fi
current_path="$(pwd -P)"
if [[ "$current_path" =~ ^(/mnt/[a-zA-Z]/Users/[^/]+) ]]; then
  candidates+=("${BASH_REMATCH[1]}/.foundry/bin/forge.exe")
fi

for candidate in "${candidates[@]}"; do
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    exit 0
  fi
done

echo "forge executable not found. Install Foundry or add forge to PATH." >&2
exit 127
