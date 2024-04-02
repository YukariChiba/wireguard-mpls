# wireguard-mpls

Wireguard, but compatible with mpls, no MTU overhead.

## Source

The origin code is copied from wireguard kernel module from linux-6.8.2.

## Compile

`make`

## Usage

Setup wireguard tunnels as usual, route MPLS traffic into wg interfaces, and enjoy.

## Limit

- Currently, only one MPLS label per IP packet is supported.
- MTU is reduced to 1416, may fix it soon.
- Only IPv4/IPv6 packets are allowed to be MPLS payload, may add fallback option to accept more protocols.
  - However, TTL would be propagated from inner IP headers to MPLS headers, inner protocols without TTL are not supported.
- Can not disable MPLS function. Use sysctl for temporary solution.

## TODO

- [x] MPLS type encoding (send)
- [x] MPLS type decoding (receive)
- [x] MPLS packet to IP (send)
- [x] IP packet to MPLS (receive)
- [x] TTL back propagation (receive)
- [x] MPLS handing (receive)
- [ ] Multi-layer MPLS headers handling (non-IP inner protocol handling?)
- [ ] Adjust MPLS to use MTU 1420
- [x] BUG: encap ip packet from wg1, decap mpls and send to wg2 

## Test

- `test-install.sh`: replace current wireguard with wireguard-mpls.
- `test-tunnel.sh`: set up a tunnel from host to netns with MPLS routing.
- `test-router.sh`: set up 6 netns and 5 tunnels with MPLS routing.

## Benchmark

`WIP`
