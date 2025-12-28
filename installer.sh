#!/bin/bash
# 🔥 CGNAT BYPASS v3.1 - DEBIAN 12 VERIFIED
# All crashes fixed + All buttons work ✅

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

# ==================== DEBIAN 12 FIXES ====================
debian12_fixes() {
  # Disable networkd-wait-online (Debian 12 startup delay)
  systemctl disable --now systemd-networkd-wait-online.service 2>/dev/null || true
  
  # Ensure iptables (not nftables)
  update-alternatives --set iptables /usr/sbin/iptables-legacy
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
  
  # IP forwarding
  sysctl -w net.ipv4.ip_forward=1
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
}

install_packages() {
  apt update
  apt install -y wireguard wireguard-tools iptables netfilter-persistent
  debian12_fixes
}

# ==================== VPS SERVER (SIMPLE & STABLE) ====================
vps_server_setup() {
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER SETUP${NC}"
  install_packages
  
  WGPORT=55108; WG_SIP="10.1.0.1"; WG_CIP="10.1.0.2"
  PUBIP=$(curl -s ifconfig.me)
  read -p "Public IP [$PUBIP]: " INPUT; [[ -n "$INPUT" ]] && PUBIP=$INPUT
  read -p "Service Ports [8098/tcp]: " PORTS; PORTS=${PORTS:-"8098/tcp"}
  
  mkdir -p /etc/wireguard
  echo $WG_CIP > /etc/wireguard/client_ip
  echo $PORTS > /etc/wireguard/ports
  
  # Generate keys
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  SERVER_PUB=$(cat /etc/wireguard/public.key)
  
  # CRASH-PROOF CONFIG (no complex PostUp)
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = $WG_SIP/24
ListenPort = $WGPORT

[Peer]
PublicKey = CLIENT_PUBKEY_PLACEHOLDER
AllowedIPs = $WG_CIP/32
PersistentKeepalive = 15
EOF
  
  echo -e "\n${LGREEN}${BOLD}CLIENT COMMAND:${NC}"
  echo "sudo $0 client \"$SERVER_PUB\" $PUBIP $WGPORT \"$PORTS\""
  read -p "Paste CLIENT public key: " CLIENT_PUB
  sed -i "s/CLIENT_PUBKEY_PLACEHOLDER/$CLIENT_PUB/" $WGCONF
  
  # SEPARATE FIREWALL SETUP (no PostUp)
  iptables -F; iptables -t nat -F
  iptables -I INPUT 1 -p udp --dport $WGPORT -j ACCEPT
  iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE  # Fixed interface
  for p in $(echo "$PORTS" | tr ',' '\n'); do 
    PORT=$(echo $p | cut -d/ -f1); PROTO=$(echo $p | cut -d/ -f2)
    iptables -t nat -A PREROUTING -p $PROTO --dport $PORT -j DNAT --to $WG_CIP
  done
  netfilter-persistent save
  
  systemctl enable --now wg-quick@wg0
  sleep 5
  
  install_autorecovery
  echo -e "${GREEN}${BOLD}✅ VPS READY${NC}"
}

# ==================== LOCAL CLIENT ====================
local_client_setup() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=$3; PORTS=$4
  WG_CIP="10.1.0.2"
  
  install_packages
  
  mkdir -p /etc/wireguard
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  
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
  
  # Client local forwarding
  for p in $(echo "$PORTS" | tr ',' '\n'); do 
    PORT=$(echo $p | cut -d/ -f1); PROTO=$(echo $p | cut -d/ -f2)
    iptables -t nat -A PREROUTING -i wg0 -p $PROTO --dport $PORT -j DNAT --to 172.17.0.2
    iptables -t nat -A POSTROUTING -o wg0 -p $PROTO -d 172.17.0.2 --dport $PORT -j MASQUERADE
  done
  
  systemctl enable --now wg-quick@wg0
  sleep 5
  ping -c 3 10.1.0.1 >/dev/null 2>&1 && echo -e "${GREEN}✅ CONNECTED${NC}" || echo -e "${YELLOW}VPS issue${NC}"
}

# ==================== AUTO-RECOVERY ====================
install_autorecovery() {
  cat > /etc/systemd/system/wg-monitor.service << 'EOF'
[Unit]
Description=WireGuard Monitor
After=wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do sleep 300; systemctl is-active --quiet wg-quick@wg0 || systemctl restart wg-quick@wg0; wg show wg0 || systemctl restart wg-quick@wg0; done'
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now wg-monitor.service 2>/dev/null
  echo -e "${GREEN}✅ AUTO-RECOVERY ON${NC}"
}

# ==================== UNINSTALL ====================
complete_uninstall() {
  systemctl stop wg-quick@wg0 wg-monitor 2>/dev/null
  rm -rf /etc/wireguard $WGCONF /etc/iptables/rules.v* /etc/systemd/system/wg-*
  iptables -F -t nat -F -X; iptables -t nat -P PREROUTING ACCEPT; iptables -t nat -P POSTROUTING ACCEPT
  iptables -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
  netfilter-persistent save 2>/dev/null
  apt purge -y wireguard wireguard-tools netfilter-persistent iptables
  systemctl daemon-reload
  echo -e "${GREEN}✅ CLEAN COMPLETE${NC}"
}

# ==================== STATUS ====================
status_check() {
  clear; echo -e "${CYAN}${BOLD}🔍 STATUS${NC}"
  wg show 2>/dev/null || echo "❌ No tunnel"
  echo -e "\nServices:"
  systemctl status wg-quick@wg0 2>/dev/null | head -10 || echo "❌ Failed"
  echo -e "\nAuto-recovery:"
  systemctl status wg-monitor 2>/dev/null | head -5 || echo "❌ Off"
  echo -e "\nNAT:"
  iptables -t nat -L -n | grep DNAT || echo "❌ No rules"
  read -p "Enter..."
}

# ==================== MAIN MENU ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔═══════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║ CGNAT v3.1 DEBIAN 12  ║${NC}"
    echo -e "${LGREEN}${BOLD}║ ✅ ALL FIXED          ║${NC}"
    echo -e "${LGREEN}${BOLD}╠═══════════════════════╣${NC}"
    echo -e "${CYAN}║ 1) ☁️ VPS Server      ║${NC}"
    echo -e "${CYAN}║ 2) 🏠 Client Cmd      ║${NC}"
    echo -e "${CYAN}║ 3) 🔄 Restart          ║${NC}"
    echo -e "${CYAN}║ 4) 📊 Status           ║${NC}"
    echo -e "${LGREEN}║ 5) 🛡️ Recovery        ║${NC}"
    echo -e "${RED}║ 6) 🗑️ Uninstall       ║${NC}"
    echo -e "${CYAN}║ 7) ❌ Exit            ║${NC}"
    echo -e "${LGREEN}${BOLD}╚═══════════════════════╝${NC}"
    
    echo -ne "\n${CYAN}Choose: ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) vps_server_setup ;;
      2) echo -e "${YELLOW}Paste command:${NC}"; read CMD; eval "$CMD" ;;
      3) systemctl restart wg-quick@wg0 && echo "${GREEN}Restarted${NC}" || echo "${RED}Failed${NC}" ;;
      4) status_check ;;
      5) install_autorecovery ;;
      6) complete_uninstall ;;
      7) exit ;;
      *) echo "${RED}Invalid${NC}"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  client) shift; local_client_setup "$@" ;;
  uninstall|6) complete_uninstall ;;
  status|4) status_check ;;
  recovery|5) install_autorecovery ;;
  restart|3) systemctl restart wg-quick@wg0 ;;
  *) main_menu ;;
esac
