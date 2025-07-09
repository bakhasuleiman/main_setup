#!/bin/bash

LOG_FILE="/var/log/monitoring-setup.log"
exec > >(tee -a $LOG_FILE) 2>&1

function install_stack() {
  echo "Installing Monitoring Stack..."
  install_docker
  install_docker_compose
  create_users_and_directories
  setup_prometheus
  setup_grafana
  setup_zabbix
  setup_urbackup
  configure_docker_compose
  enable_autostart
}

function install_docker() {
  echo "Installing Docker..."
  if [[ $(lsb_release -si) == "Ubuntu" ]]; then
    sudo apt update
    sudo apt install -y \
      ca-certificates \
      curl \
      gnupg \
      lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif [[ $(lsb_release -si) == "Arch" ]]; then
    sudo pacman -Syu --noconfirm
    sudo pacman -S --noconfirm docker docker-compose
  fi

  sudo systemctl enable --now docker.service
  echo "Docker installed successfully!"
}

function install_docker_compose() {
  echo "Installing Docker Compose..."
  if ! command -v docker-compose &> /dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.16.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  fi
  echo "Docker Compose installed successfully!"
}

function create_users_and_directories() {
  echo "Creating system users and directories..."

  # Создаем пользователей
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin prometheus
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin grafana
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin zabbix
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin urbackup

  # Создаем директории для данных
  sudo mkdir -p /opt/data/{prometheus,grafana,zabbix,urbackup}

  # Устанавливаем владельцев и права
  sudo chown -R prometheus:prometheus /opt/data/prometheus
  sudo chown -R grafana:grafana /opt/data/grafana
  sudo chown -R zabbix:zabbix /opt/data/zabbix
  sudo chown -R urbackup:urbackup /opt/data/urbackup
  sudo chmod -R 750 /opt/data/*

  echo "Users and directories created successfully!"
}

function setup_prometheus() {
  echo "Setting up Prometheus..."
  sudo mkdir -p /opt/monitoring-stack/prometheus
  sudo nano /opt/monitoring-stack/prometheus/prometheus.yml
  # Добавить конфигурацию Prometheus в prometheus.yml (вместо nano можно использовать echo для автоматизации)

  sudo docker-compose up -d prometheus
  echo "Prometheus setup completed!"
}

function setup_grafana() {
  echo "Setting up Grafana..."
  sudo docker-compose up -d grafana
  echo "Grafana setup completed!"
}

function setup_zabbix() {
  echo "Setting up Zabbix..."
  sudo docker-compose up -d zabbix-db zabbix-server zabbix-web
  echo "Zabbix setup completed!"
}

function setup_urbackup() {
  echo "Setting up UrBackup..."
  sudo docker-compose up -d urbackup
  echo "UrBackup setup completed!"
}

function configure_docker_compose() {
  echo "Configuring Docker Compose..."

  cat <<EOF > /opt/monitoring-stack/docker-compose.yml
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    user: "967:966"
    volumes:
      - /opt/data/prometheus:/prometheus
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    ports:
      - "9090:9090"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    user: "963:962"
    ports:
      - "3000:3000"
    volumes:
      - /opt/data/grafana:/var/lib/grafana
    depends_on:
      - prometheus
    restart: unless-stopped

  zabbix-db:
    image: postgres:13
    container_name: zabbix-db
    environment:
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbixpass
      POSTGRES_DB: zabbix
    volumes:
      - /opt/data/zabbix:/var/lib/postgresql/data
    restart: unless-stopped

  zabbix-server:
    image: zabbix/zabbix-server-pgsql:latest
    container_name: zabbix-server
    environment:
      DB_SERVER_HOST: zabbix-db
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbixpass
    depends_on:
      - zabbix-db
    ports:
      - "10051:10051"
    restart: unless-stopped

  zabbix-web:
    image: zabbix/zabbix-web-nginx-pgsql:latest
    container_name: zabbix-web
    environment:
      DB_SERVER_HOST: zabbix-db
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbixpass
      ZBX_SERVER_HOST: zabbix-server
    depends_on:
      - zabbix-server
    ports:
      - "8080:8080"
    restart: unless-stopped

  urbackup:
    image: uroni/urbackup-server
    container_name: urbackup
    ports:
      - "55413:55413"
      - "55414:55414"
    volumes:
      - /opt/data/urbackup:/backups
    restart: unless-stopped
EOF
  echo "Docker Compose file configured!"
}

function enable_autostart() {
  echo "Enabling autostart..."
  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl enable --now docker.service
  echo "Autostart enabled!"
}

PS3='Please enter your choice: '
options=("Install Stack" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "Install Stack")
            install_stack
            ;;
        "Quit")
            break
            ;;
        *)
            echo "Invalid option $REPLY"
            ;;
    esac
done
