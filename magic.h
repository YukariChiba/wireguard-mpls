#ifndef _WG_MAGIC_H
#define _WG_MAGIC_H

#include <linux/skbuff.h>
#include <linux/ip.h>
#include <linux/ipv6.h>
#include <net/ip_tunnels.h>
#include <net/mpls.h>
#include <net/mpls.h>

static inline bool decap_mpls(struct sk_buff *skb){
    struct mpls_shim_hdr *hdr;
    hdr = mpls_hdr(skb);
    // use reserved tailroom for mpls label + exp + bos
    __u32 skb_lse = be32_to_cpu(hdr->label_stack_entry) >>8;
    // if stacked
    if (!(skb_lse & 1)) {
        skb_pull(skb, MPLS_HLEN);
        skb_reset_network_header(skb);
        skb->protocol = htons(ETH_P_MPLS_UC);
        skb->reserved_tailroom = skb_lse;
        return true;
    }
    // do not trust inner_protocol since skb would be forwarded and decap
    // if (skb->inner_protocol == htons(ETH_P_IP) || skb->inner_protocol == htons(ETH_P_IPV6)) {
    skb_pull(skb, MPLS_HLEN);
    skb_reset_network_header(skb);
    __be16 real_protocol = ip_tunnel_parse_protocol(skb);

    // real_protocol != inner_protocol
    if (real_protocol != htons(ETH_P_IP) && real_protocol != htons(ETH_P_IPV6))
        return false;

    skb->protocol = real_protocol;
    skb->reserved_tailroom = skb_lse;
    return true;
}

static inline void encap_mpls(struct sk_buff *skb){
    if (skb->reserved_tailroom){
        __u8 inner_ttl;
        __be16 inner_protocol = skb->protocol;
        if (inner_protocol == htons(ETH_P_IPV6))
            inner_ttl = ipv6_hdr(skb)->hop_limit;
        if (inner_protocol == htons(ETH_P_IP))
            inner_ttl = ip_hdr(skb)->ttl;
        if (inner_protocol == htons(ETH_P_MPLS_UC))
            inner_ttl = be32_to_cpu(mpls_hdr(skb)->label_stack_entry) & 0xff;
        skb_push(skb, MPLS_HLEN);
        skb_reset_network_header(skb);
        skb->protocol = htons(ETH_P_MPLS_UC);
        struct mpls_shim_hdr *hdr;
        hdr = mpls_hdr(skb);
        hdr->label_stack_entry = 
            mpls_entry_encode(
                skb->reserved_tailroom >>4, // label
                inner_ttl, // ttl
                (skb->reserved_tailroom >>1)&0b111, // exp
                skb->reserved_tailroom & 1 // bos
            ).label_stack_entry;
        skb->reserved_tailroom = 0;
        skb->inner_protocol = inner_protocol;
    }
}

#endif /* _WG_MAGIC_H */
