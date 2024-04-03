#!/bin/bash

sudo modprobe wireguard

sudo rmmod wireguard || true

sudo modprobe curve25519_x86_64 libchacha20poly1305 ip6_udp_tunnel udp_tunnel

sudo insmod ./wireguard.ko

