#!/bin/bash
# 🔥 CGNAT BYPASS v8.5 - STABLE & FAST
# Removed problematic packages, optimized installation
# Works on CasaOS, Ubuntu, Debian

if [ $EUID != 0 ]; then
  exec sudo "$0" "$@"
  exit $?
fi

# ==================== COLORS ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ==================== VARIABLES ====================
WGCONF="/etc/wireguard/wg0.conf"
WGDIR="/etc/wireguard"
MONITORLOG="/var/log/wg-monitor.log"

# ==================== FUNCTIONS ====================
log_info() {
  echo -e "${CYAN}ℹ️  $1${NC}"
}

log_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
  echo -e "${RED}❌ $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_header() {
  clear
  echo ""
  echo "╔════════════════════════════════════════╗"
  echo "║     CGNAT BYPASS v8.5 - STABLE         ║"
  echo "║        ALL-IN-ONE SOLUTION             ║"
  echo "╚════════════════════════════════════════╝"
  echo ""
}

# ==================== QUICK PACKAGE FIX ====================
quick_fix() {
  log_info "Fixing broken packages..."
  apt clean >/dev/null 2>&1
  apt autoclean >/dev/null 2>&1
  dpkg --configure -a >/dev/null 2>&1
  apt --fix-broken install -y >/dev/null 2>&1
  apt update >/dev/null 2>&1
  log_success "Package cache cleared"
}

# ==================== INSTALL MINIMAL DEPENDENCIES ====================
install_dependencies() {
  log_info "Installing minimal dependencies..."
  
  quick_fix
  
  # Only essential packages - no problematic ones
  apt install -y \
    curl \
    iputils-ping \
    net-tools \
    iptables \
    iptables-persistent \
    netfilter-persistent \
    ufw \
    2>&1 | grep -v "^Reading\|^Building\|^Selecting\|^Note"
  
  if ! command -v iptables &> /dev/null; then
    log_error "iptables installation failed"
    return 1
  fi
  
  log_success "Dependencies installed"
  return 0
}

# ==================== INSTALL WIREGUARD ====================
install_wireguard() {
  log_info "Installing WireGuard..."
  
  apt remove -y wireguard wireguard-tools 2>/dev/null || true
  apt autoremove -y >/dev/null 2>&1
  
  apt install -y \
    wireguard \
    wireguard-tools \
    2>&1 | grep -v "^Reading\|^Building"
  
  if command -v wg &> /dev/null; then
    log_success "WireGuard installed"
    wg --version
    return 0
  else
    log_error "WireGuard installation failed"
    return 1
  fi
}

# ==================== SYSTEM SETUP ====================
setup_system() {
  log_info "Setting up system..."
  
  if ! install_dependencies; then
    log_error "Dependency installation failed"
    exit 1
  fi
  
  if ! install_wireguard; then
    log_error "Cannot continue without WireGuard"
    exit 1
  fi
  
  mkdir -p "$WGDIR"
  chmod 700 "$WGDIR"
  
  log_info "Enabling IP forwarding..."
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
  sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null 2>&1
  
  {
    echo "net.ipv4.ip_forward=1"
    echo "net.ipv4.conf.all.forwarding=1"
  } | tee -a /etc/sysctl.conf >/dev/null
  
  sysctl -p >/dev/null 2>&1
  
  log_success "System setup complete"
}

# ==================== VPS SERVER SETUP ====================
vps_server() {
  print_header
  echo "☁️  VPS SERVER SETUP"
  echo ""
  
  setup_system
  
  WGPORT=55108
  WG_SERVER_IP="10.1.0.1"
  WG_CLIENT_IP="10.1.0.2"
  
  log_info "Detecting public IP..."
  PUB_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
  
  echo ""
  echo -n "Public IP [$PUB_IP]: "
  read -r input_ip
  [[ -n "$input_ip" ]] && PUB_IP="$input_ip"
  
  echo -n "WireGuard Port [55108]: "
  read -r input_port
  [[ -n "$input_port" ]] && WGPORT="$input_port"
  
  echo -n "Service Ports (comma-separated) [80,443,8098]: "
  read -r SERVICE_PORTS
  SERVICE_PORTS=${SERVICE_PORTS:-"80,443,8098"}
  
  log_info "Generating WireGuard keys..."
  wg genkey | tee "$WGDIR/server_private.key" | wg pubkey > "$WGDIR/server_public.key"
  chmod 600 "$WGDIR/server_private.key"
  SERVER_PUBLIC_KEY=$(cat "$WGDIR/server_public.key")
  
  echo "$WG_CLIENT_IP" > "$WGDIR/client_ip"
  echo "$SERVICE_PORTS" > "$WGDIR/service_ports"
  echo "$PUB_IP" > "$WGDIR/public_ip"
  echo "$WGPORT" > "$WGDIR/wg_port"
  
  echo ""
  echo "════════════════════════════════════════"
  echo "📋 CLIENT SETUP COMMAND"
  echo "════════════════════════════════════════"
  echo ""
  echo "Copy and run this on LOCAL/CasaOS:"
  echo ""
  echo "sudo bash ./installer.sh client \"$SERVER_PUBLIC_KEY\" $PUB_IP $WGPORT \"$SERVICE_PORTS\""
  echo ""
  echo "════════════════════════════════════════"
  echo ""
  
  echo -n "Paste client public key: "
  read -r CLIENT_PUBLIC_KEY
  
  if [[ ${#CLIENT_PUBLIC_KEY} -ne 44 ]]; then
    log_error "Invalid key length (must be 44 chars)"
    exit 1
  fi
  
  log_info "Creating WireGuard configuration..."
  cat > "$WGCONF" << EOF
[Interface]
PrivateKey = $(cat "$WGDIR/server_private.key")
Address = $WG_SERVER_IP/24
ListenPort = $WGPORT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $WG_CLIENT_IP/32
PersistentKeepalive = 15
EOF

  chmod 600 "$WGCONF"
  
  log_info "Configuring firewall..."
  ufw --force enable >/dev/null 2>&1
  ufw default deny incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  
  ufw allow 22/tcp >/dev/null 2>&1
  ufw allow 22/udp >/dev/null 2>&1
  log_success "SSH allowed"
  
  ufw allow "$WGPORT/udp" >/dev/null 2>&1
  log_success "WireGuard port $WGPORT/UDP allowed"
  
  IFS=',' read -ra PORTS <<< "$SERVICE_PORTS"
  for port in "${PORTS[@]}"; do
    port=$(echo "$port" | xargs)
    ufw allow "$port/tcp" >/dev/null 2>&1
    ufw allow "$port/udp" >/dev/null 2>&1
    log_success "Port $port allowed"
  done
  
  log_info "Setting up port forwarding..."
  for port in "${PORTS[@]}"; do
    port=$(echo "$port" | xargs)
    iptables -t nat -A PREROUTING -p tcp --dport "$port" -j DNAT --to-destination "$WG_CLIENT_IP:$port" 2>/dev/null || true
    iptables -t nat -A PREROUTING -p udp --dport "$port" -j DNAT --to-destination "$WG_CLIENT_IP:$port" 2>/dev/null || true
    log_success "Forwarding $port → $WG_CLIENT_IP"
  done
  
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
  netfilter-persistent save >/dev/null 2>&1
  
  log_info "Starting WireGuard..."
  systemctl enable wg-quick@wg0 >/dev/null 2>&1
  systemctl restart wg-quick@wg0
  sleep 3
  
  if systemctl is-active --quiet wg-quick@wg0; then
    log_success "WireGuard is running"
  else
    log_error "WireGuard failed to start"
    log_warning "Check: sudo journalctl -u wg-quick@wg0 -n 30"
  fi
  
  install_monitor
  
  echo ""
  echo "════════════════════════════════════════"
  log_success "VPS SERVER SETUP COMPLETE"
  echo "════════════════════════════════════════"
  echo ""
  
  sleep 2
  wg show
  
  echo ""
  echo -n "Press Enter to continue..."
  read -r
}

# ==================== LOCAL CLIENT SETUP ====================
local_client() {
  SERVER_PUB=$1
  PUBIP=$2
  WGPORT=$3
  PORTS=$4
  
  WG_CLIENT_IP="10.1.0.2"
  WG_SERVER_IP="10.1.0.1"
  
  print_header
  echo "🏠 LOCAL CLIENT SETUP"
  echo ""
  
  if [[ -z "$SERVER_PUB" ]] || [[ ${#SERVER_PUB} -ne 44 ]]; then
    log_error "Invalid server public key"
    exit 1
  fi
  
  if [[ -z "$PUBIP" ]]; then
    log_error "VPS IP address required"
    exit 1
  fi
  
  WGPORT=${WGPORT:-55108}
  PORTS=${PORTS:-"8098"}
  
  log_info "VPS: $PUBIP:$WGPORT"
  log_info "Ports: $PORTS"
  
  setup_system
  
  log_info "Generating client keys..."
  wg genkey | tee "$WGDIR/client_private.key" | wg pubkey > "$WGDIR/client_public.key"
  chmod 600 "$WGDIR/client_private.key"
  CLIENT_PUBLIC_KEY=$(cat "$WGDIR/client_public.key")
  
  echo ""
  echo "════════════════════════════════════════"
  echo "🔑 YOUR PUBLIC KEY"
  echo "════════════════════════════════════════"
  echo ""
  echo "$CLIENT_PUBLIC_KEY"
  echo ""
  echo "(Give this to VPS operator)"
  echo "════════════════════════════════════════"
  echo ""
  
  log_info "Creating WireGuard configuration..."
  cat > "$WGCONF" << EOF
[Interface]
PrivateKey = $(cat "$WGDIR/client_private.key")
Address = $WG_CLIENT_IP/24
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBIP:$WGPORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 15
EOF

  chmod 600 "$WGCONF"
  
  log_info "Starting WireGuard..."
  systemctl enable wg-quick@wg0 >/dev/null 2>&1
  systemctl restart wg-quick@wg0
  sleep 4
  
  log_info "Testing tunnel connection..."
  
  if ping -c 3 "$WG_SERVER_IP" >/dev/null 2>&1; then
    echo ""
    log_success "TUNNEL CONNECTED ✨"
    echo ""
    echo "Test your services:"
    IFS=',' read -ra PORTS_ARRAY <<< "$PORTS"
    for port in "${PORTS_ARRAY[@]}"; do
      port=$(echo "$port" | xargs | sed 's|/.*||')
      echo "  → http://$PUBIP:$port"
    done
    echo ""
  else
    echo ""
    log_error "TUNNEL NOT RESPONDING"
    echo ""
    log_warning "Troubleshooting:"
    echo "  1. VPS running: ssh root@$PUBIP 'wg show'"
    echo "  2. Config: cat /etc/wireguard/wg0.conf"
    echo "  3. Logs: journalctl -u wg-quick@wg0 -n 30"
    echo ""
  fi
  
  install_monitor
  
  echo "════════════════════════════════════════"
  log_success "LOCAL CLIENT SETUP COMPLETE"
  echo "════════════════════════════════════════"
  echo ""
  
  echo -n "Press Enter to continue..."
  read -r
}

# ==================== AUTO-RECOVERY ====================
install_monitor() {
  log_info "Installing auto-recovery monitor..."
  
  mkdir -p "$(dirname "$MONITORLOG")"
  
  cat > /etc/systemd/system/wg-monitor.service << 'MONITOR_EOF'
[Unit]
Description=WireGuard Monitor & Auto-Recovery
After=wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do sleep 60; if ! systemctl is-active --quiet wg-quick@wg0; then systemctl restart wg-quick@wg0; fi; done'
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
MONITOR_EOF

  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable wg-monitor.service >/dev/null 2>&1
  systemctl restart wg-monitor.service >/dev/null 2>&1
  
  log_success "Auto-recovery installed"
}

# ==================== STATUS CHECK ====================
status_check() {
  print_header
  echo "🔍 WIREGUARD STATUS"
  echo ""
  
  if command -v wg &> /dev/null; then
    wg show 2>/dev/null || log_error "WireGuard not responding"
  else
    log_error "WireGuard not installed"
    return
  fi
  
  echo ""
  echo "📡 SERVICE STATUS"
  echo ""
  systemctl status wg-quick@wg0 --no-pager 2>/dev/null | head -12
  
  echo ""
  echo -n "Press Enter to continue..."
  read -r
}

# ==================== REPAIR ====================
repair_all() {
  print_header
  echo "🔨 REPAIRING..."
  echo ""
  
  log_info "Installing any missing dependencies..."
  install_dependencies
  
  log_info "Restarting WireGuard..."
  systemctl restart wg-quick@wg0
  sleep 2
  
  log_info "Reloading firewall..."
  ufw reload >/dev/null 2>&1
  
  log_info "Restarting monitor..."
  systemctl restart wg-monitor >/dev/null 2>&1
  
  echo ""
  log_success "REPAIR COMPLETE"
  echo ""
  
  status_check
}

# ==================== UNINSTALL ====================
uninstall_all() {
  print_header
  echo "⚠️  COMPLETE UNINSTALL"
  echo ""
  echo -n "Type 'yes' to confirm: "
  read -r confirm
  
  if [[ "$confirm" != "yes" ]]; then
    log_info "Uninstall cancelled"
    return
  fi
  
  systemctl stop wg-quick@wg0 wg-monitor 2>/dev/null || true
  systemctl disable wg-quick@wg0 wg-monitor 2>/dev/null || true
  rm -rf "$WGDIR" "$WGCONF" /etc/systemd/system/wg-monitor* 2>/dev/null || true
  apt purge -y wireguard wireguard-tools 2>/dev/null || true
  apt autoremove -y >/dev/null 2>&1
  systemctl daemon-reload >/dev/null 2>&1
  
  echo ""
  log_success "UNINSTALL COMPLETE"
  echo ""
}

# ==================== MAIN MENU ====================
main_menu() {
  while true; do
    print_header
    echo "╔════════════════════════════════════════╗"
    echo "║  1) ☁️  VPS Server Setup                ║"
    echo "║  2) 🏠 Local Client Setup               ║"
    echo "╠════════════════════════════════════════╣"
    echo "║  3) 🔍 Status Check                    ║"
    echo "║  4) 🔨 Repair All                      ║"
    echo "║  5) 🗑️  Complete Uninstall            ║"
    echo "║  6) ❌ Exit                            ║"
    echo "╚════════════════════════════════════════╝"
    
    echo ""
    echo -n "Choose (1-6): "
    read -r CHOICE
    
    case $CHOICE in
      1) vps_server ;;
      2)
        echo ""
        echo "Paste CLIENT command from VPS:"
        echo -n "Command: "
        read -r CMD
        eval "$CMD"
        ;;
      3) status_check ;;
      4) repair_all ;;
      5) uninstall_all ;;
      6) log_info "Goodbye!"; exit 0 ;;
      *)
        log_error "Invalid choice"
        sleep 1
        ;;
    esac
  done
}

# ==================== ENTRY POINT ====================
case "${1:-}" in
  client) shift; local_client "$@" ;;
  uninstall) uninstall_all ;;
  status) status_check ;;
  repair) repair_all ;;
  *) main_menu ;;
esac
