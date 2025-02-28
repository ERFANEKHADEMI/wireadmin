#!/usr/bin/env bash
set -e

TOR_CONFIG="/etc/tor/torrc"
ENV_FILE="/app/.env"

echo "                                                   "
echo " _       ___           ___       __          _     "
echo "| |     / (_)_______  /   | ____/ /___ ___  (_)___ "
echo "| | /| / / / ___/ _ \/ /| |/ __  / __ \`__ \/ / __ \\"
echo "| |/ |/ / / /  /  __/ ___ / /_/ / / / / / / / / / /"
echo "|__/|__/_/_/   \___/_/  |_\__,_/_/ /_/ /_/_/_/ /_/ "
echo "                                                   "

mkdir -p /var/vlogs

touch "${ENV_FILE}"
chmod 400 "${ENV_FILE}"

if ! grep -q "AUTH_SECRET" "${ENV_FILE}"; then
  tee -a "${ENV_FILE}" &>/dev/null <<EOF
AUTH_SECRET=$(openssl rand -base64 32)
EOF
fi

# Checking if there is `UI_PASSWORD` environment variable
# if there was, converting it to hex and storing it to
# the .env
if [ -n "$UI_PASSWORD" ]; then
  sed -i '/^HASHED_PASSWORD/d' "${ENV_FILE}"
  tee -a "${ENV_FILE}" &>/dev/null <<EOF
HASHED_PASSWORD=$(printf "%s" "${UI_PASSWORD}" | od -A n -t x1 | tr -d ' \n')
EOF
  unset UI_PASSWORD
else
  echo "[error] no password set for the UI"
  exit 1
fi

# Remove duplicated envs
awk -F= '!a[$1]++' "${ENV_FILE}" >"/tmp/$(basename "${ENV_FILE}")" &&
  mv "/tmp/$(basename "${ENV_FILE}")" "${ENV_FILE}"

# Starting Redis server in detached mode
screen -L -Logfile /var/vlogs/redis -dmS "redis" \
  bash -c "redis-server --port 6479 --daemonize no --dir /data --appendonly yes"

# Starting Tor
source /scripts/tord.sh

# Generate Tor configuration
generate_tor_config

# Start Tor on the background
screen -L -Logfile /var/vlogs/tor -dmS "tor" tor -f "${TOR_CONFIG}"

sleep 1
echo -e "\n======================== Versions ========================"
echo -e "Alpine Version: \c" && cat /etc/alpine-release
echo -e "WireGuard Version: \c" && wg -v | head -n 1 | awk '{print $1,$2}'
echo -e "Tor Version: \c" && tor --version | head -n 1
echo -e "Obfs4proxy Version: \c" && obfs4proxy -version
echo -e "\n========================= Torrc ========================="
cat "${TOR_CONFIG}"
echo -e "========================================================\n"
sleep 1

screen -L -Logfile /var/vlogs/warmup -dmS warmup \
  bash -c "sleep 10; echo -n '[+] Warming Up...'; curl -s http://127.0.0.1:3000/; echo -e 'Done!'"

exec "$@"
