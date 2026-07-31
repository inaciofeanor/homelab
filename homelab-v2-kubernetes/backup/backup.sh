#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/backup.conf"
INCLUDE_HOSTPATHS=false
K3S_STOPPED=false
PARTIAL_DIR=""

usage() {
  cat <<'EOF'
Uso: sudo ./backup.sh [--include-hostpaths] DESTINO

Cria um backup frio e portátil dos PVCs local-path, metadados do cluster e
repositório. --include-hostpaths também arquiva as bibliotecas grandes.
EOF
}

log() { printf '[backup] %s\n' "$*"; }
die() { printf '[backup] ERRO: %s\n' "$*" >&2; exit 1; }

cleanup() {
  local status=$?
  if $K3S_STOPPED; then
    log "Reiniciando k3s..."
    systemctl start k3s || true
    K3S_STOPPED=false
  fi
  if (( status != 0 )) && [[ -n "$PARTIAL_DIR" ]]; then
    printf '[backup] Backup incompleto preservado em: %s\n' "$PARTIAL_DIR" >&2
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

DESTINATION=""
while (($#)); do
  case "$1" in
    --include-hostpaths) INCLUDE_HOSTPATHS=true ;;
    -h|--help) usage; exit 0 ;;
    -*) die "Opção desconhecida: $1" ;;
    *) [[ -z "$DESTINATION" ]] || die "Informe apenas um destino"; DESTINATION="$1" ;;
  esac
  shift
done

[[ -n "$DESTINATION" ]] || { usage; exit 2; }
(( EUID == 0 )) || die "Execute com sudo para ler os volumes e controlar o k3s"
for command in kubectl systemctl tar sha256sum findmnt; do
  command -v "$command" >/dev/null || die "Comando obrigatório ausente: $command"
done
systemctl is-active --quiet k3s || die "O serviço k3s não está ativo"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
else
  # Deve acompanhar os hostPath declarados nos manifests.
  HOST_PATHS=$'/mnt/dados-homelab-novo/ebooks\n/mnt/dados-jellyfin/media\n/mnt/dados-homelab-novo/music\n/mnt/dados-homelab-novo/photos\n/mnt/dados-homelab-novo/roms'
fi

mkdir -p -- "$DESTINATION"
DESTINATION="$(cd -- "$DESTINATION" && pwd)"
case "$DESTINATION/" in
  /var/lib/rancher/k3s/*) die "O destino não pode ficar dentro do diretório do k3s" ;;
esac

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_NAME="homelab-$TIMESTAMP"
PARTIAL_DIR="$DESTINATION/.$BACKUP_NAME.partial"
FINAL_DIR="$DESTINATION/$BACKUP_NAME"
[[ ! -e "$PARTIAL_DIR" && ! -e "$FINAL_DIR" ]] || die "O backup $BACKUP_NAME já existe"
mkdir -p "$PARTIAL_DIR"/{cluster,pvcs,hostpaths,repository}

log "Exportando metadados do cluster..."
kubectl version -o yaml > "$PARTIAL_DIR/cluster/kubernetes-version.yaml"
kubectl get nodes -o yaml > "$PARTIAL_DIR/cluster/nodes.yaml"
kubectl get pv -o yaml > "$PARTIAL_DIR/cluster/persistent-volumes.yaml"
kubectl get pvc -A -o yaml > "$PARTIAL_DIR/cluster/persistent-volume-claims.yaml"
kubectl get all,configmap,secret,ingress,pvc -A -o yaml > "$PARTIAL_DIR/cluster/resources.yaml"
kubectl get pv -o jsonpath='{range .items[?(@.spec.local.path)]}{.spec.claimRef.namespace}{"\t"}{.spec.claimRef.name}{"\t"}{.spec.local.path}{"\n"}{end}' \
  | sort > "$PARTIAL_DIR/pvcs.tsv"

log "Arquivando o repositório de configuração..."
tar --numeric-owner --exclude='.git' -czf "$PARTIAL_DIR/repository/homelab.tar.gz" -C "$REPO_DIR" .

cat > "$PARTIAL_DIR/metadata.txt" <<EOF
format_version=1
created_utc=$TIMESTAMP
hostname=$(hostname)
include_hostpaths=$INCLUDE_HOSTPATHS
repository_relative_path=repository/homelab.tar.gz
EOF

log "Parando k3s para obter uma cópia consistente..."
systemctl stop k3s
K3S_STOPPED=true

while IFS=$'\t' read -r namespace claim source; do
  [[ -n "$namespace" && -n "$claim" && -n "$source" ]] || continue
  [[ -d "$source" ]] || die "Diretório do PVC $namespace/$claim não encontrado: $source"
  archive="${namespace}__${claim}.tar.gz"
  log "PVC $namespace/$claim"
  tar --numeric-owner -czf "$PARTIAL_DIR/pvcs/$archive" -C "$source" .
done < "$PARTIAL_DIR/pvcs.tsv"

if $INCLUDE_HOSTPATHS; then
  : > "$PARTIAL_DIR/hostpaths.tsv"
  while IFS= read -r source; do
    [[ -n "$source" ]] || continue
    [[ -d "$source" ]] || die "hostPath não encontrado: $source"
    case "$DESTINATION/" in
      "$source"/*) die "O destino está dentro do hostPath $source e causaria recursão" ;;
    esac
    archive="$(printf '%s' "$source" | sed 's#^/##; s#[/]#__#g').tar.gz"
    printf '%s\t%s\n' "$source" "$archive" >> "$PARTIAL_DIR/hostpaths.tsv"
    log "hostPath $source"
    tar --numeric-owner -czf "$PARTIAL_DIR/hostpaths/$archive" -C "$source" .
  done <<< "$HOST_PATHS"
fi

log "Reiniciando k3s..."
systemctl start k3s
K3S_STOPPED=false
timeout 120 sh -c 'until kubectl get nodes >/dev/null 2>&1; do sleep 2; done' \
  || die "k3s não respondeu após reiniciar"

log "Gerando checksums..."
(
  cd "$PARTIAL_DIR"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)
mv -- "$PARTIAL_DIR" "$FINAL_DIR"
PARTIAL_DIR=""
log "Backup concluído: $FINAL_DIR"
du -sh "$FINAL_DIR"

