# This file is used to configure the environment and set up cron jobs for backing up and restoring PostgreSQL databases using Patroni and WAL-G.
# Этот файл используется для настройки окружения и установки cron задач для резервного копирования и восстановления баз данных PostgreSQL с использованием Patroni и WAL-G.

# Set the default text editor to nano
# Установить текстовый редактор по умолчанию на nano
export VISUAL=nano
export EDITOR="$VISUAL"

# Open the crontab file for editing
# Открыть файл crontab для редактирования
sudo nano /etc/crontab

# Set the PATH environment variable
# Установить переменную окружения PATH
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:

# Edit the sudoers file to allow the postgres user to run commands without a password
# Редактировать файл sudoers, чтобы позволить пользователю postgres выполнять команды без пароля
visudo

# Allow the postgres user to run any command without a password
# Разрешить пользователю postgres выполнять любые команды без пароля
postgres ALL=(ALL:ALL) ALL
postgres ALL=(ALL) NOPASSWD: ALL

# All further actions should be performed as the postgres user
# Все дальнейшие действия должны выполняться от имени пользователя postgres

#### Backup section ####
# Install jq for JSON processing
# Установить jq для обработки JSON
sudo apt install jq  # For Debian/Ubuntu
sudo yum install jq  # For RHEL/CentOS

# Create a backup script
# Создать скрипт резервного копирования
nano patroni_leader_backup.sh

#!/bin/bash

# Set the PATH environment variable
# Установить переменную окружения PATH
export PATH=/opt/tantor/db/15/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:

# Exit immediately if a command exits with a non-zero status
# Прекратить выполнение при ошибке
set -e

# Data directory path
# Путь до дата директории
DATA_DIR="/var/lib/postgresql/tantor-se-15/data"

# Patroni configuration file path
# Путь к конфигурации Patroni
CONFIG_FILE="/etc/patroni/config.yml"

# Check for required tools
# Проверка наличия необходимых инструментов
for cmd in patronictl jq wal-g; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd not found. Ensure it is installed and available in PATH."
        echo "Ошибка: $cmd не найден. Убедитесь, что он установлен и доступен в PATH."
        exit 1
    fi
done

# Get all IP addresses of the current host
# Получение всех IP-адресов текущего хоста
CURRENT_IPS=$(hostname -I) || { echo "Failed to get IP addresses."; echo "Не удалось получить IP-адреса."; exit 1; }

# Get the leader IP from patronictl list
# Получение строки с лидером из patronictl list
LEADER_IP=$(patronictl -c "$CONFIG_FILE" list --format json | jq -r '.[] | select(.Role == "Leader") | .Host') || { echo "Failed to get leader IP."; echo "Не удалось получить IP лидера."; exit 1; }

# Check if the leader IP is in the list of current host IPs
# Проверка, содержится ли IP лидера в списке IP текущего хоста
if echo "$CURRENT_IPS" | grep -qw "$LEADER_IP"; then
    echo "$(date): Current node is the leader. Starting WAL-G backup..."
    echo "$(date): Текущий узел является лидером. Начало резервного копирования WAL-G..."
    wal-g backup-push "$DATA_DIR" -f || { echo "WAL-G backup failed."; echo "Ошибка выполнения WAL-G backup."; exit 1; }
    echo "$(date): Backup completed successfully."
    echo "$(date): Резервное копирование завершено успешно."
else
    echo "$(date): Current node is not the leader. No backup performed."
    echo "$(date): Текущий узел не является лидером. Резервное копирование не выполнено."
fi

# Make the backup script executable
# Сделать скрипт резервного копирования исполняемым
sudo chmod +x /var/lib/postgresql/patroni_leader_backup.sh

# Edit the crontab file to schedule the backup script
# Редактировать файл crontab для планирования скрипта резервного копирования
sudo nano /etc/crontab

# /etc/crontab: system-wide crontab
# Unlike any other crontab you don't have to run the `crontab'
# command to install the new version when you edit this file
# and files in /etc/cron.d. These files also have username fields,
# that none of the other crontabs do.

SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin:/usr/bin

# Schedule the backup script to run every 3 hours
# Запланировать выполнение скрипта резервного копирования каждые 3 часа
0 */3 * * * postgres /var/lib/postgresql/patroni_leader_backup.sh >> /var/log/patroni_backup.log 2>&1
#*/2 * * * * postgres /var/lib/postgresql/patroni_leader_backup.sh >> /var/log/patroni_backup.log 2>&1

# Example of job definition:
# .---------------- minute (0 - 59)
# |  .------------- hour (0 - 23)
# |  |  .---------- day of month (1 - 31)
# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# |  |  |  |  |
# *  *  *  *  * user-name command to be executed
17 *    * * *   root    cd / && run-parts --report /etc/cron.hourly
25 6    * * *   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.daily )
47 6    * * 7   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.weekly )
52 6    1 * *   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.monthly )
#

######## Before recovery, Patroni must be disabled on non-Leader nodes
#### All actions should be performed as the postgres user
# Перед восстановлением нужно отключить Patroni на остальных нодах, которые не являются Leader
# Все действия должны выполняться от имени пользователя postgres

# Create a recovery script
# Создать скрипт восстановления
nano patroni_leader_recovery.sh

#!/bin/bash

# Exit immediately if a command exits with a non-zero status
# Прекратить выполнение при ошибке
set -e

# Data directory path
# Путь до дата директории
DATA_DIR="/var/lib/postgresql/tantor-se-15/data"

# Patroni configuration file path
# Путь к конфигурации Patroni
CONFIG_FILE="/etc/patroni/config.yml"

# Check for available backups
# Проверка наличия бэкапов
echo "Getting the list of available backups..."
echo "Получение списка доступных бэкапов..."
wal-g backup-list || { echo "No backups found."; echo "Бэкапы не найдены."; exit 1; }

# Ask the user to select a backup
# Просьба пользователю выбрать бэкап
read -p "Enter the backup name to restore (or LATEST for the latest): " backup
read -p "Введите имя бэкапа для восстановления (или LATEST для последнего): " backup

if [[ -z "$backup" ]]; then
    echo "Backup name not entered. Exiting."
    echo "Имя бэкапа не введено. Завершение."
    exit 1
fi

# Stop Patroni on the current node
# Остановка Patroni на текущей ноде
echo "Stopping Patroni on the current node..."
echo "Остановка Patroni на текущей ноде..."
sudo systemctl stop patroni
wait

# Check the cluster status
# Проверка состояния кластера
echo "Patroni node list before cluster removal:"
echo "Список нод Patroni перед удалением кластера:"
patronictl -c "$CONFIG_FILE" list

# Remove the cluster using expect for automatic confirmation
# Удаление кластера с использованием expect для автоматического подтверждения
echo "Removing cluster Cluster2U..."
echo "Удаление кластера Cluster2U..."
expect <<EOF
spawn patronictl -c "$CONFIG_FILE" remove Cluster2U
expect "Please confirm the cluster name to remove:"
send "Cluster2U\n"
expect "You are about to remove all information in DCS for Cluster2U, please type: \"Yes I am aware\":"
send "Yes I am aware\n"
expect eof
EOF

# Check the cluster status: should be uninitialized
# Проверка состояния кластера: должен быть uninitialized
if ! patronictl -c "$CONFIG_FILE" list | grep -q "uninitialized"; then
    echo "Cluster is not in uninitialized state. Exiting with error."
    echo "Кластер не находится в состоянии uninitialized. Завершение с ошибкой."
    exit 1
fi

# Clear the data directory
# Очистка директории данных
echo "Clearing the data directory..."
echo "Очистка директории данных..."
rm -rf "$DATA_DIR"/*
wait

# Restore the backup
# Восстановление бэкапа
echo "Restoring backup $backup..."
echo "Восстановление бэкапа $backup..."
wal-g backup-fetch "$DATA_DIR" "$backup"
wait

# Create the recovery signal file
# Создание сигнального файла
echo "Creating recovery.signal..."
echo "Создание recovery.signal..."
touch "$DATA_DIR"/recovery.signal

# Start Patroni
# Запуск Patroni
echo "Starting Patroni..."
echo "Запуск Patroni..."
sudo systemctl start patroni
wait

# Check the status after recovery
# Проверка состояния после восстановления
echo "Patroni status after recovery:"
echo "Состояние Patroni после восстановления:"
patronictl -c "$CONFIG_FILE" list

echo "Recovery completed."
echo "Восстановление завершено."

####

# Make the recovery script executable
# Сделать скрипт восстановления исполняемым
chmod 777 /path/to/patroni_leader_recovery.sh
chmod +x /path/to/patroni_leader_recovery.sh

# Run the recovery script and log the output
# Запустить скрипт восстановления и записать вывод в лог
/path/to/patroni_leader_recovery.sh >> /var/log/patroni_recovery.log 2>&1