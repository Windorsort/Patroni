# This file is used to update the system, install necessary packages, and configure MinIO.
# Этот файл используется для обновления системы, установки необходимых пакетов и настройки MinIO.

sudo apt-get update
apt-get install sudo
usermod -aG wheel admin
usermod -aG wheel root
newgrp wheel
export VISUAL=nano
export EDITOR="$VISUAL"
visudo
admin ALL=(ALL) NOPASSWD: ALL
root ALL=(ALL) NOPASSWD: ALL

sudo apt-get install -y curl wget nano
wget https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
chmod +x /usr/local/bin/minio
chmod 777 -R /usr/local/bin
sudo useradd -r minio-user -s /sbin/nologin
sudo mkdir /mnt/minio-data
sudo chown -R minio-user:minio-user /mnt/minio-data
sudo nano /etc/systemd/system/minio.service

[Unit]
Description=MinIO Object Storage
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target

[Service]
User=minio-user
Group=minio-user
ExecStart=/usr/local/bin/minio server /mnt/minio-data --console-address ":9001"
Environment="MINIO_ROOT_USER=admin"
Environment="MINIO_ROOT_PASSWORD=SuperSecretPassword123"

[Install]
WantedBy=multi-user.target

sudo systemctl daemon-reload
sudo systemctl enable minio
sudo systemctl start minio