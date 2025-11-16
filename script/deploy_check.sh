#!/usr/bin/env bash
set -euo pipefail

# Deployment environment preflight checker
# Auto-load .env.local if present, then verify required variables.

if [ -f .env.local ]; then
  echo "[info] Loading .env.local"
  # Allow sourcing even if some vars unset
  set +u
  source .env.local
  set -u
fi

MISSING=()
PLACEHOLDER_ISSUES=()

required_vars=(KAMAL_REGISTRY_PASSWORD RAILS_MASTER_KEY SECRET_KEY_BASE POSTGRES_PASSWORD)

check_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    MISSING+=("$name")
  fi
}

for v in "${required_vars[@]}"; do
  check_var "$v"
done

# Detect placeholder SECRET_KEY_BASE
if [ "${SECRET_KEY_BASE:-}" = "REPLACE_WITH_GENERATED_SECRET_KEY_BASE" ]; then
  PLACEHOLDER_ISSUES+=("SECRET_KEY_BASE is still placeholder. Generate one: ruby -rsecurerandom -e 'puts SecureRandom.hex(64)' and update .env.local")
fi

if [ ${#MISSING[@]} -gt 0 ] || [ ${#PLACEHOLDER_ISSUES[@]} -gt 0 ]; then
  echo "ERROR: Environment validation failed." >&2
  if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Missing variables:" >&2
    for v in "${MISSING[@]}"; do echo "  - $v" >&2; done
  fi
  if [ ${#PLACEHOLDER_ISSUES[@]} -gt 0 ]; then
    echo "Placeholder issues:" >&2
    for p in "${PLACEHOLDER_ISSUES[@]}"; do echo "  - $p" >&2; done
  fi
  cat >&2 <<'EOF'

Fix steps:
  1. Edit .env.local and set real values.
     Example:
       export KAMAL_REGISTRY_PASSWORD="<docker_pat_token>"
       export RAILS_MASTER_KEY="$(cat config/master.key)"   # or keep existing
       export SECRET_KEY_BASE="$(ruby -rsecurerandom -e 'puts SecureRandom.hex(64)')"
       export POSTGRES_PASSWORD="<secure_db_password>"
  2. Re-load: source .env.local
  3. Re-run: ./script/deploy_check.sh
EOF
  exit 1
fi

echo "All required deployment environment variables are present."
