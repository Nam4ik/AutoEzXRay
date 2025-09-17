check_root() {
  # check root
  [[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege 
 " && exit 1
}

install_xray() { 

  echo "Installing XRay-core services and X3-UI"

  bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh  )
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh  )" @ install
}

copy_config() { 
  echo -e "${green} OK: Copying configs for XRay daemon."
  cp ./configs/config.json
}

keygen() {
  echo -e "${green} OK: Generating UUIDs and x25519 keys"
  /usr/local/bin/xray x25519 > keys.xray 
  /usr/local/bin/xray uuid > uuid.xray   
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

# Main execution
check_root
install_xray
configure_iptables
configure_nftables
configure_firewalld
configure_ufw

echo "Installation and configuration completed."
