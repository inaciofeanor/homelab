#!/usr/bin/env bash
set -Eeuo pipefail

# Rotaciona as credenciais do homelab e salva uma cÃ³pia local, fora do Git.
# Execute como o usuÃ¡rio que possui acesso ao kubectl, sem sudo.

umask 077
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/homelab"
RECOVERY_FILE="$STATE_DIR/credentials.env"

command -v kubectl >/dev/null || { echo "kubectl nÃ£o encontrado" >&2; exit 1; }
command -v openssl >/dev/null || { echo "openssl nÃ£o encontrado" >&2; exit 1; }

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
[[ ! -e "$RECOVERY_FILE" ]] || {
  echo "Recusado: $RECOVERY_FILE jÃ¡ existe. Mova-o para o gerenciador de senhas antes de rodar novamente." >&2
  exit 1
}

secret_value() {
  kubectl get secret -n homelab "$1" -o "jsonpath={.data.$2}" | base64 --decode
}
new_password() {
  openssl rand -hex 32
}

old_nextcloud_root="$(secret_value nextcloud-db-secrets MYSQL_ROOT_PASSWORD)"
old_romm_root="$(secret_value romm-secrets MARIADB_ROOT_PASSWORD)"
old_immich_db="$(secret_value immich-db-secrets DB_PASSWORD)"

nextcloud_root="$(new_password)"
nextcloud_db="$(new_password)"
nextcloud_admin="$(new_password)"
immich_db="$(new_password)"
romm_root="$(new_password)"
romm_db="$(new_password)"
romm_auth="$(openssl rand -hex 32)"

write_secret() {
  local name="$1"
  shift
  kubectl create secret generic "$name" -n homelab "$@" --dry-run=client -o yaml | kubectl apply -f -
}

update_nextcloud_config_password() {
  local password="$1"
  kubectl exec -n homelab deploy/nextcloud -- `
    env NEXTCLOUD_DB_PASSWORD="$password" su -s /bin/sh www-data -c `
    'php -r '\''$CONFIG = []; include "/var/www/html/config/config.php"; $CONFIG["dbpassword"] = getenv("NEXTCLOUD_DB_PASSWORD"); file_put_contents("/var/www/html/config/config.php", "<?php\n\$CONFIG = " . var_export($CONFIG, true) . ";\n");'\'''
}

echo "Rotacionando banco do Nextcloud..."
kubectl exec -n homelab deploy/nextcloud-db -- \
  mariadb -uroot -p"$old_nextcloud_root" -e \
  "ALTER USER 'nextcloud'@'%' IDENTIFIED BY '$nextcloud_db'; ALTER USER 'root'@'localhost' IDENTIFIED BY '$nextcloud_root';"
write_secret nextcloud-db-secrets \
  --from-literal=MYSQL_ROOT_PASSWORD="$nextcloud_root" \
  --from-literal=MYSQL_PASSWORD="$nextcloud_db"update_nextcloud_config_password "$nextcloud_db"


echo "Rotacionando administrador do Nextcloud..."
kubectl exec -n homelab deploy/nextcloud -- \
  env OC_PASS="$nextcloud_admin" su -s /bin/sh www-data -c \
  'php /var/www/html/occ user:resetpassword --password-from-env admin'
write_secret nextcloud-app-secrets \
  --from-literal=NEXTCLOUD_ADMIN_USER=admin \
  --from-literal=NEXTCLOUD_ADMIN_PASSWORD="$nextcloud_admin"

echo "Rotacionando banco do Immich..."
kubectl exec -n homelab deploy/immich-postgres -- \
  env PGPASSWORD="$old_immich_db" psql -h 127.0.0.1 -U immich -d immich -c \
  "ALTER USER immich WITH PASSWORD '$immich_db';"
write_secret immich-db-secrets --from-literal=DB_PASSWORD="$immich_db"

echo "Rotacionando banco do RomM..."
kubectl exec -n homelab deploy/romm-db -- \
  mariadb -uroot -p"$old_romm_root" -e \
  "ALTER USER 'romm'@'%' IDENTIFIED BY '$romm_db'; ALTER USER 'root'@'localhost' IDENTIFIED BY '$romm_root';"
write_secret romm-secrets \
  --from-literal=DB_PASSWD="$romm_db" \
  --from-literal=MARIADB_ROOT_PASSWORD="$romm_root" \
  --from-literal=ROMM_AUTH_SECRET_KEY="$romm_auth"

cat > "$RECOVERY_FILE" <<EOF
# Gerado em $(date -u +%Y-%m-%dT%H:%M:%SZ). Importe em um gerenciador de senhas.
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=$nextcloud_admin
NEXTCLOUD_DB_PASSWORD=$nextcloud_db
NEXTCLOUD_DB_ROOT_PASSWORD=$nextcloud_root
IMMICH_DB_PASSWORD=$immich_db
ROMM_DB_PASSWORD=$romm_db
ROMM_DB_ROOT_PASSWORD=$romm_root
ROMM_AUTH_SECRET_KEY=$romm_auth
EOF
chmod 600 "$RECOVERY_FILE"

kubectl rollout restart -n homelab deploy/nextcloud deploy/immich-server deploy/romm
kubectl rollout status -n homelab deploy/nextcloud --timeout=180s
kubectl rollout status -n homelab deploy/immich-server --timeout=180s
kubectl rollout status -n homelab deploy/romm --timeout=180s

echo "RotaÃ§Ã£o concluÃ­da. Credenciais de recuperaÃ§Ã£o: $RECOVERY_FILE"
