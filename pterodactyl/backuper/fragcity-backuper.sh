#!/usr/bin/env bash
# FragCity platform backuper. The full VMware clone remains the whole-machine recovery layer.
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${FRAGCITY_BACKUP_CONFIG:-/etc/fragcity/backuper.conf}"
MODE="${1:---run}"
VERIFY_TARGET="${2:-}"
log() { printf '[fragcity-backuper] %s %s\n' "$(date -Is)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
FragCity platform backuper
  --run           Create and verify a backup, then apply retention.
  --dry-run       Check dependencies, DB access, Redis and paths; no backup.
  --verify FILE   Verify checksum and nested archives.
  --check-config  Validate config only (CI).
  --help          Show help.
USAGE
}
case "$MODE" in
  --help|-h) usage; exit 0 ;;
  --run|--dry-run|--verify|--check-config) ;;
  *) usage >&2; exit 2 ;;
esac

BACKUP_ROOT="/var/backups/fragcity"
RETENTION_DAYS=14
MIN_FREE_SPACE_MB=2048
BACKUP_PATHS=(etc var/www opt/fragcity/cs2-kus-addons var/lib/pterodactyl/fragcity-addon-provisioner usr/local/bin usr/local/sbin usr/local/libexec)
EXTRA_BACKUP_PATHS=()
MARIADB_ARGS=()
REDIS_CLI_ARGS=()
REDIS_PASSWORD_FILE=""
BACKUP_ENCRYPTION=0
GPG_PASSPHRASE_FILE=""

if [[ -e "$CONFIG_FILE" || -L "$CONFIG_FILE" ]]; then
  [[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || die "Config path is not a safe regular file: $CONFIG_FILE"
  if [[ "${FRAGCITY_BACKUP_TEST_MODE:-0}" != "1" ]]; then
    [[ "$(stat -c '%u' "$CONFIG_FILE")" == "0" ]] || die "Config must be root-owned."
    config_mode="$(stat -c '%a' "$CONFIG_FILE")"
    [[ "$config_mode" == "400" || "$config_mode" == "600" ]] || die "Config must have mode 0400 or 0600."
  fi
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
elif [[ "$MODE" != "--verify" || "$VERIFY_TARGET" == *.gpg || "$MODE" == "--check-config" ]]; then
  die "Missing config: $CONFIG_FILE"
fi

case "$BACKUP_ROOT/" in /var/backups/*) ;; *) die "BACKUP_ROOT must be below /var/backups." ;; esac
case "$BACKUP_ROOT/" in *"/../"*) die "BACKUP_ROOT cannot contain '..'." ;; esac
[[ "$BACKUP_ROOT" != "/var/backups/" && ! -L "$BACKUP_ROOT" ]] || die "Unsafe BACKUP_ROOT."
[[ "$RETENTION_DAYS" =~ ^[1-9][0-9]{0,3}$ ]] || die "RETENTION_DAYS must be 1..9999."
[[ "$MIN_FREE_SPACE_MB" =~ ^[1-9][0-9]{0,7}$ ]] || die "MIN_FREE_SPACE_MB must be positive."
[[ "$BACKUP_ENCRYPTION" == "0" || "$BACKUP_ENCRYPTION" == "1" ]] || die "BACKUP_ENCRYPTION must be 0 or 1."
for array_name in BACKUP_PATHS EXTRA_BACKUP_PATHS MARIADB_ARGS REDIS_CLI_ARGS; do
  declare -p "$array_name" 2>/dev/null | grep -q '^declare -a ' || die "$array_name must be a Bash array."
done
validate_path() {
  local path="$1"
  [[ -n "$path" && "$path" != /* && "$path" != *"//"* ]] || return 1
  case "/$path/" in *"/../"*) return 1 ;; esac
}
for path in "${BACKUP_PATHS[@]}" "${EXTRA_BACKUP_PATHS[@]}"; do
  validate_path "$path" || die "Unsafe path in config: $path"
done
validate_secret_file() {
  local secret_path="$1" secret_label="$2" secret_mode
  [[ -n "$secret_path" && -f "$secret_path" && ! -L "$secret_path" ]] || die "$secret_label file is missing or unsafe."
  case "$secret_path" in /root/fragcity-backup-secrets/*) ;; *) die "$secret_label file must be stored under /root/fragcity-backup-secrets/ so it cannot be included in the platform archive." ;; esac
  [[ "$(stat -c '%u' "$secret_path")" == "0" ]] || die "$secret_label file must be root-owned."
  secret_mode="$(stat -c '%a' "$secret_path")"
  [[ "$secret_mode" == "400" || "$secret_mode" == "600" ]] || die "$secret_label file must have mode 0400 or 0600."
}
if [[ -n "$REDIS_PASSWORD_FILE" ]]; then
  validate_secret_file "$REDIS_PASSWORD_FILE" "Redis password"
fi
if [[ "$BACKUP_ENCRYPTION" == "1" ]]; then
  validate_secret_file "$GPG_PASSPHRASE_FILE" "GPG passphrase"
fi
if [[ "$MODE" == "--check-config" ]]; then
  log "Config valid; destination=$BACKUP_ROOT retention=$RETENTION_DAYS days."
  exit 0
fi

verify_archive_core() {
  local archive="$1" temp_dir payload
  [[ -f "$archive" && ! -L "$archive" ]] || die "Archive is missing or unsafe: $archive"
  temp_dir="$(mktemp -d /var/tmp/fragcity-backup-verify.XXXXXX)" || die "Cannot create verification temp directory."
  payload="$temp_dir/backup.tar.gz"
  if [[ "$archive" == *.gpg ]]; then
    [[ "$BACKUP_ENCRYPTION" == "1" && -n "$GPG_PASSPHRASE_FILE" ]] || { rm -rf -- "$temp_dir"; die "Encrypted archive; configure its root-only GPG passphrase file first."; }
    if ! gpg --batch --quiet --no-symkey-cache --pinentry-mode loopback --passphrase-file "$GPG_PASSPHRASE_FILE" --decrypt "$archive" > "$payload"; then
      rm -rf -- "$temp_dir"; die "GPG decryption/integrity check failed."
    fi
  else
    if ! cp -- "$archive" "$payload"; then rm -rf -- "$temp_dir"; die "Could not stage archive for verification."; fi
  fi
  if ! gzip -t "$payload"; then rm -rf -- "$temp_dir"; die "Outer gzip integrity check failed."; fi
  mkdir -p "$temp_dir/extracted"
  if ! tar -xzf "$payload" --no-same-owner --no-same-permissions -C "$temp_dir/extracted"; then
    rm -rf -- "$temp_dir"; die "Could not extract backup for verification."
  fi
  if ! (
    cd "$temp_dir/extracted"
    sha256sum -c metadata/SHA256SUMS
    gzip -t databases/mariadb-all.sql.gz
    tar -tzf files/platform-files.tar.gz >/dev/null
  ); then
    rm -rf -- "$temp_dir"; die "Nested archive/checksum verification failed."
  fi
  if command -v redis-check-rdb >/dev/null 2>&1; then
    if ! redis-check-rdb "$temp_dir/extracted/databases/redis.rdb" >/dev/null 2>&1; then
      rm -rf -- "$temp_dir"; die "Redis RDB validation failed."
    fi
  fi
  rm -rf -- "$temp_dir"
}

# Verification is intentionally independent of the live MariaDB, Redis and Git checkout.
if [[ "$MODE" == "--verify" ]]; then
  for cmd in tar gzip sha256sum mktemp cp mkdir rm; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required verification command missing: $cmd"
  done
  if [[ "$VERIFY_TARGET" == *.gpg ]]; then
    command -v gpg >/dev/null 2>&1 || die "gpg is required to verify this encrypted archive."
  fi
  [[ -n "$VERIFY_TARGET" ]] || die "--verify requires an archive path."
  if [[ -f "$VERIFY_TARGET.sha256" ]]; then
    (cd "$(dirname -- "$VERIFY_TARGET")" && sha256sum -c "$(basename -- "$VERIFY_TARGET").sha256") || die "Outer SHA-256 sidecar check failed."
  fi
  verify_archive_core "$VERIFY_TARGET"
  log "VERIFIED: $VERIFY_TARGET"
  exit 0
fi

[[ "$(id -u)" -eq 0 ]] || die "Run as root."
for cmd in mariadb mariadb-dump redis-cli tar gzip sha256sum flock findmnt df stat git; do
  command -v "$cmd" >/dev/null 2>&1 || die "Required command missing: $cmd"
done
if [[ "$BACKUP_ENCRYPTION" == "1" ]]; then command -v gpg >/dev/null 2>&1 || die "gpg is required for encryption."; fi
[[ -d "$REPO_ROOT/.git" && "$REPO_ROOT" == "/opt/fragcity/cs2-kus-addons" ]] || die "Expected Git checkout at /opt/fragcity/cs2-kus-addons."
[[ "$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)" == "integration/kus-monorepo" ]] || die "Checkout must be on integration/kus-monorepo."

mkdir -p -- "$BACKUP_ROOT"
chmod 0700 "$BACKUP_ROOT"
[[ ! -L "$BACKUP_ROOT" ]] || die "Backup root is a symlink."
if [[ -n "$REDIS_PASSWORD_FILE" ]]; then
  [[ -f "$REDIS_PASSWORD_FILE" && ! -L "$REDIS_PASSWORD_FILE" ]] || die "Redis password file is missing or unsafe."
  [[ "$(stat -c '%u' "$REDIS_PASSWORD_FILE")" == "0" ]] || die "Redis password file must be root-owned."
  redis_mode="$(stat -c '%a' "$REDIS_PASSWORD_FILE")"
  [[ "$redis_mode" == "400" || "$redis_mode" == "600" ]] || die "Redis password file must have mode 0400 or 0600."
  export REDISCLI_AUTH
  REDISCLI_AUTH="$(<"$REDIS_PASSWORD_FILE")"
fi

check_database() {
  local listing db required found
  listing="$(mariadb "${MARIADB_ARGS[@]}" --user=root --batch --skip-column-names --execute='SHOW DATABASES;')" || die "Cannot query MariaDB with local root/socket authentication."
  DATABASES=()
  while IFS= read -r db; do
    [[ -n "$db" ]] || continue
    case "$db" in information_schema|performance_schema) continue ;; esac
    DATABASES+=("$db")
  done <<< "$listing"
  (("${#DATABASES[@]}" > 0)) || die "No restorable MariaDB databases found."
  for required in panel paymenter; do
    found=0
    for db in "${DATABASES[@]}"; do [[ "$db" == "$required" ]] && found=1; done
    [[ "$found" == "1" ]] || die "Expected FragCity database '$required' was not found."
  done
}
check_redis() {
  local response
  response="$(redis-cli "${REDIS_CLI_ARGS[@]}" PING 2>&1)" || die "Redis PING failed: $response"
  [[ "$response" == "PONG" ]] || die "Unexpected Redis PING response: $response"
}
check_paths() {
  local path
  for path in "${BACKUP_PATHS[@]}" "${EXTRA_BACKUP_PATHS[@]}"; do
    [[ -e "/$path" || -L "/$path" ]] || die "Backup source does not exist: /$path"
  done
  [[ -d "$REPO_ROOT/.git" ]] || die "Repository metadata is missing."
}
check_paths
check_database
check_redis
available_mb="$(df -Pm "$BACKUP_ROOT" | awk 'NR==2 {print $4}')"
[[ "$available_mb" =~ ^[0-9]+$ ]] || die "Cannot determine free space at destination."
((available_mb >= MIN_FREE_SPACE_MB)) || die "Insufficient destination space."
if [[ "$MODE" == "--dry-run" ]]; then
  log "DRY RUN PASSED: MariaDB databases, Redis PONG, configured paths and storage check."
  log "No backup files were created."
  exit 0
fi


exec 8>/run/lock/fragcity-backuper.lock
flock -n 8 || die "Another backup run is active."
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
STAGE="$BACKUP_ROOT/.incomplete-$STAMP-$$"
ARCHIVE_NAME="fragcity-platform-$STAMP.tar.gz"
[[ "$BACKUP_ENCRYPTION" == "1" ]] && ARCHIVE_NAME+=".gpg"
ARCHIVE_TMP="$BACKUP_ROOT/.tmp-$ARCHIVE_NAME"
PLAIN_TMP="$BACKUP_ROOT/.tmp-plain-$STAMP.tar.gz"
cleanup() {
  [[ ! -d "$STAGE" ]] || rm -rf -- "$STAGE"
  [[ ! -e "$ARCHIVE_TMP" ]] || rm -f -- "$ARCHIVE_TMP"
  [[ ! -e "$PLAIN_TMP" ]] || rm -f -- "$PLAIN_TMP"
}
trap cleanup EXIT
install -d -o root -g root -m 0700 "$STAGE/databases" "$STAGE/files" "$STAGE/metadata"
log "Starting backup."

DB_ERROR="$STAGE/metadata/mariadb-dump.stderr.log"
if mariadb-dump "${MARIADB_ARGS[@]}" --user=root --databases "${DATABASES[@]}" \
    --single-transaction --routines --events --triggers --hex-blob --quick \
    --default-character-set=utf8mb4 2>"$DB_ERROR" | gzip -1 > "$STAGE/databases/mariadb-all.sql.gz"; then
  [[ -s "$STAGE/databases/mariadb-all.sql.gz" ]] || die "MariaDB dump is empty."
  gzip -t "$STAGE/databases/mariadb-all.sql.gz" || die "MariaDB dump gzip validation failed."
else
  cat "$DB_ERROR" >&2 || true
  die "MariaDB logical dump failed."
fi
[[ -s "$DB_ERROR" ]] || rm -f "$DB_ERROR"
printf '%s\n' "${DATABASES[@]}" > "$STAGE/metadata/mariadb-databases.txt"
log "MariaDB dump completed."

if ! redis-cli "${REDIS_CLI_ARGS[@]}" --rdb "$STAGE/databases/redis.rdb" >/dev/null 2>"$STAGE/metadata/redis-rdb.stderr.log"; then
  cat "$STAGE/metadata/redis-rdb.stderr.log" >&2 || true
  die "Redis RDB export failed."
fi
[[ -s "$STAGE/databases/redis.rdb" ]] || die "Redis RDB export is empty."
if command -v redis-check-rdb >/dev/null 2>&1; then
  redis-check-rdb "$STAGE/databases/redis.rdb" > "$STAGE/metadata/redis-check-rdb.log" 2>&1 || die "Redis RDB validation failed."
fi
log "Redis snapshot completed."

# The existing publisher takes this lock exclusively while fast-forwarding the repo.
GIT_LOCK="$REPO_ROOT/.git/fragcity-payload-stage.lock"
[[ ! -L "$GIT_LOCK" ]] || die "Provisioner Git lock path is a symlink."
touch "$GIT_LOCK"
exec 9>"$GIT_LOCK"
flock -s 9
TAR_PATHS=("${BACKUP_PATHS[@]}" "${EXTRA_BACKUP_PATHS[@]}")
for path in "${TAR_PATHS[@]}"; do [[ -e "/$path" || -L "/$path" ]] || die "Backup path disappeared: /$path"; done
TAR_EXCLUDES=(
  --exclude='*/storage/logs/*'
  --exclude='*/storage/framework/cache/*'
  --exclude='*/storage/framework/sessions/*'
  --exclude='*/storage/framework/views/*'
  --exclude='*/bootstrap/cache/*'
  --exclude='*/node_modules/*'
)
# Never put credential files configured above into the archive, even if an
# administrator later adds /root or another secret directory to the include list.
for secret_path in "$REDIS_PASSWORD_FILE" "$GPG_PASSPHRASE_FILE"; do
  if [[ -n "$secret_path" ]]; then
    secret_relative="${secret_path#/}"
    TAR_EXCLUDES+=(--exclude="$secret_relative")
  fi
done
tar --create --gzip --file="$STAGE/files/platform-files.tar.gz" \
  --numeric-owner --acls --xattrs --one-file-system \
  "${TAR_EXCLUDES[@]}" \
  --directory=/ -- "${TAR_PATHS[@]}" || die "Platform file archive failed."
GIT_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
flock -u 9
exec 9>&-
tar -tzf "$STAGE/files/platform-files.tar.gz" >/dev/null || die "Platform archive failed tar validation."
log "Platform files archived."
{
  printf 'FragCity Platform Backup\ncreated_utc=%s\n' "$STAMP"
  printf 'hostname=%s\n' "$(hostname -f 2>/dev/null || hostname)"
  printf 'kernel=%s\n' "$(uname -r)"
  printf 'repository_branch=integration/kus-monorepo\nrepository_commit=%s\n' "$GIT_COMMIT"
  printf 'mariadb_version=%s\n' "$(mariadb --version)"
  printf 'redis_version=%s\n' "$(redis-cli --version)"
  printf 'backup_root=%s\nretention_days=%s\nencryption=%s\n' "$BACKUP_ROOT" "$RETENTION_DAYS" "$BACKUP_ENCRYPTION"
  printf '\nIncluded databases:\n%s\n' "${DATABASES[*]}"
  printf '\nIncluded file paths:\n'
  printf '  /%s\n' "${TAR_PATHS[@]}"
  printf '\nExcluded:\n  /srv\n  /var/lib/pterodactyl/volumes\n  /var/lib/docker\n'
} > "$STAGE/metadata/manifest.txt"
(
  cd "$STAGE"
  sha256sum databases/mariadb-all.sql.gz databases/redis.rdb files/platform-files.tar.gz > metadata/SHA256SUMS
)
tar -czf "$PLAIN_TMP" -C "$STAGE" metadata databases files
gzip -t "$PLAIN_TMP" || die "Final package gzip check failed."
if [[ "$BACKUP_ENCRYPTION" == "1" ]]; then
  gpg --batch --yes --quiet --no-symkey-cache --pinentry-mode loopback \
    --passphrase-file "$GPG_PASSPHRASE_FILE" --symmetric --cipher-algo AES256 \
    --output "$ARCHIVE_TMP" "$PLAIN_TMP" || die "GPG encryption failed."
  rm -f -- "$PLAIN_TMP"
else
  mv -- "$PLAIN_TMP" "$ARCHIVE_TMP"
fi
verify_archive_core "$ARCHIVE_TMP"
FINAL="$BACKUP_ROOT/$ARCHIVE_NAME"
[[ ! -e "$FINAL" && ! -e "$FINAL.sha256" ]] || die "Refusing to overwrite a timestamped backup."
mv -- "$ARCHIVE_TMP" "$FINAL"
HASH="$(sha256sum "$FINAL" | awk '{print $1}')"
printf '%s  %s\n' "$HASH" "$ARCHIVE_NAME" > "$FINAL.sha256.tmp"
chmod 0600 "$FINAL" "$FINAL.sha256.tmp"
mv -- "$FINAL.sha256.tmp" "$FINAL.sha256"

find "$BACKUP_ROOT" -maxdepth 1 -type f \
  \( -name 'fragcity-platform-*.tar.gz' -o -name 'fragcity-platform-*.tar.gz.gpg' \
     -o -name 'fragcity-platform-*.tar.gz.sha256' -o -name 'fragcity-platform-*.tar.gz.gpg.sha256' \) \
  -mtime "+$RETENTION_DAYS" -delete
ROOT_SOURCE="$(findmnt -n -o SOURCE -T / 2>/dev/null || true)"
DEST_SOURCE="$(findmnt -n -o SOURCE -T "$BACKUP_ROOT" 2>/dev/null || true)"
if [[ -n "$ROOT_SOURCE" && "$ROOT_SOURCE" == "$DEST_SOURCE" ]]; then
  log "WARNING: destination is on the same filesystem as /. Mount independent storage at $BACKUP_ROOT for off-VM safety."
fi
log "SUCCESS: $FINAL"
log "SHA256: $HASH"
