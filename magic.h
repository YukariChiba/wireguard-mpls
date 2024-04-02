#ifndef _WG_MAGIC_H
#define _WG_MAGIC_H

#include <linux/skbuff.h>
#include <linux/ip.h>
#include <linux/ipv6.h>
#include <net/ip_tunnels.h>
#include <net/mpls.h>

static inline bool decap_mpls(struct sk_buff *skb){
    struct mpls_shim_hdr *hdr;
    hdr = mpls_hdr(skb);
	skb_pull(skb, MPLS_HLEN);
	skb_reset_network_header(skb);
	__be16 real_protocol = ip_tunnel_parse_protocol(skb);
    if (real_protocol == htons(ETH_P_IP) || real_protocol == htons(ETH_P_IPV6)) {
        skb->protocol = real_protocol;
        // use reserved tailroom for mpls tags
        skb->reserved_tailroom = be32_to_cpu(hdr->label_stack_entry) >>12;
        return true;
    }
    return false;
}

static inline void encap_mpls(struct sk_buff *skb){
    if (skb->reserved_tailroom){
        __u8 inner_ttl = ip_hdr(skb)->ttl;
        skb->protocol = htons(ETH_P_MPLS_UC);
        skb_push(skb, MPLS_HLEN);
        skb_reset_network_header(skb);
        struct mpls_shim_hdr *hdr;
        hdr = mpls_hdr(skb);
        hdr->label_stack_entry = 
             mpls_entry_encode(skb->reserved_tailroom, inner_ttl, 0, true).label_stack_entry;
    }
}

#endif /* _WG_MAGIC_H */