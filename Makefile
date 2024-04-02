KDIR:=/lib/modules/$(shell uname -r)/build
PWD:=$(shell pwd)

obj-m+= wireguard.o

wireguard-m := main.o
wireguard-m += noise.o
wireguard-m += device.o
wireguard-m += peer.o
wireguard-m += timers.o
wireguard-m += queueing.o
wireguard-m += send.o
wireguard-m += receive.o
wireguard-m += socket.o
wireguard-m += peerlookup.o
wireguard-m += allowedips.o
wireguard-m += ratelimiter.o
wireguard-m += cookie.o
wireguard-m += netlink.o
wireguard-m += magic.o

default:
	make -j$(nproc) -C $(KDIR) M=$(PWD) modules
clean:
	make -j$(nproc) -C $(KDIR) M=$(PWD) clean

test-install: default
	./test-install.sh

test-tunnel: test-install
	./test-tunnel.sh

test-router: test-install
	./test-router.sh
