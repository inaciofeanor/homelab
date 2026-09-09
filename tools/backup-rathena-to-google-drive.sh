#!/usr/bin/env bash
set -Eeuo pipefail

# Dump diário consistente do MariaDB usado pelo rAthena e pelo FluxCP.
DEST_ROOT="/mnt/d/Google Drive/Backups/rAthena"
NAMESPACE="homelab"
RETENTION_DAYS=14
LOCK_FILE="/tmp/backup-rathena-google-drive.lock"
PARTIALS=()
STAGING_DIR=""

umask 077
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

if ! mountpoint -q "/mnt/d"; then
  echo "ERRO: /mnt/d não está montado." >&2
  exit 1
fi

cleanup() {
  local partial
  for partial in "${PARTIALS[@]}"; do
    rm -f -- "$partial"
  done
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    rm -rf -- "$STAGING_DIR"
  fi
}
trap cleanup EXIT

mkdir -p -- "$DEST_ROOT"
db_pod="$(kubectl -n "$NAMESPACE" get pod -l app=rathena-db --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$db_pod" ]] || { echo "ERRO: pod do MariaDB do rAthena não encontrado." >&2; exit 1; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$DEST_ROOT/rathena-$stamp.sql.gz"
partial="$archive.partial"
checksum="$archive.sha256"
metadata="$DEST_ROOT/rathena-$stamp.txt"
PARTIALS+=("$partial")
STAGING_DIR="$(mktemp -d /tmp/rathena-backup.XXXXXX)"

echo "Exportando MariaDB do rAthena..."
kubectl -n "$NAMESPACE" exec "$db_pod" -- sh -ec '
  exec mariadb-dump --user="$MARIADB_USER" --password="$MARIADB_PASSWORD" \
    --single-transaction --quick --skip-lock-tables --routines --events --triggers \
    "$MARIADB_DATABASE"
' > "$STAGING_DIR/rathena.sql"

[[ -s "$STAGING_DIR/rathena.sql" ]] || { echo "ERRO: dump do MariaDB vazio." >&2; exit 1; }
grep -q '^-- MariaDB dump' "$STAGING_DIR/rathena.sql" || { echo "ERRO: dump inválido." >&2; exit 1; }

gzip -9c "$STAGING_DIR/rathena.sql" > "$partial"
gzip -t "$partial"
mv -- "$partial" "$archive"
sha256sum "$archive" > "$checksum"

{
  echo "timestamp_utc=$stamp"
  echo "service=rAthena/FluxCP"
  echo "namespace=$NAMESPACE"
  echo "database_pod=$db_pod"
  echo "database=mariadb/ragnarok"
  echo "packetver=20211103"
  echo "archive=$(basename "$archive")"
  kubectl -n "$NAMESPACE" get pvc rathena-db-data -o wide
} > "$metadata"

find "$DEST_ROOT" -maxdepth 1 -type f -name '*.sql.gz' -mtime +"$RETENTION_DAYS" -delete
find "$DEST_ROOT" -maxdepth 1 -type f -name '*.sql.gz.sha256' -mtime +"$RETENTION_DAYS" -delete
find "$DEST_ROOT" -maxdepth 1 -type f -name '*.txt' -mtime +"$RETENTION_DAYS" -delete

echo "Backup do rAthena concluído: $archive"
du -h "$archive"
