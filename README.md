# wireguard-mpls

Wireguard, but compatible with mpls, no MTU overhead.

## How

- Decapsulate MPLS header (`decap_mpls`) before sending traffic out of WG interface
- Encapsulate MPLS header (`encap_mpls`) after receiving traffic from WG interface
- Nearly all magical stuff is in `magic.h`
- Use back progagation of TTL from inner IP header to restore MPLS TTL
- Add `MESSAGE_DATA_MPLS = 5` to avoid conflicts with some providers (e.g., cloudflare)
  - Also add `MESSAGE_DATA_MPLS_MC = 6` as multicast MPLS
- select `0.0.0.0` and `::` as peer for non-IP(mpls) traffic

```
(IP) ==[encap]==> (MPLS|IP) ==[wg-decap]==> (WG|IP) ==[wg-encap]==> (MPLS|IP) ==[decap]==> (IP)

╔═══════════════════════════════════════════════════════════════════════════════════╗
║                               WireGuard Header                                    ║
╠════════════════════════════════════════════════════════════════╦══════════════════╣
║ type                                                           ║ others           ║
║ 32 bit                                                         ║ (we don't care)  ║
╠══════════════════════════════════════════╦═════════════════════╬══════════════════╣
║ reserved zero 24 bit                     ║ type 8 bit          ║                  ║
║ Used for MPLS Label/Exp/BoS              ║ new type for MPLS   ║                  ║
╚══════════════════════════════════════════╩═════════════════════╩══════════════════╝

╔═══════════════════════════════════════════════════════════════════════════════════╗
║                               MPLS Header                                         ║
╠══════════════════════════════╦═══════╦═══════╦════════════════════════════════════╣
║ Label                        ║ Exp   ║ BoS   ║ TTL                                ║
║ 20 bit                       ║ 3 bit ║ 1 bit ║ 8 bit                              ║
╠══════════════════════════════╩═══════╩═══════╬════════════════════════════════════╣
║   Put in Wireguard reserved zeros (24 bit)   ║ Extracted from inner IP header TTL ║
╚══════════════════════════════════════════════╩════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════════════════════╗
║                            sk_buff reserved room                                  ║
╠══════════════════════╦════════════════════════════════════════════════════════════╣
║ type                 ║ MPLS Data (label + exp + bos)                              ║
║ 8 bit                ║ 24 bit                                                     ║
╠══════════════════════╬════════════════════════════════════════════════════════════╣
║ 0 for MPLS_UC        ║ used in wg pkt processing                                  ║
║ 1 for MPLS_MC        ║ (clear before finish post-receive processing)              ║
╚══════════════════════╩════════════════════════════════════════════════════════════╝
```

## Source

The origin code is copied from wireguard kernel module from linux-6.8.2.

## Compile

- `make`
- use `wireguard.ko`

## Usage

Setup wireguard tunnels as usual, route MPLS traffic into wg interfaces, and enjoy.

## Limit

- MTU is reduced to 1416, may fix it soon.
- ~~Only IPv4/IPv6 packets are allowed to be MPLS payload, may add fallback option to accept more protocols.~~ (Now supported)
  - However, TTL would be propagated from inner IP headers to MPLS headers, inner protocols without TTL would cause MPLS TTL to always be 64.
- Can not disable MPLS function. Use sysctl for temporary solution.
- Non-IP traffic would be sent to peers with allowed-ips 0.0.0.0/0 and/or ::/0.
- There will be MTU issues. For 2 stacked labels, working MTU is reduced to 1408.
- Multicast MPLS is never tested!

## TODO

- [x] MPLS type encoding (send)
- [x] MPLS type decoding (receive)
- [x] MPLS packet to IP (send)
- [x] IP packet to MPLS (receive)
- [x] TTL back propagation (receive)
- [x] MPLS handing (receive)
- [x] Multi-layer MPLS headers handling
- [x] non-IP inner protocol handling
- [ ] Adjust MPLS to use MTU 1420
- [x] BUG: encap ip packet from wg1, decap mpls and send to wg2 

## Test

- `make test-install`: replace current wireguard with wireguard-mpls.
- `make test-tunnel`: set up a tunnel from host to netns with MPLS routing.
- `make test-router`: set up 6 netns and 5 tunnels with MPLS routing, run traceroutes.
- `make test-stack`: set up a tunnel from host to netns with MPLS routing with stacked labels.

## Benchmark

`WIP`
(From the results of known tests, there is little difference in performance)
