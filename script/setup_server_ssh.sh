#!/usr/bin/env bash
# Install local SSH public keys on the Contabo production server
# (207.180.216.54, see config/deploy.yml) and verify key-based login.
#
# Usage: script/setup_server_ssh.sh
# You will be prompted for the server's root password once per key.

set -euo pipefail

SERVER="${SERVER:-root@84.247.137.120}"
KEYS=(
  "$HOME/.ssh/contabo_ed25519.pub" # dedicated Contabo key
  "$HOME/.ssh/id_ed25519.pub"   # personal key
  "$HOME/.ssh/salato_deploy.pub" # Kamal deploy key
)

PUBKEYS=""
for key in "${KEYS[@]}"; do
  if [ ! -f "$key" ]; then
    echo "Skipping missing key: $key"
    continue
  fi
  echo "==> Will install $key on $SERVER"
  PUBKEYS+="$(cat "$key")"$'\n'
done

# Contabo images ship /root/.ssh/authorized_keys with the immutable attribute
# (chattr +i), which makes ssh-copy-id fail with "Operation not permitted".
# Clear the flag, append the keys (deduplicated), then restore permissions.
# Everything runs in one SSH session, so the password is asked only once.
echo "==> Installing keys (enter the root password once)"
printf '%s' "$PUBKEYS" | ssh -o StrictHostKeyChecking=accept-new "$SERVER" '
  set -e
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  chattr -ia ~/.ssh ~/.ssh/authorized_keys 2>/dev/null || true
  touch ~/.ssh/authorized_keys
  cat >> ~/.ssh/authorized_keys
  sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  echo "Installed $(wc -l < ~/.ssh/authorized_keys) key(s) in ~/.ssh/authorized_keys"
'

echo "==> Verifying key-based login"
for key in "${KEYS[@]}"; do
  [ -f "$key" ] || continue
  ssh -o BatchMode=yes -o ConnectTimeout=10 -i "${key%.pub}" "$SERVER" \
    "echo 'OK: ${key##*/} accepted by' \$(hostname)"
done

echo "Done. Connect with: ssh contabo"
