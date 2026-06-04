#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

status=0

scan() {
  local label="$1"
  local pattern="$2"
  shift 2
  if rg --hidden \
    --glob '!.git/' \
    --glob '!.build/' \
    --glob '!DerivedData/' \
    --glob '!*.xcuserstate' \
    --glob '!*.dSYM/' \
    --glob '!*.dSYM.zip' \
    "$@" \
    -n "$pattern" .; then
    echo "secret-scan: matched ${label}" >&2
    status=1
  fi
}

scan "Jupiter API key env" 'JUP(ITER)?_API_KEY=[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
scan "keyed Solana RPC env" '(SOLANA_RPC_URL|HELIUS_RPC_URL)=https?://[^[:space:]]*api-key=[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
scan "keyed Solana RPC baked into source" '"(SOLANA_RPC_URL|HELIUS_RPC_URL)"[[:space:]]*:[[:space:]]*"https?://[^"]*api-key=[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
scan "WalletConnect project id env" 'WALLETCONNECT_PROJECT_ID=[0-9a-fA-F]{32}'
scan "WalletConnect project id baked into source" '"WALLETCONNECT_PROJECT_ID"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]{32}"'
scan "private key material" '(PRIVATE_KEY|SECRET_KEY|MNEMONIC|RECOVERY_PHRASE)='
scan "raw wallet callback logs" 'callback_raw=[^[:space:]]*(data|payload|session)=' \
  --glob '!Sources/**' \
  --glob '!Tests/**'
scan "unsafe wallet payload logs" '(payload_json_raw|session_token_raw|signed_message_raw|transaction_raw|signature_raw)=' \
  --glob '!Sources/**' \
  --glob '!Tests/**'

if [[ "$status" -ne 0 ]]; then
  echo "secret-scan: failed; remove committed secrets/raw wallet logs or use placeholders." >&2
  exit "$status"
fi

echo "secret-scan: ok"
