# wireguard-mpls

Wireguard, but compatible with mpls, no MTU overhead.

## How

- Decapsulate MPLS header before sending traffic out of WG interface
- Encapsulate MPLS header after receiving traffic from WG interface
- Use back progagation of TTL from inner IP header to restore MPLS TTL
- Add `MESSAGE_DATA_MPLS = 5` to avoid conflicts with some providers (e.g., cloudflare)

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
```

## Source

The origin code is copied from wireguard kernel module from linux-6.8.2.

## Compile

- `make`
- use `wireguard.ko`

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

- `make test-install`: replace current wireguard with wireguard-mpls.
- `make test-tunnel`: set up a tunnel from host to netns with MPLS routing.
- `make test-router`: set up 6 netns and 5 tunnels with MPLS routing, run traceroutes.

## Benchmark

`WIP`
(From the results of known tests, there is little difference in performance)
