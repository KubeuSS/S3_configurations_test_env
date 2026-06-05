#!/bin/bash
set -e

IP_FILE="nodes_ips.txt"
MINIO_ACCESS_KEY="admin"
MINIO_SECRET_KEY="admin123"
CONFIGS_DIR="configs"
RESULTS_BASE="results"
GARAGE_CREDS_FILE="garage_credentials.env"

wait_healthy() {
    local storage="$1"
    local ip="$2"
    local retries=40

    if [ "$storage" = "garage" ]; then
        until curl -s --max-time 2 -o /dev/null "http://${ip}:3900/" 2>/dev/null; do
            retries=$((retries - 1))
            [ "$retries" -eq 0 ] && { echo "  [!!] Garage nie odpowiada po 60s — przerywam." >&2; exit 1; }
            sleep 2
        done
    else
        until curl -sf "http://${ip}:9000/minio/health/ready" > /dev/null 2>&1; do
            retries=$((retries - 1))
            [ "$retries" -eq 0 ] && { echo "  [!!] MinIO nie odpowiada po 60s — przerywam." >&2; exit 1; }
            sleep 2
        done
    fi
}

read -r FIRST_VM FIRST_IP < "$IP_FILE"

for conf in "$CONFIGS_DIR"/*.conf; do
    unset EC_CLASS OBJ_SIZE OBJECTS DURATION CONCURRENT STORAGE_TYPE REPLICATION_FACTOR
    source "$conf"

    STORAGE="$STORAGE_TYPE"
    [ -z "$STORAGE" ] && { echo "  [!!] Brak STORAGE_TYPE w $conf" >&2; exit 1; }
    LABEL=$(basename "$conf" .conf)
    TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
    RESULT_DIR="${RESULTS_BASE}/${TIMESTAMP}_${LABEL}"
    mkdir -p "$RESULT_DIR"

    if [ "$STORAGE" = "garage" ]; then
        HOST="${FIRST_IP}:3900"
        TAG="rep=${REPLICATION_FACTOR:-3}"
    else
        HOST="${FIRST_IP}:9000"
        TAG="EC=${EC_CLASS:-brak}"
    fi

    echo ""
    echo "=== [$LABEL] storage=${STORAGE} | ${TAG} | obj=${OBJ_SIZE} | conc=${CONCURRENT} | ${DURATION} ==="

    echo "  Czyszczenie poprzedniego konfigu..."
    ./minio_clear
    ./garage_clear

    echo "  Wdrażanie ${STORAGE}..."
    if [ "$STORAGE" = "garage" ]; then
        REPLICATION_FACTOR="${REPLICATION_FACTOR:-3}" ./garage_deploy.sh
        [ ! -f "$GARAGE_CREDS_FILE" ] && { echo "  [!!] Brak $GARAGE_CREDS_FILE" >&2; exit 1; }
        source "$GARAGE_CREDS_FILE"
        ACCESS_KEY="$GARAGE_ACCESS_KEY"
        SECRET_KEY="$GARAGE_SECRET_KEY"
    else
        EC_CLASS="$EC_CLASS" ./minio_deploy.sh
        ACCESS_KEY="$MINIO_ACCESS_KEY"
        SECRET_KEY="$MINIO_SECRET_KEY"
    fi

    echo "  Oczekiwanie na gotowość..."
    wait_healthy "$STORAGE" "$FIRST_IP"

    echo "  Czyszczenie cache VM..."
    while read -r VM_NAME VM_IP; do
        multipass exec "$VM_NAME" -- bash -c \
            "sync && echo 3 | sudo tee /proc/sys/vm/drop_caches" < /dev/null > /dev/null &
    done < "$IP_FILE"
    wait

    echo "  Uruchamianie benchmarku..."
    retries=3
    sleep 10

    WARP_REGION_ARG=""
    [ "$STORAGE" = "garage" ] && WARP_REGION_ARG="--region=garage"

    until warp mixed \
        --host="$HOST" \
        --access-key="$ACCESS_KEY" \
        --secret-key="$SECRET_KEY" \
        ${WARP_REGION_ARG} \
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
        echo "  ${STORAGE} jeszcze nie gotowy, retry za 5s... ($retries pozostało)"
        sleep 5
    done

    cp "$conf" "${RESULT_DIR}/config.conf"
    {
        echo "label:       $LABEL"
        echo "timestamp:   $TIMESTAMP"
        echo "storage:     $STORAGE"
        if [ "$STORAGE" = "garage" ]; then
            echo "replication: ${REPLICATION_FACTOR:-3}"
        else
            echo "ec_class:    ${EC_CLASS:-brak}"
        fi
        echo "obj_size:    $OBJ_SIZE"
        echo "objects:     $OBJECTS"
        echo "duration:    $DURATION"
        echo "concurrent:  $CONCURRENT"
    } > "${RESULT_DIR}/info.txt"

    echo "  Wyniki zapisane w: $RESULT_DIR"
done

echo ""
echo "Testy zakończone."
