#!/usr/bin/env bash
set -Eeuo pipefail

# Backup dos PVCs do Memos e do Actual Budget para o Google Drive montado pelo WSL.
DEST_ROOT="/mnt/d/Google Drive/Backups"
NAMESPACE="homelab"
RETENTION_DAYS=14
LOCK_FILE="/tmp/backup-memos-actual-google-drive.lock"
PARTIALS=()

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
    rm -f "$partial"
  done
}
trap cleanup EXIT

backup_service() {
  local service="$1"
  local label="$2"
  local destination="$3"
  local tar_root="$4"
  local tar_source="$5"
  local pvc="$6"
  local dest="$DEST_ROOT/$destination"
  local pod stamp archive partial checksum metadata

  mkdir -p "$dest"
  pod="$(kubectl -n "$NAMESPACE" get pod -l "$label" -o jsonpath='{.items[0].metadata.name}')"
  if [[ -z "$pod" ]]; then
    echo "ERRO: nenhum pod de $service está disponível." >&2
    return 1
  fi

  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  archive="$dest/${destination,,}-$stamp.tar.gz"
  partial="$archive.partial"
  checksum="$archive.sha256"
  metadata="$dest/${destination,,}-$stamp.txt"
  PARTIALS+=("$partial")

  kubectl -n "$NAMESPACE" exec "$pod" --     tar -C "$tar_root" -czf - "$tar_source" > "$partial"

  tar -tzf "$partial" >/dev/null
  mv "$partial" "$archive"
  sha256sum "$archive" > "$checksum"

  {
    echo "timestamp_utc=$stamp"
    echo "service=$service"
    echo "namespace=$NAMESPACE"
    echo "pod=$pod"
    echo "source=$tar_root/$tar_source"
    echo "archive=$(basename "$archive")"
    kubectl -n "$NAMESPACE" get pvc "$pvc" -o wide
  } > "$metadata"

  find "$dest" -maxdepth 1 -type f -name '*.tar.gz' -mtime +"$RETENTION_DAYS" -delete
  find "$dest" -maxdepth 1 -type f -name '*.tar.gz.sha256' -mtime +"$RETENTION_DAYS" -delete
  find "$dest" -maxdepth 1 -type f -name '*.txt' -mtime +"$RETENTION_DAYS" -delete

  echo "Backup de $service concluído: $archive"
}

backup_service "Memos" "app=memos" "Memos" "/var/opt" "memos" "memos-data"
backup_service "Actual Budget" "app=actual-budget" "Actual-Budget" "/data" "." "actual-budget-data"
