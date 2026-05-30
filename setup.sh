#!/bin/bash

WARP_VERSION="1.5.0"
WARP_DEB="warp_${WARP_VERSION}_amd64.deb"
WARP_URL="https://dl.min.io/aistor/warp/release/linux-amd64/archive/${WARP_DEB}"

ok()      { echo "[OK]  $1"; }
install() { echo "[>>]  $1"; }
fail()    { echo "[!!]  $1"; }

has() { command -v "$1" &>/dev/null; }

echo "=== Sprawdzanie zależności ==="
MISSING=0

if has multipass; then
    ok "multipass $(multipass version | head -1 | awk '{print $2}')"
else
    fail "multipass nie znaleziony"
    echo "      Zainstaluj: sudo snap install multipass"
    MISSING=1
fi

if has warp; then
    ok "warp $(warp --version 2>/dev/null | head -1 || echo '')"
else
    install "Pobieranie i instalowanie warp ${WARP_VERSION}..."
    wget -q "$WARP_URL" -O "/tmp/${WARP_DEB}"
    sudo dpkg -i "/tmp/${WARP_DEB}" -q
    rm "/tmp/${WARP_DEB}"
    ok "warp ${WARP_VERSION} zainstalowany"
fi

if has mc; then
    ok "mc"
else
    install "Pobieranie i instalowanie mc..."
    wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /tmp/mc
    chmod +x /tmp/mc
    sudo mv /tmp/mc /usr/local/bin/
    ok "mc zainstalowany"
fi

for tool in curl wget; do
    if has "$tool"; then
        ok "$tool"
    else
        install "Instalowanie $tool..."
        sudo apt-get install -y "$tool" -qq
        ok "$tool zainstalowany"
    fi
done

echo ""

if [ "$MISSING" -eq 1 ]; then
    echo "=== Zainstaluj brakujące zależności i uruchom setup.sh ponownie. ==="
    exit 1
fi

mkdir -p results

echo "=== Gotowe. Kolejne kroki: ==="
echo "  1. ./cluster_sim up"
echo "  2. ./minio_deploy.sh lub ./minio_deploy2.sh"
echo "  3. ./livecheck"
echo "  4. ./test"
