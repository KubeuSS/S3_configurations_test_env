#!/bin/bash
set -e
IP_FILE="nodes_ips.txt"
MINIO_USER="admin"
MINIO_PASSWORD="admin123"
MINIO_URLS=""


while read -r VM_NAME VM_IP; do
    MINIO_URLS="$MINIO_URLS http://$VM_IP:9000/mnt/minio-data"
done < "$IP_FILE"


while read -r VM_NAME VM_IP; do
	(
    multipass exec "$VM_NAME" -- wget -q -O minio https://dl.min.io/server/minio/release/linux-amd64/minio < /dev/null
    multipass exec "$VM_NAME" -- chmod +x minio < /dev/null
    multipass exec "$VM_NAME" -- bash -c "
        if ! mountpoint -q /mnt/minio-data; then
            dd if=/dev/zero of=/home/ubuntu/minio-disk.img bs=1M count=3333 2>/dev/null
            sudo mkfs.ext4 -F /home/ubuntu/minio-disk.img
            sudo mkdir -p /mnt/minio-data
            sudo mount -o loop /home/ubuntu/minio-disk.img /mnt/minio-data
            sudo chown ubuntu:ubuntu /mnt/minio-data
        fi
    " < /dev/null
) &
done < "$IP_FILE"

wait

while read -r VM_NAME VM_IP; do
    multipass exec "$VM_NAME" -- bash -c \
        "MINIO_ROOT_USER=$MINIO_USER MINIO_ROOT_PASSWORD=$MINIO_PASSWORD \
        nohup ./minio server \
        --address 0.0.0.0:9000 \
        --console-address 0.0.0.0:9001 \
        $MINIO_URLS > minio.log 2>&1 &" < /dev/null &
done < "$IP_FILE"



echo "Login: $MINIO_USER | Hasło: $MINIO_PASSWORD"

