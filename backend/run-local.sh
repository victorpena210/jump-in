#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v java >/dev/null || { printf '%s\n' 'Install JDK 17 or later first.'; exit 1; }
command -v mvn >/dev/null || { printf '%s\n' 'Install Maven 3.9 or later first.'; exit 1; }
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi
if [[ -z "${OPENAI_API_KEY:-}" || -z "${JUMPIN_ACCESS_TOKEN:-}" ]]; then
  printf '%s\n' 'Run ./configure-local.sh first, or set OPENAI_API_KEY and JUMPIN_ACCESS_TOKEN in your environment.'
  exit 1
fi
exec mvn -B -ntp spring-boot:run
