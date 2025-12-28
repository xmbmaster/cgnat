#!/bin/bash
# 🔥 CGNAT BYPASS v4.1 - NO PLACEHOLDERS + BULLETPROOF
# VPS + Local + Auto-Fix + Recovery ✅

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

fix_system() {
  apt update >/dev/null 2>&1
  apt install -y wireguard wireguard-tools iptables netfilter-persistent curl iputils-ping
  sysctl -w net.ipv4.ip_forward=1
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
}

# ==================== VPS SERVER (NO PLACEHOLDER BUG) ====================
vps_setup() {
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER SETUP${NC}"
  fix_system
  
  echo -e "${YELLOW}${BOLD}ORACLE VCN:${NC} UDP 55108 + service ports"
  read -p "Press Enter AFTER VCN rules added..."
  
  WGPORT=55108; WG_SIP="10.1.0.1"; WG_CIP="10.1.0.2"
  PUBIP=$(curl -s ifconfig.me 2>/dev/null || echo "DETECT")
  read -p "Public IP [$PUBIP]: " INPUT; [[ -n "$INPUT" ]] && PUBIP=$INPUT
  read -p "Service Ports [8098/tcp]: " PORTS; PORTS=${PORTS:-"8098/tcp"}
  
  mkdir -p /etc/wireguard
  echo $WG_CIP > /etc/wireguard/client_ip
  echo $PORTS > /etc/wireguard/ports
  
  # Generate keys
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  SERVER_PUB=$(cat /etc/wireguard/public.key)
  
  echo -e "\n${LGREEN}${BOLD}CLIENT COMMAND:${NC}"
  echo "sudo $0 client \"$SERVER_PUB\" $PUBIP $WGPORT \"$PORTS\""
  
  # GET CLIENT KEY FIRST
  echo -e "${CYAN}On LOCAL server, run client command above, then paste its public key:${NC}"
  read -p "CLIENT PUBLIC KEY: " CLIENT_PUB
  
  # VALIDATE KEY
  if [[ ${#CLIENT_PUB} -ne 44 ]]; then
    echo -e "${RED}Invalid key length! Must be 44 chars.${NC}"
    exit 1
  fi
  
  # BUILD CONFIG DIRECTLY (NO PLACEHOLDER)
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = $WG_SIP/24
ListenPort = $WGPORT

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $WG_CIP/32
PersistentKeepalive = 15
EOF
  
  echo -e "${GREEN}✅ Config created:${NC}"
  cat $WGCONF
  
  # MANUAL FIREWALL
  iptables -F; iptables -t nat -F
  iptables -I INPUT 1 -p udp --dport $WGPORT -j ACCEPT
  iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
  for p in $(echo "$PORTS" | tr ',' '\n'); do 
    PORT=$(echo $p | cut -d/ -f1); PROTO=$(echo $p | cut -d/ -f2 2>/dev/null || echo tcp)
    iptables -t nat -A PREROUTING -p $PROTO --dport $PORT -j DNAT --to $WG_CIP
  done
  netfilter-persistent save 2>/dev/null || true
  
  ufw allow $WGPORT/udp 2>/dev/null || true
  ufw allow OpenSSH 2>/dev/null || true
  
  systemctl enable --now wg-quick@wg0
  sleep 5
  
  install_recovery
  echo -e "${GREEN}${BOLD}✅ VPS READY!${NC}"
  echo -e "${YELLOW}Verify: wg show${NC}"
}

# ==================== LOCAL CLIENT ====================
local_setup() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=$3; PORTS=$4
  WG_CIP="10.1.0.2"; WG_SIP="10.1.0.1"
  
  echo -e "${LGREEN}${BOLD}🏠 LOCAL CLIENT${NC}"
  fix_system
  
  mkdir -p /etc/wireguard
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  CLIENT_PUB=$(cat /etc/wireguard/public.key)
  
  echo -e "${GREEN}${BOLD}YOUR PUBLIC KEY: $CLIENT_PUB${NC}"
  echo -e "${GREEN}${BOLD}Copy this to VPS server!${NC}"
  
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = $WG_CIP/24

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBIP:$WGPORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 15
EOF
  
  # Local Docker forwarding
  iptables -t nat -F PREROUTING POSTROUTING
  for p in $(echo "$PORTS" | tr ',' '\n'); do 
    PORT=$(echo $p | cut -d/ -f1); PROTO=$(echo $p | cut -d/ -f2 2>/dev/null || echo tcp)
    iptables -t nat -A PREROUTING -i wg0 -p $PROTO --dport $PORT -j DNAT --to 172.17.0.2:$PORT
    iptables -t nat -A POSTROUTING -o wg0 -p $PROTO -d 172.17.0.2 --dport $PORT -j MASQUERADE
  done
  netfilter-persistent save 2>/dev/null || true
  
  systemctl enable --now wg-quick@wg0
  sleep 5
  
  if ping -c 3 $WG_SIP >/dev/null 2>&1; then
    echo -e "${GREEN}${BOLD}✅ TUNNEL UP${NC}"
  else
    echo -e "${RED}${BOLD}❌ VPS DOWN${NC}"
    echo -e "${YELLOW}On VPS run: wg show${NC}"
  fi
}

# ==================== RECOVERY ====================
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
  echo -e "${GREEN}✅ RECOVERY ON${NC}"
}

diagnostics() {
  clear; echo -e "${CYAN}${BOLD}DIAGNOSTICS${NC}"
  wg show 2>/dev/null || echo "❌ No tunnel"
  echo -e "\nServices:"
  systemctl status wg-quick@wg0 2>/dev/null | head -10
  echo -e "\nUDP 55108:"
  ss -ulnp | grep 55108 || echo "❌ Closed"
  echo -e "\nNAT:"
  iptables -t nat -L | grep DNAT || echo "❌ None"
  echo -e "\nLogs:"
  journalctl -u wg-quick@wg0 -n 5
  read -p "Enter..."
}

uninstall_all() {
  systemctl stop wg-quick@wg0 wg-monitor
  rm -rf /etc/wireguard $WGCONF /etc/iptables/rules.v* /etc/systemd/system/wg-*
  iptables -F -t nat -F -X; iptables -P INPUT ACCEPT
  netfilter-persistent save 2>/dev/null
  apt purge -y wireguard* netfilter-persistent iptables
  systemctl daemon-reload
  echo -e "${GREEN}✅ CLEAN${NC}"
}

# ==================== MAIN MENU ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔═══════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║ CGNAT v4.1 FIXED      ║${NC}"
    echo -e "${LGREEN}${BOLD}║ NO PLACEHOLDER BUG    ║${NC}"
    echo -e "${LGREEN}${BOLD}╠═══════════════════════╣${NC}"
    echo -e "${CYAN}║ 1) ☁️ VPS Server      ║${NC}"
    echo -e "${CYAN}║ 2) 🏠 Local Client    ║${NC}"
    echo -e "${CYAN}║ 3) 🔧 Fix VPS         ║${NC}"
    echo -e "${CYAN}║ 4) 📊 Diagnostics     ║${NC}"
    echo -e "${LGREEN}║ 5) 🛡️ Recovery       ║${NC}"
    echo -e "${RED}║ 6) 🗑️ Uninstall      ║${NC}"
    echo -e "${CYAN}║ 7) ❌ Exit           ║${NC}"
    echo -e "${LGREEN}${BOLD}╚═══════════════════════╝${NC}"
    
    echo -ne "\n${CYAN}Choose: ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) vps_setup ;;
      2) echo -e "${YELLOW}Paste VPS command:${NC}"; read CMD; eval "$CMD" ;;
      3) iptables -F; iptables -I INPUT 1 -p udp --dport 55108 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; netfilter-persistent save; echo "${GREEN}Fixed${NC}" ;;
      4) diagnostics ;;
      5) install_recovery ;;
      6) uninstall_all ;;
      7) exit ;;
      *) echo "${RED}Invalid${NC}"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  client) shift; local_setup "$@" ;;
  fix|3) iptables -I INPUT 1 -p udp --dport 55108 -j ACCEPT; echo "${GREEN}Fixed${NC}" ;;
  diagnose|4) diagnostics ;;
  recovery|5) install_recovery ;;
  uninstall|6) uninstall_all ;;
  *) main_menu ;;
esac
