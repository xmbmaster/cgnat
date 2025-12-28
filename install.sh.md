# Download script
curl -sL https://raw.githubusercontent.com/xmbmaster/cgnat/refs/heads/main/install.sh -o install.sh

# Make executable
chmod +x install.sh

# Run as root (interactive prompts for IPs/ports)
sudo ./install.sh
