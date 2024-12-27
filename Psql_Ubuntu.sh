# This file is used to prepare the machines (2 networks: 1 internal network not controlled by Kubernetes, 1 public network)
# Этот файл используется для подготовки машин (2 сети: 1 внутренняя сеть, не контролируемая Kubernetes, 1 публичная сеть)

#### как делал для ubuntu
# Prepare the machines (2 networks: 1 internal network not controlled by Kubernetes, 1 public network)
# Подготовливаем машины (2 сети: 1 внутренняя сеть, не контролируемая Kubernetes, 1 публичная сеть)
https://github.com/big-town/ha-cluster
# Setup ETCD on separate 3 machines besides openssh-server, you need to install etcd-server etcd-client
# Настройка ETCD на отдельных 3 машинах помимо openssh-server, нужно поставить etcd-server etcd-client
apt install etcd-server -y
# Install the configuration from GitHub
# Установить конфигурацию с GitHub
nano /etc/default/etcd

ETCD_NAME="pp_services_1"
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://10.101.10.101:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.101.10.101:2380"
ETCD_INITIAL_CLUSTER_TOKEN="XXX"
ETCD_INITIAL_CLUSTER="pp_services_1=http://10.101.10.101:2380,pp_services_2=http://10.101.10.101:2380,pp_services_3=http://10.101.10.101:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_ELECTION_TIMEOUT="5000"
ETCD_HEARTBEAT_INTERVAL="1000"
# Start the ETCD service
# Запускаем сервис ETCD
service etcd start
# Check the ETCD service status
# Проверяем статус сервиса ETCD
service etcd status
# If something goes wrong, in our case 1 out of 3 machines started
# Если что-то пошло не так, в нашем случае 1 из 3 машин начала
# ругаться на невозможность записи в каталог
# /var/lib/etcd/ #дал права chmod 777 на директорию
# Check the voting status
# Проверяем статус голосования
etcdctl member list
# Check the cluster status
# Проверяем состояние кластера
etcdctl cluster-health
# Create 2 more machines for the databases/patroni
# Создаю еще 2 машины под базы/patroni
# Install PostgreSQL on Ubuntu
# Установка PostgreSQL на Ubuntu
apt install postgresql postgresql-contrib -y
# Start the PostgreSQL service
# Запускаем сервис PostgreSQL
systemctl start postgresql.service
systemctl status postgresql.service
# Disable PostgreSQL as a standalone service, now the database will be managed by Patroni
# Отключаем PostgreSQL как самостоятельный сервис, теперь базой будет управлять Patroni
systemctl disable postgresql
# Install Patroni from the repository
# Установка Patroni из репозитория
echo "deb [arch=amd64] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/postgresql.list
# Add the key
# Добавляем ключ
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
# Install Patroni
# Установка Patroni
apt-get install patroni
# Install the latest version of Patroni using pip
# Установить самую свежую версию Patroni, установить через pip
# apt install python3-pip -y
# pip3 install patroni
# Create the Patroni service
# Создать сервис Patroni
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

# Reload the services
# Перезагружаем сервисы
systemctl daemon-reload
# Enable the service to start on boot
# Добавляем сервис в автозапуск
systemctl enable patroni
# Create the Patroni configuration file
# Создать файл конфигурации Patroni
nano /etc/patroni/patroni.yml # Take the configuration from GitHub, be sure to specify the path to the database, it will be different for everyone

scope: pg-ha-cluster
name: pp_pg_2

log:
  level: WARNING
  format: '%(asctime)s %(levelname)s: %(message)s'
  dateformat: ''
  max_queue_size: 1000
  dir: /var/log/postgresql
  file_num: 4
  file_size: 25000000
  loggers:
    postgres.postmaster: WARNING
    urllib3: DEBUG

restapi:
  listen: 0.0.0.0:8008
  connect_address: 10.101.10.102:8008

etcd:
  hosts:
  - 10.101.10.51:2379
  - 10.101.10.52:2379
  - 10.101.10.53:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 0
    synchronous_mode: true
    synchronous_mode_strict: false
    postgresql:
#      recovery_conf:
#        restore_command: /usr/local/bin/restore_wal.sh %p %f
#        recovery_target_time: '2021-06-11 13:20:00'
#        recovery_target_action: promote
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: 200
        shared_buffers: 2GB
        effective_cache_size: 6GB
        maintenance_work_mem: 512MB
        checkpoint_completion_target: 0.7
        wal_buffers: 16MB
        default_statistics_target: 100
        random_page_cost: 1.1
        effective_io_concurrency: 200
        work_mem: 2621kB
        min_wal_size: 1GB
        max_wal_size: 4GB
        max_worker_processes: 40
        max_parallel_workers_per_gather: 4
        max_parallel_workers: 40
        max_parallel_maintenance_workers: 4

        max_locks_per_transaction: 64
        max_prepared_transactions: 0
        wal_level: replica
        wal_log_hints: on
        track_commit_timestamp: off
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_segments: 8
        logging_collector: on
        log_destination: csvlog
        log_directory: pg_log
        log_min_messages: warning
        log_min_error_statement: error
        log_min_duration_statement: 1000
        log_duration: off
        log_statement: all

  initdb:
  - encoding: UTF8
  - data-checksums

  pg_hba:
  - host all postgres all md5
  - host replication repl all md5

  users:
    postgres:
      password: mypassword
      options:
        - createrole
        - createdb
    repl:
      password: mypassword
      options:
        - replication

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 10.101.10.102:5432
  data_dir: /var/lib/postgresql/12/main
  bin_dir: /usr/lib/postgresql/12/bin
  config_dir: /var/lib/postgresql/12/main
  pgpass: /var/lib/postgresql/.pgpass
  pg_hba:
    - host all postgres 0.0.0.0/0 md5
    - local all all trust
    - host replication repl all md5
  authentication:
    replication:
      username: repl
      password: mypassword
    superuser:
      username: postgres
      password: mypassword
  parameters:
#   archive_mode: on
#   archive_command: /usr/local/bin/copy_wal.sh %p %f
#   archive_timeout: 600
    unix_socket_directories: '/var/run/postgresql'
    port: 5432

# Upload the scripts for archiving
# Закидываем скрипты для архивации
# nano /usr/local/bin/copy_wal.sh
# nano /usr/local/bin/restore_wal.sh
# Make the files executable
# Делаем файлы исполняемыми
# chmod a+x /usr/local/bin/copy_wal.sh
# chmod a+x /usr/local/bin/restore_wal.sh
# Reinstall pip
# Переустановка pip
# curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
# python3 get-pip.py --force-reinstall

# Remove files from the main directory
# Удаляем файлы из каталога main
rm -rf /var/lib/postgresql/14/main/
# Start the Patroni service on the master
# Запускаем сервис Patroni на мастере
service patroni start
# Install the HAProxy service
# Установка сервиса HAProxy
apt update
apt install haproxy
systemctl enable haproxy
nano /etc/haproxy/haproxy.cfg

global
    maxconn 100000
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
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
    bind 10.102.10.101:7000
    stats enable
    stats uri /

listen master
    bind 10.22.4.153:5000
    maxconn 10000
    option tcplog
    option httpchk OPTIONS /primary
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 4 on-marked-down shutdown-sessions
    server patroni4 10.102.10.101:5432 check port 8008
    server patroni5 10.102.10.102:5432 check port 8008
    server patroni6 10.102.10.103:5432 check port 8008

listen replicas
    bind 10.22.4.153:5001
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /replica?lag=100MB
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
    server patroni4 10.102.10.101:5432 check port 8008
    server patroni5 10.102.10.102:5432 check port 8008
    server patroni6 10.102.10.103:5432 check port 8008

listen replicas_sync
    bind 10.22.4.153:5002
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /sync
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
    server patroni4 10.102.10.101:5432 check port 8008
    server patroni5 10.102.10.102:5432 check port 8008
    server patroni6 10.102.10.103:5432 check port 8008

listen replicas_async
    bind 10.22.4.153:5003
    maxconn 10000
    option tcplog
        option httpchk OPTIONS /async?lag=100MB
        balance roundrobin
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 2 on-marked-down shutdown-sessions
    server patroni4 10.102.10.101:5432 check port 8008
    server patroni5 10.102.10.102:5432 check port 8008
    server patroni6 10.102.10.103:5432 check port 8008

# Check HAProxy operation
# Проверяем работу HAProxy
psql -h 10.22.4.153 -p 5000 -U postgres -c "select pg_is_in_recovery()"