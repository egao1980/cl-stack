# cache-protocol (P2)

**Status:** **shipped** — [`egao1980/cache-protocol`](https://github.com/egao1980/cache-protocol) OCI **0.2.0** (`stack-cache`) + [`cache-backend-redis`](https://github.com/egao1980/cache-backend-redis) **0.2.0**.

CLOS cache: `cache-get` / `cache-put` (`:ttl` seconds, any real) / `cache-delete` / `cache-incr` / `cache-cas`. Code written against the in-memory backend behaves the same on Redis / Valkey.

| Python (redis-py) | cl-stack |
|---|---|
| `redis.Redis(host, port, username=, password=, db=)` | `make-redis-cache-backend :host :port :username :password :db` (lazy connect, `HELLO 3 AUTH`, `SELECT`; Redis 5 falls back to `AUTH` on RESP2) |
| `redis.from_url("rediss://user:pw@host:6380/0")` | `make-redis-cache-backend :url "rediss://…"` (TLS through cl-stack-ssl; `?db=` and IPv6 literals read as redis-py reads them; explicit keywords win) |
| `with redis.Redis(...) as r:` / `r.close()` | `with-redis-cache` / `cl:close` |
| `r.set(k, v, ex=60)` / `px=1500` | `cache-put c k v :ttl 60` / `:ttl 1.5` (sent as `PX 1500`) |
| `r.incr(k)` | `cache-incr` (keeps the TTL) |
| `WATCH` / `MULTI` CAS, `SET NX` | `cache-cas c k expected new [:ttl]` (Lua; expected `nil` = create-if-absent) |
| `cachetools.TTLCache` | `make-in-memory-ttl-cache` (sub-second monotonic clock, `monotonic-seconds`; one lock: atomic `incr` / `cas`) |

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Expiry** | An entry is gone once its TTL has elapsed (`expiry <= now`); TTL is any real, and a NaN TTL is a `cache-error` |
| **Atomicity** | `incr` and `cas` are atomic on every backend (the in-memory one under a recursive bt2 lock) |
| **`incr`** | Keeps the entry's TTL (Redis `INCR`); only integer text (`-?[0-9]+`) counts, anything else is a `cache-error` |
| **Conditions** | `cache-error` (`key`, `message`) → `cache-cas-mismatch` (`expected`, `actual`), `cache-connection-error` (`cause`: usocket / stream / cl+ssl) |
| **Redis errors** | Every error reply signals `cache-error` with the server's text; a URL error masks the password |
| **Reconnect** | A dropped socket is resent once on a new connection (`:retries`, default 1); then `cache-connection-error` with a `reconnect` restart. A refused connect or a refused `AUTH` is not retried |
| **Transport** | usocket; TLS cl+ssl via cl-stack-ssl; URLs via quri (0.7.2 for userinfo before an IPv6 literal) |

## Open

- [cache-backend-redis#9](https://github.com/egao1980/cache-backend-redis/issues/9): on Windows (SBCL), over plain TCP, a server that accepts and never answers blocks the call past `:connect-timeout` (TLS and other platforms fail on time)

Demo: [cl-stack-demos `harness/cache-ttl`](https://github.com/egao1980/cl-stack-demos/tree/main/harness/cache-ttl) (cache-protocol 0.2.0).
