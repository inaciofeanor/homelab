#!/usr/bin/env bash
set -Eeuo pipefail

# Backup do PVC do Memos para o Google Drive montado pelo WSL.
DEST="/mnt/d/Google Drive/Backups/Memos"
NAMESPACE="homelab"
LABEL="app=memos"
RETENTION_DAYS=14
LOCK_FILE="/tmp/backup-memos-google-drive.lock"

umask 077
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0
mkdir -p "$DEST"

if ! mountpoint -q "/mnt/d"; then
  echo "ERRO: /mnt/d não está montado." >&2
  exit 1
fi

pod="$(kubectl -n "$NAMESPACE" get pod -l "$LABEL" -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "$pod" ]]; then
  echo "ERRO: nenhum pod do Memos está disponível." >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$DEST/memos-$stamp.tar.gz"
partial="$archive.partial"
checksum="$archive.sha256"
metadata="$DEST/memos-$stamp.txt"

cleanup() {
  rm -f "$partial"
}
trap cleanup EXIT

kubectl -n "$NAMESPACE" exec "$pod" --   tar -C /var/opt -czf - memos > "$partial"

tar -tzf "$partial" >/dev/null
mv "$partial" "$archive"
sha256sum "$archive" > "$checksum"

{
  echo "timestamp_utc=$stamp"
  echo "namespace=$NAMESPACE"
  echo "pod=$pod"
  echo "source=/var/opt/memos"
  echo "archive=$(basename "$archive")"
  kubectl -n "$NAMESPACE" get pvc memos-data -o wide
} > "$metadata"

find "$DEST" -maxdepth 1 -type f -name 'memos-*.tar.gz' -mtime +"$RETENTION_DAYS" -delete
find "$DEST" -maxdepth 1 -type f -name 'memos-*.tar.gz.sha256' -mtime +"$RETENTION_DAYS" -delete
find "$DEST" -maxdepth 1 -type f -name 'memos-*.txt' -mtime +"$RETENTION_DAYS" -delete

echo "Backup do Memos concluído: $archive"
