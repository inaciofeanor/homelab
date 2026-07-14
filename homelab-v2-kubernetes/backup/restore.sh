#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
RESTORE_HOSTPATHS=false
FORCE=false
K3S_STOPPED=false

usage() {
  cat <<'EOF'
Uso: sudo ./restore.sh [--restore-hostpaths] [--force] DIRETORIO_DO_BACKUP

Pré-requisitos: k3s novo e ativo; manifests ajustados para o novo computador.
Por segurança, dados existentes só são sobrescritos com --force.
EOF
}

log() { printf '[restore] %s\n' "$*"; }
die() { printf '[restore] ERRO: %s\n' "$*" >&2; exit 1; }

cleanup() {
  local status=$?
  if $K3S_STOPPED; then
    log "Reiniciando k3s..."
    systemctl start k3s || true
    K3S_STOPPED=false
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

BACKUP_DIR=""
while (($#)); do
  case "$1" in
    --restore-hostpaths) RESTORE_HOSTPATHS=true ;;
    --force) FORCE=true ;;
    -h|--help) usage; exit 0 ;;
    -*) die "Opção desconhecida: $1" ;;
    *) [[ -z "$BACKUP_DIR" ]] || die "Informe apenas um backup"; BACKUP_DIR="$1" ;;
  esac
  shift
done

[[ -n "$BACKUP_DIR" ]] || { usage; exit 2; }
(( EUID == 0 )) || die "Execute com sudo"
for command in kubectl systemctl tar sha256sum; do
  command -v "$command" >/dev/null || die "Comando obrigatório ausente: $command"
done
BACKUP_DIR="$(cd -- "$BACKUP_DIR" && pwd)"
[[ -f "$BACKUP_DIR/metadata.txt" && -f "$BACKUP_DIR/SHA256SUMS" && -f "$BACKUP_DIR/pvcs.tsv" ]] \
  || die "Diretório não parece ser um backup compatível"

log "Validando integridade..."
(cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS)
systemctl is-active --quiet k3s || die "O serviço k3s não está ativo"

log "Aplicando manifests para criar namespaces e PVCs..."
kubectl apply -k "$MANIFEST_DIR"
timeout 180 sh -c 'until ! kubectl get pvc -A --no-headers 2>/dev/null | grep -qv " Bound "; do sleep 3; done' \
  || die "Nem todos os PVCs ficaram Bound. Corrija o cluster e tente novamente"

NEW_MAP="$(mktemp)"
trap 'rm -f "$NEW_MAP"; cleanup' EXIT INT TERM
kubectl get pv -o jsonpath='{range .items[?(@.spec.local.path)]}{.spec.claimRef.namespace}{"\t"}{.spec.claimRef.name}{"\t"}{.spec.local.path}{"\n"}{end}' \
  | sort > "$NEW_MAP"

log "Parando k3s para restaurar os PVCs..."
systemctl stop k3s
K3S_STOPPED=true

while IFS=$'\t' read -r namespace claim old_source; do
  [[ -n "$namespace" && -n "$claim" ]] || continue
  target="$(awk -F '\t' -v ns="$namespace" -v pvc="$claim" '$1 == ns && $2 == pvc { print $3; exit }' "$NEW_MAP")"
  archive="$BACKUP_DIR/pvcs/${namespace}__${claim}.tar.gz"
  if [[ -z "$target" ]]; then
    log "AVISO: PVC $namespace/$claim não existe no cluster novo; ignorado"
    continue
  fi
  [[ -f "$archive" ]] || die "Arquivo ausente para $namespace/$claim"
  mkdir -p "$target"
  if [[ -n "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ]] && ! $FORCE; then
    die "Destino do PVC $namespace/$claim não está vazio; use --force somente após conferir"
  fi
  if $FORCE; then
    find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  fi
  log "PVC $namespace/$claim"
  tar --numeric-owner -xzf "$archive" -C "$target"
done < "$BACKUP_DIR/pvcs.tsv"

if $RESTORE_HOSTPATHS; then
  [[ -f "$BACKUP_DIR/hostpaths.tsv" ]] || die "Este backup não contém hostPaths"
  while IFS=$'\t' read -r target archive; do
    [[ -n "$target" && -n "$archive" ]] || continue
    mkdir -p "$target"
    if [[ -n "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ]] && ! $FORCE; then
      die "hostPath $target não está vazio; use --force somente após conferir"
    fi
    if $FORCE; then
      find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    fi
    log "hostPath $target"
    tar --numeric-owner -xzf "$BACKUP_DIR/hostpaths/$archive" -C "$target"
  done < "$BACKUP_DIR/hostpaths.tsv"
fi

log "Reiniciando k3s..."
systemctl start k3s
K3S_STOPPED=false
timeout 180 sh -c 'until kubectl get nodes >/dev/null 2>&1; do sleep 2; done' \
  || die "k3s não respondeu após reiniciar"
kubectl get pods -A
log "Restauração concluída. Verifique todos os serviços antes de apagar o backup."

