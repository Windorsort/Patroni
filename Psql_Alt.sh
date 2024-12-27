# This file is used to update the system and install necessary packages for setting up ETCD, Patroni, Keepalived, and HAProxy.
# Этот файл используется для обновления системы и установки необходимых пакетов для настройки ETCD, Patroni, Keepalived и HAProxy.

apt-get update
apt-get install wget
apt-get install haproxy
apt-get install patroni
apt-get install keepalived
apt-get install postgresql16 postgresql16-server postgresql16-contrib
apt-get install ./etcd-3.5.9-alt1.x86_64.rpm
apt-get install python3-module-etcd3
apt-get install wget
apt-get install curl
apt-get install nano
apt-get install docker-engine
apt-get install docker-compose
apt-get install -y python3-module-pip sshpass git
pip3 install ansible
wget https://git.altlinux.org/tasks/322021/build/100/x86_64/rpms/etcd-3.5.9-alt1.x86_64.rpm

# Configure the ETCD service
# Настроить сервис ETCD
nano /etc/etcd/etcd.conf

ETCD_NAME="pp_services_1"
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.155.131:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.155.131:2380"
ETCD_INITIAL_CLUSTER_TOKEN="cluster"
ETCD_INITIAL_CLUSTER="pp_services_1=http://192.168.155.131:2380,pp_services_2=http://192.168.155.132:2380,pp_services_3=http://192.168.155.133:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_ELECTION_TIMEOUT="5000"
ETCD_HEARTBEAT_INTERVAL="1000"
ETCD_ENABLE_V2

# Remove any existing ETCD member data and start the service
# Удалить любые существующие данные участника ETCD и запустить службу
rm -rf /var/lib/etcd/member/*
service etcd start
systemctl enable etcd
systemctl status etcd.service
etcdctl endpoint status --write-out=table

# Initialize PostgreSQL and start the service
# Инициализировать PostgreSQL и запустить службу
/etc/init.d/postgresql initdb
service postgresql start
systemctl status postgresql.service
systemctl disable postgresql
rm -rf /var/lib/pgsql/data/*

# Configure the Patroni service
# Настроить службу Patroni
systemctl edit --full --force patroni.service

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

# Enable and start the Patroni service
# Включить и запустить службу Patroni
systemctl enable patroni
mkdir /etc/patroni
chmod 777 /etc/patroni
chown postgres:postgres /etc/patroni
nano /etc/patroni/patroni.yml

scope: cluster
name: patroni1
namespace: /service

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.155.131:8008
  authentication:
    username: patroni
    password: cluster

etcd3:
  hosts: 192.168.155.131:2379,192.168.155.132:2379,192.168.155.133:2379

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
        shared_buffers: 8021MB
        effective_cache_size: 24063MB
        work_mem: 128MB
        maintenance_work_mem: 256MB
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
        log_directory: /var/log/pgsql
        hot_standby_feedback: on
        max_standby_streaming_delay: 30s
        wal_receiver_status_interval: 10s
        idle_in_transaction_session_timeout: 10min
        jit: off
        max_worker_processes: 24
        max_parallel_workers: 8
        max_parallel_workers_per_gather: 2
        max_parallel_maintenance_workers: 2
        tcp_keepalives_count: 10
        tcp_keepalives_idle: 300
        tcp_keepalives_interval: 30

  initdb:  # List options to be passed on to initdb
    - encoding: UTF8
    - locale: en_US.UTF-8
    - data-checksums

  pg_hba:  # Add following lines to pg_hba.conf after running 'initdb'
    - local all postgres    trust
    - local all pgbouncer   trust
    - local replication postgres    trust
    - host  all all 192.168.155.131/32  scram-sha-256
    - host  all all 192.168.155.132/32  scram-sha-256
    - host  all all 192.168.155.133/32  scram-sha-256
    - host  replication replicator  localhost   trust
    - host  replication replicator  192.168.155.131/32  scram-sha-256
    - host  replication replicator  192.168.155.132/32  scram-sha-256
    - host  replication replicator  192.168.155.133/32  scram-sha-256

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.155.131:5432
  use_unix_socket: true
  data_dir: /var/lib/pgsql/data/
  bin_dir: /usr/bin/
  config_dir: /var/lib/pgsql/data/
  pgpass: /var/lib/pgsql/.pgpass_patroni
  authentication:
    replication:
      username: replicator
      password: cluster
    superuser:
      username: postgres
      password: cluster
  parameters:
    unix_socket_directories: /var/lib/pgsql/

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

# Create the log directory for Patroni and start the service
# Создать директорию журналов для Patroni и запустить службу
mkdir /var/log/pgsql
chmod 777 /var/log/pgsql
chown postgres:postgres /var/log/pgsql
systemctl start patroni
systemctl status patroni
patronictl -c /etc/patroni/patroni.yml list

# Configure the Keepalived service
# Настроить сервис Keepalived
nano /etc/keepalived/keepalived.conf

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
   virtual_router_id 220
   priority  100
   advert_int 2
   state  BACKUP
   virtual_ipaddress {
       192.168.155.220
   }
   track_script {
       haproxy_check
   }
   authentication {
      auth_type PASS
      auth_pass cluster
   }
}

# Enable and start the Keepalived service
# Включить и запустить службу Keepalived
systemctl enable keepalived
systemctl start keepalived
systemctl status keepalived
ip -br a

# Configure the HAProxy service
# Настроить сервис HAProxy
nano /etc/haproxy/haproxy.cfg

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
    bind 192.168.155.131:7000
    stats enable
    stats uri /

listen master
    bind 192.168.155.220:5000
    maxconn 10000
    option tcplog
    option httpchk OPTIONS /primary
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 4 on-marked-down shutdown-sessions
    server patronialt4 192.168.155.131:5432 check port 8008
    server patronialt5 192.168.155.132:5432 check port 8008
    server patronialt6 192.168.155.133:5432 check port 8008

listen replicas
    bind 192.168.155.220:5001
    maxconn 10000
    option tcplog
    option httpchk OPTIONS /replica?lag=100MB
    balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
    server patronialt4 192.168.155.131:5432 check port 8008
    server patronialt5 192.168.155.132:5432 check port 8008
    server patronialt6 192.168.155.133:5432 check port 8008

listen replicas_sync
    bind 192.168.155.220:5002
    maxconn 10000
    option tcplog
    option httpchk OPTIONS /sync
    balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
    server patronialt4 192.168.155.131:5432 check port 8008
    server patronialt5 192.168.155.132:5432 check port 8008
    server patronialt6 192.168.155.133:5432 check port 8008

listen replicas_async
    bind 192.168.155.220:5003
    maxconn 10000
    option tcplog
    option httpchk OPTIONS /async?lag=100MB
    balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
    server patronialt4 192.168.155.131:5432 check port 8008
    server patronialt5 192.168.155.132:5432 check port 8008
    server patronialt6 192.168.155.133:5432 check port 8008

# Enable and start the HAProxy service
# Включить и запустить службу HAProxy
systemctl enable haproxy.service
systemctl start haproxy.service
systemctl status haproxy.service

# Verify that HAProxy is running
# Проверить, работает ли HAProxy
psql -h 192.168.155.220 -p 5000 -U postgres -c "CREATE TABLE test_table1 (id INT, name TEXT);"