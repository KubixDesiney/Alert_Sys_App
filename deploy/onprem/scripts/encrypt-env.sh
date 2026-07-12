#!/usr/bin/env bash
# At-rest encryption for the secret configuration.
#   encrypt-env.sh          .env -> .env.enc (AES-256-CBC, PBKDF2), then shreds .env
#   encrypt-env.sh decrypt  .env.enc -> .env (chmod 600)
# The passphrase is asked interactively and never stored.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "decrypt" ]]; then
  [[ -f .env.enc ]] || { echo ".env.enc not found"; exit 1; }
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in .env.enc -out .env
  chmod 600 .env
  echo ".env decrypted (chmod 600). Remember to re-encrypt after maintenance."
else
  [[ -f .env ]] || { echo ".env not found"; exit 1; }
  openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -in .env -out .env.enc
  command -v shred >/dev/null 2>&1 && shred -u .env || rm -f .env
  echo ".env encrypted to .env.enc and plaintext removed."
  echo "NOTE: docker compose needs .env at runtime — decrypt before (re)starting the stack."
fi
