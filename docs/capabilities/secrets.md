# secrets-protocol (P2)

**Issues:** [#104](https://github.com/egao1980/cl-stack/issues/104)  
**Status:** brief **locked** — CLOS protocol + backends; **CSPRNG / tokens / compare / UUID / password hashes**

Python `secrets` + Java `SecureRandom` + password KDFs — **not** digests/AEAD (those live in [`crypto-protocol`](crypto.md)).

Conventions: [API.md](../API.md). Crypto: [crypto.md](crypto.md).

---

## Prior art

| Ecosystem | Surface | Steal |
|-----------|---------|-------|
| **Python** | `secrets` (`token_*`, `compare_digest`) | App-facing CSPRNG helpers; constant-time compare |
| **Python** | `uuid` | v4 required; v7 if cheap |
| **Java** | `SecureRandom`, `MessageDigest.isEqual` | Strong RNG; constant-time equality |
| **CL** | Ironclad OS PRNG + `uuid` | Default via `crypto-backend-ironclad` |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | CLOS protocol + backends | Swappable RNG (OS vs test deterministic) |
| **Default backend (A)** | OS CSPRNG via **Ironclad** `:os` PRNG | Same entropy story as crypto |
| **Tokens** | `token-bytes` / `token-hex` / `token-urlsafe` | Python `secrets` DX |
| **Compare** | `constant-time-equal` on octet vectors | Timing-safe MAC/password checks |
| **UUID** | v4 required; v7 when backend supports | uuid lib = v4; v7 follow-on OK |
| **Password hashing** | **Argon2id** preferred; bcrypt / PBKDF2 allowed | Ironclad has argon2i/d, bcrypt, pbkdf2 — default **argon2i** until argon2id lands |
| **Not here** | AEAD / digests / HMAC | → crypto-protocol |
| **Windows** | Required | Pure Lisp path |

---

## Protocol surface

Package nick: `stack-secrets`.

```lisp
(defclass secrets-backend () ())
(defvar *secrets-backend* nil)

(defgeneric backend-random-bytes (backend n) → octets)
(defun random-bytes (n &key (backend *secrets-backend*)))
(defun token-bytes (n &key (backend *secrets-backend*)))
(defun token-hex (n &key (backend *secrets-backend*)))      ; n = entropy bytes
(defun token-urlsafe (n &key (backend *secrets-backend*)))

(defun constant-time-equal (a b) → boolean)  ; protocol helper; backend may override

(defgeneric backend-uuid (backend &key version) → string)  ; default :v4
(defun uuid (&key (version :v4) (backend *secrets-backend*)))

;;; Password hashing (slow KDF)
(defgeneric backend-password-hash (backend password &key algorithm))
(defgeneric backend-password-verify (backend password hash))
(defun hash-password (password &key (algorithm :argon2i) (backend *secrets-backend*)))
(defun verify-password (password hash &key (backend *secrets-backend*)))
```

`password` accepts string (UTF-8 octets) or octets. Never log passwords/hashes at info.

---

## Non-goals

- Vault / KMS / keyring product
- TOTP/HOTP (follow-on)
- Deterministic test RNG as default (test-only backend OK)

---

## Implementation tasks

- [x] Brief lock — this doc
- [x] `secrets-protocol` + `secrets-backend-os` (+ uuid) + Rove
- [x] Cookbook section in [crypto.md](../cookbooks/crypto.md)
- [ ] OCI publish
