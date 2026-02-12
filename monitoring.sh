#!/bin/bash
#
# Minimal Monitoring Stack Setup (Prometheus + Node Exporter + Grafana)
# Compact, single-file script for Linux environments (codespaces, VMs, containers)
# Usage: bash monitoring.sh [install|start|stop|status|cleanup]
#

set -e

# Configuration
INSTALL_DIR="${HOME}/.monitoring"
PROMETHEUS_VERSION="2.50.0"
NODE_EXPORTER_VERSION="1.7.0"
GRAFANA_VERSION="10.2.2"
PROMETHEUS_PORT=9090
NODE_EXPORTER_PORT=9100
GRAFANA_PORT=3000

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Utility functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

check_requirements() {
    log_info "Checking requirements..."
    
    # Check if we have curl and wget
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed."
        exit 1
    fi
    
    # Check if ports are available
    for port in $PROMETHEUS_PORT $NODE_EXPORTER_PORT $GRAFANA_PORT; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_warn "Port $port is already in use"
        fi
    done
}

install_prometheus() {
    log_info "Installing Prometheus..."
    
    # Try apt with sudo (most reliable)
    if command -v apt-get &> /dev/null; then
        log_info "Attempting to install Prometheus via apt..."
        
        # Try with sudo if available
        if command -v sudo &> /dev/null; then
            if sudo -n true 2>/dev/null; then
                # sudo available without password
                sudo apt-get update -qq > /dev/null 2>&1 || true
                if sudo apt-get install -y prometheus > /dev/null 2>&1; then
                    log_info "Prometheus installed via apt"
                    return
                fi
            else
                # sudo available but needs password - skip
                log_info "sudo requires password, using binary installation instead"
            fi
        elif apt-get --version &>/dev/null; then
            # Running as root or with full apt access
            apt-get update -qq > /dev/null 2>&1 || true
            if apt-get install -y prometheus > /dev/null 2>&1; then
                log_info "Prometheus installed via apt"
                return
            fi
        fi
    fi
    
    # Fallback to binary download (no privileges needed)
    log_info "Installing Prometheus from binary..."
    PROM_DIR="${INSTALL_DIR}/prometheus"
    mkdir -p "${PROM_DIR}"
    
    if [ ! -f "${PROM_DIR}/prometheus" ]; then
        cd /tmp
        PROM_FILE="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
        curl -sL "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROM_FILE}" -o "${PROM_FILE}"
        tar xzf "${PROM_FILE}"
        cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" "${PROM_DIR}/"
        cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" "${PROM_DIR}/" 2>/dev/null || true
        chmod +x "${PROM_DIR}/prometheus" "${PROM_DIR}/promtool" 2>/dev/null || true
        rm -rf "prometheus-${PROMETHEUS_VERSION}.linux-amd64" "${PROM_FILE}"
    fi
    
    log_info "Prometheus installed at ${PROM_DIR}"
}

install_node_exporter() {
    log_info "Installing Node Exporter..."
    
    NE_DIR="${INSTALL_DIR}/node_exporter"
    mkdir -p "${NE_DIR}"
    
    if [ ! -f "${NE_DIR}/node_exporter" ]; then
        log_info "Downloading Node Exporter from binary..."
        cd /tmp
        NE_FILE="node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
        curl -sL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${NE_FILE}" -o "${NE_FILE}"
        tar xzf "${NE_FILE}"
        cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" "${NE_DIR}/"
        chmod +x "${NE_DIR}/node_exporter"
        rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64" "${NE_FILE}"
    fi
    
    log_info "Node Exporter installed at ${NE_DIR}"
}

install_grafana() {
    log_info "Installing Grafana..."
    
    # Try apt with sudo (most reliable)
    if command -v apt-get &> /dev/null; then
        log_info "Attempting to install Grafana via apt..."
        
        # Try with sudo if available
        if command -v sudo &> /dev/null; then
            if sudo -n true 2>/dev/null; then
                # sudo available without password
                sudo apt-get update -qq > /dev/null 2>&1 || true
                if sudo apt-get install -y grafana > /dev/null 2>&1; then
                    log_info "Grafana installed via apt"
                    mkdir -p "${INSTALL_DIR}/grafana"
                    return
                fi
            else
                # sudo available but needs password - skip
                log_info "sudo requires password, using binary installation instead"
            fi
        elif apt-get --version &>/dev/null; then
            # Running as root or with full apt access
            apt-get update -qq > /dev/null 2>&1 || true
            if apt-get install -y grafana > /dev/null 2>&1; then
                log_info "Grafana installed via apt"
                mkdir -p "${INSTALL_DIR}/grafana"
                return
            fi
        fi
    fi
    
    # Fallback to binary download (no privileges needed)
    log_info "Installing Grafana from binary..."
    GRAFANA_DIR="${INSTALL_DIR}/grafana"
    mkdir -p "${GRAFANA_DIR}"
    mkdir -p "${GRAFANA_DIR}/data"
    mkdir -p "${GRAFANA_DIR}/logs"
    mkdir -p "${GRAFANA_DIR}/plugins"
    
    # Check if already installed
    if find "${GRAFANA_DIR}" -name "grafana-server" -type f 2>/dev/null | grep -q .; then
        log_info "Grafana already installed"
        return
    fi
    
    cd /tmp
    
    # List of versions to try (most recent first)
    VERSIONS=("10.2.2" "10.0.0" "9.5.3" "9.5.0")
    
    for VER in "${VERSIONS[@]}"; do
        GRAFANA_FILE="grafana-${VER}.linux-amd64.tar.gz"
        log_info "Attempting to download Grafana ${VER}..."
        
        if curl -sL --max-time 30 "https://dl.grafana.com/oss/release/${GRAFANA_FILE}" -o "${GRAFANA_FILE}" 2>/dev/null; then
            if [ -f "${GRAFANA_FILE}" ] && tar tzf "${GRAFANA_FILE}" &>/dev/null; then
                log_info "Successfully downloaded Grafana ${VER}"
                tar xzf "${GRAFANA_FILE}" -C "${GRAFANA_DIR}"
                rm -f "${GRAFANA_FILE}"
                
                # Verify binary exists
                if find "${GRAFANA_DIR}" -name "grafana-server" -type f 2>/dev/null | grep -q .; then
                    log_info "Grafana ${VER} installed successfully"
                    return
                else
                    log_warn "Binary not found after extraction, trying next version..."
                    rm -rf "${GRAFANA_DIR}/grafana-${VER}"
                fi
            fi
        fi
        
        # Clean up failed download
        rm -f "${GRAFANA_FILE}"
    done
    
    log_error "Failed to download any version of Grafana"
    return 1
}

setup_grafana_provisioning() {
    log_info "Setting up Grafana Prometheus datasource..."
    
    GRAFANA_DIR="${INSTALL_DIR}/grafana"
    
    # Find the Grafana home directory using the binary location
    GRAFANA_BIN=$(find "${GRAFANA_DIR}" -name "grafana-server" -type f 2>/dev/null | head -1)
    if [ -z "$GRAFANA_BIN" ]; then
        log_warn "Grafana binary not found yet, skipping provisioning for now"
        return
    fi
    
    GRAFANA_HOME=$(dirname "$GRAFANA_BIN" | xargs dirname)
    PROV_DIR="${GRAFANA_HOME}/conf/provisioning/datasources"
    mkdir -p "${PROV_DIR}"
    
    cat > "${PROV_DIR}/prometheus.yml" <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:${PROMETHEUS_PORT}
    isDefault: true
    editable: true
EOF
    
    log_info "Grafana datasource provisioning configured at ${PROV_DIR}"
}

start_services() {
    log_info "Starting services..."
    
    PROM_DIR="${INSTALL_DIR}/prometheus"
    NE_DIR="${INSTALL_DIR}/node_exporter"
    GRAFANA_DIR="${INSTALL_DIR}/grafana"
    
    # Start Node Exporter
    if ! pgrep -f "node_exporter" > /dev/null; then
        log_info "Starting Node Exporter on port ${NODE_EXPORTER_PORT}..."
        "${NE_DIR}/node_exporter" \
            --web.listen-address=":${NODE_EXPORTER_PORT}" \
            --collector.netdev.device-exclude="^veth.*" \
            > "${NE_DIR}/node_exporter.log" 2>&1 &
        echo $! > "${NE_DIR}/node_exporter.pid"
        sleep 2
    else
        log_warn "Node Exporter is already running"
    fi
    
    # Start Prometheus
    if ! pgrep -f "prometheus" > /dev/null; then
        log_info "Starting Prometheus on port ${PROMETHEUS_PORT}..."
        PROM_DIR="${INSTALL_DIR}/prometheus"
        
        # Check if system prometheus is available
        if command -v prometheus &>/dev/null; then
            log_info "Using system-installed Prometheus"
            mkdir -p "${PROM_DIR}"
            
            # Create prometheus config
            cat > "${PROM_DIR}/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:${PROMETHEUS_PORT}']
  
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:${NODE_EXPORTER_PORT}']
EOF
            
            prometheus \
                --config.file="${PROM_DIR}/prometheus.yml" \
                --storage.tsdb.path="${PROM_DIR}/data" \
                --web.listen-address="localhost:${PROMETHEUS_PORT}" \
                > "${PROM_DIR}/prometheus.log" 2>&1 &
            echo $! > "${PROM_DIR}/prometheus.pid"
        else
            log_info "Using locally-installed Prometheus"
            
            # Create prometheus config
            cat > "${PROM_DIR}/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:${PROMETHEUS_PORT}']
  
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:${NODE_EXPORTER_PORT}']
EOF
            
            "${PROM_DIR}/prometheus" \
                --config.file="${PROM_DIR}/prometheus.yml" \
                --storage.tsdb.path="${PROM_DIR}/data" \
                --web.listen-address="localhost:${PROMETHEUS_PORT}" \
                > "${PROM_DIR}/prometheus.log" 2>&1 &
            echo $! > "${PROM_DIR}/prometheus.pid"
        fi
        
        sleep 3
    else
        log_warn "Prometheus is already running"
    fi
    
    # Start Grafana
    if ! pgrep -f "grafana-server" > /dev/null; then
        log_info "Starting Grafana on port ${GRAFANA_PORT}..."
        GRAFANA_DIR="${INSTALL_DIR}/grafana"
        
        # Check if system grafana is available
        if command -v grafana-server &>/dev/null; then
            log_info "Using system-installed Grafana"
            GF_SERVER_HTTP_PORT="${GRAFANA_PORT}" \
            GF_PATHS_DATA="${GRAFANA_DIR}/data" \
            GF_PATHS_LOGS="${GRAFANA_DIR}/logs" \
            GF_PATHS_PLUGINS="${GRAFANA_DIR}/plugins" \
            grafana-server \
                > "${GRAFANA_DIR}/grafana.log" 2>&1 &
            echo $! > "${GRAFANA_DIR}/grafana.pid"
        else
            # Use locally installed binary
            log_info "Using locally-installed Grafana"
            
            # Find the grafana-server binary (works with any version)
            GRAFANA_BIN=$(find "${GRAFANA_DIR}" -name "grafana-server" -type f 2>/dev/null | head -1)
            
            if [ -z "$GRAFANA_BIN" ] || [ ! -f "$GRAFANA_BIN" ]; then
                log_error "Grafana binary not found in ${GRAFANA_DIR}"
                return 1
            fi
            
            # Ensure binary is executable
            chmod +x "$GRAFANA_BIN"
            
            # Get the Grafana home directory (parent of bin directory)
            GRAFANA_HOME=$(dirname "$GRAFANA_BIN" | xargs dirname)
            
            # Create config directory and minimal config
            mkdir -p "${GRAFANA_HOME}/conf"
            cat > "${GRAFANA_HOME}/conf/defaults.ini" <<'GRAFANA_CFG'
[server]
http_port = 3000
protocol = http

[security]
admin_user = admin
admin_password = admin

[auth.anonymous]
enabled = true

[database]
type = sqlite3
path = grafana.db

[paths]
logs = logs
data = data
plugins = plugins
GRAFANA_CFG
            
            # Start Grafana with explicit settings
            GF_PATHS_DATA="${GRAFANA_DIR}/data" \
            GF_PATHS_LOGS="${GRAFANA_DIR}/logs" \
            GF_PATHS_PLUGINS="${GRAFANA_DIR}/plugins" \
            GF_PATHS_HOME="${GRAFANA_HOME}" \
            GF_SERVER_HTTP_PORT="${GRAFANA_PORT}" \
            nohup "$GRAFANA_BIN" \
                --config="${GRAFANA_HOME}/conf/defaults.ini" \
                --homepath="${GRAFANA_HOME}" \
                > "${GRAFANA_DIR}/grafana.log" 2>&1 &
            echo $! > "${GRAFANA_DIR}/grafana.pid"
        fi
        
        GRAFANA_PID=$!
        log_info "Grafana starting with PID $GRAFANA_PID, waiting for startup..."
        
        # Wait and check multiple times
        for i in {1..10}; do
            sleep 1
            if ! kill -0 $GRAFANA_PID 2>/dev/null; then
                log_error "Grafana process died. Error log:"
                tail -30 "${GRAFANA_DIR}/grafana.log" 2>/dev/null || echo "(no log file)"
                return 1
            fi
        done
        
        log_info "Grafana started successfully"
    else
        log_warn "Grafana is already running"
    fi
    
    log_info "All services started successfully!"
}

stop_services() {
    log_info "Stopping services..."
    
    for service in prometheus node_exporter grafana-server; do
        if pgrep -f "$service" > /dev/null; then
            log_info "Stopping $service..."
            pkill -f "$service" || true
        fi
    done
    
    sleep 1
    log_info "Services stopped"
}

status_services() {
    echo ""
    log_info "Monitoring Stack Status:"
    echo ""
    
    if pgrep -f "node_exporter" > /dev/null; then
        echo -e "${GREEN}✓${NC} Node Exporter is running on http://localhost:${NODE_EXPORTER_PORT}/metrics"
    else
        echo -e "${RED}✗${NC} Node Exporter is NOT running"
    fi
    
    if pgrep -f "prometheus" > /dev/null; then
        echo -e "${GREEN}✓${NC} Prometheus is running on http://localhost:${PROMETHEUS_PORT}"
    else
        echo -e "${RED}✗${NC} Prometheus is NOT running"
    fi
    
    if pgrep -f "grafana-server" > /dev/null; then
        echo -e "${GREEN}✓${NC} Grafana is running on http://localhost:${GRAFANA_PORT}"
        echo "   Default credentials: admin / admin"
    else
        echo -e "${RED}✗${NC} Grafana is NOT running"
    fi
    
    echo ""
}

cleanup() {
    log_warn "Cleaning up monitoring stack..."
    stop_services
    
    if [ -d "${INSTALL_DIR}" ]; then
        log_info "Removing ${INSTALL_DIR}..."
        rm -rf "${INSTALL_DIR}"
    fi
    
    log_info "Cleanup complete"
}

diagnose_grafana() {
    log_info "Diagnosing Grafana..."
    echo ""
    
    GRAFANA_DIR="${INSTALL_DIR}/grafana"
    
    if [ ! -d "$GRAFANA_DIR" ]; then
        log_error "Grafana directory not found at $GRAFANA_DIR"
        return 1
    fi
    
    log_info "Grafana directory structure:"
    ls -la "$GRAFANA_DIR" 2>/dev/null | head -10
    echo ""
    
    # Check for binary
    GRAFANA_BIN=$(find "$GRAFANA_DIR" -name "grafana-server" -type f 2>/dev/null | head -1)
    if [ -n "$GRAFANA_BIN" ]; then
        log_info "Found Grafana binary: $GRAFANA_BIN"
        log_info "Binary is executable: $([ -x "$GRAFANA_BIN" ] && echo 'Yes' || echo 'No')"
    else
        log_error "Grafana binary not found"
    fi
    echo ""
    
    # Check logs
    if [ -f "$GRAFANA_DIR/grafana.log" ]; then
        log_info "Last 30 lines of Grafana log:"
        echo "---"
        tail -30 "$GRAFANA_DIR/grafana.log"
        echo "---"
    else
        log_warn "No Grafana log file found yet"
    fi
    echo ""
    
    # Check port
    log_info "Checking port ${GRAFANA_PORT}..."
    if netstat -tuln 2>/dev/null | grep -q ":${GRAFANA_PORT} "; then
        log_info "Port ${GRAFANA_PORT} is in use"
    else
        log_warn "Port ${GRAFANA_PORT} is not in use"
    fi
}

show_usage() {
    cat << EOF
Usage: bash monitoring.sh [command]

Commands:
  install      Install all components (default)
  start        Start all services
  stop         Stop all services
  status       Show service status
  diagnose     Diagnose Grafana issues
  cleanup      Stop services and remove all files

Environment:
  INSTALL_DIR  Installation directory (default: \$HOME/.monitoring)

Installation directory: ${INSTALL_DIR}
Prometheus port: ${PROMETHEUS_PORT}
Node Exporter port: ${NODE_EXPORTER_PORT}
Grafana port: ${GRAFANA_PORT}

Example:
  bash monitoring.sh install
  bash monitoring.sh status
  bash monitoring.sh diagnose
  bash monitoring.sh stop
  bash monitoring.sh cleanup

EOF
}

main() {
    local command="${1:-install}"
    
    case "$command" in
        install)
            check_requirements
            install_prometheus
            install_node_exporter
            install_grafana
            setup_grafana_provisioning
            start_services
            status_services
            log_info "Setup complete! Access services at:"
            echo "  Prometheus: http://localhost:${PROMETHEUS_PORT}"
            echo "  Grafana:    http://localhost:${GRAFANA_PORT} (admin/admin)"
            echo "  Node Exporter metrics: http://localhost:${NODE_EXPORTER_PORT}/metrics"
            ;;
        start)
            start_services
            status_services
            ;;
        stop)
            stop_services
            ;;
        status)
            status_services
            ;;
        diagnose)
            diagnose_grafana
            ;;
        cleanup)
            cleanup
            ;;
        -h|--help|help)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
