#!/bin/bash

NET_ENV_INTERFACE="wlan0"

NET_ENV_INTERFACE_LOWER=`echo "$NET_ENV_INTERFACE" | tr '[:upper:]' '[:lower:]'`
NET_ENV_INTERFACE_UPPER=`echo "$NET_ENV_INTERFACE" | tr '[:lower:]' '[:upper:]'`

function init(){
  service hostapd stop > /dev/null 2>&1
  service dnsmasq stop > /dev/null 2>&1
  systemctl disable hostapd > /dev/null 2>&1
  systemctl disable dnsmasq > /dev/null 2>&1
}

function ensureDefaultDhcpcdConf(){
  if test ! -f /etc/dhcpcd.base.conf
  then
    touch /etc/dhcpcd.base.conf
    cat <<EOF > /etc/dhcpcd.base.conf &
# A sample configuration for dhcpcd.
# See dhcpcd.conf(5) for details.
# Allow users of this group to interact with dhcpcd via the control socket.
#controlgroup wheel
# Inform the DHCP server of our hostname for DDNS.
hostname
# Use the hardware address of the interface for the Client ID.
clientid
# or
# Use the same DUID + IAID as set in DHCPv6 for DHCPv4 ClientID as per RFC4361.
# Some non-RFC compliant DHCP servers do not reply with this set.
# In this case, comment out duid and enable clientid above.
#duid
# Persist interface configuration when dhcpcd exits.
persistent
# Rapid commit support.
# Safe to enable by default because it requires the equivalent option set
# on the server to actually work.
option rapid_commit
# A list of options to request from the DHCP server.
option domain_name_servers, domain_name, domain_search, host_name
option classless_static_routes
# Most distributions have NTP support.
option ntp_servers
# Respect the network MTU. This is applied to DHCP routes.
option interface_mtu
# A ServerID is required by RFC2131.
require dhcp_server_identifier
# Generate Stable Private IPv6 Addresses instead of hardware based ones
slaac private
EOF
  fi
}

function ensureDefaultInterfaceConf(){
  cat <<EOF > /etc/network/interfaces &
# interfaces(5) file used by ifup(8) and ifdown(8)
# Please note that this file is written to be used with dhcpcd
# For static IP, consult /etc/dhcpcd.conf and 'man dhcpcd.conf'
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d
EOF

  mkdir -p /etc/network/default
  if test ! -f /etc/network/default/auto
  then
    touch /etc/network/default/auto
    cat <<EOF > /etc/network/default/auto &
auto lo
iface lo inet loopback
EOF
  fi

  if test ! -L /etc/network/interfaces.d/auto
  then
    ln -s /etc/network/default/auto /etc/network/interfaces.d/auto
  fi
}

function unsetAccesPoint(){
  ensureDefaultInterfaceConf

  PREVIOUS_CONF=`grep -Pzo '# TTB START DEFINITION (?!ACCESS_POINT)[\s\S]*?\n[\s\S]*?\n# TTB END DEFINITION (?!ACCESS_POINT)[\s\S]*?\n' /etc/dhcpcd.conf`
  ensureDefaultDhcpcdConf
  cp /etc/dhcpcd.base.conf /etc/dhcpcd.conf
  echo "$PREVIOUS_CONF" >> /etc/dhcpcd.conf
  echo "" >> /etc/dhcpcd.conf
}

function rollback_dnsmasq(){
  if [ -e /etc/dnsmasq.base.conf ]
  then
    mv /etc/dnsmasq.base.conf /etc/dnsmasq.conf
  fi
}

function rollback_ip_forwarding(){
  IPFORWARDING_COMMENT=`sed -n '/^#[ ]*net\.ipv4\.ip\_forward\=1/=' /etc/sysctl.conf`

  if test "" != "$IPFORWARDING_COMMENT"
  then
    sed -i 's/^net\.ipv4\.ip\_forward\=1/# net\.ipv4\.ip\_forward\=1/' /etc/sysctl.conf
  fi

  comment="digitalairwaysAPRules"

  iptables-save | grep -v "$comment" | iptables-restore

  iptables-save >/etc/iptables/rules.v4
  ip6tables-save >/etc/iptables/rules.v6
}

init
unsetAccesPoint
rollback_dnsmasq
rollback_ip_forwarding

service networking restart
