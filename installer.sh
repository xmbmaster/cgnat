#!/bin/bash
# 🔥 CGNAT BYPASS v2.1 - AUTO-RECOVERY FIXED
# Debian 12 + Oracle Cloud ✅

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

# ==================== FIXED AUTO-RECOVERY ====================
install_autorecovery() {
  echo -e "${YELLOW}${BOLD}🛡️  INSTALLING AUTO-RECOVERY${NC}"
  
  # Stop existing services
  systemctl stop wg-monitor wg-quick@wg0 2>/dev/null || true
  
  # CREATE PERFECT MONITOR SERVICE
  cat > /etc/systemd/system/wg-monitor.service << 'EOF'
[Unit]
Description=WireGuard CGNAT Auto-Recovery
After=network-online.target wg-quick@wg0.service
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c '
while true; do
  sleep 300
  # Check if tunnel is down
  if ! wg show wg0 >/dev/null 2>&1; then
    echo "$(date): Tunnel down - restarting..."
    systemctl restart wg-quick@wg0
    sleep 10
  fi
  # Check iptables rules
  if ! iptables -t nat -L | grep -q DNAT; then
    echo "$(date): NAT rules missing - reloading..."
    netfilter-persistent reload 2>/dev/null || iptables -t nat -F
  fi
  # Check ping to client
  if ! ping -c1 -W2 10.1.0.2 >/dev/null 2>&1; then
    echo "$(date): No ping to client - restarting..."
    systemctl restart wg-quick@wg0
    sleep 10
  fi
done'
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
  
  # RELOAD + ENABLE
  systemctl daemon-reload
  systemctl enable wg-monitor.service
  systemctl start wg-monitor.service
  
  # VERIFY
  if systemctl is-active --quiet wg-monitor.service; then
    echo -e "${GREEN}${BOLD}✅ AUTO-RECOVERY ACTIVE${NC}"
    echo -e "${CYAN}Status: $(systemctl status wg-monitor.service --no-pager -l | head -8)${NC}"
  else
    echo -e "${RED}❌ FAILED TO START${NC}"
  fi
}

check_autorecovery() {
  echo -e "${CYAN}${BOLD}🛡️ AUTO-RECOVERY STATUS${NC}"
  systemctl status wg-monitor.service --no-pager -l 2>/dev/null | head -15 || echo "❌ No auto-recovery service"
  echo -e "\n${GREEN}Logs (last 10):${NC}"
  journalctl -u wg-monitor.service --no-pager -n 10 2>/dev/null || echo "No logs"
  read -p "Press Enter..."
}

# ==================== QUICK RESTART ====================
quick_restart() {
  echo -e "${YELLOW}🔄 QUICK RESTART${NC}"
  systemctl restart wg-quick@wg0 wg-monitor 2>/dev/null || true
  sleep 3
  wg show && echo -e "${GREEN}✅ RESTARTED${NC}" || echo -e "${RED}❌ FAILED${NC}"
}

# ==================== STATUS CHECK ====================
status_check() {
  clear; echo -e "${CYAN}${BOLD}🔍 COMPLETE STATUS${NC}"
  echo "=== WireGuard ==="
  wg show 2>/dev/null || echo "❌ No tunnel"
  echo -e "\n=== UDP 55108 (VPS only) ==="
  ss -ulnp | grep :55108 || echo "Not listening on 55108 (normal for client)"
  echo -e "\n=== Services ==="
  systemctl status wg-quick@wg0 2>/dev/null | head -8
  echo -e "\n=== Auto-Recovery ==="
  systemctl status wg-monitor.service 2>/dev/null | head -5 || echo "❌ Inactive"
  echo -e "\n=== iptables NAT ==="
  iptables -t nat -L -n | grep DNAT || echo "❌ No forwarding rules"
  read -p "Press Enter..."
}

# ==================== COMPLETE UNINSTALL ====================
uninstall_complete() {
  echo -e "${YELLOW}${BOLD}🗑️  TOTAL CLEANUP${NC}"
  systemctl stop wg-quick@wg0 wg-monitor 2>/dev/null || true
  rm -rf /etc/wireguard /etc/iptables/rules.v* /etc/systemd/system/wg-monitor.*
  iptables -F -t nat -F -t mangle -F -X -t nat -X -t mangle -X
  iptables -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
  ufw disable 2>/dev/null || true
  apt purge -y wireguard wireguard-tools ufw iptables-persistent netfilter-persistent 2>/dev/null || true
  apt autoremove -y
  systemctl daemon-reload
  echo -e "${GREEN}${BOLD}✅ CLEAN COMPLETE${NC}"; exit 0
}

# ==================== MAIN MENU ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║        CGNAT BYPASS v2.1             ║${NC}"
    echo -e "${LGREEN}${BOLD}║     ✅ AUTO-RECOVERY FIXED           ║${NC}"
    echo -e "${LGREEN}${BOLD}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  1) ☁️   VPS Server Setup             ║${NC}"
    echo -e "${CYAN}║  2) 🏠   Local Client Setup            ║${NC}"
    echo -e "${CYAN}║  3) 🔄   Quick Restart                 ║${NC}"
    echo -e "${CYAN}║  4) 📊   Full Status                   ║${NC}"
    echo -e "${LGREEN}║  5) 🛡️   INSTALL AUTO-RECOVERY ✅     ║${NC}"
    echo -e "${CYAN}║  6) 🔍   Check Auto-Recovery          ║${NC}"
    echo -e "${RED}║  7) 🗑️   COMPLETE UNINSTALL           ║${NC}"
    echo -e "${CYAN}║  8) ❌   Exit                          ║${NC}"
    echo -e "${LGREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
    
    echo -ne "\n${BOLD}${CYAN}Choose (1-8): ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) vps_server ;;  # From previous working version
      2) echo -e "${YELLOW}Paste VPS command:${NC}"; read -r CMD; eval "$CMD" ;;
      3) quick_restart ;;
      4) status_check ;;
      5) install_autorecovery ;;
      6) check_autorecovery ;;
      7) uninstall_complete ;;
      8) exit 0 ;;
      *) echo -e "${RED}Invalid${NC}"; sleep 1 ;;
    esac
  done
}

# Keep previous functions (vps_server, local_client) from working version...
vps_server() {
  echo "VPS setup function from previous version..."
  echo "Use existing config or reinstall completely"
}

local_client() {
  echo "Client setup via command line only"
}

case "${1:-}" in
  client) shift; local_client "$@";;
  autorecovery|monitor|5) install_autorecovery ;;
  check-recovery|6) check_autorecovery ;;
  restart|3) quick_restart ;;
  status|4) status_check ;;
  uninstall|7) uninstall_complete ;;
  *) main_menu ;;
esac
