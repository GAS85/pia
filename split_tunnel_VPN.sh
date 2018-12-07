#!/bin/bash

# By Georgiy Sitnikov.
#
# Will do setup Split Tunnel. More under:
# https://gist.github.com/GAS85/4e40ece16ffa748e7138b9aa4c37ca52
#
# AS-IS without any warranty

# Check if you are root user, otherwise will not work
[[ $(id -u) -eq 0 ]] || { echo >&2 "Must be root to run this script."; exit 1; }

# Optinally
#wget https://swupdate.openvpn.net/repos/repo-public.gpg -O - | apt-key add -
#echo "deb http://build.openvpn.net/debian/openvpn/stable xenial main" | tee -a /etc/apt/sources.list.d/openvpn.list

echo "Step 1. Install needed Packages"
echo "Install OpenVPN, iptables and unzip"

apt-get update
apt-get install openvpn unzip iptables -y
echo
echo "Step 2. Create systemd Service for OpenVPN"
cat > /etc/systemd/system/openvpn@openvpn.service << EOF
[Unit]
# https://gist.github.com/GAS85/4e40ece16ffa748e7138b9aa4c37ca52
Description=OpenVPN connection to %i
Documentation=man:openvpn(8)
Documentation=https://community.openvpn.net/openvpn/wiki/Openvpn23ManPage
Documentation=https://community.openvpn.net/openvpn/wiki/HOWTO
After=network.target

[Service]
RuntimeDirectory=openvpn
PrivateTmp=true
KillMode=mixed
Type=forking
ExecStart=/usr/sbin/openvpn --daemon ovpn-%i --status /run/openvpn/%i.status 10 --cd /etc/openvpn --script-security 2 --config /etc/openvpn/%i.conf --writepid /run/openvpn/%i.pid
PIDFile=/run/openvpn/%i.pid
ExecReload=/bin/kill -HUP $MAINPID
WorkingDirectory=/etc/openvpn
Restart=on-failure
RestartSec=3
ProtectSystem=yes
LimitNPROC=10
DeviceAllow=/dev/null rw
DeviceAllow=/dev/net/tun rw

[Install]
WantedBy=multi-user.target
EOF

echo "Now enable the openvpn@openvpn.service we just created"
systemctl enable openvpn@openvpn.service
echo
echo "Step 3. Create PIA Configuration File for Split Tunneling"
cd /tmp
wget https://www.privateinternetaccess.com/openvpn/openvpn.zip
unzip openvpn.zip
cp crl.rsa.2048.pem ca.rsa.2048.crt /etc/openvpn/
echo
echo "Step 4. Create Modified PIA Configuration File for Split Tunneling"
echo "Create the OpenVPN configuration file"
echo "under /etc/openvpn/openvpn.conf"
cat > /etc/openvpn/openvpn.conf << EOF
client
dev tun
proto udp
remote czech.privateinternetaccess.com 1198
remote sweden.privateinternetaccess.com 1198
remote nl.privateinternetaccess.com 1198
remote-random
resolv-retry infinite
nobind
persist-key
persist-tun
cipher aes-128-cbc
auth sha1
tls-client
remote-cert-tls server
auth-user-pass /etc/openvpn/login.txt
auth-nocache
comp-lzo
verb 1
reneg-sec 0
crl-verify /etc/openvpn/crl.rsa.2048.pem
ca /etc/openvpn/ca.rsa.2048.crt
disable-occ
script-security 2
route-noexec

#up and down scripts to be executed when VPN starts or stops
up /etc/openvpn/iptables.sh
down /etc/openvpn/update-resolv-conf
EOF

echo
echo "Step 5. Make OpenVPN Auto Login on Service Start"
# Ask the PIA user for login details
echo
echo "Please enter your PIA username and Password"
read -p 'Username: ' uservar
read -p 'Password: ' passvar
echo
echo $uservar > /etc/openvpn/login.txt
echo $passvar >> /etc/openvpn/login.txt
echo Thanks you $uservar we now have your PIA login details saved in /etc/openvpn/login.txt
echo
echo "Step 6. Configure VPN DNS Servers to Stop DNS Leaks"
sed -i -e "s/# foreign_option_1=\'dhcp-option DNS 193.43.27.132\'/foreign_option_1=\'dhcp-option DNS 209.222.18.222\'/g" /etc/openvpn/update-resolv-conf

sed -i -e "s/# foreign_option_2=\'dhcp-option DNS 193.43.27.133\'/foreign_option_2=\'dhcp-option DNS 209.222.18.218\'/g" /etc/openvpn/update-resolv-conf

sed -i -e "s/# foreign_option_3=\'dhcp-option DOMAIN be.bnc.ch\'/foreign_option_3=\'dhcp-option DNS 8.8.8.8\'/g" /etc/openvpn/update-resolv-conf

echo
echo "Step 7. Create vpn User"
adduser --disabled-login vpn
echo
echo "Enter username with the user you would like to add to the vpn group"
echo "E.g. your regular user: $(grep 1000 /etc/passwd | cut -f1 -d:)"
read -p 'Username: ' username
usermod -aG vpn $username
echo Thanks you, $username added to VPN group.
echo
echo Group name of your regular user that you would like to add the vpn user to
read -p 'Group: ' groupname
usermod -aG $groupname vpn
echo Thanks you.
echo
echo Get Routing Information for the iptables Script
echo
echo "We need the local IP and the name of the network interface."
echo "Again, make sure you are using a static IP on your machine or reserved DHCP also known as static DHCP, but configured on your router!"
interface=$(ip route list | grep default | cut -f5 -d" ")
localipaddr=$(ip route get 8.8.8.8 | awk '{print $NF; exit}')
echo
echo Local Default interface is $interface
echo Local IP Address is $localipaddr

while true; do
    read -p "Are listed IP Addr and Interface correct?" yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) corrections=1;break;;
        * ) echo "Please answer yes or no.";;
    esac
done

if [ "$corrections" == 1 ]; then
	read -p 'Please enter correct defailt interface: ' interface
	read -p 'Please enter correct IP Address: ' localipaddr
fi

echo
echo Flush current iptables rules
iptables -F
echo Add rule, which will block vpn user’s access to Internet (except the loopback device). 
iptables -A OUTPUT ! -o lo -m owner --uid-owner vpn -j DROP
echo Install iptables-persistent to save this single rule that will be always applied on each system start.
echo
echo During the install, iptables-persistent will ask you to save current iptables rules to /etc/iptables/rules.v4, accept this with YES.
echo
apt-get install iptables-persistent -y

echo
echo "Step 8. iptables Script for vpn User"

cat > /etc/openvpn/iptables.sh << EOF
#! /bin/bash
# Niftiest Software – www.niftiestsoftware.com
# Modified version by HTPC Guides – www.htpcguides.com

export INTERFACE="tun0"
export VPNUSER="vpn"
export LOCALIP="'$localipaddr'"
export NETIF="'$interface'"

# flushes all the iptables rules, if you have other rules to use then add them into the script
iptables -F -t nat
iptables -F -t mangle
iptables -F -t filter

# mark packets from $VPNUSER
iptables -t mangle -A OUTPUT -j CONNMARK --restore-mark
iptables -t mangle -A OUTPUT ! --dest $LOCALIP -m owner --uid-owner $VPNUSER -j MARK --set-mark 0x1
iptables -t mangle -A OUTPUT --dest $LOCALIP -p udp --dport 53 -m owner --uid-owner $VPNUSER -j MARK --set-mark 0x1
iptables -t mangle -A OUTPUT --dest $LOCALIP -p tcp --dport 53 -m owner --uid-owner $VPNUSER -j MARK --set-mark 0x1
# Added Local Open Ports Like Aria2 RPC, Torrent GUI
iptables -t mangle -A OUTPUT --src $LOCALIP -p tcp -m tcp -m multiport --sports 6800,7777 -m owner --uid-owner $VPNUSER -j MARK --set-mark 0x0
# Continue marking
iptables -t mangle -A OUTPUT ! --src $LOCALIP -j MARK --set-mark 0x1
iptables -t mangle -A OUTPUT -j CONNMARK --save-mark

# allow responses
iptables -A INPUT -i $INTERFACE -m conntrack --ctstate ESTABLISHED -j ACCEPT

# block everything incoming on $INTERFACE to prevent accidental exposing of ports
iptables -A INPUT -i $INTERFACE -j REJECT

# let $VPNUSER access lo and $INTERFACE
iptables -A OUTPUT -o lo -m owner --uid-owner $VPNUSER -j ACCEPT
iptables -A OUTPUT -o $INTERFACE -m owner --uid-owner $VPNUSER -j ACCEPT

# all packets on $INTERFACE needs to be masqueraded
iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE

# reject connections from predator IP going over $NETIF
iptables -A OUTPUT ! --src $LOCALIP -o $NETIF -j REJECT

#ADD YOUR RULES HERE

iptables -A INPUT -p tcp -m tcp -m multiport -j ACCEPT --dports 22,80,443
iptables -A INPUT -p tcp -m tcp -m multiport -m state --state ESTABLISHED,RELATED -j ACCEPT --sports 22,53,80,443,8080,6800,7777
iptables -A INPUT -s 127.0.0.1/32 -j ACCEPT
iptables -A INPUT -p tcp -m tcp -s 192.168.0.0/24 --dports 6800,7777 -j ACCEPT
iptables -A INPUT -j DROP

# Start routing script
/etc/openvpn/routing.sh

exit 0
EOF

#Make the iptables script executable
chmod +x /etc/openvpn/iptables.sh

echo
echo "Step 9. Routing Rules Script for the Marked Packets"

cat > /etc/openvpn/routing.sh << EOF
#! /bin/bash
# Niftiest Software – www.niftiestsoftware.com
# Modified version by HTPC Guides – www.htpcguides.com

VPNIF="tun0"
VPNUSER="vpn"
GATEWAYIP=$(ifconfig $VPNIF | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | egrep -v '255|(127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})' | tail -n1)
if [[ `ip rule list | grep -c 0x1` == 0 ]]; then
ip rule add from all fwmark 0x1 lookup $VPNUSER
fi
ip route replace default via $GATEWAYIP table $VPNUSER
ip route append default via 127.0.0.1 dev lo table $VPNUSER
ip route flush cache

# run update-resolv-conf script to set VPN DNS
/etc/openvpn/update-resolv-conf

exit 0
EOF

# Finally, make the script executable
chmod +x /etc/openvpn/routing.sh

echo
echo "Step 10. Configure Split Tunnel VPN Routing"
echo "200     vpn" >> /etc/iproute2/rt_tables

echo
echo "Step 11. Change Reverse Path Filtering"
echo "net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.eth0.rp_filter = 2" > /etc/sysctl.d/9999-vpn.conf
echo Apply new sysctl rules
sysctl --system

echo
echo "Testing the VPN Split Tunnel"
echo
systemctl status openvpn@openvpn.service
echo
echo "Check IP address"
echo "Regular User"
curl ipinfo.io
echo
echo "VPN User"
sudo -u vpn -i -- curl ipinfo.io
echo
echo "If Location and IPs are different - everything is fine"
echo
echo Check DNS Server
echo
sudo -u vpn -i -- cat /etc/resolv.conf
echo
echo "If outupt is following, everything is ok:
# Dynamic resolv.conf(5) file for glibc resolver(3) generated by resolvconf(8)
# DO NOT EDIT THIS FILE BY HAND -- YOUR CHANGES WILL BE OVERWRITTEN
nameserver 209.222.18.222
nameserver 209.222.18.218
nameserver 8.8.8.8"

exit 0
