#!/bin/bash

NETNS_PFX="wg-test"
LOWER_IF_PFX="wg-test-eth"
UPPER_IF_PFX="wg-test-wg"
MPLS_IP_PFX="169.254.3"
MPLS_IP6_PFX="fc03"
PORT_PFX="1000"

sudo modprobe mpls_router
sudo modprobe mpls_iptunnel

function sysctl_node()
{
  nodeid=$1
  sudo ip netns exec ${NETNS_PFX}-$nodeid sysctl -w -q "$2"
}

function setup_node()
{
  nodeid=$1
  sudo ip netns add ${NETNS_PFX}-$nodeid
  sudo ip netns exec ${NETNS_PFX}-$nodeid ip link set lo up
  sudo ip netns exec ${NETNS_PFX}-$nodeid ip a add ${MPLS_IP_PFX}.${nodeid} dev lo
  sudo ip netns exec ${NETNS_PFX}-$nodeid ip a add ${MPLS_IP6_PFX}::${nodeid} dev lo

  sysctl_node $nodeid "net.ipv4.ip_forward=1"
  sysctl_node $nodeid "net.ipv6.conf.all.forwarding=1"

  wg genkey > /tmp/wg-test.key.$nodeid
}

function connect_node()
{
  nodeid_a=$1
  nodeid_b=$2
  mpls=$3

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip link add ${LOWER_IF_PFX}-${nodeid_b} type veth peer name ${LOWER_IF_PFX}-${nodeid_a}
  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip link set ${LOWER_IF_PFX}-${nodeid_a} netns ${NETNS_PFX}-$nodeid_b

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip addr add fe80::$nodeid_a/64 dev ${LOWER_IF_PFX}-${nodeid_b}
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b ip addr add fe80::$nodeid_b/64 dev ${LOWER_IF_PFX}-${nodeid_a}

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip link set ${LOWER_IF_PFX}-${nodeid_b} addrgenmode none
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b ip link set ${LOWER_IF_PFX}-${nodeid_a} addrgenmode none

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip link set ${LOWER_IF_PFX}-${nodeid_b} up
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b ip link set ${LOWER_IF_PFX}-${nodeid_a} up

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip link add ${UPPER_IF_PFX}-${nodeid_b} type wireguard
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b ip link add ${UPPER_IF_PFX}-${nodeid_a} type wireguard

  if [ ! -z $mpls ]; then
    sysctl_node $nodeid_a "net.mpls.platform_labels=114514"
    sysctl_node $nodeid_a "net.mpls.conf.${UPPER_IF_PFX}-${nodeid_b}.input=1"
    sysctl_node $nodeid_b "net.mpls.platform_labels=114514"
    sysctl_node $nodeid_b "net.mpls.conf.${UPPER_IF_PFX}-${nodeid_a}.input=1"
  fi

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a wg set ${UPPER_IF_PFX}-${nodeid_b} listen-port ${PORT_PFX}${nodeid_b} private-key /tmp/wg-test.key.$nodeid_a
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b wg set ${UPPER_IF_PFX}-${nodeid_a} listen-port ${PORT_PFX}${nodeid_a} private-key /tmp/wg-test.key.$nodeid_b

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a wg set ${UPPER_IF_PFX}-${nodeid_b} peer $(wg pubkey < /tmp/wg-test.key.$nodeid_b) persistent-keepalive 15 allowed-ips 0.0.0.0/0,::/0 endpoint [fe80::$nodeid_b%${LOWER_IF_PFX}-${nodeid_b}]:${PORT_PFX}${nodeid_a}
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b wg set ${UPPER_IF_PFX}-${nodeid_a} peer $(wg pubkey < /tmp/wg-test.key.$nodeid_a) persistent-keepalive 15 allowed-ips 0.0.0.0/0,::/0 endpoint [fe80::$nodeid_a%${LOWER_IF_PFX}-${nodeid_a}]:${PORT_PFX}${nodeid_b}

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip link set ${UPPER_IF_PFX}-${nodeid_b} up
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b ip link set ${UPPER_IF_PFX}-${nodeid_a} up

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip -6 addr add fe80::$nodeid_a/64 dev ${UPPER_IF_PFX}-${nodeid_b}
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b ip -6 addr add fe80::$nodeid_b/64 dev ${UPPER_IF_PFX}-${nodeid_a}
}

function route_node_mpls()
{
  nodeid_a=$1
  nodeid_b=$2
  label_a=$3
  label_b=$4
  if [ -z $label_b ]; then
    sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip -M route add $label_a via inet6 fe80::$nodeid_b dev ${UPPER_IF_PFX}-${nodeid_b}
  else
    sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip -M route add $label_a as $label_b via inet6 fe80::$nodeid_b dev ${UPPER_IF_PFX}-${nodeid_b}
  fi
}

function route_node()
{
  nodeid_a=$1
  nodeid_b=$2
  target=$3
  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip route add $target src ${MPLS_IP_PFX}.$nodeid_a nexthop via inet6 fe80::$nodeid_b dev ${UPPER_IF_PFX}-${nodeid_b}
}

function route6_node()
{
  nodeid_a=$1
  nodeid_b=$2
  target=$3
  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip -6 route add $target src ${MPLS_IP6_PFX}::$nodeid_a via fe80::$nodeid_b dev ${UPPER_IF_PFX}-${nodeid_b}
}

function route_node_encap()
{
  nodeid_a=$1
  nodeid_b=$2
  target=$3
  label=$4
  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip route add $target src ${MPLS_IP_PFX}.$nodeid_a encap mpls $label via inet6 fe80::$nodeid_b dev ${UPPER_IF_PFX}-${nodeid_b}
}

function route6_node_encap()
{
  nodeid_a=$1
  nodeid_b=$2
  target=$3
  label=$4
  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip -6 route add $target src ${MPLS_IP6_PFX}::$nodeid_a encap mpls $label via fe80::$nodeid_b dev ${UPPER_IF_PFX}-${nodeid_b}
}

function info_tunnel()
{
  INFOLIST=()
  for nodeid in 1 2 3 4 5 6; do
    INFOLIST+=(`sudo ip netns exec wg-test-$nodeid wg | grep "handshake" | wc -l`)
  done
  echo ${INFOLIST[@]}
}

function clean_up()
{
  for lnode in 1 2 3 4 5 6; do
    sudo ip netns del ${NETNS_PFX}-$lnode
  done
}

echo "Setting up nodes..."

for lnode in 1 2 3 4 5 6; do
  setup_node $lnode
done

echo "Connecting nodes..."

connect_node 1 2
connect_node 2 3 1
connect_node 3 4 1
connect_node 4 5 1
connect_node 5 6

# 1 -(w)-> 2 -(w|101)-> 3 -(w|102)-> 4 -(w|103)-> 5 -(w)-> 6
# 1 <-(w)- 2 <-(w|203)- 3 <-(w|202)- 4 <-(w|201)- 5 <-(w)- 6

echo "Setting up routes..."

route_node_encap 2 3 default 101
route_node_encap 5 4 default 201
route6_node_encap 2 3 default 101
route6_node_encap 5 4 default 201

route_node_mpls 3 4 101 102
route_node_mpls 4 3 201 202

route_node_mpls 4 5 102 103
route_node_mpls 3 2 202 203

route_node_mpls 5 6 103
route_node_mpls 2 1 203

route_node 1 2 0/0
route6_node 1 2 ::/0
route_node 6 5 0/0
route6_node 6 5 ::/0

route_node 2 1 ${MPLS_IP_PFX}.1/32
route6_node 2 1 ${MPLS_IP6_PFX}::1/128
route_node 5 6 ${MPLS_IP_PFX}.6/32
route6_node 5 6 ${MPLS_IP6_PFX}::6/128

echo "Waiting for handshake..."

wait_counter=0
tunnel_info="`info_tunnel`"

while [ $wait_counter -le 30 ] && [ "$tunnel_info" != "1 2 2 2 2 1" ]
do
  wait_counter=$(( $wait_counter + 1 ))
  sleep 1
  echo "time: $wait_counter, tunnels: $tunnel_info"
  tunnel_info="`info_tunnel`"
done

if [ "$tunnel_info" != "1 2 2 2 2 1" ]; then
  echo "error: tunnels not up"
  exit 1
fi

read -p "Press any key to start test..."

sudo ip netns exec ${NETNS_PFX}-1 ping ${MPLS_IP_PFX}.6 -c 1
sudo ip netns exec ${NETNS_PFX}-6 ping ${MPLS_IP_PFX}.1 -c 1

sudo ip netns exec ${NETNS_PFX}-1 traceroute -e -I ${MPLS_IP_PFX}.6 -w 0.3 -q 1 -n
sudo ip netns exec ${NETNS_PFX}-6 traceroute -e -I ${MPLS_IP_PFX}.1 -w 0.3 -q 1 -n
sudo ip netns exec ${NETNS_PFX}-1 traceroute6 -e -I ${MPLS_IP6_PFX}::6 -w 0.3 -q 1 -n
sudo ip netns exec ${NETNS_PFX}-6 traceroute6 -e -I ${MPLS_IP6_PFX}::1 -w 0.3 -q 1 -n
read -p "Press any key to exit..."

clean_up
