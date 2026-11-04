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
DATA_PARTIAL=""
DATA_REMOTE_PREFIX=""
umask 077
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

cleanup() {
  [[ -z "$PARTIAL" ]] || rm -f -- "$PARTIAL"
  [[ -z "$DATA_PARTIAL" ]] || rm -f -- "$DATA_PARTIAL"
  if [[ -n "$REMOTE_PREFIX" && -n "${db_pod:-}" ]]; then
    kubectl -n "$NAMESPACE" exec "$db_pod" -- sh -c "rm -f -- $REMOTE_PREFIX $REMOTE_PREFIX.part-*" >/dev/null 2>&1 || true
  fi
  if [[ -n "$DATA_REMOTE_PREFIX" && -n "${app_pod:-}" ]]; then
    kubectl -n "$NAMESPACE" exec "$app_pod" -c n8n -- sh -c "rm -f -- $DATA_REMOTE_PREFIX $DATA_REMOTE_PREFIX.part-*" >/dev/null 2>&1 || true
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

if [[ "$SERVICE" == "n8n" ]]; then
  app_pod="$(kubectl -n "$NAMESPACE" get pod -l app=n8n --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
  [[ -n "$app_pod" ]] || { echo "ERRO: pod do n8n nao encontrado para copiar o PVC." >&2; exit 1; }

  data_archive="$DEST_ROOT/n8n-data-$stamp.tar.gz"
  DATA_PARTIAL="$data_archive.partial"
  DATA_REMOTE_PREFIX="/tmp/n8n-data-$stamp.tar.gz"
  echo "Arquivando o PVC n8n-data..."
  kubectl -n "$NAMESPACE" exec "$app_pod" -c n8n -- tar -C /home/node -czf "$DATA_REMOTE_PREFIX" .n8n
  kubectl -n "$NAMESPACE" exec "$app_pod" -c n8n -- split -b 32m "$DATA_REMOTE_PREFIX" "$DATA_REMOTE_PREFIX.part-"

  : > "$DATA_PARTIAL"
  while IFS= read -r part; do
    [[ -n "$part" ]] || continue
    kubectl -n "$NAMESPACE" exec "$app_pod" -c n8n -- cat "$part" >> "$DATA_PARTIAL"
  done < <(kubectl -n "$NAMESPACE" exec "$app_pod" -c n8n -- sh -c "ls -1 $DATA_REMOTE_PREFIX.part-*")

  [[ -s "$DATA_PARTIAL" ]] || { echo "ERRO: arquivo do PVC vazio." >&2; exit 1; }
  remote_size="$(kubectl -n "$NAMESPACE" exec "$app_pod" -c n8n -- stat -c %s "$DATA_REMOTE_PREFIX" | tr -d '\r')"
  local_size="$(stat -c %s "$DATA_PARTIAL")"
  [[ "$local_size" == "$remote_size" ]] || { echo "ERRO: PVC copiado parcialmente." >&2; exit 1; }
  tar -tzf "$DATA_PARTIAL" >/dev/null
  mv -- "$DATA_PARTIAL" "$data_archive"
  DATA_PARTIAL=""
  kubectl -n "$NAMESPACE" exec "$app_pod" -c n8n -- sh -c "rm -f -- $DATA_REMOTE_PREFIX $DATA_REMOTE_PREFIX.part-*"
  DATA_REMOTE_PREFIX=""
  sha256sum "$data_archive" > "$data_archive.sha256"
  {
    echo "data_pod=$app_pod"
    echo "data_archive=$(basename "$data_archive")"
    echo "data_source=/home/node/.n8n (PVC n8n-data)"
  } >> "$metadata"
  find "$DEST_ROOT" -maxdepth 1 -type f -name 'n8n-data-*.tar.gz' -mtime +"$RETENTION_DAYS" -delete
  find "$DEST_ROOT" -maxdepth 1 -type f -name 'n8n-data-*.tar.gz.sha256' -mtime +"$RETENTION_DAYS" -delete
fi

find "$DEST_ROOT" -maxdepth 1 -type f -name '*.dump' -mtime +"$RETENTION_DAYS" -delete
find "$DEST_ROOT" -maxdepth 1 -type f -name '*.dump.sha256' -mtime +"$RETENTION_DAYS" -delete
find "$DEST_ROOT" -maxdepth 1 -type f -name '*.txt' -mtime +"$RETENTION_DAYS" -delete

echo "Backup do $SERVICE concluido: $archive"
du -h "$archive"
if [[ "$SERVICE" == "n8n" ]]; then
  echo "PVC n8n-data: $data_archive"
  du -h "$data_archive"
fi
