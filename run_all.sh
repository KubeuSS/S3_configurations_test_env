#!/bin/bash
set -e

IP_FILE="nodes_ips.txt"
ACCESS_KEY="admin"
SECRET_KEY="admin123"
CONFIGS_DIR="configs"
RESULTS_BASE="results"

wait_healthy() {
    local host="$1"
    local retries=30
    until curl -sf "http://$host/minio/health/ready" > /dev/null 2>&1; do
        retries=$((retries - 1))
        if [ "$retries" -eq 0 ]; then
            echo "  [!!] MinIO nie odpowiada po 60s — przerywam." >&2
            exit 1
        fi
        sleep 2
    done
}

read -r FIRST_VM FIRST_IP < "$IP_FILE"
HOST="${FIRST_IP}:9000"

for conf in "$CONFIGS_DIR"/*.conf; do
    unset EC_CLASS OBJ_SIZE OBJECTS DURATION CONCURRENT
    source "$conf"

    LABEL=$(basename "$conf" .conf)
    TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
    RESULT_DIR="${RESULTS_BASE}/${TIMESTAMP}_${LABEL}"
    mkdir -p "$RESULT_DIR"

    echo ""
    echo "=== [$LABEL] EC=${EC_CLASS:-brak} | obj=${OBJ_SIZE} | conc=${CONCURRENT} | ${DURATION} ==="

    echo "  Czyszczenie danych..."
    ./minio_clear

    echo "  Wdrażanie MinIO..."
    EC_CLASS="$EC_CLASS" ./minio_deploy.sh

    echo "  Oczekiwanie na gotowość..."
    wait_healthy "$HOST"

    echo "  Czyszczenie cache VM..."
    while read -r VM_NAME VM_IP; do
        multipass exec "$VM_NAME" -- bash -c \
            "sync && echo 3 | sudo tee /proc/sys/vm/drop_caches" < /dev/null > /dev/null &
    done < "$IP_FILE"
    wait

    echo "  Uruchamianie benchmarku..."
    retries=3
    sleep 10

    until warp mixed \
        --host="$HOST" \
        --access-key="$ACCESS_KEY" \
        --secret-key="$SECRET_KEY" \
        --obj.size "$OBJ_SIZE" \
        --objects "$OBJECTS" \
        --duration "$DURATION" \
        --concurrent "$CONCURRENT" \
        --benchdata "${RESULT_DIR}/warp" --no-color > /dev/null
    do
        retries=$((retries - 1))
        if [ "$retries" -eq 0 ]; then
            echo "  [!!] Benchmark nie wystartował po 3 próbach." >&2
            exit 1
        fi
        echo "  MinIO jeszcze nie gotowy, retry za 5s... ($retries pozostało)"
        sleep 5
    done

    cp "$conf" "${RESULT_DIR}/config.conf"
    {
        echo "label:       $LABEL"
        echo "timestamp:   $TIMESTAMP"
        echo "ec_class:    ${EC_CLASS:-brak}"
        echo "obj_size:    $OBJ_SIZE"
        echo "objects:     $OBJECTS"
        echo "duration:    $DURATION"
        echo "concurrent:  $CONCURRENT"
    } > "${RESULT_DIR}/info.txt"

    echo "  Wyniki zapisane w: $RESULT_DIR"
done

echo ""
echo "Testy zakończone."
