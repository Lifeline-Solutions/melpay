#!/usr/bin/env bash
set -euo pipefail

MISSING=()

check_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    MISSING+=("$name")
  fi
}

check_var KAMAL_REGISTRY_PASSWORD
check_var RAILS_MASTER_KEY
check_var SECRET_KEY_BASE
# Optional DB password
if grep -q POSTGRES_PASSWORD .kamal/secrets 2>/dev/null; then
  check_var POSTGRES_PASSWORD || true
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: Missing required environment variables:" >&2
  for v in "${MISSING[@]}"; do echo "  - $v" >&2; done
  echo "Export them, then re-run: source .env.local (if you added them there)" >&2
  exit 1
fi

echo "All required deployment environment variables are present."
