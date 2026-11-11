#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
SCRIPT="$ROOT/fragcity-backuper.sh"
INSTALLER="$ROOT/install.sh"

bash -n "$SCRIPT"
bash -n "$INSTALLER"
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

# Prove archive verification works without a live DB, Redis daemon or repo checkout.
VERIFY_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$VERIFY_ROOT"' EXIT
mkdir -p "$VERIFY_ROOT/input/metadata" "$VERIFY_ROOT/input/databases" "$VERIFY_ROOT/input/files" "$VERIFY_ROOT/sample-platform"
printf 'SELECT 1;\\n' | gzip -1 > "$VERIFY_ROOT/input/databases/mariadb-all.sql.gz"
printf 'test-rdb-placeholder\\n' > "$VERIFY_ROOT/input/databases/redis.rdb"
printf 'platform test\\n' > "$VERIFY_ROOT/sample-platform/readme.txt"
tar -czf "$VERIFY_ROOT/input/files/platform-files.tar.gz" -C "$VERIFY_ROOT/sample-platform" .
(
  cd "$VERIFY_ROOT/input"
  sha256sum databases/mariadb-all.sql.gz databases/redis.rdb files/platform-files.tar.gz > metadata/SHA256SUMS
)
tar -czf "$VERIFY_ROOT/fragcity-test.tar.gz" -C "$VERIFY_ROOT/input" metadata databases files
sha256sum "$VERIFY_ROOT/fragcity-test.tar.gz" | sed "s#  .*#  fragcity-test.tar.gz#" > "$VERIFY_ROOT/fragcity-test.tar.gz.sha256"
mkdir -p "$VERIFY_ROOT/min-bin"
for command_name in tar gzip sha256sum mktemp mkdir rm date dirname basename grep; do
  ln -s "$(command -v "$command_name")" "$VERIFY_ROOT/min-bin/$command_name"
done
PATH="$VERIFY_ROOT/min-bin" FRAGCITY_BACKUP_CONFIG="$VERIFY_ROOT/no-config" \
  /bin/bash "$SCRIPT" --verify "$VERIFY_ROOT/fragcity-test.tar.gz"

if grep -Eq 'systemctl (enable|disable|start|stop).*fragcity-addon-(provision|payload-sync)' "$INSTALLER"; then
  echo "Backuper installer must not control existing Provisioner timers." >&2
  exit 1
fi

echo "PASS: Backuper syntax, CLI safety, checksum and auto-update isolation guards."
