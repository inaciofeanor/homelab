#!/usr/bin/env bash
set -Eeuo pipefail

# Backup diário do banco e dos PVCs auxiliares do RomM para o Google Drive
# montado pelo WSL. A biblioteca /romm/library não é incluída.
DEST_ROOT="/mnt/d/Google Drive/Backups/RomM"
NAMESPACE="homelab"
DATABASE_NAME="romm"
RETENTION_DAYS=14
LOCK_FILE="/tmp/backup-romm-google-drive.lock"
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

db_pod="$(kubectl -n "$NAMESPACE" get pod -l app=romm-db \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
romm_pod="$(kubectl -n "$NAMESPACE" get pod -l app=romm \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"

[[ -n "$db_pod" ]] || { echo "ERRO: pod do MariaDB do RomM não encontrado." >&2; exit 1; }
[[ -n "$romm_pod" ]] || { echo "ERRO: pod do RomM não encontrado." >&2; exit 1; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$DEST_ROOT/romm-$stamp.tar.gz"
partial="$archive.partial"
checksum="$archive.sha256"
metadata="$DEST_ROOT/romm-$stamp.txt"
PARTIALS+=("$partial")
STAGING_DIR="$(mktemp -d /tmp/romm-backup.XXXXXX)"

echo "Exportando MariaDB do RomM..."
kubectl -n "$NAMESPACE" exec "$db_pod" -- sh -ec '
  exec mariadb-dump \
    --user="$MARIADB_USER" \
    --password="$MARIADB_PASSWORD" \
    --single-transaction \
    --quick \
    --skip-lock-tables \
    --routines \
    --events \
    --triggers \
    "$MARIADB_DATABASE"
' > "$STAGING_DIR/romm.sql"

[[ -s "$STAGING_DIR/romm.sql" ]] || { echo "ERRO: dump do MariaDB vazio." >&2; exit 1; }
grep -q '^-- MariaDB dump' "$STAGING_DIR/romm.sql" \
  || { echo "ERRO: dump do MariaDB não parece válido." >&2; exit 1; }

echo "Arquivando resources, assets e config..."
kubectl -n "$NAMESPACE" exec "$romm_pod" -- \
  tar -C /romm -czf - resources assets config > "$STAGING_DIR/romm-files.tar.gz"
tar -tzf "$STAGING_DIR/romm-files.tar.gz" >/dev/null

tar -C "$STAGING_DIR" -czf "$partial" romm.sql romm-files.tar.gz
tar -tzf "$partial" >/dev/null
mv -- "$partial" "$archive"
sha256sum "$archive" > "$checksum"

{
  echo "timestamp_utc=$stamp"
  echo "service=RomM"
  echo "namespace=$NAMESPACE"
  echo "database_pod=$db_pod"
  echo "application_pod=$romm_pod"
  echo "database=mariadb/$DATABASE_NAME"
  echo "sources=/romm/resources,/romm/assets,/romm/config"
  echo "library_included=false"
  echo "archive=$(basename "$archive")"
  kubectl -n "$NAMESPACE" get pvc \
    romm-db-data romm-resources romm-assets romm-config -o wide
} > "$metadata"

find "$DEST_ROOT" -maxdepth 1 -type f -name '*.tar.gz' \
  -mtime +"$RETENTION_DAYS" -delete
find "$DEST_ROOT" -maxdepth 1 -type f -name '*.tar.gz.sha256' \
  -mtime +"$RETENTION_DAYS" -delete
find "$DEST_ROOT" -maxdepth 1 -type f -name '*.txt' \
  -mtime +"$RETENTION_DAYS" -delete

echo "Backup do RomM concluído: $archive"
du -h "$archive"
