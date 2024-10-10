#!/bin/bash

NETNS="wg-test"
NIC="wg-test"
HOST_VETH_IP="169.254.0.1"
NS_VETH_IP="169.254.0.2"
HOST_WG_IP="169.254.1.1"
NS_WG_IP="169.254.1.2"
HOST_MPLS_IP="169.254.2.1"
NS_MPLS_IP="169.254.2.2"
HOST_PORT="11001"
NS_PORT="11002"

sudo ip netns add ${NETNS}
sudo ip link add ${NIC} type veth peer name ${NIC}-ns
sudo ip link set ${NIC}-ns netns ${NETNS}
sudo ip addr add ${HOST_VETH_IP}/30 dev ${NIC}
sudo ip netns exec ${NETNS} ip addr add ${NS_VETH_IP}/30 dev ${NIC}-ns
sudo ip link set ${NIC} up
sudo ip netns exec ${NETNS} ip link set ${NIC}-ns up

wg genkey > host-privkey 2> /dev/null
wg genkey > ns-privkey 2> /dev/null
sudo ip link add ${NIC}-wg type wireguard
sudo wg set ${NIC}-wg listen-port ${HOST_PORT} private-key host-privkey
sudo ip addr add ${HOST_WG_IP}/32 dev ${NIC}-wg peer ${NS_WG_IP}
sudo ip addr add ${HOST_MPLS_IP}/32 dev ${NIC}-wg
sudo wg set ${NIC}-wg peer $(wg pubkey < ns-privkey) allowed-ips 0.0.0.0/0 endpoint ${NS_VETH_IP}:${NS_PORT}
sudo ip link set ${NIC}-wg up

sudo ip netns exec ${NETNS} ip link add ${NIC}-wg type wireguard
sudo ip netns exec ${NETNS} wg set ${NIC}-wg listen-port ${NS_PORT} private-key $PWD/ns-privkey
sudo ip netns exec ${NETNS} ip addr add ${NS_WG_IP}/32 dev ${NIC}-wg peer ${HOST_WG_IP}
sudo ip netns exec ${NETNS} ip addr add ${NS_MPLS_IP}/32 dev ${NIC}-wg
sudo ip netns exec ${NETNS} wg set ${NIC}-wg peer $(wg pubkey < $PWD/host-privkey) allowed-ips 0.0.0.0/0 endpoint ${HOST_VETH_IP}:${HOST_PORT}
sudo ip netns exec ${NETNS} ip link set ${NIC}-wg up
rm host-privkey
rm ns-privkey

sudo modprobe mpls_router
sudo modprobe mpls_iptunnel

sudo ip route add ${NS_MPLS_IP}/32 encap mpls 100/200 via ${NS_WG_IP} src ${HOST_MPLS_IP}
sudo ip netns exec ${NETNS} ip route add ${HOST_MPLS_IP}/32 encap mpls 300/400 via ${HOST_WG_IP} src ${NS_MPLS_IP}
sudo sysctl -w "net.mpls.platform_labels=114514"
sudo sysctl -w "net.mpls.conf.wg-test-wg.input=1"
sudo ip netns exec ${NETNS} sysctl -w "net.mpls.platform_labels=114514"
sudo ip netns exec ${NETNS} sysctl -w "net.mpls.conf.wg-test-wg.input=1"

sudo ip netns exec ${NETNS} ip a add ${NS_MPLS_IP} dev lo
sudo ip netns exec ${NETNS} ip link set lo up

sudo ip netns exec ${NETNS} ip -M route add 100 as 101 via inet ${NS_WG_IP} dev ${NIC}-wg
sudo ip -M route add 101 via inet ${HOST_WG_IP} dev ${NIC}-wg
sudo ip netns exec ${NETNS} ip -M route add 200 dev lo

sudo ip -M route add 300 as 301 via inet ${NS_WG_IP} dev ${NIC}-wg
sudo ip netns exec ${NETNS} ip -M route add 301 via inet ${HOST_WG_IP} dev ${NIC}-wg
sudo ip -M route add 400 dev lo

echo "Now you can ping 169.254.2.2 from host."

if [ -x "$(command -v tcpdump)" ]; then
  sudo tcpdump -i ${NIC}-wg -nn -l
elif [ -x "$(command -v wireshark)" ]; then
  sudo wireshark -i ${NIC}-wg -k
else
  read -p "Press any key to continue..."
fi

sudo ip netns del ${NETNS}
sudo ip link del ${NIC}
sudo ip link del ${NIC}-wg



#
#  169.254.2.1 --> 169.254.2.2:
#   send -(ip)-> HOST -(100)-> NS -(101)-> HOST -(102) -> NS -(ip)-> NS(lo)
#   
#  169.254.2.2 --> 169.254.2.1: 
#   send -(ip)-> NS -(200)-> HOST -(201)-> NS -(202) -> HOST -(ip)-> HOST(lo)
#
#
