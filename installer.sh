#!/bin/bash
# 🔥 CGNAT BYPASS v6.5 - SAFE ALL-IN-ONE
# VPS + Local + Auto-Recovery + NO iptables Touch

if [ $EUID != 0 ]; then
  exec sudo "$0" "$@"
  exit $?
fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

# ==================== SYSTEM SETUP ====================
setup_system() {
  apt update >/dev/null 2>&1
  apt install -y wireguard wireguard-tools curl iputils-ping netfilter-persistent
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
}

# ==================== VPS SERVER ====================
vps_server() {
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER SETUP${NC}"
  setup_system

  WGPORT=55108
  WG_SERVER_IP="10.1.0.1"
  WG_CLIENT_IP="10.1.0.2"
  PUB_IP=$(curl -s ifconfig.me)
  read -p "Public IP [$PUB_IP]: " input_ip
  [[ -n "$input_ip" ]] && PUB_IP="$input_ip"
  read -p "Service Ports [8098/tcp]: " SERVICE_PORTS
  SERVICE_PORTS=${SERVICE_PORTS:-"8098/tcp"}

  mkdir -p /etc/wireguard
  echo "$WG_CLIENT_IP" > /etc/wireguard/client_ip

  wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
  chmod 600 /etc/wireguard/server_private.key
  SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)

  echo ""
  echo -e "${LGREEN}${BOLD}CLIENT COMMAND (run on local):${NC}"
  echo "sudo $0 client \"$SERVER_PUBLIC_KEY\" $PUB_IP $WGPORT \"$SERVICE_PORTS\""
  echo ""
  echo -e "${CYAN}Run above on LOCAL, then paste its public key:${NC}"
  read -p "Client public key: " CLIENT_PUBLIC_KEY

  if [[ ${#CLIENT_PUBLIC_KEY} -ne 44 ]]; then
    echo -e "${RED}Invalid key length! Must be 44 chars.${NC}"
    exit 1
  fi

  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/server_private.key)
Address = $WG_SERVER_IP/24
ListenPort = $WGPORT

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $WG_CLIENT_IP/32
PersistentKeepalive = 15
EOF

  ufw allow $WGPORT/udp 2>/dev/null || true
  ufw allow OpenSSH 2>/dev/null || true
  for port_entry in $(echo "$SERVICE_PORTS" | tr ',' ' '); do
    ufw allow "$port_entry" 2>/dev/null || true
  done

  systemctl enable --now wg-quick@wg0
  sleep 5

  install_recovery
  echo -e "${GREEN}${BOLD}✅ VPS SERVER READY${NC}"
}

# ==================== LOCAL CLIENT ====================
local_client() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=$3; PORTS=$4
  WG_CLIENT_IP="10.1.0.2"
  WG_SERVER_IP="10.1.0.1"

  echo -e "${LGREEN}${BOLD}🏠 LOCAL CLIENT SETUP${NC}"
  setup_system

  mkdir -p /etc/wireguard
  wg genkey | tee /etc/wireguard/client_private.key | wg pubkey > /etc/wireguard/client_public.key
  chmod 600 /etc/wireguard/client_private.key
  CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/client_public.key)

  echo -e "${GREEN}${BOLD}YOUR PUBLIC KEY (give to VPS): $CLIENT_PUBLIC_KEY${NC}"

  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/client_private.key)
Address = $WG_CLIENT_IP/24

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBIP:$WGPORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 15
EOF

  systemctl enable --now wg-quick@wg0
  sleep 5

  if ping -c 3 $WG_SERVER_IP >/dev/null 2>&1; then
    echo -e "${GREEN}${BOLD}✅ TUNNEL CONNECTED${NC}"
  else
    echo -e "${RED}${BOLD}❌ VPS NOT RESPONDING${NC}"
    echo -e "${YELLOW}Check VPS: wg show${NC}"
  fi
}

# ==================== AUTO-RECOVERY ====================
install_recovery() {
  cat > /etc/systemd/system/wg-monitor.service << 'EOF'
[Unit]
Description=WireGuard Monitor
After=wg-quick@wg0.service
[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do sleep 300; systemctl is-active --quiet wg-quick@wg0 || systemctl restart wg-quick@wg0; done'
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now wg-monitor.service 2>/dev/null || true
  echo -e "${GREEN}${BOLD}✅ AUTO-RECOVERY INSTALLED${NC}"
}

# ==================== STATUS CHECK ====================
status_check() {
  clear
  echo -e "${CYAN}${BOLD}🔍 STATUS${NC}"
  wg show 2>/dev/null || echo "❌ No tunnel"
  echo -e "\n${CYAN}Services:${NC}"
  systemctl status wg-quick@wg0 2>/dev/null | head -10
  echo -e "\n${CYAN}Recovery:${NC}"
  systemctl status wg-monitor 2>/dev/null | head -5
  read -p "Press Enter..."
}

# ==================== UNINSTALL ====================
uninstall_all() {
  echo -e "${YELLOW}${BOLD}🗑️  SAFE UNINSTALL${NC}"
  systemctl stop wg-quick@wg0 wg-monitor 2>/dev/null || true
  rm -rf /etc/wireguard $WGCONF /etc/systemd/system/wg-*
  apt purge -y wireguard wireguard-tools netfilter-persistent 2>/dev/null || true
  echo -e "${GREEN}${BOLD}✅ CLEAN COMPLETE${NC}"
  echo -e "${YELLOW}CasaOS remains intact.${NC}"
  exit 0
}

# ==================== MAIN MENU ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║        CGNAT BYPASS v6.5             ║${NC}"
    echo -e "${LGREEN}${BOLD}║     SAFE ALL-IN-ONE                  ║${NC}"
    echo -e "${LGREEN}${BOLD}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  1) ☁️  VPS Server Setup              ║${NC}"
    echo -e "${CYAN}║  2) 🏠 Local Client Setup             ║${NC}"
    echo -e "${CYAN}║  3) 🔧 Fix VPS Issues                 ║${NC}"
    echo -e "${CYAN}║  4) 📊 Status Check                  ║${NC}"
    echo -e "${LGREEN}║  5) 🛡️  Auto-Recovery                ║${NC}"
    echo -e "${RED}║  6) 🗑️  Complete Uninstall           ║${NC}"
    echo -e "${CYAN}║  7) ❌ Exit                           ║${NC}"
    echo -e "${LGREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
    
    echo -ne "\n${CYAN}Choose (1-7): ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) vps_server ;;
      2) echo -e "${YELLOW}Paste VPS command:${NC}"; read CMD; eval "$CMD" ;;
      3) ufw allow 55108/udp 2>/dev/null || true; echo -e "${GREEN}Fixed${NC}" ;;
      4) status_check ;;
      5) install_recovery ;;
      6) uninstall_all ;;
      7) exit 0 ;;
      *) echo -e "${RED}Invalid${NC}"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  client) shift; local_client "$@" ;;
  uninstall|6) uninstall_all ;;
  status|4) status_check ;;
  recovery|5) install_recovery ;;
  *) main_menu ;;
esac
