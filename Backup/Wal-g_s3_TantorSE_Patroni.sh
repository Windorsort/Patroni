# This file is used to configure the environment and set up the necessary components for installing and configuring WAL-G and Patroni for PostgreSQL.
# Этот файл используется для настройки окружения и установки необходимых компонентов для установки и настройки WAL-G и Patroni для PostgreSQL.

# Astra Linux repository configuration
# Конфигурация репозитория Astra Linux
deb http://download.astralinux.ru/astra/frozen/1.7_x86-64/1.7.3/uu/2/repository-base 1.7_x86-64 main non-free contrib
deb http://download.astralinux.ru/astra/frozen/1.7_x86-64/1.7.3/uu/2/repository-extended 1.7_x86-64 main contrib non-free

# WAL-G PATRONI

# Download the database installer script manually due to certificate issues
# Скачать установщик для Базы и саму базу, у меня ругался на сертификат я скачал вручную
wget --no-check-certificate https://public.tantorlabs.ru/db_installer.sh
chmod +x db_installer.sh
./db_installer.sh --do-initdb --from-file=./tantor-se-server-15_15.2.1_amd64.deb
systemctl status tantor-se-server-15.service
systemctl disable tantor-se-server-15.service
rm -rf /var/lib/postgresql/tantor-se-15/data/*
ls -la /var/lib/postgresql/tantor-se-15/data/

# Download and install WAL-G
# Скачать и установить WAL-G
wget https://wiki.astralinux.ru/tandocs/files/283918239/283918246/1/1697628698923/pool_w_wal-g_wal-g_2.0.1-1_amd64.deb
apt install ./pool_w_wal-g_wal-g_2.0.1-1_amd64.deb

# Create log files for WAL-G
# Создать файлы журналов для WAL-G
touch /var/lib/postgresql/walg.log /var/lib/postgresql/walg-bootstrap.log
chown postgres:postgres /var/lib/postgresql/walg.log /var/lib/postgresql/walg-bootstrap.log

# Optionally, create a symbolic link to the WAL-G binary
# Опционально - сделать ссылку на бинарный файл (пути могут отличаться), разместив его в каталоге, доступном в переменной $PATH
ln -s /usr/bin/wal-g /usr/local/bin/wal-g

# Switch to the postgres user
# Переключиться на пользователя postgres
su - postgres

# Navigate to the PostgreSQL data directory
# Перейти в директорию данных PostgreSQL
postgres@cs-db-001:~$ pwd
/var/lib/postgresql

# Add WAL-G configuration
# Добавить конфигурацию WAL-G
nano .walg.json

{
  "PGDATA": "/var/lib/postgresql/tantor-se-15/data", # Data Directory
  "AWS_ACCESS_KEY_ID": "ebf5671762505578FSJ2", # User key from the Cyber GUI
  "AWS_SECRET_ACCESS_KEY": "0Qtd9ljr5zQXDHwu720KR9yHSbPXCUrAIupgsBJ4", # User password from the Cyber GUI
  "WALE_S3_PREFIX": "s3://bucket113/s3", # Specify the name of the pre-created bucket in the GUI and the folder in it
  "AWS_ENDPOINT": "http://2u.s3node.ru", # Specify the domain of the S3 server
  "AWS_S3_FORCE_PATH_STYLE": "True", # Use the value where the DOMAIN comes first in the address bar during resolution, followed by the BACKET
  "WALG_UPLOAD_CONCURRENCY": "64", # Number of threads for upload, not more than the number of processor threads
  "WALG_DOWNLOAD_CONCURRENCY": "64", # Number of threads for download, not more than the number of processor threads
  "WALG_COMPRESSION_METHOD": "brotli", # Archiving method Brotli is the most optimal
  "WALG_DELTA_MAX_STEPS": "3", # Number of steps for incremental backup after which a full backup will be performed
  "WALG_UPLOAD_DISK_CONCURRENCY": "64", # Number of processes that will be occupied by the disk for archiving/unarchiving
  "WALG_NETWORK_RATE_LIMIT": "Null", # No restrictions
  "WALG_DISK_RATE_LIMIT": "Null", # No restrictions
  "WALG_S3_MAX_PART_SIZE": "1073741824" # Size in bytes, about 1 GIGA, how much volume will be in 1 partition
}

# Create necessary directories and scripts for Patroni
# Создать необходимые директории и скрипты для Patroni
mkdir /opt/tantor/etc
mkdir /opt/tantor/etc/patroni
touch /opt/tantor/etc/patroni/tantor-wal-g.sh
chmod +x /opt/tantor/etc/patroni/tantor-wal-g.sh
chown postgres: -R /opt/tantor

# Edit the Patroni WAL-G script
# Редактировать скрипт Patroni WAL-G
nano /opt/tantor/etc/patroni/tantor-wal-g.sh

#!/bin/bash

# Define WAL-G configuration path
# Определить путь к конфигурации WAL-G
config_path="/var/lib/postgresql/.walg.json"
pgdata_dir="/var/lib/postgresql/tantor-se-15/data"

# Check if the base directory exists, create if it doesn't
# Проверить, существует ли базовая директория, создать, если нет
if [ ! -d "$pgdata_dir" ]; then
    echo "Creating base directory: $pgdata_dir"
    mkdir -p "$pgdata_dir"
fi

# Check for existing backups and catchups
# Проверить наличие существующих резервных копий и дополнений
backup_list=$(wal-g --config "$config_path" backup-list 2>&1)
catchup_list=$(wal-g --config "$config_path" catchup-list 2>&1)

function get_latest_date() {
   #echo "$1" | grep -v 'name' | awk '{print $2 "T" $3}' | sort | tail -n1
   echo "$1" | tail -n +2 | awk '{print $2 " " $0}' | sort | tail -n 1 | cut -d' ' -f2-
   # date -d "$1 | grep -v 'name' | awk '{print $2 "T" $4}' | sed 's/T$//')" "+%Y-%m-%d %H:%M:%S"
}

# Check for "No backups found"
# Проверить наличие "No backups found"
if [[ "$backup_list" == *"No backups found"* && "$catchup_list" == *"No backups found"* ]]; then
    # Standard DB init if no backups are found
    # Стандартная инициализация БД, если резервные копии не найдены
    echo "No backups found, initializing standard database..." >> /var/log/pgsql/patroni.log
    /opt/tantor/db/15/bin/initdb -D $pgdata_dir
    exit 0
else
    # Determine latest backup and perform appropriate fetch
    # Определить последнюю резервную копию и выполнить соответствующее извлечение
    latest_backup_date=$(get_latest_date "$backup_list")
    latest_catchup_date=$(get_latest_date "$catchup_list")
    #latest_catchup_date=0

    if [[ "$latest_backup_date" > "$latest_catchup_date" ]]; then
        echo "Latest backup date: $latest_backup_date" >> /var/log/pgsql/patroni.log
        wal-g --config "$config_path" backup-fetch "$pgdata_dir" LATEST
    else
        echo "Latest catchup date: $latest_catchup_date" >> /var/log/pgsql/patroni.log
        wal-g --config "$config_path" catchup-fetch "$pgdata_dir" LATEST
    fi
fi

# Add the IP address of the HA node or the node with S3 to the hosts file
# Добавить IP-адрес узла HA или узла с S3 в файл hosts
nano /etc/hosts
192.168.130.101 2u.s3node.ru

# WAL-G Commands
# Команды WAL-G
wal-g backup-list
wal-g backup-push /var/lib/postgresql/tantor-se-15/data # Backup the database
wal-g backup-fetch /var/lib/postgresql/tantor-se-15/data LATEST # Restore the latest backup version
touch /var/lib/postgresql/tantor-se-15/data/recovery.signal # Execute after fetch but before restarting Patroni

# For Patroni

# Install ETCD
# Установка ETCD
apt install etcd

# Edit the ETCD default configuration file
# Редактировать файл конфигурации ETCD по умолчанию
nano /etc/default/etcd

ETCD_NAME="pp_services_1"
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.130.232:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.130.232:2380"
ETCD_INITIAL_CLUSTER_TOKEN="cluster"
ETCD_INITIAL_CLUSTER="pp_services_1=http://192.168.130.232:2380,pp_services_2=http://192.168.130.229:2380,pp_services_3=http://192.168.130.230:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_ELECTION_TIMEOUT="5000"
ETCD_HEARTBEAT_INTERVAL="1000"

# Reload the systemd daemon and restart ETCD
# Перезагрузить демон systemd и перезапустить ETCD
systemctl daemon-reload
systemctl restart etcd

# List ETCD members
# Список участников ETCD
etcdctl member list

# Install Patroni
# Установка Patroni
apt-get -y install python3-pip
pip3 install patroni
pip3 install psycopg2-binary
pip3 install psycopg
pip3 install python-etcd
pip3 install etcd3

# Create the Patroni systemd service file
# Создать файл систеmd службы Patroni
cat <<EOF > /lib/systemd/system/patroni.service
[Unit]
Description=Runners to orchestrate a high-availability TantorDB
After=network.target
ConditionPathExists=/etc/patroni/config.yml

[Service]
Type=simple

User=postgres
Group=postgres

# Read in configuration file if it exists, otherwise proceed
# Прочитать файл конфигурации, если он существует, в противном случае продолжить
EnvironmentFile=-/etc/patroni_env.conf

WorkingDirectory=~

# Pre-commands to start watchdog device
# Uncomment if watchdog is part of your patroni setup
#ExecStartPre=-/usr/bin/sudo /sbin/modprobe softdog
#ExecStartPre=-/usr/bin/sudo /bin/chown postgres /dev/watchdog

# Start the patroni process
# Запустить процесс patroni
ExecStart=/usr/local/bin/patroni /etc/patroni/config.yml

# Send HUP to reload from patroni.yml
# Отправить HUP для перезагрузки из patroni.yml
ExecReload=/bin/kill -s HUP $MAINPID

# only kill the patroni process, not it's children, so it will gracefully stop postgres
# Убить только процесс patroni, а не его дочерние процессы, чтобы он остановил postgres корректно
KillMode=process

# Give a reasonable amount of time for the server to start up/shut down
# Дать разумное количество времени для запуска/остановки сервера
TimeoutSec=60

# Do not restart the service if it crashes, we want to manually inspect database on failure
# Не перезапускать службу в случае сбоя, мы хотим вручную проверить базу данных при сбое
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Create the Patroni configuration directory and set ownership
# Создать директорию конфигурации Patroni и установить владельца
mkdir /etc/patroni
chown postgres: -R /etc/patroni

# Edit the Patroni configuration file
# Редактировать файл конфигурации Patroni
nano /etc/patroni/config.yml

scope: Cluster
name: patroni1
namespace: /service

etcd3:
  hosts: 192.168.130.232:2379,192.168.130.229:2379,192.168.130.230:2379

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.130.232:8008

bootstrap:
  method: wal-g
  wal-g:
    command: "/opt/tantor/etc/patroni/tantor-wal-g.sh"
    recovery_conf:
      restore_command: '/usr/local/bin/wal-g --config /var/lib/postgresql/.walg.json wal-fetch "%f" "%p" 2>&1 | tee -a /var/lib/postgresql/walg.log'
      recovery_target_timeline: latest
      recovery_target_action: promote
      recovery_target_time: ''
  method: initdb
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    master_start_timeout: 300
    synchronous_mode: true
    synchronous_mode_strict: false
    synchronous_node_count: 1
    postgresql:
      use_pg_rewind: true
      remove_data_directory_on_diverged_timelines: true
      remove_data_directory_on_rewind_failure: true
      use_slots: true
      parameters:
        max_connections: 1000
        superuser_reserved_connections: 5
        password_encryption: scram-sha-256
        max_locks_per_transaction: 512
        max_prepared_transactions: 0
        huge_pages: try
        shared_buffers: 4GB
        effective_cache_size: 12GB
        work_mem: 32MB
        maintenance_work_mem: 1GB
        checkpoint_timeout: 15min
        checkpoint_completion_target: 0.9
        min_wal_size: 2GB
        max_wal_size: 8GB
        wal_buffers: 32MB
        default_statistics_target: 1000
        seq_page_cost: 1
        random_page_cost: 1.1
        effective_io_concurrency: 200
        synchronous_commit: on
        autovacuum: on
        autovacuum_max_workers: 5
        autovacuum_vacuum_scale_factor: 0.01
        autovacuum_analyze_scale_factor: 0.01
        autovacuum_vacuum_cost_limit: 500
        autovacuum_vacuum_cost_delay: 2
        autovacuum_naptime: 1s
        max_files_per_process: 4096
        archive_mode: on
        archive_timeout: 300s
        archive_command: '/usr/local/bin/wal-g --config /var/lib/postgresql/.walg.json wal-push "%p" 2>&1 | tee -a /var/lib/postgresql/walg.log'
        wal_level: hot_standby
        wal_keep_size: 2GB
        max_wal_senders: 10
        max_replication_slots: 10
        hot_standby: on
        wal_log_hints: on
        wal_compression: on
        shared_preload_libraries: pg_stat_statements,auto_explain
        pg_stat_statements.max: 10000
        pg_stat_statements.track: all
        pg_stat_statements.track_utility: false
        pg_stat_statements.save: true
        auto_explain.log_min_duration: 10s
        auto_explain.log_analyze: true
        auto_explain.log_buffers: true
        auto_explain.log_timing: false
        auto_explain.log_triggers: true
        auto_explain.log_verbose: true
        auto_explain.log_nested_statements: true
        auto_explain.sample_rate: 0.01
        track_io_timing: on
        log_lock_waits: on
        log_temp_files: 0
        track_activities: on
        track_activity_query_size: 4096
        track_counts: on
        track_functions: all
        log_checkpoints: on
        logging_collector: on
        log_truncate_on_rotation: on
        log_rotation_age: 1d
        log_rotation_size: 0
        log_line_prefix: '%t [%p-%l] %r %q%u@%d '
        log_filename: postgresql-%a.log
        log_directory: /var/log/pgsql/
        hot_standby_feedback: on
        max_standby_streaming_delay: 30s
        wal_receiver_status_interval: 10s
        idle_in_transaction_session_timeout: 10min
        jit: off
        max_worker_processes: 15
        max_parallel_workers: 8
        max_parallel_workers_per_gather: 4
        max_parallel_maintenance_workers: 4
        tcp_keepalives_count: 10
        tcp_keepalives_idle: 300
        tcp_keepalives_interval: 30
      recovery_conf:
        restore_command: '/usr/local/bin/wal-g --config /var/lib/postgresql/.walg.json wal-fetch "%f" "%p" 2>&1 |tee -a /var/lib/postgresql/walg.log'

  initdb:  # List options to be passed on to initdb
    - encoding: UTF8
    - locale: ru_RU.UTF-8
    - data-checksums

  pg_hba:  # Add following lines to pg_hba.conf after running 'initdb'
    - local   all             all                                     trust
    - local   replication     all                                     trust
    - host    replication     all             127.0.0.1/32            trust
    - host    replication     all             ::1/128                 trust
    - host replication replicator 127.0.0.1/32 scram-sha-256
    - local replication postgres    scram-sha-256
    - host all astra 192.168.130.232/32 scram-sha-256
    - host all postgres 192.168.130.232/32 scram-sha-256
    - host all astra 192.168.130.229/32 scram-sha-256
    - host all postgres 192.168.130.229/32 scram-sha-256
    - host all astra 192.168.130.230/32 scram-sha-256
    - host all postgres 192.168.130.230/32 scram-sha-256
    - host replication replicator  localhost   scram-sha-256
    - host replication replicator 192.168.130.232/32 scram-sha-256
    - host replication replicator 192.168.130.229/32 scram-sha-256
    - host replication replicator 192.168.130.230/32 scram-sha-256

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.130.232:5432
  use_unix_socket: true
  data_dir: /var/lib/postgresql/tantor-se-15/data/
  bin_dir: /opt/tantor/db/15/bin
  config_dir: /var/lib/postgresql/tantor-se-15/data/
  pgpass: /var/lib/postgresql/tantor-se-15/.pgpass_patroni
  authentication:
    replication:
      username: replicator
      password: cluster
    superuser:
      username: postgres
      password: cluster
  parameters:
    unix_socket_directories: /var/run/postgresql

watchdog:
  mode: automatic
  device: /dev/watchdog
  safety_margin: 5

tags:
  nosync: false
  noloadbalance: false
  nofailover: false
  clonefrom: false

# Enable and start the Patroni service
# Включить и запустить службу Patroni
systemctl enable patroni
mkdir /var/log/pgsql
chmod 777 -R /var/log/pgsql
chown postgres: -R /var/log/pgsql

# List the contents of the PostgreSQL data directory and set ownership and permissions
# Вывести содержимое директории данных PostgreSQL и установить владельца и права доступа
ls -la /var/lib/postgresql/tantor-se-15
sudo chown -R postgres: -R /var/lib/postgresql
sudo chmod 700 -R /var/lib/postgresql

# Reload the systemd daemon and restart Patroni
# Перезагрузить демон systemd и перезапустить Patroni
systemctl daemon-reload
sudo systemctl restart patroni

#### Keepalived ####

# Install Keepalived
# Установить Keepalived
apt-get install keepalived

# Enable IP nonlocal bind
# Включить IP nonlocal bind
net.ipv4.ip_nonlocal_bind=1 в /etc/sysctl.conf

# Apply the sysctl configuration
# Применить конфигурацию sysctl
sysctl -p

# Create the Keepalived configuration file
# Создать файл конфигурации Keepalived
cat <<EOF > /etc/keepalived/keepalived.conf

! Configuration File for keepalived

global_defs {
   router_id ocp_vrrp
   enable_script_security
   script_user root
}

vrrp_script haproxy_check {
   script "/usr/libexec/keepalived/haproxy_check.sh"
   interval 2
   weight 2
}

vrrp_instance VI_1 {
   interface eth0
   virtual_router_id 50
   priority  100
   advert_int 2
   state  BACKUP
   virtual_ipaddress {
       172.16.190.50
   }
   track_script {
       haproxy_check
   }
   authentication {
      auth_type PASS
      auth_pass cluster
   }
}
EOF

# Enable and start the Keepalived service
# Включить и запустить службу Keepalived
systemctl enable keepalived
systemctl start keepalived
systemctl status keepalived
ip -br a

#### HaPROXY ####

# Install HAProxy
# Установить HAProxy
apt-get install haproxy

# Create the HAProxy configuration file
# Создать файл конфигурации HAProxy
cat <<EOF > /etc/haproxy/haproxy.cfg
global
    maxconn 100000
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy-master.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode               tcp
    log                global
    retries            2
    timeout queue      5s
    timeout connect    5s
    timeout client     60m
    timeout server     60m
    timeout check      15s

listen stats
    mode http
    bind 192.168.130.67:7000
    stats enable
    stats uri /

listen master
    bind 192.168.130.100:5000
    maxconn 10000
    option tcplog
    option httpchk OPTIONS /primary
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 4 on-marked-down shutdown-sessions
 server astra1 172.20.130.101:5432 check port 8008
 server astra2 172.20.130.102:5432 check port 8008
 server astra3 172.20.130.103:5432 check port 8008

listen replicas
    bind 192.168.130.100:5001
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /replica?lag=100MB
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
 server astra1 172.20.130.101:5432 check port 8008
 server astra2 172.20.130.102:5432 check port 8008
 server astra3 172.20.130.103:5432 check port 8008

listen replicas_sync
    bind 192.168.130.100:5002
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /sync
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
 server astra1 172.20.130.101:5432 check port 8008
 server astra2 172.20.130.102:5432 check port 8008
 server astra3 172.20.130.103:5432 check port 8008

listen replicas_async
    bind 192.168.130.100:5003
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /async?lag=100MB
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
 server astra1 172.20.130.101:5432 check port 8008
 server astra2 172.20.130.102:5432 check port 8008
 server astra3 172.20.130.103:5432 check port 8008
EOF

# Enable and start the HAProxy service
# Включить и запустить службу HAProxy
systemctl enable haproxy.service
systemctl start haproxy.service
systemctl status haproxy.service

# Verify that HAProxy is running
# Проверить, работает ли HAProxy
psql -h 172.16.190.50 -p 5000 -U postgres -c "CREATE TABLE test_table1 (id INT, name TEXT);"