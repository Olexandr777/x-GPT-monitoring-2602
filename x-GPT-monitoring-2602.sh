#!/usr/bin/env bash

set -e

echo "Updating system..."
sudo apt-get update -y

echo "Installing dependencies..."
sudo apt-get install -y wget tar apt-transport-https software-properties-common

#############################################
# Install Node Exporter
#############################################
echo "Installing Node Exporter..."

NODE_EXPORTER_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep tag_name | cut -d '"' -f 4)

wget https://github.com/prometheus/node_exporter/releases/download/${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION#v}.linux-amd64.tar.gz

tar xvf node_exporter-*.tar.gz
sudo mv node_exporter-*/node_exporter /usr/local/bin/

# systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

#############################################
# Install Prometheus
#############################################
echo "Installing Prometheus..."

PROM_VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep tag_name | cut -d '"' -f 4)

wget https://github.com/prometheus/prometheus/releases/download/${PROM_VERSION}/prometheus-${PROM_VERSION#v}.linux-amd64.tar.gz

tar xvf prometheus-*.tar.gz
cd prometheus-*/ || exit

sudo mv prometheus promtool /usr/local/bin/
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo cp -r consoles console_libraries /etc/prometheus/

# Prometheus config
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: "node"
    static_configs:
      - targets: ["localhost:9100"]
EOF

# systemd service
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus

[Install]
WantedBy=default.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus

cd ..

#############################################
# Install Grafana
#############################################
echo "Installing Grafana..."

wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
sudo apt-get update -y
sudo apt-get install -y grafana

sudo systemctl enable --now grafana-server

#############################################
# Done
#############################################

echo ""
echo "=============================================="
echo " Monitoring stack installed successfully!"
echo ""
echo " Prometheus:     http://localhost:9090"
echo " Node Exporter:  http://localhost:9100/metrics"
echo " Grafana:        http://localhost:3000"
echo ""
echo " Login to Grafana with:"
echo "   user: admin"
echo "   pass: admin"
echo "=============================================="
