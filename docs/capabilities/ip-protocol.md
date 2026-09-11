# ip-protocol (P1)

**Status:** **shipped** — [`egao1980/ip-protocol`](https://github.com/egao1980/ip-protocol) OCI **0.1.0** (`stack-ip`). Pure Lisp, no deps.

`parse-ip` / `parse-network` / `ip-contains-p` / `ip-overlaps-p` plus private / loopback / link-local / multicast / unspecified predicates.

No IPv4-mapped IPv6. IPv4 rejects leading zeros. IPv6 `ip-string` is exploded (no `::` compression).
