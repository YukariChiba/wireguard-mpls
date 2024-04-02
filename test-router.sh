#!/bin/bash

NETNS_PFX="wg-test"
LOWER_IF_PFX="wg-test-eth"
UPPER_IF_PFX="wg-test-wg"
ETH_IP_PFX="169.254.1"
WG_IP_PFX="169.254.2"
MPLS_IP_PFX="169.254.3"
PORT_PFX="1000"

sudo modprobe mpls_router
sudo modprobe mpls_iptunnel

function setup_node()
{
  nodeid=$1
  sudo ip netns add ${NETNS_PFX}-$nodeid
  sudo ip netns exec ${NETNS_PFX}-$nodeid ip link set lo up
  sudo ip netns exec ${NETNS_PFX}-$nodeid ip a add ${MPLS_IP_PFX}.${nodeid} dev lo

  wg genkey > /tmp/wg-test.key.$nodeid
}

function connect_node()
{
  nodeid_a=$1
  nodeid_b=$2
  mpls=$3

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip link add ${LOWER_IF_PFX}-${nodeid_b} type veth peer name ${LOWER_IF_PFX}-${nodeid_a}
  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip link set ${LOWER_IF_PFX}-${nodeid_a} netns ${NETNS_PFX}-$nodeid_b

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip addr add ${ETH_IP_PFX}.$nodeid_a/32 peer ${ETH_IP_PFX}.$nodeid_b/32 dev ${LOWER_IF_PFX}-${nodeid_b}
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b ip addr add ${ETH_IP_PFX}.$nodeid_b/32 peer ${ETH_IP_PFX}.$nodeid_a/32 dev ${LOWER_IF_PFX}-${nodeid_a}

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip link set ${LOWER_IF_PFX}-${nodeid_b} up
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b ip link set ${LOWER_IF_PFX}-${nodeid_a} up

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip link add ${UPPER_IF_PFX}-${nodeid_b} type wireguard
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b ip link add ${UPPER_IF_PFX}-${nodeid_a} type wireguard

  if [ -z $mpls ]; then
    sudo ip netns exec ${NETNS_PFX}-$nodeid_a sysctl -w "net.ipv4.ip_forward=1"
    sudo ip netns exec ${NETNS_PFX}-$nodeid_b sysctl -w "net.ipv4.ip_forward=1"
  else
    sudo ip netns exec ${NETNS_PFX}-$nodeid_a sysctl -w "net.mpls.platform_labels=114514"
    sudo ip netns exec ${NETNS_PFX}-$nodeid_a sysctl -w "net.mpls.conf.${UPPER_IF_PFX}-${nodeid_b}.input=1"
    sudo ip netns exec ${NETNS_PFX}-$nodeid_b sysctl -w "net.mpls.platform_labels=114514"
    sudo ip netns exec ${NETNS_PFX}-$nodeid_b sysctl -w "net.mpls.conf.${UPPER_IF_PFX}-${nodeid_a}.input=1"
  fi

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a wg set ${UPPER_IF_PFX}-${nodeid_b} listen-port ${PORT_PFX}${nodeid_b} private-key /tmp/wg-test.key.$nodeid_a
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b wg set ${UPPER_IF_PFX}-${nodeid_a} listen-port ${PORT_PFX}${nodeid_a} private-key /tmp/wg-test.key.$nodeid_b

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a wg set ${UPPER_IF_PFX}-${nodeid_b} peer $(wg pubkey < /tmp/wg-test.key.$nodeid_b) persistent-keepalive 15 allowed-ips 0.0.0.0/0 endpoint ${ETH_IP_PFX}.$nodeid_b:${PORT_PFX}${nodeid_a}
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b wg set ${UPPER_IF_PFX}-${nodeid_a} peer $(wg pubkey < /tmp/wg-test.key.$nodeid_a) persistent-keepalive 15 allowed-ips 0.0.0.0/0 endpoint ${ETH_IP_PFX}.$nodeid_a:${PORT_PFX}${nodeid_b}

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip link set ${UPPER_IF_PFX}-${nodeid_b} up
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b ip link set ${UPPER_IF_PFX}-${nodeid_a} up

  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip addr add ${WG_IP_PFX}.$nodeid_a/24 dev ${UPPER_IF_PFX}-${nodeid_b}
  sudo ip netns exec ${NETNS_PFX}-$nodeid_b ip addr add ${WG_IP_PFX}.$nodeid_b/24 dev ${UPPER_IF_PFX}-${nodeid_a}
}

function route_node_mpls_lo()
{
  nodeid=$1
  label=$2
  sudo ip netns exec ${NETNS_PFX}-$nodeid ip -M route add $label dev lo
}

function route_node_mpls_eth()
{
  nodeid_a=$1
  nodeid_b=$2
  label_a=$3
  label_b=$4
  if [ -z $label_b ]; then
    sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip -M route add $label_a via inet ${ETH_IP_PFX}.$nodeid_b dev ${LOWER_IF_PFX}-${nodeid_b}
  else
    sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip -M route add $label_a as $label_b via inet ${ETH_IP_PFX}.$nodeid_b dev ${LOWER_IF_PFX}-${nodeid_b}
  fi
}

function route_node_mpls()
{
  nodeid_a=$1
  nodeid_b=$2
  label_a=$3
  label_b=$4
  if [ -z $label_b ]; then
    sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip -M route add $label_a via inet ${WG_IP_PFX}.$nodeid_b dev ${UPPER_IF_PFX}-${nodeid_b}
  else
    sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip -M route add $label_a as $label_b via inet ${WG_IP_PFX}.$nodeid_b dev ${UPPER_IF_PFX}-${nodeid_b}
  fi
}

function route_node()
{
  nodeid_a=$1
  nodeid_b=$2
  target=$3
  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip route add $target via ${WG_IP_PFX}.$nodeid_b dev ${UPPER_IF_PFX}-${nodeid_b} src ${MPLS_IP_PFX}.$nodeid_a
}

function route_node_encap()
{
  nodeid_a=$1
  nodeid_b=$2
  target=$3
  label=$4
  sudo ip netns exec ${NETNS_PFX}-$nodeid_a ip route add $target encap mpls $label via ${WG_IP_PFX}.$nodeid_b dev ${UPPER_IF_PFX}-${nodeid_b} src ${MPLS_IP_PFX}.$nodeid_a
}

for lnode in 1 2 3 4 5 6; do
  setup_node $lnode
done

connect_node 1 2
connect_node 2 3 1
connect_node 3 4 1
connect_node 4 5 1
connect_node 5 6

route_node_encap 2 3 default 101
route_node_encap 5 4 default 201

route_node_mpls 3 4 101 102
route_node_mpls 4 3 201 202

route_node_mpls 4 5 102 103
route_node_mpls 3 2 202 203

route_node_mpls_eth 5 6 103
route_node_mpls_eth 2 1 203

route_node 1 2 default
route_node 6 5 default

route_node 2 1 ${MPLS_IP_PFX}.1/32
route_node 5 6 ${MPLS_IP_PFX}.6/32

read -p "Press any key to continue..."

for lnode in 1 2 3 4 5 6; do
  sudo ip netns del ${NETNS_PFX}-$lnode
done

