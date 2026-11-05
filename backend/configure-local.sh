#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -f .env ]]; then
  printf '%s\n' 'A local .env already exists. Edit it to update your key; it was not overwritten.'
  exit 0
fi
command -v openssl >/dev/null || { printf '%s\n' 'OpenSSL is required to generate your backend token.'; exit 1; }
read -r -s -p 'OpenAI API key (hidden): ' jumpin_api_key
printf '\n'
if [[ ! "$jumpin_api_key" =~ ^[A-Za-z0-9_-]{20,}$ ]]; then
  printf '%s\n' 'The key format was not recognized. Nothing was saved.'
  exit 1
fi
umask 077
jumpin_token="$(openssl rand -hex 32)"
{
  printf 'OPENAI_API_KEY=%s\n' "$jumpin_api_key"
  printf 'OPENAI_MODEL=gpt-4.1-mini\n'
  printf 'JUMPIN_ACCESS_TOKEN=%s\n' "$jumpin_token"
  printf 'BIND_ADDRESS=127.0.0.1\nPORT=8080\n'
} > .env
unset jumpin_api_key
printf '%s\n' 'Saved private configuration. Run ./run-local.sh to start the backend.'
if command -v pbcopy >/dev/null; then
  printf '%s' "$jumpin_token" | pbcopy
  printf '%s\n' 'The backend access token is on your clipboard. Paste it into Jump In → Coach settings.'
else
  printf '%s\n' 'Copy JUMPIN_ACCESS_TOKEN from .env into Jump In → Coach settings.'
fi
unset jumpin_token
