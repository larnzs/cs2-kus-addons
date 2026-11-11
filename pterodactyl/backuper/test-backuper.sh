#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
SCRIPT="$ROOT/fragcity-backuper.sh"
INSTALLER="$ROOT/install.sh"

bash -n "$SCRIPT" "$INSTALLER"
bash "$SCRIPT" --help | grep -Fq -- '--verify'
bash "$SCRIPT" --help | grep -Fq -- '--dry-run'

set +e
bash "$SCRIPT" --invalid-mode >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 2 ]] || { echo "Invalid CLI mode must exit 2 (got $status)." >&2; exit 1; }

grep -Fq 'mariadb-dump' "$SCRIPT"
grep -Fq -- '--rdb' "$SCRIPT"
grep -Fq 'sha256sum -c metadata/SHA256SUMS' "$SCRIPT"
grep -Fq 'fragcity-payload-stage.lock' "$SCRIPT"

if grep -Eq 'systemctl (enable|disable|start|stop).*fragcity-addon-(provision|payload-sync)' "$INSTALLER"; then
  echo "Backuper installer must not control existing Provisioner timers." >&2
  exit 1
fi

echo "PASS: Backuper syntax, CLI safety, checksum and auto-update isolation guards."
