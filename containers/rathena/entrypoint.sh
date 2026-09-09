#!/usr/bin/env bash
set -Eeuo pipefail

: "${DB_HOST:?DB_HOST is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"

DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-ragnarok}"
DB_USER="${DB_USER:-ragnarok}"
SERVER_NAME="${SERVER_NAME:-Feanor Ragnarok}"
PUBLIC_IP="${PUBLIC_IP:-127.0.0.1}"

until mariadb-admin ping -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" "-p${DB_PASSWORD}" --silent; do
  sleep 2
done

cat > conf/import/inter_conf.txt <<EOF
login_server_ip: ${DB_HOST}
login_server_port: ${DB_PORT}
login_server_id: ${DB_USER}
login_server_pw: ${DB_PASSWORD}
login_server_db: ${DB_NAME}
ipban_db_ip: ${DB_HOST}
ipban_db_port: ${DB_PORT}
ipban_db_id: ${DB_USER}
ipban_db_pw: ${DB_PASSWORD}
ipban_db_db: ${DB_NAME}
char_server_ip: ${DB_HOST}
char_server_port: ${DB_PORT}
char_server_id: ${DB_USER}
char_server_pw: ${DB_PASSWORD}
char_server_db: ${DB_NAME}
map_server_ip: ${DB_HOST}
map_server_port: ${DB_PORT}
map_server_id: ${DB_USER}
map_server_pw: ${DB_PASSWORD}
map_server_db: ${DB_NAME}
web_server_ip: ${DB_HOST}
web_server_port: ${DB_PORT}
web_server_id: ${DB_USER}
web_server_pw: ${DB_PASSWORD}
web_server_db: ${DB_NAME}
log_db_ip: ${DB_HOST}
log_db_port: ${DB_PORT}
log_db_id: ${DB_USER}
log_db_pw: ${DB_PASSWORD}
log_db_db: ${DB_NAME}
EOF

cat > conf/import/login_conf.txt <<EOF
new_account: no
EOF

cat > conf/import/char_conf.txt <<EOF
server_name: ${SERVER_NAME}
login_ip: 127.0.0.1
char_ip: ${PUBLIC_IP}
EOF

cat > conf/import/map_conf.txt <<EOF
char_ip: 127.0.0.1
map_ip: ${PUBLIC_IP}
EOF

./login-server &
login_pid=$!
./char-server &
char_pid=$!
./map-server &
map_pid=$!

terminate() {
  kill -TERM "${login_pid}" "${char_pid}" "${map_pid}" 2>/dev/null || true
  wait || true
}
trap terminate TERM INT

set +e
wait -n "${login_pid}" "${char_pid}" "${map_pid}"
status=$?
set -e
terminate
exit "${status}"
