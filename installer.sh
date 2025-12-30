#!/bin/bash
# 🔥 CGNAT BYPASS v8.0 - COMPLETE ALL-IN-ONE
# VPS + Local + Full Setup + Auto-Recovery + Diagnostics
# Works on CasaOS, Ubuntu, Debian

if [ $EUID != 0 ]; then
  exec sudo "$0" "$@"
  exit $?
fi

# ==================== COLORS & VARIABLES ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[36m'
LGREEN='\033[92m'
BOLD='\033[1m'
NC='\033[0m'

WGCONF="/etc/wireguard/wg0.conf"
WGDIR="/etc/wireguard"
MONITORLOG="/var/log/wg-monitor.log"
IPRULES="/etc/iptables/rules.v4"

# ==================== UTILITY FUNCTIONS ====================
log_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

print_header() {
  clear
  echo -e "${LGREEN}${BOLD}╔════════════════════════════════════════╗${NC}"
  echo -e "${LGREEN}${BOLD}║     CGNAT BYPASS v8.0 - COMPLETE      ║${NC}"
  echo -e "${LGREEN}${BOLD}║        ALL-IN-ONE SOLUTION             ║${NC}"
  echo -e "${LGREEN}${BOLD}╚════════════════════════════════════════╝${NC}"
  echo ""
}

# ==================== INSTALL WIREGUARD ====================
install_wireguard() {
  log_info "Installing WireGuard..."
  
  # Remove old versions
  apt remove -y wireguard wireguard-tools 2>/dev/null || true
  apt autoremove -y >/dev/null 2>&1
  
  # Update system
  apt update >/dev/null 2>&1
  
  # Install dependencies
  apt install -y curl gnupg2 lsb-release ubuntu-keyring ca-certificates >/dev/null 2>&1
  
  # Add WireGuard repository
  mkdir -p /etc/apt/keyrings
  
  # Try to add official repo
  if ! curl -fsSL https://build.opensuse.org/projects/home:sthnfdj/public_key 2>/dev/null | gpg --dearmor --yes -o /etc/apt/keyrings/wireguard-archive-keyring.gpg 2>/dev/null; then
    log_warning "Could not add official repo, using default"
  else
    echo "deb [signed-by=/etc/apt/keyrings/wireguard-archive-keyring.gpg] http://deb.wireguard.com/ubuntu $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/wireguard.list >/dev/null
    apt update >/dev/null 2>&1
  fi
  
  # Install WireGuard
  apt install -y wireguard wireguard-tools >/dev/null 2>&1
  
  # Install kernel headers for module compilation
  apt install -y linux-headers-$(uname -r) >/dev/null 2>&1
  
  # Verify installation
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
  
  # Install WireGuard
  if ! install_wireguard; then
    log_error "Cannot continue without WireGuard"
    exit 1
  fi
  
  # Install other dependencies
  apt install -y \
    curl \
    iputils-ping \
    iptables-persistent \
    netfilter-persistent \
    ufw \
    net-tools \
    resolvconf \
    openresolv \
    >/dev/null 2>&1
  
  # Create WireGuard directory
  mkdir -p $WGDIR
  chmod 700 $WGDIR
  
  # Enable IP forwarding
  log_info "Enabling IP forwarding..."
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
  sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null 2>&1
  sysctl -w net.ipv4.conf.default.forwarding=1 >/dev/null 2>&1
  
  # Persist settings
  {
    echo "net.ipv4.ip_forward=1"
    echo "net.ipv4.conf.all.forwarding=1"
    echo "net.ipv4.conf.default.forwarding=1"
  } | tee -a /etc/sysctl.conf >/dev/null
  
  sysctl -p >/dev/null 2>&1
  
  log_success "System setup complete"
}

# ==================== VPS SERVER SETUP ====================
vps_server() {
  print_header
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER SETUP${NC}"
  echo ""
  
  setup_system
  
  # Configuration
  WGPORT=55108
  WG_SERVER_IP="10.1.0.1"
  WG_CLIENT_IP="10.1.0.2"
  
  # Get public IP
  log_info "Detecting public IP..."
  PUB_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
  
  read -p "${CYAN}Public IP [$PUB_IP]: ${NC}" input_ip
  [[ -n "$input_ip" ]] && PUB_IP="$input_ip"
  
  read -p "${CYAN}WireGuard Port [55108]: ${NC}" input_port
  [[ -n "$input_port" ]] && WGPORT="$input_port"
  
  read -p "${CYAN}Service Ports (comma-separated) [80,443,8098]: ${NC}" SERVICE_PORTS
  SERVICE_PORTS=${SERVICE_PORTS:-"80,443,8098"}
  
  log_info "Generating WireGuard keys..."
  wg genkey | tee $WGDIR/server_private.key | wg pubkey > $WGDIR/server_public.key
  chmod 600 $WGDIR/server_private.key
  SERVER_PUBLIC_KEY=$(cat $WGDIR/server_public.key)
  
  # Store configuration
  echo "$WG_CLIENT_IP" > $WGDIR/client_ip
  echo "$SERVICE_PORTS" > $WGDIR/service_ports
  echo "$PUB_IP" > $WGDIR/public_ip
  echo "$WGPORT" > $WGDIR/wg_port
  
  echo ""
  echo -e "${LGREEN}${BOLD}════════════════════════════════════════${NC}"
  echo -e "${LGREEN}${BOLD}📋 CLIENT SETUP COMMAND${NC}"
  echo -e "${LGREEN}${BOLD}════════════════════════════════════════${NC}"
  echo ""
  echo -e "${YELLOW}Copy and run this on LOCAL/CasaOS:${NC}"
  echo ""
  echo -e "${BOLD}sudo bash ./installer.sh client \"$SERVER_PUBLIC_KEY\" $PUB_IP $WGPORT \"$SERVICE_PORTS\"${NC}"
  echo ""
  echo -e "${LGREEN}${BOLD}════════════════════════════════════════${NC}"
  echo ""
  
  read -p "${CYAN}Paste client public key: ${NC}" CLIENT_PUBLIC_KEY
  
  if [[ ${#CLIENT_PUBLIC_KEY} -ne 44 ]]; then
    log_error "Invalid key length (must be 44 chars)"
    exit 1
  fi
  
  # Create WireGuard config
  log_info "Creating WireGuard configuration..."
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat $WGDIR/server_private.key)
Address = $WG_SERVER_IP/24
ListenPort = $WGPORT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE
SaveCounters = true

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $WG_CLIENT_IP/32
PersistentKeepalive = 15
EOF

  chmod 600 $WGCONF
  
  # Setup firewall
  log_info "Configuring firewall..."
  ufw --force enable >/dev/null 2>&1
  ufw default deny incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  ufw default allow routed in >/dev/null 2>&1
  
  # Allow SSH
  ufw allow 22/tcp >/dev/null 2>&1
  ufw allow 22/udp >/dev/null 2>&1
  log_success "SSH allowed"
  
  # Allow WireGuard
  ufw allow $WGPORT/udp >/dev/null 2>&1
  log_success "WireGuard port $WGPORT/UDP allowed"
  
  # Allow service ports
  IFS=',' read -ra PORTS <<< "$SERVICE_PORTS"
  for port in "${PORTS[@]}"; do
    port=$(echo $port | xargs)
    ufw allow $port/tcp >/dev/null 2>&1
    ufw allow $port/udp >/dev/null 2>&1
    log_success "Port $port allowed"
  done
  
  # Setup iptables port forwarding
  log_info "Setting up port forwarding..."
  for port in "${PORTS[@]}"; do
    port=$(echo $port | xargs)
    iptables -t nat -A PREROUTING -p tcp --dport $port -j DNAT --to-destination $WG_CLIENT_IP:$port 2>/dev/null || true
    iptables -t nat -A PREROUTING -p udp --dport $port -j DNAT --to-destination $WG_CLIENT_IP:$port 2>/dev/null || true
    log_success "Forwarding $port → $WG_CLIENT_IP"
  done
  
  # Save iptables rules
  mkdir -p /etc/iptables
  iptables-save > $IPRULES 2>/dev/null || true
  netfilter-persistent save >/dev/null 2>&1
  
  # Enable and start WireGuard
  log_info "Starting WireGuard..."
  systemctl enable wg-quick@wg0 >/dev/null 2>&1
  systemctl restart wg-quick@wg0
  sleep 3
  
  # Verify
  if systemctl is-active --quiet wg-quick@wg0; then
    log_success "WireGuard is running"
  else
    log_error "WireGuard failed to start"
  fi
  
  # Install monitoring
  install_monitor
  
  echo ""
  echo -e "${LGREEN}${BOLD}════════════════════════════════════════${NC}"
  log_success "VPS SERVER SETUP COMPLETE"
  echo -e "${LGREEN}${BOLD}════════════════════════════════════════${NC}"
  echo ""
  
  # Show status
  sleep 2
  wg show
  
  read -p "Press Enter to continue..."
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
  echo -e "${LGREEN}${BOLD}🏠 LOCAL CLIENT SETUP${NC}"
  echo ""
  
  # Validate inputs
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
  
  # Generate keys
  log_info "Generating client keys..."
  wg genkey | tee $WGDIR/client_private.key | wg pubkey > $WGDIR/client_public.key
  chmod 600 $WGDIR/client_private.key
  CLIENT_PUBLIC_KEY=$(cat $WGDIR/client_public.key)
  
  echo ""
  echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}🔑 YOUR PUBLIC KEY${NC}"
  echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
  echo ""
  echo -e "${YELLOW}${BOLD}$CLIENT_PUBLIC_KEY${NC}"
  echo ""
  echo -e "${CYAN}(Give this to VPS operator)${NC}"
  echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
  echo ""
  
  # Create WireGuard config
  log_info "Creating WireGuard configuration..."
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat $WGDIR/client_private.key)
Address = $WG_CLIENT_IP/24
DNS = 8.8.8.8, 8.8.4.4
PostUp = resolvectl default-route yes
PostDown = resolvectl default-route no

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBIP:$WGPORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 15
EOF

  chmod 600 $WGCONF
  
  # Enable and start WireGuard
  log_info "Starting WireGuard..."
  systemctl enable wg-quick@wg0 >/dev/null 2>&1
  systemctl restart wg-quick@wg0
  sleep 4
  
  # Test connection
  log_info "Testing tunnel connection..."
  
  if ping -c 3 $WG_SERVER_IP >/dev/null 2>&1; then
    echo ""
    log_success "TUNNEL CONNECTED"
    echo ""
    echo -e "${CYAN}${BOLD}Test your services:${NC}"
    IFS=',' read -ra PORTS_ARRAY <<< "$PORTS"
    for port in "${PORTS_ARRAY[@]}"; do
      port=$(echo $port | xargs | sed 's|/.*||')
      echo -e "${YELLOW}  → http://$PUBIP:$port${NC}"
    done
    echo ""
  else
    echo ""
    log_error "TUNNEL NOT RESPONDING"
    echo ""
    log_warning "Troubleshooting steps:"
    echo "  1. Check VPS is running: ssh root@$PUBIP 'wg show'"
    echo "  2. Check firewall: sudo ufw status"
    echo "  3. Check logs: journalctl -u wg-quick@wg0"
    echo ""
  fi
  
  # Install monitoring
  install_monitor
  
  echo -e "${LGREEN}${BOLD}════════════════════════════════════════${NC}"
  log_success "LOCAL CLIENT SETUP COMPLETE"
  echo -e "${LGREEN}${BOLD}════════════════════════════════════════${NC}"
  echo ""
  
  read -p "Press Enter to continue..."
}

# ==================== MONITOR & AUTO-RECOVERY ====================
install_monitor() {
  log_info "Installing auto-recovery monitor..."
  
  mkdir -p $(dirname $MONITORLOG)
  
  cat > /etc/systemd/system/wg-monitor.service << 'MONITOR_EOF'
[Unit]
Description=WireGuard Monitor & Auto-Recovery
After=wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do \
  sleep 60; \
  if ! systemctl is-active --quiet wg-quick@wg0; then \
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Tunnel DOWN - Restarting..." >> /var/log/wg-monitor.log; \
    systemctl restart wg-quick@wg0; \
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Tunnel RESTARTED" >> /var/log/wg-monitor.log; \
  else \
    if ! ping -c 1 10.1.0.1 >/dev/null 2>&1 && ! ping -c 1 10.1.0.2 >/dev/null 2>&1; then \
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] Peer DOWN - Restarting..." >> /var/log/wg-monitor.log; \
      systemctl restart wg-quick@wg0; \
    fi; \
  fi; \
done'
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
  echo -e "${CYAN}${BOLD}🔍 WIREGUARD STATUS${NC}"
  echo ""
  
  if command -v wg &> /dev/null; then
    wg show 2>/dev/null || log_error "WireGuard not responding"
  else
    log_error "WireGuard not installed"
    return
  fi
  
  echo ""
  echo -e "${CYAN}${BOLD}📡 SERVICE STATUS${NC}"
  echo ""
  systemctl status wg-quick@wg0 --no-pager 2>/dev/null | head -12
  
  echo ""
  echo -e "${CYAN}${BOLD}🛡️  FIREWALL (UFW)${NC}"
  echo ""
  ufw status | head -20
  
  echo ""
  echo -e "${CYAN}${BOLD}🔀 PORT FORWARDING${NC}"
  echo ""
  iptables -t nat -L -n 2>/dev/null | grep -A 10 "PREROUTING" || log_warning "No forwarding rules"
  
  echo ""
  echo -e "${CYAN}${BOLD}📊 MONITOR STATUS${NC}"
  echo ""
  systemctl status wg-monitor --no-pager 2>/dev/null | head -8
  
  echo ""
  read -p "Press Enter to continue..."
}

# ==================== FULL DIAGNOSTIC ====================
full_diagnostic() {
  print_header
  echo -e "${CYAN}${BOLD}🔧 FULL DIAGNOSTIC${NC}"
  echo ""
  
  echo -e "${YELLOW}1. IP Forwarding${NC}"
  sysctl net.ipv4.ip_forward 2>/dev/null | grep -E "= 1" >/dev/null && log_success "Enabled" || log_error "Disabled"
  
  echo ""
  echo -e "${YELLOW}2. WireGuard Installation${NC}"
  if command -v wg &> /dev/null; then
    log_success "Installed: $(wg --version)"
  else
    log_error "Not installed"
  fi
  
  echo ""
  echo -e "${YELLOW}3. WireGuard Service${NC}"
  systemctl is-active wg-quick@wg0 >/dev/null 2>&1 && log_success "Running" || log_error "Stopped"
  
  echo ""
  echo -e "${YELLOW}4. Configuration${NC}"
  [[ -f $WGCONF ]] && log_success "Config exists" || log_error "Missing config"
  
  echo ""
  echo -e "${YELLOW}5. Firewall Status${NC}"
  ufw status | grep -q "Status: active" && log_success "UFW active" || log_error "UFW inactive"
  
  echo ""
  echo -e "${YELLOW}6. Monitor Service${NC}"
  systemctl is-active wg-monitor >/dev/null 2>&1 && log_success "Running" || log_error "Stopped"
  
  echo ""
  echo -e "${YELLOW}7. Recent Logs${NC}"
  tail -5 $MONITORLOG 2>/dev/null || log_warning "No monitor logs yet"
  
  echo ""
  echo -e "${YELLOW}8. Network Interfaces${NC}"
  ip addr show wg0 2>/dev/null || log_error "wg0 interface not found"
  
  echo ""
  read -p "Press Enter to continue..."
}

# ==================== REPAIR ALL ====================
repair_all() {
  print_header
  echo -e "${YELLOW}${BOLD}🔨 REPAIRING ALL...${NC}"
  echo ""
  
  log_info "Restarting WireGuard..."
  systemctl restart wg-quick@wg0
  sleep 2
  
  log_info "Reloading firewall..."
  ufw reload >/dev/null 2>&1
  
  log_info "Reloading iptables..."
  iptables-restore < $IPRULES 2>/dev/null || true
  netfilter-persistent reload >/dev/null 2>&1
  
  log_info "Restarting monitor..."
  systemctl restart wg-monitor >/dev/null 2>&1
  
  log_info "Applying sysctl settings..."
  sysctl -p >/dev/null 2>&1
  
  sleep 3
  
  echo ""
  log_success "REPAIR COMPLETE"
  echo ""
  
  status_check
}

# ==================== LOGS VIEW ====================
view_logs() {
  print_header
  echo -e "${CYAN}${BOLD}📋 MONITOR LOGS${NC}"
  echo ""
  
  if [[ -f $MONITORLOG ]]; then
    tail -30 $MONITORLOG
  else
    log_warning "No logs yet"
  fi
  
  echo ""
  read -p "Press Enter to continue..."
}

# ==================== UNINSTALL ====================
uninstall_all() {
  print_header
  echo -e "${RED}${BOLD}⚠️  COMPLETE UNINSTALL${NC}"
  echo ""
  log_warning "This will remove WireGuard completely"
  echo ""
  read -p "${YELLOW}Type 'yes' to confirm: ${NC}" confirm
  
  if [[ "$confirm" != "yes" ]]; then
    log_info "Uninstall cancelled"
    return
  fi
  
  log_info "Stopping services..."
  systemctl stop wg-quick@wg0 2>/dev/null || true
  systemctl stop wg-monitor 2>/dev/null || true
  
  log_info "Disabling services..."
  systemctl disable wg-quick@wg0 2>/dev/null || true
  systemctl disable wg-monitor 2>/dev/null || true
  
  log_info "Removing files..."
  rm -rf $WGDIR $WGCONF /etc/systemd/system/wg-monitor* 2>/dev/null || true
  
  log_info "Removing packages..."
  apt purge -y wireguard wireguard-tools 2>/dev/null || true
  apt autoremove -y >/dev/null 2>&1
  
  systemctl daemon-reload >/dev/null 2>&1
  
  echo ""
  log_success "UNINSTALL COMPLETE"
  log_info "CasaOS and other services remain intact"
  echo ""
  
  read -p "Press Enter to continue..."
}

# ==================== UPDATE CHECK ====================
check_update() {
  print_header
  echo -e "${CYAN}${BOLD}📦 UPDATE CHECK${NC}"
  echo ""
  
  log_info "Checking for updates..."
  apt update >/dev/null 2>&1
  
  if apt list --upgradable 2>/dev/null | grep wireguard >/dev/null; then
    log_warning "WireGuard update available"
    read -p "${YELLOW}Update now? (yes/no): ${NC}" update
    
    if [[ "$update" == "yes" ]]; then
      log_info "Updating WireGuard..."
      systemctl stop wg-quick@wg0
      apt upgrade -y wireguard wireguard-tools >/dev/null 2>&1
      systemctl restart wg-quick@wg0
      log_success "Updated successfully"
    fi
  else
    log_success "WireGuard is up to date"
  fi
  
  echo ""
  read -p "Press Enter to continue..."
}

# ==================== MAIN MENU ====================
main_menu() {
  while true; do
    print_header
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  1) ☁️  VPS Server Setup                ║${NC}"
    echo -e "${CYAN}║  2) 🏠 Local Client Setup               ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  3) 🔍 Status Check                    ║${NC}"
    echo -e "${CYAN}║  4) 🔧 Full Diagnostic                 ║${NC}"
    echo -e "${CYAN}║  5) 🔨 Repair All                      ║${NC}"
    echo -e "${CYAN}║  6) 📋 View Monitor Logs               ║${NC}"
    echo -e "${CYAN}║  7) 📦 Check Updates                   ║${NC}"
    echo -e "${LGREEN}║  8) 🛡️  Reinstall Auto-Recovery       ║${NC}"
    echo -e "${RED}║  9) 🗑️  Complete Uninstall            ║${NC}"
    echo -e "${CYAN}║ 10) ❌ Exit                            ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════╝${NC}"
    
    echo -ne "\n${CYAN}Choose (1-10): ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) vps_server ;;
      2)
        echo -e "${YELLOW}Paste the complete CLIENT command from VPS:${NC}"
        echo -e "${CYAN}Example: sudo bash ./installer.sh client \"KEY\" IP PORT \"PORTS\"${NC}"
        echo ""
        read -p "Command: " CMD
        eval "$CMD"
        ;;
      3) status_check ;;
      4) full_diagnostic ;;
      5) repair_all ;;
      6) view_logs ;;
      7) check_update ;;
      8) install_monitor ;;
      9) uninstall_all ;;
      10) log_info "Goodbye!"; exit 0 ;;
      *) log_error "Invalid choice"; sleep 1 ;;
    esac
  done
}

# ==================== ENTRY POINT ====================
case "${1:-}" in
  client)
    shift
    local_client "$@"
    ;;
  uninstall|9)
    uninstall_all
    ;;
  status|3)
    status_check
    ;;
  diagnostic|4)
    full_diagnostic
    ;;
  repair|5)
    repair_all
    ;;
  logs|6)
    view_logs
    ;;
  update|7)
    check_update
    ;;
  recovery|8)
    install_monitor
    ;;
  *)
    main_menu
    ;;
esac
