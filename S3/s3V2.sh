cat <<EOF >> /etc/hosts
192.168.130.101 X.s3node.ru
EOF


# WAL-G

touch /var/lib/postgresql/.walg.json
chown postgres: /var/lib/postgresql/.walg.json
chmod 777 /var/lib/postgresql/.walg.json


# local

cat > /var/lib/postgresql/.walg.json <<EOF 
{
    "WALG_COMPRESSION_METHOD": "brotli",
    "WALG_DELTA_MAX_STEPS": "5",
    "WALG_FILE_PREFIX": "/var/lib/postgresql/walgdata",
    "PGDATA": "/var/lib/postgresql/tantor-se-15/data",
    "PGHOST": "/var/run/postgresql/.s.PGSQL.5432"
}
EOF

# HTTP 80 brotli

cat > /var/lib/postgresql/.walg.json <<EOF
{
    "AWS_ACCESS_KEY_ID": "a090f1001253c513KD5D",
    "AWS_SECRET_ACCESS_KEY": "fnFyuXKlMTuGjc2bZlRMA0QQBkOXbZiLHAs0e1Cx",
    "WALE_S3_PREFIX": "s3://bucket113/s3",
    "AWS_ENDPOINT": "http://X.s3node.ru",
    "AWS_S3_FORCE_PATH_STYLE":"True",
    "WALG_COMPRESSION_METHOD": "brotli",
    "WALG_DELTA_MAX_STEPS": "5"
}
EOF
или

# HTTP 80 lz4

cat > /var/lib/postgresql/.walg.json <<EOF
{
    "AWS_ACCESS_KEY_ID": "a090f1001253c513KD5D",
    "AWS_SECRET_ACCESS_KEY": "fnFyuXKlMTuGjc2bZlRMA0QQBkOXbZiLHAs0e1Cx",
    "WALE_S3_PREFIX": "s3://bucket113/backupwalg",
    "AWS_ENDPOINT": "http://X.s3node.ru",
    "AWS_S3_FORCE_PATH_STYLE":"True",
    "WALG_COMPRESSION_METHOD": "lz4"
}
EOF

# HTTPS 443

cat > /var/lib/postgresql/.walg.json <<EOF
{
    "AWS_ACCESS_KEY_ID": "a090f1001253c513KD5D",
    "AWS_SECRET_ACCESS_KEY": "fnFyuXKlMTuGjc2bZlRMA0QQBkOXbZiLHAs0e1Cx",
    "WALE_S3_PREFIX": "s3://bucket113/s3",
    "AWS_ENDPOINT": "https://X.s3node.ru",
    "AWS_S3_FORCE_PATH_STYLE":"True",
    "WALG_COMPRESSION_METHOD": "brotli",
    "WALG_DELTA_MAX_STEPS": "5",
    "WALG_S3_CA_CERT_FILE": "/var/lib/postgresql/mycert.crt"
}
EOF

# тюн s3

cat > /var/lib/postgresql/.walg.json <<EOF
{
  "PGDATA": "/mnt/database/pgdata",
  "AWS_ACCESS_KEY_ID": "ebf5671762505578FSJ2",
  "AWS_SECRET_ACCESS_KEY": "0Qtd9ljr5zQXDHwu720KR9yHSbPXCUrAIupgsBJ4",
  "WALE_S3_PREFIX": "s3://bucket113/s113",
  "AWS_ENDPOINT": "https://X.s3node.ru:9443",
  "WALG_S3_CA_CERT_FILE": "/var/lib/postgresql/mycert.crt",
  "AWS_S3_FORCE_PATH_STYLE": "True",
  "WALG_UPLOAD_CONCURRENCY": "64",
  "WALG_DOWNLOAD_CONCURRENCY": "64",
  "WALG_COMPRESSION_METHOD": "brotli",
  "WALG_DELTA_MAX_STEPS": "3",
  "WALG_UPLOAD_DISK_CONCURRENCY": "64",
  "WALG_NETWORK_RATE_LIMIT": "Null",
  "WALG_DISK_RATE_LIMIT": "Null",
  "WALG_S3_MAX_PART_SIZE": "1073741824"
}


{
  "AWS_ACCESS_KEY_ID": "a090f1001253c513KD5D",
  // Идентификатор доступа для подключения к S3-совместимому хранилищу.
  // Задается пользователем и выдается провайдером S3.
  
  "AWS_SECRET_ACCESS_KEY": "fnFyuXKlMTuGjc2bZlRMA0QQBkOXbZiLHAs0e1Cx",
  // Секретный ключ доступа для S3, связанный с AWS_ACCESS_KEY_ID.
  // Предоставляется пользователем и провайдером S3, хранится конфиденциально.

  "WALE_S3_PREFIX": "s3://bucket113/s3",
  // Указывает расположение S3-бакета, где будут храниться бэкапы.
  // Формат: s3://<bucket_name>/<prefix>. Задается пользователем.

  "AWS_ENDPOINT": "http://X.s3node.ru",
  // Указывает URL-адрес S3-совместимого сервиса, если используется не AWS S3.
  // Например, MinIO, Yandex.Cloud или другие провайдеры S3. Устанавливается пользователем.

  "AWS_S3_FORCE_PATH_STYLE": "True",
  // Использует адресацию в стиле пути для бакетов вместо поддоменов.
  // Полезно для некоторых S3-совместимых хранилищ. Обычно требуется, если провайдер не поддерживает поддоменный стиль.

  "WALG_DOWNLOAD_CONCURRENCY": "32",
  // Количество потоков, используемых при загрузке данных из S3 для ускорения восстановления.
  // Чем больше значение, тем больше потоков, но слишком высокое значение может увеличить нагрузку на сеть и CPU.

  "WALG_UPLOAD_CONCURRENCY": "64",
  // Количество потоков для одновременной загрузки данных в S3, что ускоряет бэкап.
  // При 100-гигабитной сети 64 потока может быть оптимально для быстрого загрузки больших объемов данных.

  "WALG_COMPRESSION_METHOD": "lz4",
  // Метод сжатия для бэкапов. LZ4 — быстрая компрессия с низким уровнем сжатия.
  // Выбран для скорости; другие методы (например, brotli) обеспечивают лучшее сжатие, но медленнее.

  "WALG_COMPRESSION_LEVEL": "1",
  // Уровень сжатия для lz4. Уровень 1 — минимальное сжатие, высокая скорость.
  // Если приоритет у скорости, этот уровень оптимален.

  "WALG_UPLOAD_DISK_CONCURRENCY": "32",
  // Количество потоков для записи данных с диска при загрузке в S3.
  // Оптимизирует использование диска во время загрузки. Чем выше значение, тем выше нагрузка на диск.

  "WALG_DOWNLOAD_DISK_CONCURRENCY": "32",
  // Количество потоков для записи данных на диск при восстановлении из S3.
  // Настроено для повышения производительности, особенно на высокопроизводительных дисках.

  "WALG_NETWORK_RATE_LIMIT": "null",
  // Лимит скорости сети для WAL-G (например, 100M для 100 Мбит/с). Null отключает лимит.
  // Можно задать для ограничения, если сеть сильно загружена.

  "WALG_DISK_RATE_LIMIT": "null",
  // Лимит скорости диска для WAL-G (например, 50M для 50 Мбит/с). Null отключает лимит.
  // Полезен, если вы хотите ограничить интенсивность записи для других приложений.

  "WALG_PRELOAD_BACKUPS": "true"
  // Предварительная загрузка метаданных для всех бэкапов, что ускоряет операции, такие как list.
  // Полезно, если у вас много бэкапов и важно быстро находить нужные.
}
EOF

# NFS

cat <<EOF > /var/lib/postgresql/.walg.json
{
    "WALG_FILE_PREFIX": "/mnt/wal-g/backups/",
    "WALG_COMPRESSION_METHOD": "brotli",
    "WALG_DELTA_MAX_STEPS": "1",
    "PGDATA": "/var/lib/postgresql/tantor-se-15/data",
    "PGHOST": "/var/run/postgresql/.s.PGSQL.5432"
}
EOF

# проверка подключения

aws s3 ls s3://bucket113/s3/ --endpoint-url http://X.s3node.ru:80

aws s3 ls s3://bucket113/s3/ --endpoint-url https://X.s3node.ru:443

# создание сертификата

openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout mykey.key -out mycert.crt -config /root/openssl.cnf -extensions req_ext


cat <<EOF > /root/openssl.cnf
[req]
default_bits        = 2048
prompt              = no
default_md          = sha256
req_extensions      = req_ext
distinguished_name  = req_distinguished_name

[req_distinguished_name]
C  = RU
ST = Moscow
L  = Moscow
O  = My Company
OU = My Department
CN = X.s3node.ru

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = X.s3node.ru
DNS.2 = www.X.s3node.ru
EOF


Работа с s3 локальным GeeseFS

# как ставить
https://github.com/yandex-cloud/geesefs
wget https://github.com/yandex-cloud/geesefs/releases/latest/download/geesefs-linux-amd64
chmod a+x geesefs-linux-amd64
sudo cp geesefs-linux-amd64 /usr/bin/geesefs

mkdir /mnt/s3
chmod 777 /mnt/s3
geesefs --endpoint http://X.s3node.ru:80 bucket113 /mnt/s3 # для http 80

geesefs --endpoint https://X.s3node.ru:443 bucket113 /mnt/s3 # для https 443

export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
cp /var/lib/postgresql/mycert.crt /usr/local/share/ca-certificates/
update-ca-certificates

mkdir /mnt/s3
chmod 777 /mnt/s3
geesefs --endpoint https://X.s3node.ru:443 bucket113 /mnt/s3

# Настройка HaProxy

#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    # Настройка безопасности для DH-параметров
    tune.ssl.default-dh-param 2048  # Использование безопасных параметров DH

    # Turn on stats unix socket
    stats socket /var/lib/haproxy/stats

#---------------------------------------------------------------------
# Default settings for all frontend and backend sections
#---------------------------------------------------------------------
defaults
    mode                    http  # HTTP mode для анализа запросов и работы с HTTP
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

#---------------------------------------------------------------------
# Frontend for HTTPS (SSL termination)
#---------------------------------------------------------------------
frontend https_frontend
    bind *:9443 ssl crt /etc/haproxy/mypem.pem  # Путь к вашему SSL-сертификату
    mode http  # После расшифровки SSL работает как HTTP
    option httplog
    option forwardfor
    default_backend http_servers

#---------------------------------------------------------------------
# Backend for HTTP servers
#---------------------------------------------------------------------
backend http_servers
    balance roundrobin
    http-check expect status 200  # Проверка на успешный ответ 200
    server X-node-10 192.168.230.101:80 check
    server X-node-11 192.168.230.102:80 check
    server X-node-12 192.168.230.103:80 check
