#!/bin/bash
set -e

GARAGE_VERSION="2.3.0"
GARAGE_URL="https://garagehq.deuxfleurs.fr/_releases/v${GARAGE_VERSION}/x86_64-unknown-linux-musl/garage"
GARAGE_RPC_PORT=3901
GARAGE_S3_PORT=3900
GARAGE_ADMIN_PORT=3903
REPLICATION="${REPLICATION_FACTOR:-3}"
IP_FILE="nodes_ips.txt"
CREDS_FILE="garage_credentials.env"

RPC_SECRET=$(openssl rand -hex 32)

mapfile -t VM_NAMES < <(awk '{print $1}' "$IP_FILE")
mapfile -t VM_IPS  < <(awk '{print $2}' "$IP_FILE")
N=${#VM_NAMES[@]}

#instalacja i start Garage na każdej VM równolegle
for i in $(seq 0 $((N-1))); do
    VM_NAME="${VM_NAMES[$i]}"
    VM_IP="${VM_IPS[$i]}"

    CONFIG_B64=$(printf \
'metadata_dir = "/home/ubuntu/garage-meta"
data_dir = "/home/ubuntu/garage-data"
db_engine = "lmdb"

replication_factor = %s

rpc_bind_addr = "[::]:3901"
rpc_public_addr = "%s:3901"
rpc_secret = "%s"
bootstrap_peers = []

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage.tld"

[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.garage.tld"
index = "index.html"

[admin]
api_bind_addr = "0.0.0.0:3903"
' "$REPLICATION" "$VM_IP" "$RPC_SECRET" | base64 -w 0)

    multipass exec "$VM_NAME" -- bash -c "
        if ! ~/garage --version 2>/dev/null | grep -q '${GARAGE_VERSION}'; then
            wget -q '${GARAGE_URL}' -O ~/garage && chmod +x ~/garage
        fi
        pkill -9 garage 2>/dev/null || true
        sleep 0.5
        mkdir -p ~/garage-meta ~/garage-data
        echo '${CONFIG_B64}' | base64 -d > ~/garage.toml
        nohup ~/garage -c ~/garage.toml server > ~/garage.log 2>&1 &
    " < /dev/null &
done
wait

echo "startowanie Garage..."
sleep 5

#pobieranie ID każdego węzła
FIRST_VM="${VM_NAMES[0]}"
declare -a NODE_ADDRS
for i in $(seq 0 $((N-1))); do
    VM_NAME="${VM_NAMES[$i]}"
    VM_IP="${VM_IPS[$i]}"
    NODE_FULL=$(multipass exec "$VM_NAME" -- bash -c \
        "~/garage -c ~/garage.toml node id 2>/dev/null" < /dev/null | tr -d '\r\n')
    NODE_ID=$(echo "$NODE_FULL" | cut -d'@' -f1)
    NODE_ADDRS+=("${NODE_ID}@${VM_IP}:${GARAGE_RPC_PORT}")
    echo "  ${VM_NAME}: ${NODE_ID:0:16}..."
done

#łączenie wszystkich węzłów z węzłem 1 adminem
FIRST_NODE_ADDR="${NODE_ADDRS[0]}"
for i in $(seq 1 $((N-1))); do
    multipass exec "${VM_NAMES[$i]}" -- bash -c \
        "~/garage -c ~/garage.toml node connect '${FIRST_NODE_ADDR}'" < /dev/null &
done
wait
sleep 2

#przypisanie layoutu (z węzła 1)
for i in $(seq 0 $((N-1))); do
    NODE_ID=$(echo "${NODE_ADDRS[$i]}" | cut -d'@' -f1)
    multipass exec "$FIRST_VM" -- bash -c \
        "~/garage -c ~/garage.toml layout assign '${NODE_ID}' --zone dc1 --capacity 3.3G --tag '${VM_NAMES[$i]}'" < /dev/null
done

#zatwierdzanie layoutu
multipass exec "$FIRST_VM" -- bash -c \
    "~/garage -c ~/garage.toml layout apply --version 1" < /dev/null
sleep 3

#klucz dostępu
KEY_OUT=$(multipass exec "$FIRST_VM" -- bash -c \
    "~/garage -c ~/garage.toml key create bench-key" < /dev/null)

KEY_ID=$(echo "$KEY_OUT"     | grep -i "Key ID"     | awk '{print $NF}')
KEY_SECRET=$(echo "$KEY_OUT" | grep -i "Secret key" | awk '{print $NF}')

if [ -z "$KEY_ID" ] || [ -z "$KEY_SECRET" ]; then
    echo "  [!!] Nie udało się uzyskać credentials Garage." >&2
    echo "$KEY_OUT" >&2
    exit 1
fi

#uprawnienia + bucket
multipass exec "$FIRST_VM" -- bash -c \
    "~/garage -c ~/garage.toml key allow --create-bucket '${KEY_ID}'" < /dev/null

#credentials na hoście
printf 'GARAGE_ACCESS_KEY=%s\nGARAGE_SECRET_KEY=%s\n' "$KEY_ID" "$KEY_SECRET" > "$CREDS_FILE"

echo "  Login: ${KEY_ID} | Hasło: ${KEY_SECRET}"
echo "  Credentials zapisane w: ${CREDS_FILE}"
