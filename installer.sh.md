# Download script
curl -sL https://raw.githubusercontent.com/xmbmaster/cgnat/refs/heads/main/installer.sh -o installer.sh

# Make executable
chmod +x installer.sh

# Run as root (interactive prompts for IPs/ports)
sudo ./installer.sh
