#!/usr/bin/env bash
set -Eeuo pipefail

# Logical PostgreSQL backup for database major-version migrations.
# Usage: backup-postgres-to-google-drive.sh immich|n8n
SERVICE="${1:-}"
NAMESPACE="homelab"
RETENTION_DAYS=14

case "$SERVICE" in
  immich)
    APP_LABEL="immich-postgres"
    DATABASE="immich"
    USERNAME="immich"
    DEST_ROOT="/mnt/d/Google Drive/Backups/Immich"
    ;;
  n8n)
    APP_LABEL="n8n-db"
    DATABASE="n8n"
    USERNAME="n8n"
    DEST_ROOT="/mnt/d/Google Drive/Backups/n8n"
    ;;
  *)
    echo "Uso: $0 immich|n8n" >&2
    exit 2
    ;;
esac

LOCK_FILE="/tmp/backup-$SERVICE-postgres-google-drive.lock"
PARTIAL=""
REMOTE_PREFIX=""
umask 077
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

cleanup() {
  [[ -z "$PARTIAL" ]] || rm -f -- "$PARTIAL"
  if [[ -n "$REMOTE_PREFIX" && -n "${db_pod:-}" ]]; then
    kubectl -n "$NAMESPACE" exec "$db_pod" -- sh -c "rm -f -- $REMOTE_PREFIX $REMOTE_PREFIX.part-*" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mountpoint -q /mnt/d || { echo "ERRO: /mnt/d nao esta montado." >&2; exit 1; }
for command in kubectl sha256sum; do
  command -v "$command" >/dev/null || { echo "ERRO: comando ausente: $command" >&2; exit 1; }
done

mkdir -p -- "$DEST_ROOT"
db_pod="$(kubectl -n "$NAMESPACE" get pod -l "app=$APP_LABEL" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$db_pod" ]] || { echo "ERRO: pod de banco do $SERVICE nao encontrado." >&2; exit 1; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$DEST_ROOT/$SERVICE-postgres-$stamp.dump"
PARTIAL="$archive.partial"
checksum="$archive.sha256"
metadata="$DEST_ROOT/$SERVICE-postgres-$stamp.txt"

echo "Exportando PostgreSQL do $SERVICE..."
REMOTE_PREFIX="/tmp/$SERVICE-postgres-$stamp.dump"
kubectl -n "$NAMESPACE" exec "$db_pod" -- pg_dump --username="$USERNAME" --dbname="$DATABASE" --format=custom --compress=9 --no-password --file="$REMOTE_PREFIX"
kubectl -n "$NAMESPACE" exec "$db_pod" -- pg_restore --list "$REMOTE_PREFIX" >/dev/null
kubectl -n "$NAMESPACE" exec "$db_pod" -- split -b 32m "$REMOTE_PREFIX" "$REMOTE_PREFIX.part-"

: > "$PARTIAL"
while IFS= read -r part; do
  [[ -n "$part" ]] || continue
  echo "Copiando $(basename "$part")..."
  kubectl -n "$NAMESPACE" exec "$db_pod" -- cat "$part" >> "$PARTIAL"
done < <(kubectl -n "$NAMESPACE" exec "$db_pod" -- sh -c "ls -1 $REMOTE_PREFIX.part-*")

[[ -s "$PARTIAL" ]] || { echo "ERRO: dump vazio." >&2; exit 1; }
remote_size="$(kubectl -n "$NAMESPACE" exec "$db_pod" -- stat -c %s "$REMOTE_PREFIX" | tr -d '\r')"
local_size="$(stat -c %s "$PARTIAL")"
[[ "$local_size" == "$remote_size" ]] || { echo "ERRO: dump copiado parcialmente." >&2; exit 1; }
mv -- "$PARTIAL" "$archive"
PARTIAL=""
kubectl -n "$NAMESPACE" exec "$db_pod" -- sh -c "rm -f -- $REMOTE_PREFIX $REMOTE_PREFIX.part-*"
REMOTE_PREFIX=""
sha256sum "$archive" > "$checksum"

{
  echo "timestamp_utc=$stamp"
  echo "service=$SERVICE"
  echo "namespace=$NAMESPACE"
  echo "database=$DATABASE"
  echo "database_pod=$db_pod"
  echo "format=pg_dump-custom"
  echo "archive=$(basename "$archive")"
  kubectl -n "$NAMESPACE" exec "$db_pod" -- psql     --username="$USERNAME" --dbname="$DATABASE" --tuples-only --no-align     --command="select version();"
} > "$metadata"

find "$DEST_ROOT" -maxdepth 1 -type f -name '*.dump' -mtime +"$RETENTION_DAYS" -delete
find "$DEST_ROOT" -maxdepth 1 -type f -name '*.dump.sha256' -mtime +"$RETENTION_DAYS" -delete
find "$DEST_ROOT" -maxdepth 1 -type f -name '*.txt' -mtime +"$RETENTION_DAYS" -delete

echo "Backup do $SERVICE concluido: $archive"
du -h "$archive"
