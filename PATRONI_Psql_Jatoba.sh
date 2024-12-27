# This file is used to configure the environment and set up the necessary components for installing and configuring Jatoba, ETCD, Patroni, Keepalived, and HAProxy.
# Этот файл используется для настройки окружения и установки необходимых компонентов для установки и настройки Jatoba, ETCD, Patroni, Keepalived и HAProxy.

#### Psql_Jatoba ####

# Create the directory on all nodes
# Создам на всех узлах
mkdir /mnt/jatoba
cd /mnt/jatoba

# Download the distribution on one node and distribute it to the nodes
# Скачиваем на один узел дистриб и распространяем его на узлы
mkdir /localrepo

scp ./jatoba-5.5.3-54782.alt10.tar.gz 10.22.101.112:/localrepo
scp ./jatoba-5.5.3-54782.alt10.tar.gz 10.22.101.113:/localrepo

cd /localrepo
tar -xvf ./jatoba-5.5.3-54782.alt10.tar.gz ./

cd /mnt/jatoba
bash ./jatoba.sh install
[INFO] Основная версия Jatoba 5
# Change the main version of Jatoba [1-9][n] (Default[n]: Enter)? 5
[INFO] Основная версия Jatoba была изменена на 5
# Do you want to install Jatoba (y/n) (Default[y]: Enter)? y
[INFO] Установка Jatoba была начата!
[LICENSE] Set the type of activation, e.g. offline or online?
# Choose the type of activation:
1) online
2) offline
# Enter [1-2]
# Default[2] (Enter): 1
[LICENSE] The type of activation was specified as <offline>
[LICENSE] Set the license key, e.g. XXX-XXX-XXX-XXX? XXXXX-XXXXX-XXXXX-XXX
[LICENSE] The license key was specified as <XXXXX-XXXXX-XXXXX-XXX>
[LICENSE] Set the email, e.g. mail@mail.org? XXX@XXX.ru
[LICENSE] The email address was specified as <XXX@XXXX.ru>
[LICENSE] Set the license server address, e.g. https://lic.ru?
# Default: [https://license.gaz-is.ru] (Enter):
[LICENSE] The license server address was specified as <https://license.gaz-is.ru>

# Installation starts
# Enter the new SUPERUSER_PWD?
# Password (default sql): XXX
# Enter the password again: XXX
ALTER ROLE
[INFO] To find the list of installed packages, use the command: rpm -qa jatoba5*
[INFO] To find the list of available packages, use the command: apt-cache search jatoba5

# Jatoba is installed!

# Checking

systemctl status jatoba-5

su - postgres
psql
select jatoba_version();

# If your license has expired, I sympathize with you, contact Mikhey

# Download the archive with the license from the email XXX@XXXX.ru
# Inside the file, replace the name with .cer
# Connect to the VM with the database in the directory
# /usr/jatoba-5/bin/
# Run /usr/jatoba-5/bin/jactivator
# Choose online re-registration
# /usr/jatoba-5/bin/license.cer
# A code will be sent to your email, enter it
# After this, systemctl start jatoba-5.service
# systemctl enable jatoba-5.service

apt-get update
apt-get install wget

#### ETCD ####
wget https://git.altlinux.org/tasks/322021/build/100/x86_64/rpms/etcd-3.5.9-alt1.x86_64.rpm
apt-get install ./etcd-3.5.9-alt1.x86_64.rpm

# Create the ETCD configuration file
# Создать файл конфигурации ETCD
cat <<EOF > /etc/etcd/etcd.conf
ETCD_NAME="pp_services_1"
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://172.16.150.51:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://172.16.150.51:2380"
ETCD_INITIAL_CLUSTER_TOKEN="cluster"
ETCD_INITIAL_CLUSTER="pp_services_1=http://172.16.150.51:2380,pp_services_2=http://172.16.150.52:2380,pp_services_3=http://172.16.150.53:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_ELECTION_TIMEOUT="5000"
ETCD_HEARTBEAT_INTERVAL="1000"
EOF

# Enable and start the ETCD service
# Включить и запустить службу ETCD
systemctl enable etcd
rm -rf /var/lib/etcd/member/*
service etcd start
systemctl status etcd.service

# Check ETCD status
# Проверить статус ETCD
etcdctl endpoint status --write-out=table
etcdctl member list --write-out=table
etcdctl cluster-health # для старой версии ETCD
etcdctl endpoint health # для новой

# Disable Jatoba and clear data
# Отключить Jatoba и очистить данные
systemctl disable jatoba
rm -rf /var/lib/jatoba/5/data/*
ls -la /var/lib/jatoba/5/data/

#### Patroni ####

# Install Patroni
# Установить Patroni
apt-get install patroni
systemctl edit --full --force patroni.service

# Create the Patroni systemd service file
# Создать файл систеmd службы Patroni
cat <<EOF > /lib/systemd/system/patroni.service
[Unit]
Description=Runners to orchestrate a high-availability PostgreSQL
After=network.target
ConditionPathExists=/etc/patroni/patroni.yml

[Service]
Type=simple

User=postgres
Group=postgres

# Read in configuration file if it exists, otherwise proceed
# Прочитать файл конфигурации, если он существует, в противном случае продолжить
EnvironmentFile=-/etc/patroni_env.conf

# the default is the user's home directory, and if you want to change it, you must provide an absolute path.
# WorkingDirectory=/home/sameuser

# Pre-commands to start watchdog device
# Uncomment if watchdog is part of your patroni setup
#ExecStartPre=-/usr/bin/sudo /sbin/modprobe softdog
#ExecStartPre=-/usr/bin/sudo /bin/chown postgres /dev/watchdog

# Start the patroni process
# Запустить процесс patroni
ExecStart=/usr/bin/patroni /etc/patroni/patroni.yml

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

# Reload the systemd daemon and enable Patroni
# Перезагрузить демон systemd и включить Patroni
systemctl daemon-reload
systemctl enable patroni
mkdir /etc/patroni
chmod 777 /etc/patroni
chown postgres:postgres /etc/patroni

# Edit the Patroni configuration file
# Редактировать файл конфигурации Patroni
nano /etc/patroni/patroni.yml

scope: cluster
name: patroni1
namespace: /service

restapi:
  listen: 0.0.0.0:8008
  connect_address: 172.16.150.51:8008
#  certfile: /etc/ssl/certs/ssl-cert-snakeoil.pem
#  keyfile: /etc/ssl/private/ssl-cert-snakeoil.key
#  authentication:
#    username: patroni
#    password: cluster

etcd3:
  hosts: 172.16.150.51:2379,172.16.150.52:2379,172.16.150.53:2379

# shared_buffers: Memory allocated for PostgreSQL buffers. Usually recommended around 25% of total memory.
# effective_cache_size: Memory available for data caching by the operating system. Usually set to 50-75% of total memory.
# work_mem: Memory allocated for sorting and hashing in queries. Recommended value is 1 to 2% of total memory per CPU.
# maintenance_work_mem: Memory for maintenance operations such as vacuuming and index creation. Usually set to 5-10% of total memory.
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
      use_slots: true
      parameters:
        max_connections: 500
        superuser_reserved_connections: 5
        password_encryption: scram-sha-256
        max_locks_per_transaction: 512
        max_prepared_transactions: 0
        huge_pages: try
        shared_buffers: 4GB  # 25% от 16 GB
        effective_cache_size: 12GB  # 75% от 16 GB
        work_mem: 32MB  # 2% от 16 GB / 8 CPU
        maintenance_work_mem: 1GB  # 6.25% от 16 GB
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
        archive_command: cd .
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
        max_worker_processes: 16  # 2 * CPU
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
#    - psql -c "CREATE USER navigator WITH SUPERUSER PASSWORD 'password';"
#    - psql -c "GRANT ALL PRIVILEGES ON SCHEMA public TO navigator;"
#    - psql -c "CREATE DATABASE navigator_base;"
#    - psql -c "CREATE USER user2u WITH PASSWORD 'XXX';"
#    - psql -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO user2u;"

  pg_hba:  # Add following lines to pg_hba.conf after running 'initdb'
  # - host all all 192.168.113.200/32 md5
    - local   all             all                                     trust
    - local   replication     all                                     trust
    - host    replication     all             127.0.0.1/32            trust
    - host    replication     all             ::1/128                 trust
    - host replication replicator 127.0.0.1/32 scram-sha-256
    - local replication postgres    scram-sha-256
    - host all navigator 172.16.150.51/32 scram-sha-256
    - host all postgres 172.16.150.51/32 scram-sha-256
    - host all user2u 172.16.150.51/32 scram-sha-256
    - host all navigator 172.16.150.52/32 scram-sha-256
    - host all postgres 172.16.150.52/32 scram-sha-256
    - host all user2u 172.16.150.52/32 scram-sha-256
    - host all navigator 172.16.150.53/32 scram-sha-256
    - host all postgres 172.16.150.53/32 scram-sha-256
    - host all user2u 172.16.150.53/32 scram-sha-256
    - host replication replicator  localhost   scram-sha-256
    - host replication replicator 172.16.150.51/32 scram-sha-256
    - host replication replicator 172.16.150.52/32 scram-sha-256
    - host replication replicator 172.16.150.53/32 scram-sha-256

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 172.16.150.51:5432
  use_unix_socket: true
  data_dir: /var/lib/jatoba/5/data/
  bin_dir: /usr/jatoba-5/bin/
  config_dir: /var/lib/jatoba/5/data/
  pgpass: /var/lib/jatoba/5/.pgpass_patroni

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
    unix_socket_directories: /var/run/jatoba

  remove_data_directory_on_rewind_failure: false
  remove_data_directory_on_diverged_timelines: false

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

# Create the log directory for Patroni
# Создать директорию журналов для Patroni
mkdir /var/log/pgsql
chmod 777 /var/log/pgsql
chown postgres:postgres /var/log/pgsql

####
Previously, we take a piece of the license in the postgresql.conf file
####

lic_product_name = 'Jatoba'
lic_file_path = '/usr/jatoba-5/bin/jatoba.cer'
lic_server_addr = https://license.gaz-is.ru
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'jatoba-%a.log'
log_rotation_age = 1d
log_rotation_size = 0
log_truncate_on_rotation = on
log_line_prefix = '%m [%p] '

####
rm -rf /var/lib/jatoba/5/data*
systemctl start patroni
nano /var/lib/jatoba/5/data/postgresql.conf insert the license block at the end of the config
systemctl restart patroni
systemctl status patroni
patronictl -c /etc/patroni/patroni.yml list

#### Keepalived ####

# Install Keepalived
# Установить Keepalived
apt-get install keepalived

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
   interface ens3
   virtual_router_id 50
   priority  100
   advert_int 2
   state  BACKUP
   virtual_ipaddress {
       172.16.150.50
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
    user _haproxy
    group _haproxy
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
    bind 172.16.150.51:7000
    stats enable
    stats uri /

listen master
    bind 172.16.150.50:5000
    maxconn 10000
    option tcplog
    option httpchk OPTIONS /primary
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 4 on-marked-down shutdown-sessions
 server SQLjatoba1 172.16.150.51:5432 check port 8008
 server SQLjatoba2 172.16.150.52:5432 check port 8008
 server SQLjatoba3 172.16.150.53:5432 check port 8008

listen replicas
    bind 172.16.150.50:5001
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /replica?lag=100MB
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
 server SQLjatoba1 172.16.150.51:5432 check port 8008
 server SQLjatoba2 172.16.150.52:5432 check port 8008
 server SQLjatoba3 172.16.150.53:5432 check port 8008

listen replicas_sync
    bind 172.16.150.50:5002
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /sync
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
 server SQLjatoba1 172.16.150.51:5432 check port 8008
 server SQLjatoba2 172.16.150.52:5432 check port 8008
 server SQLjatoba3 172.16.150.53:5432 check port 8008

listen replicas_async
    bind 172.16.150.50:5003
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /async?lag=100MB
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
 server SQLjatoba1 172.16.150.51:5432 check port 8008
 server SQLjatoba2 172.16.150.52:5432 check port 8008
 server SQLjatoba3 172.16.150.53:5432 check port 8008
EOF

# Enable and start the HAProxy service
# Включить и запустить службу HAProxy
systemctl enable haproxy.service
systemctl start haproxy.service
systemctl status haproxy.service

# Verify that HAProxy is running
# Проверить, работает ли HAProxy
psql -h 172.16.150.50 -p 5000 -U postgres -c "CREATE TABLE test_table1 (id INT, name TEXT);"