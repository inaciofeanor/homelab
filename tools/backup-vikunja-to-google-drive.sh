#!/usr/bin/env bash
set -Eeuo pipefail

# Backup diário nativo do Vikunja para o Google Drive montado pelo WSL.
# O comando `vikunja dump` inclui banco de dados, configuração e anexos.
DEST_ROOT="/mnt/d/Google Drive/Backups/Vikunja"
NAMESPACE="homelab"
RETENTION_DAYS=14
LOCK_FILE="/tmp/backup-vikunja-google-drive.lock"
PARTIALS=()
HELPER_POD=""
DUMP_NAME=""

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
  if [[ -n "$HELPER_POD" ]]; then
    if [[ -n "$DUMP_NAME" ]]; then
      kubectl -n "$NAMESPACE" exec "$HELPER_POD" -- \
        rm -f -- "/backup/$DUMP_NAME" >/dev/null 2>&1 || true
    fi
    kubectl -n "$NAMESPACE" delete pod "$HELPER_POD" \
      --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p -- "$DEST_ROOT"

vikunja_pod="$(kubectl -n "$NAMESPACE" get pod -l app=vikunja \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$vikunja_pod" ]] \
  || { echo "ERRO: pod do Vikunja não encontrado." >&2; exit 1; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$DEST_ROOT/vikunja-$stamp.zip"
partial="$archive.partial"
checksum="$archive.sha256"
metadata="$DEST_ROOT/vikunja-$stamp.txt"
DUMP_NAME=".vikunja-backup-$stamp.zip"
HELPER_POD="vikunja-backup-${stamp,,}"
PARTIALS+=("$partial")

echo "Gerando dump nativo do Vikunja..."
kubectl -n "$NAMESPACE" exec "$vikunja_pod" -- \
  /app/vikunja/vikunja dump \
  --path /app/vikunja/files \
  --filename "$DUMP_NAME"

cat <<EOF | kubectl -n "$NAMESPACE" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $HELPER_POD
  labels:
    app: vikunja-backup-helper
spec:
  restartPolicy: Never
  containers:
    - name: helper
      image: busybox:1.36
      command: ["sleep", "900"]
      volumeMounts:
        - name: files
          mountPath: /backup
  volumes:
    - name: files
      persistentVolumeClaim:
        claimName: vikunja-files
EOF

kubectl -n "$NAMESPACE" wait --for=condition=Ready \
  "pod/$HELPER_POD" --timeout=180s >/dev/null
kubectl -n "$NAMESPACE" exec "$HELPER_POD" -- \
  cat "/backup/$DUMP_NAME" > "$partial"

[[ -s "$partial" ]] || { echo "ERRO: dump do Vikunja vazio." >&2; exit 1; }
python3 -m zipfile -t "$partial" >/dev/null
mv -- "$partial" "$archive"
sha256sum "$archive" > "$checksum"

{
  echo "timestamp_utc=$stamp"
  echo "service=Vikunja"
  echo "namespace=$NAMESPACE"
  echo "application_pod=$vikunja_pod"
  echo "method=vikunja dump"
  echo "includes=database,config,files"
  echo "archive=$(basename "$archive")"
  kubectl -n "$NAMESPACE" get pvc vikunja-db-data vikunja-files -o wide
} > "$metadata"

find "$DEST_ROOT" -maxdepth 1 -type f -name '*.zip' \
  -mtime +"$RETENTION_DAYS" -delete
find "$DEST_ROOT" -maxdepth 1 -type f -name '*.zip.sha256' \
  -mtime +"$RETENTION_DAYS" -delete
find "$DEST_ROOT" -maxdepth 1 -type f -name '*.txt' \
  -mtime +"$RETENTION_DAYS" -delete

echo "Backup do Vikunja concluído: $archive"
du -h "$archive"
