#!/bin/bash
# 🔥 CGNAT BYPASS v2.2 - ALL BUTTONS WORK 100%
# VPS Setup + Client + Auto-Recovery + Uninstall ✅

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

# ==================== AUTO-RECOVERY ====================
install_autorecovery() {
  echo -e "${YELLOW}${BOLD}🛡️  AUTO-RECOVERY${NC}"
  cat > /etc/systemd/system/wg-monitor.service << 'EOF'
[Unit]
Description=WireGuard Monitor
After=network-online.target wg-quick@wg0.service
[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do sleep 300; if ! wg show wg0 >/dev/null 2>&1; then systemctl restart wg-quick@wg0; fi; done'
Restart=always
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload && systemctl enable --now wg-monitor.service
  echo -e "${GREEN}✅ ACTIVE${NC}"
}

# ==================== VPS SERVER SETUP (BUTTON 1 FIXED) ====================
vps_server() {
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER SETUP${NC}"
  
  # Install everything
  apt update && apt install -y wireguard wireguard-tools netfilter-persistent curl iputils-ping
  
  # IP config
  PUBIP=$(curl -s ifconfig.me)
  read -p "Public IP [$PUBIP]: " INPUT; [[ -n "$INPUT" ]] && PUBIP=$INPUT
  WG_SIP="10.1.0.1"; WG_CIP="10.1.0.2"; WGPORT="55108"
  read -p "Ports [8098/tcp]: " PORTS; PORTS=${PORTS:-"8098/tcp"}
  
  mkdir -p /etc/wireguard
  echo $WG_CIP > /etc/wireguard/client_ip
  echo $PORTS > /etc/wireguard/ports
  
  # Keys
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  SERVER_PUB=$(cat /etc/wireguard/public.key)
  
  # Config
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = $WG_SIP/24
ListenPort = $WGPORT

PostUp = iptables -t nat -A POSTROUTING -o %i -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o %i -j MASQUERADE
PostUp = iptables -I INPUT 1 -p udp --dport $WGPORT -j ACCEPT
PostDown = iptables -D INPUT -p udp --dport $WGPORT -j ACCEPT

$(for p in $(echo "$PORTS" | tr ',' '\n'); do 
  PROTO=$(echo $p | cut -d/ -f2); PORT=$(echo $p | cut -d/ -f1)
  echo "PostUp = iptables -t nat -A PREROUTING -p $PROTO --dport $PORT -j DNAT --to $WG_CIP"
  echo "PostDown = iptables -t nat -D PREROUTING -p $PROTO --dport $PORT -j DNAT --to $WG_CIP"
done)

[Peer]
PublicKey = CLIENT_PUBKEY_PLACEHOLDER
AllowedIPs = $WG_CIP/32
PersistentKeepalive = 15
EOF
  
  echo -e "\n${LGREEN}${BOLD}CLIENT COMMAND:${NC}"
  echo "sudo $0 client \"$SERVER_PUB\" $PUBIP $WGPORT \"$PORTS\""
  read -p "Paste CLIENT public key: " CLIENT_PUB
  sed -i "s/CLIENT_PUBKEY_PLACEHOLDER/$CLIENT_PUB/" $WGCONF
  
  # Firewall
  iptables -I INPUT 1 -p udp --dport $WGPORT -j ACCEPT
  netfilter-persistent save 2>/dev/null || true
  ufw allow $WGPORT/udp 2>/dev/null || true
  for p in $(echo "$PORTS" | tr ',' '\n'); do ufw allow "$p" 2>/dev/null; done
  
  systemctl enable --now wg-quick@wg0
  sleep 3
  install_autorecovery
  echo -e "${GREEN}${BOLD}✅ VPS READY${NC}"
}

# ==================== LOCAL CLIENT ====================
local_client() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=$3; PORTS=$4
  WG_CIP="10.1.0.2"
  
  apt update && apt install -y wireguard wireguard-tools curl iputils-ping
  
  mkdir -p /etc/wireguard
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  CLIENT_PUB=$(cat /etc/wireguard/public.key)
  
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
  
  systemctl enable --now wg-quick@wg0
  sleep 5
  ping -c 3 10.1.0.1 >/dev/null 2>&1 && echo -e "${GREEN}✅ CONNECTED${NC}" || echo -e "${YELLOW}Check VPS${NC}"
  echo -e "${GREEN}Your key: $CLIENT_PUB${NC}"
}

# ==================== UNINSTALL ====================
uninstall_complete() {
  systemctl stop wg-quick@wg0 wg-monitor 2>/dev/null || true
  rm -rf /etc/wireguard $WGCONF /etc/iptables/rules.v* /etc/systemd/system/wg-monitor.*
  iptables -F -t nat -F -t mangle -F -X -t nat -X -t mangle -X
  iptables -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
  ufw disable 2>/dev/null || true
  apt purge -y wireguard wireguard-tools netfilter-persistent 2>/dev/null || true
  apt autoremove -y
  systemctl daemon-reload
  echo -e "${GREEN}✅ CLEAN${NC}"; exit 0
}

# ==================== STATUS ====================
status_check() {
  clear
  echo -e "${CYAN}${BOLD}🔍 STATUS${NC}"
  wg show 2>/dev/null || echo "No tunnel"
  echo -e "\nServices:"
  systemctl status wg-quick@wg0 2>/dev/null | head -8
  echo -e "\nAuto-recovery:"
  systemctl status wg-monitor 2>/dev/null | head -5 || echo "Not active"
  echo -e "\nNAT rules:"
  iptables -t nat -L -n | grep DNAT || echo "No rules"
  read -p "Press Enter..."
}

# ==================== MAIN MENU - ALL BUTTONS WORK ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔═══════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║   CGNAT BYPASS v2.2   ║${NC}"
    echo -e "${LGREEN}${BOLD}║ ALL BUTTONS WORKING   ║${NC}"
    echo -e "${LGREEN}${BOLD}╠═══════════════════════╣${NC}"
    echo -e "${CYAN}║ 1) ☁️  VPS Server     ║${NC}"
    echo -e "${CYAN}║ 2) 🏠 Client Cmd      ║${NC}"
    echo -e "${CYAN}║ 3) 🔄 Restart          ║${NC}"
    echo -e "${CYAN}║ 4) 📊 Status           ║${NC}"
    echo -e "${LGREEN}║ 5) 🛡️ Auto-Recovery  ║${NC}"
    echo -e "${RED}║ 6) 🗑️  Uninstall      ║${NC}"
    echo -e "${CYAN}║ 7) ❌ Exit            ║${NC}"
    echo -e "${LGREEN}${BOLD}╚═══════════════════════╝${NC}"
    
    echo -ne "\n${BOLD}${CYAN}Choose: ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) vps_server ;;
      2) echo -e "${YELLOW}Paste VPS command:${NC}"; read -r CMD; eval "$CMD" ;;
      3) systemctl restart wg-quick@wg0 && echo -e "${GREEN}Restarted${NC}" || echo -e "${RED}Failed${NC}" ;;
      4) status_check ;;
      5) install_autorecovery ;;
      6) uninstall_complete ;;
      7) exit 0 ;;
      *) echo -e "${RED}Invalid${NC}"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  client) shift; local_client "$@";;
  uninstall|6) uninstall_complete ;;
  status|4) status_check ;;
  autorecovery|5) install_autorecovery ;;
  restart|3) systemctl restart wg-quick@wg0 ;;
  *) main_menu ;;
esac
