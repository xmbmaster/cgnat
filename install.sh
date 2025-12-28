#!/bin/bash
# Fixed Oracle Cloud WireGuard Installer (Server + Client) + Auto Key Exchange + One-Click Uninstall
# Author: Adapted for full automation

WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/wg0.conf"
WG_PRIV="$WG_DIR/privatekey"
WG_PUB="$WG_DIR/publickey"
WG_CLIENT_IP_FILE="$WG_DIR/client_ip"
WG_PORTS_FILE="$WG_DIR/forwarded_ports"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[36m'
NC='\033[0m'

mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"

stop_wg(){
    echo -e "${YELLOW}Stopping WireGuard...${NC}"
    systemctl stop wg-quick@wg0 2>/dev/null
    wg-quick down wg0 2>/dev/null
}

uninstall_wg(){
    stop_wg
    echo -e "${YELLOW}Removing WireGuard and configs...${NC}"
    apt remove --purge wireguard -y
    rm -rf "$WG_DIR"
    systemctl disable wg-quick@wg0 2>/dev/null
    echo -e "${GREEN}WireGuard removed.${NC}"
    exit 0
}

install_wg(){
    echo -e "${YELLOW}Installing WireGuard...${NC}"
    apt update && apt install wireguard -y
}

enable_forwarding(){
    echo -e "${YELLOW}Enabling IP forwarding...${NC}"
    sed -i '/^net.ipv4.ip_forward/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
}

generate_keys(){
    echo -e "${YELLOW}Generating WireGuard keys...${NC}"
    umask 077
    wg genkey | tee "$WG_PRIV" | wg pubkey > "$WG_PUB"
}

read_server_info(){
    if [ "$MODE" == "client" ]; then
        read -p "Server Public Key: " SERVER_PUB
        read -p "Server Endpoint (IP:Port): " SERVER_EP
    fi
}

create_client_conf(){
    CLIENT_IP=${1:-10.1.0.2}
    WG_PORT=${2:-51820}

    echo -e "[Interface]" > "$WG_CONF"
    echo "PrivateKey = $(cat $WG_PRIV)" >> "$WG_CONF"
    echo "Address = $CLIENT_IP/24" >> "$WG_CONF"
    echo "DNS = 1.1.1.1" >> "$WG_CONF"
    echo "" >> "$WG_CONF"
    echo "[Peer]" >> "$WG_CONF"
    echo "PublicKey = $SERVER_PUB" >> "$WG_CONF"
    echo "AllowedIPs = 0.0.0.0/0" >> "$WG_CONF"
    echo "Endpoint = $SERVER_EP" >> "$WG_CONF"
    echo "PersistentKeepalive = 25" >> "$WG_CONF"

    chmod 600 "$WG_CONF"
    echo -e "${GREEN}Client config created at $WG_CONF${NC}"
}

create_server_conf(){
    SERVER_IP=${1:-10.1.0.1}
    WG_PORT=${2:-51820}

    echo -e "[Interface]" > "$WG_CONF"
    echo "PrivateKey = $(cat $WG_PRIV)" >> "$WG_CONF"
    echo "Address = $SERVER_IP/24" >> "$WG_CONF"
    echo "ListenPort = $WG_PORT" >> "$WG_CONF"

    chmod 600 "$WG_CONF"
    echo -e "${GREEN}Server config created at $WG_CONF${NC}"
}

start_wg(){
    echo -e "${YELLOW}Starting WireGuard...${NC}"
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
}

setup_firewall(){
    echo -e "${YELLOW}Configuring ufw...${NC}"
    apt install ufw -y
    ufw --force reset
    ufw allow ssh
    if [ -f "$WG_CONF" ]; then
        WGPORT=$(grep ListenPort "$WG_CONF" | awk '{print $3}')
        ufw allow $WGPORT
    fi
    ufw --force enable
    echo -e "${GREEN}Firewall configured.${NC}"
}

show_menu(){
    echo ""
    echo "1) Install & Configure WireGuard as Server"
    echo "2) Install & Configure WireGuard as Local Client"
    echo "3) Uninstall WireGuard"
    echo "4) Exit"
    read -p "Choose: " opt
    case $opt in
        1)
            MODE="server"
            install_wg
            enable_forwarding
            generate_keys
            create_server_conf
            setup_firewall
            start_wg
            echo "Server Public Key: $(cat $WG_PUB)"
            echo "Server IP and Port: $(hostname -I | awk '{print $1}'):$WG_PORT"
            ;;
        2)
            MODE="client"
            install_wg
            enable_forwarding
            generate_keys
            read_server_info
            create_client_conf
            setup_firewall
            start_wg
            ;;
        3)
            uninstall_wg
            ;;
        4)
            exit 0
            ;;
        *)
            echo "Invalid"; show_menu
            ;;
    esac
}

# main
if [ $EUID -ne 0 ]; then
    echo "Please run as root"; exit 1
fi

show_menu
