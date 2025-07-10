# This file is used to configure the environment and set up the necessary components for installing and configuring ETCD, Patroni, Keepalived, and HAProxy.
# Этот файл используется для настройки окружения и установки необходимых компонентов для установки и настройки ETCD, Patroni, Keepalived и HAProxy.

deb http://download.astralinux.ru/astra/frozen/1.7_x86-64/1.7.3/uu/2/repository-base 1.7_x86-64 main non-free contrib
deb http://download.astralinux.ru/astra/frozen/1.7_x86-64/1.7.3/uu/2/repository-extended 1.7_x86-64 main contrib non-free
#####

#### ETCD ####
# Go to the home directory or another suitable directory
# Перейдите в домашнюю директорию или другую подходящую директорию
cd ~

# Download the archive with the latest version of etcd
# Загрузите архив с последней версией etcd
curl -L https://github.com/etcd-io/etcd/releases/download/<latest_version>/etcd-<latest_version>-linux-amd64.tar.gz -o etcd.tar.gz

# Extract the archive
# Распакуйте архив
tar xzvf etcd.tar.gz

# Move the binary files to /usr/local/bin
# Переместите бинарные файлы в /usr/local/bin
cd etcd-<latest_version>-linux-amd64
sudo mv etcd etcdctl /usr/local/bin/

# Create necessary directories and set permissions
# Создайте необходимые директории и установите права доступа
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd

# Install ETCD
# Установить ETCD
apt install etcd

# Edit the ETCD systemd service file
# Редактировать файл систеmd службы ETCD
nano /lib/systemd/system/etcd.service

####
[Unit]
Description=etcd key-value store
Documentation=https://github.com/etcd-io/etcd
After=network.target

[Service]
ExecStart=/usr/local/bin/etcd \
  --name pp_services_1 \
  --data-dir /var/lib/etcd \
  --listen-peer-urls http://0.0.0.0:2380 \
  --listen-client-urls http://0.0.0.0:2379 \
  --advertise-client-urls http://172.16.190.51:2379 \
  --initial-advertise-peer-urls http://172.16.190.51:2380 \
  --initial-cluster pp_services_1=http://172.16.190.51:2380,pp_services_2=http://172.16.190.52:2380,pp_services_3=http://172.16.190.53:2380 \
  --initial-cluster-token cluster \
  --initial-cluster-state new
Restart=always
RestartSec=10s
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target

# Reload the systemd daemon and enable ETCD
# Перезагрузить демон systemd и включить ETCD
systemctl daemon-reload
systemctl enable etcd

# Remove any existing ETCD member data and start the service
# Удалить любые существующие данные участника ETCD и запустить службу
rm -rf /var/lib/etcd/member/*
service etcd start
systemctl status etcd.service

# Check ETCD status
# Проверить статус ETCD
etcdctl member list
etcdctl endpoint health

#### Psql_Tantor ####

# Download the deb package for TantorDB from the Astra license center
# Скачать из ЛК astra deb для tantorDB
https://lk-new.astralinux.ru/licenses-and-certificates/licenses/88630/iso-images

# Download the database installer script manually due to certificate issues
# Скачать установщик для Базы, у меня ругался на сертификат я скачал вручную
wget --no-check-certificate https://public.tantorlabs.ru/db_installer.sh
chmod +x db_installer.sh
./db_installer.sh --do-initdb --from-file=./tantor-se-server-15_15.2.1_amd64.deb
systemctl status tantor-se-server-15.service
# systemctl enable tantor-se-server-15.service
systemctl disable tantor-se-server-15.service
rm -rf /var/lib/postgresql/tantor-se-15/data/*
ls -la /var/lib/postgresql/tantor-se-15/data/

#### Patroni ####

# Install Patroni
# Установить Patroni
apt-get -y install python3-pip
pip3 install patroni
systemctl status patroni

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

# Create the Patroni configuration file
# Создать файл конфигурации Patroni
cat <<EOF > /etc/patroni/config.yml
scope: Cluster
name: patroni1
namespace: /service

etcd3:
  hosts: 172.16.190.51:2379,172.16.190.52:2379,172.16.190.53:2379

restapi:
  listen: 0.0.0.0:8008
  connect_address: 172.16.190.51:8008
#  certfile: /etc/ssl/certs/ssl-cert-snakeoil.pem
#  keyfile: /etc/ssl/private/ssl-cert-snakeoil.key
#  authentication:
#    username: patroni
#    password: cluster

# shared_buffers: Memory allocated for PostgreSQL buffers. Usually recommended around 25% of total memory.
# effective_cache_size: Memory available for data caching by the operating system. Usually set to 50-75% of total memory.
# work_mem: Memory allocated for sorting and hashing in queries. Recommended value is 1 to 2% of total memory per CPU.
# maintenance_work_mem: Memory for maintenance operations such as vacuuming and creating indexes. Usually set to 5-10% of total memory.
# max_worker_processes, max_parallel_workers, max_parallel_workers_per_gather: Number of parallel processes and worker processes that can run concurrently.

bootstrap:
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
        max_connections: 500
        superuser_reserved_connections: 5
        password_encryption: scram-sha-256
        max_locks_per_transaction: 512
        max_prepared_transactions: 0
        huge_pages: try
        shared_buffers: 4GB  # 25% от 15 GB
        effective_cache_size: 12GB  # 75% от 15 GB
        work_mem: 32MB  # 2% от 15 GB / 8 CPU
        maintenance_work_mem: 1GB  # 6.25% от 15 GB
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
        archive_timeout: 1800s
        archive_command: pg_probackup archive-push -B /mnt/pg_probackup/db --instance=main --wal-file-path=%p --wal-file-name=%f
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
        max_worker_processes: 15  # 2 * CPU
        max_parallel_workers: 8  # равен количеству CPU
        max_parallel_workers_per_gather: 4  # половина от количества CPU
        max_parallel_maintenance_workers: 4  # половина от количества CPU
        tcp_keepalives_count: 10
        tcp_keepalives_idle: 300
        tcp_keepalives_interval: 30

  initdb:  # List options to be passed on to initdb
    - encoding: UTF8
    - locale: ru_RU.UTF-8
    - data-checksums

#  post_init:
#    - psql -c "CREATE USER astra WITH SUPERUSER PASSWORD 'password';"
#    - psql -c "GRANT ALL PRIVILEGES ON SCHEMA public TO astra;"
#    - psql -c "CREATE DATABASE astra_base;"
#    - psql -c "CREATE USER user WITH PASSWORD 'PiGiqaap00';"
#    - psql -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO user;"

  pg_hba:  # Add following lines to pg_hba.conf after running 'initdb'
  # - host all all 192.158.113.200/32 md5
    - local   all             all                                     trust
    - local   replication     all                                     trust
    - host    replication     all             127.0.0.1/32            trust
    - host    replication     all             ::1/128                 trust
    - host replication replicator 127.0.0.1/32 scram-sha-256
    - local replication postgres    scram-sha-256
    - host all astra 172.16.190.51/32 scram-sha-256
    - host all postgres 172.16.190.51/32 scram-sha-256
    - host all user 172.16.190.51/32 scram-sha-256
    - host all astra 172.16.190.52/32 scram-sha-256
    - host all postgres 172.16.190.52/32 scram-sha-256
    - host all user 172.16.190.52/32 scram-sha-256
    - host all astra 172.16.190.53/32 scram-sha-256
    - host all postgres 172.16.190.53/32 scram-sha-256
    - host all user 172.16.190.53/32 scram-sha-256
    - host replication replicator  localhost   scram-sha-256
    - host replication replicator 172.16.190.51/32 scram-sha-256
    - host replication replicator 172.16.190.52/32 scram-sha-256
    - host replication replicator 172.16.190.53/32 scram-sha-256

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 172.16.190.51:5432
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
#    rewind:  # Has no effect on postgres 10 and lower
#      username: rewind_user
#      password: rewind_password
  parameters:
    unix_socket_directories: /var/run/postgresql/

  create_replica_methods:
    - basebackup
  basebackup:
    max-rate: '100M'
    checkpoint: 'fast'

watchdog:
  mode: automatic  # Allowed values: off, automatic, required
  device: /dev/watchdog  # Path to the watchdog device
  safety_margin: 5

tags:
  nosync: false
  noloadbalance: false
  nofailover: false
  clonefrom: false

  # specify a node to replicate from (cascading replication)
#  replicatefrom: (node name)
EOF

# Enable and start the Patroni service
# Включить и запустить службу Patroni
systemctl enable patroni
mkdir /var/log/pgsql
chmod 777 /var/log/pgsql
chown postgres:postgres /var/log/pgsql
# journalctl -u patroni -f
ls -la /var/lib/postgresql/tantor-se-15
sudo chown -R postgres:postgres /var/lib/postgresql/tantor-se-15
sudo chmod 700 /var/lib/postgresql/tantor-se-15/data
systemctl daemon-reload
sudo systemctl restart patroni
systemctl start patroni
sudo systemctl status patroni

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
    bind 172.16.190.51:7000
    stats enable
    stats uri /

listen master
    bind 172.16.190.50:5000
    maxconn 10000
    option tcplog
    option httpchk OPTIONS /primary
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 4 on-marked-down shutdown-sessions
 server astra1 172.16.190.51:5432 check port 8008
 server astra2 172.16.190.52:5432 check port 8008
 server astra3 172.16.190.53:5432 check port 8008

listen replicas
    bind 172.16.190.50:5001
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /replica?lag=100MB
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
 server astra1 172.16.190.51:5432 check port 8008
 server astra2 172.16.190.52:5432 check port 8008
 server astra3 172.16.190.53:5432 check port 8008

listen replicas_sync
    bind 172.16.190.50:5002
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /sync
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
 server astra1 172.16.190.51:5432 check port 8008
 server astra2 172.16.190.52:5432 check port 8008
 server astra3 172.16.190.53:5432 check port 8008

listen replicas_async
    bind 172.16.190.50:5003
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /async?lag=100MB
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
 server astra1 172.16.190.51:5432 check port 8008
 server astra2 172.16.190.52:5432 check port 8008
 server astra3 172.16.190.53:5432 check port 8008
EOF

# Enable and start the HAProxy service
# Включить и запустить службу HAProxy
systemctl enable haproxy.service
systemctl start haproxy.service
systemctl status haproxy.service

# Verify that HAProxy is running
# Проверить, работает ли HAProxy
psql -h 172.16.190.50 -p 5000 -U postgres -c "CREATE TABLE test_table1 (id INT, name TEXT);"
