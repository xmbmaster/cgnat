#!/bin/bash
# All-in-One WireGuard Installer for VPS & Local Machines
# Supports TCP/UDP port forwarding, firewall setup, and full uninstall

WGCONFLOC='/etc/wireguard/wg0.conf'
WGPUBKEY='/etc/wireguard/publickey'
WGCLIENTIPFILE='/etc/wireguard/client_ip'
WGPORTSFILE='/etc/wireguard/forwarded_ports'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
CYAN='\033[36m'; LCYAN='\033[96m'; MAGEN='\033[1;35m'

#---------------- Functions ----------------#

stop_wireguard() {
  echo -e "${YELLOW}Stopping WireGuard...${NC}"
  systemctl stop wg-quick@wg0 2>/dev/null
  wg-quick down wg0 2>/dev/null
}

uninstall_wireguard() {
  stop_wireguard
  echo -e "${YELLOW}Removing WireGuard configuration and packages...${NC}"
  rm -f $WGCONFLOC $WGPUBKEY $WGCLIENTIPFILE $WGPORTSFILE
  ufw --force reset
  apt remove --purge wireguard ufw -y
  apt autoremove -y
  echo -e "${GREEN}Uninstall complete.${NC}"
  exit
}

update_system() {
  echo -e "${YELLOW}Updating system...${NC}"
  apt update && apt upgrade -y
}

install_required() {
  echo -e "${YELLOW}Installing required packages...${NC}"
  apt install wireguard ufw iptables-persistent -y
}

enable_ip_forwarding() {
  echo -e "${YELLOW}Enabling IPv4 forwarding...${NC}"
  sysctl -w net.ipv4.ip_forward=1
  sed -i '/^net.ipv4.ip_forward/d' /etc/sysctl.conf
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
}

get_ip_input() {
  echo -e "${CYAN}Enter the following IPs (or press enter for default)${NC}"
  read -p "VPS Public IP [auto]: " PUBLIC_IP
  PUBLIC_IP=${PUBLIC_IP:-$(curl -s https://api.ipify.org)}
  
  read -p "WireGuard Server IP [10.1.0.1]: " WG_SERVER_IP
  WG_SERVER_IP=${WG_SERVER_IP:-10.1.0.1}
  
  read -p "WireGuard Client IP [10.1.0.2]: " WG_CLIENT_IP
  WG_CLIENT_IP=${WG_CLIENT_IP:-10.1.0.2}
  
  read -p "WireGuard Port [55108]: " WGPORT
  WGPORT=${WGPORT:-55108}
  
  echo $WG_CLIENT_IP > $WGCLIENTIPFILE
}

create_keys() {
  echo -e "${YELLOW}Creating WireGuard keys...${NC}"
  umask 077
  wg genkey | tee privatekey | wg pubkey > publickey
  mkdir -p /etc/wireguard
  mv privatekey $WGCONFLOC
  mv publickey $WGPUBKEY
}

configure_server() {
  PK_FOR_CLIENT=$(cat $WGPUBKEY)
  read -p "Enter Public Key from Local Client: " PK_FOR_SERVER
  
  echo "[Interface]" > $WGCONFLOC
  echo "PrivateKey = $(cat $WGCONFLOC)" >> $WGCONFLOC
  echo "Address = $WG_SERVER_IP/24" >> $WGCONFLOC
  echo "ListenPort = $WGPORT" >> $WGCONFLOC
  
  echo "[Peer]" >> $WGCONFLOC
  echo "PublicKey = $PK_FOR_SERVER" >> $WGCONFLOC
  echo "AllowedIPs = $WG_CLIENT_IP/32" >> $WGCONFLOC
  
  echo -e "${GREEN}Server configuration complete.${NC}"
}

configure_client() {
  read -p "Enter Public Key from VPS Server: " PK_FOR_SERVER
  echo "[Interface]" > $WGCONFLOC
  echo "PrivateKey = $(cat $WGCONFLOC)" >> $WGCONFLOC
  echo "Address = $WG_CLIENT_IP/24" >> $WGCONFLOC
  
  echo "[Peer]" >> $WGCONFLOC
  echo "PublicKey = $PK_FOR_SERVER" >> $WGCONFLOC
  echo "Endpoint = $PUBLIC_IP:$WGPORT" >> $WGCONFLOC
  echo "AllowedIPs = 0.0.0.0/0" >> $WGCONFLOC
  echo "PersistentKeepalive = 25" >> $WGCONFLOC
}

setup_firewall() {
  echo -e "${YELLOW}Setting up UFW firewall...${NC}"
  ufw --force reset
  SSHD_PORT=$(grep -E "Port [0-9]+" /etc/ssh/sshd_config | awk '{print $2}')
  ufw allow $SSHD_PORT/tcp
  ufw allow $WGPORT/udp
  read -p "Enter ports to whitelist (comma separated, e.g., 80/tcp,443/tcp): " PORTLIST
  echo $PORTLIST > $WGPORTSFILE
  for PORT in $(echo $PORTLIST | tr ',' ' '); do
    ufw allow $PORT
  done
  ufw default deny incoming
  ufw default allow outgoing
  ufw --force enable
  echo -e "${GREEN}Firewall configured.${NC}"
}

start_wireguard() {
  systemctl enable wg-quick@wg0
  systemctl start wg-quick@wg0
  echo -e "${GREEN}WireGuard started and enabled on reboot.${NC}"
}

#---------------- Menu ----------------#

clear
echo -e "${MAGEN}Oracle Cloud WireGuard Installer - All-in-One${NC}"
echo "Select an option:"
options=("Install VPS Server" "Install Local Client" "Modify Client Ports" "Uninstall WireGuard" "Exit")
select opt in "${options[@]}"; do
  case $opt in
    "Install VPS Server")
      stop_wireguard
      update_system
      install_required
      enable_ip_forwarding
      get_ip_input
      create_keys
      configure_server
      setup_firewall
      start_wireguard
      break
      ;;
    "Install Local Client")
      stop_wireguard
      update_system
      install_required
      get_ip_input
      create_keys
      configure_client
      start_wireguard
      break
      ;;
    "Modify Client Ports")
      stop_wireguard
      get_ip_input
      setup_firewall
      start_wireguard
      break
      ;;
    "Uninstall WireGuard")
      uninstall_wireguard
      ;;
    "Exit")
      exit
      ;;
    *) echo "Invalid option";;
  esac
done
