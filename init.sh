check_root() {
  # check root
  [[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege 
 " && exit 1
}

install_xray() { 
  echo "Installing XRay-core services and X3-UI"

  
  bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
}

keygen() {
  echo -e "${green} OK: Generating UUIDs and x25519 keys${plain}"
  
  
  local xray_bin=$(find /usr/local/x-ui/bin/ -name "xray-linux-*" | head -n 1)
  
  if [ ! -f "$xray_bin" ]; then
    echo -e "${red}Error: Cannot locate XRay binary. Please make sure XRay is installed.${plain}"
    return 1
  fi
  
  
  "$xray_bin" uuid > uuid.xray
  if [ $? -ne 0 ] || [ ! -s uuid.xray ]; then
    echo -e "${red}Failed to generate UUID${plain}"
    return 1
  fi
  
  
  "$xray_bin" x25519 > keys.xray
  if [ $? -ne 0 ] || [ ! -s keys.xray ]; then
    echo -e "${red}Failed to generate x25519 key${plain}"
    return 1
  fi
  
  echo -e "${green}Keys generated and saved to uuid.xray and keys.xray${plain}"
  return 0
}

configure_xray() { 
  echo -e "${green} OK: Configuring XRay daemon.${plain}"
  

  if [ ! -f "uuid.xray" ] || [ ! -f "keys.xray" ]; then
    echo -e "${red}Error: Key files not found. Please run keygen first.${plain}"
    return 1
  fi
  
  
  local uuid=$(cat uuid.xray)
  if [ -z "$uuid" ]; then
    echo -e "${red}Error: Failed to read UUID from uuid.xray${plain}"
    return 1
  fi
  

  local private_key=$(grep "PrivateKey:" keys.xray | cut -d ' ' -f 2)
  if [ -z "$private_key" ]; then
    echo -e "${red}Error: Failed to extract PrivateKey from keys.xray${plain}"
    return 1
  fi
  
  echo -e "${green}Using UUID: ${uuid}${plain}"
  echo -e "${green}Using Private Key: ${private_key}${plain}"
  
  
  local config_dir="/usr/local/x-ui/bin/config"
  mkdir -p "$config_dir"
  
  
  cat > "$config_dir/config.json" << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "protocol": ["bittorrent"],
                "outboundTag": "block"
            },
            {
                "type": "field",
                "ip": ["geoip:private"],
                "outboundTag": "block"
            },
            {
                "type": "field",
                "ip": ["geoip:cn"],
                "outboundTag": "block"
            },
            {
                "type": "field",
                "domain": ["geosite:category-ads-all"],
                "outboundTag": "block"
            }
        ]
    },
    "inbounds": [
        {
            "tag": "vless-reality-in",
            "listen": "0.0.0.0",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "www.apple.com:443", 
                    "xver": 0,
                    "serverNames": ["www.apple.com"], 
                    "privateKey": "$private_key",
                    "shortIds": ["a1b2c3d4"]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
}
EOF

  echo -e "${green}XRay configuration completed successfully!${plain}"
  echo -e "UUID: $uuid"
  echo -e "Private Key: $private_key"
  
  
  local panel_info=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null)
  if [ ! -z "$panel_info" ]; then
    local server_ip=$(curl -s --max-time 3 https://api.ipify.org)
    if [ -z "$server_ip" ]; then
      server_ip=$(curl -s --max-time 3 https://4.ident.me)
    fi
    
    local port=$(echo "$panel_info" | grep -Eo 'port: .+' | awk '{print $2}')
    local web_base_path=$(echo "$panel_info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    
    if [ ! -z "$port" ] && [ ! -z "$web_base_path" ]; then
      echo -e "\n${blue}Panel Access URL: http://${server_ip}:${port}/${web_base_path}${plain}"
    fi
  fi
  
  
  systemctl restart x-ui
  
  return 0
}

configure_iptables() {
  if command -v iptables &> /dev/null; then
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m limit --limit 10/min --limit-burst 20 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -m limit --limit 10/min --limit-burst 20 -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m limit --limit 5/min --limit-burst 10 -j ACCEPT
    iptables -A INPUT -p icmp -m limit --limit 1/sec -j ACCEPT
    iptables -A INPUT -j DROP
  fi
}

configure_nftables() {
  if command -v nft &> /dev/null; then
    nft add table inet filter
    nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; }
    nft add chain inet filter forward { type filter hook forward priority 0 \; policy drop \; }
    nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; }
    nft add rule inet filter input ct state established,related accept
    nft add rule inet filter input iif "lo" accept
    nft add rule inet filter input tcp dport { 80 } ct state new limit rate 10/minute burst 20 packets accept
    nft add rule inet filter input tcp dport { 443 } ct state new limit rate 10/minute burst 20 packets accept
    nft add rule inet filter input tcp dport { 22 } ct state new limit rate 5/minute burst 10 packets accept
    nft add rule inet filter input ip protocol icmp limit rate 1/second accept
    nft add rule inet filter input ip6 nexthdr ipv6-icmp limit rate 1/second accept
  fi
}

configure_firewalld() {
  if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --set-default-zone=drop
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --permanent --add-port=443/tcp
    firewall-cmd --reload
  fi
}

configure_ufw() {
  if command -v ufw &> /dev/null; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw enable
  fi
}


check_root
install_xray
keygen
configure_xray
configure_iptables
configure_nftables
configure_firewalld
configure_ufw

echo -e "\n${green}Installation and configuration completed successfully!${plain}"
echo "XRay is now configured with Reality protocol on port 443"
echo "Use the provided UUID and Private Key for client configuration"
