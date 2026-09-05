# Cookbook: Crypto & secrets

**Audience:** people who know PyCA `cryptography` / `secrets`, or Java JCA.

| Want | Package |
|------|---------|
| Digest / HMAC / sealed blobs | [`crypto-protocol`](https://github.com/egao1980/crypto-protocol) (`stack-crypto`) |
| Tokens / UUID / password hashes | [`secrets-protocol`](https://github.com/egao1980/secrets-protocol) (`stack-secrets`) |

Capability briefs: [crypto.md](../capabilities/crypto.md) · [secrets.md](../capabilities/secrets.md).

```lisp
;; One backend system implements both crypto-protocol and secrets-protocol
(cl-repo:load-system "crypto-backend-ironclad" :version "0.2.0")
;; binds *crypto-backend* and *secrets-backend*
```

Backend lives in **`egao1980/crypto-backend-ironclad`** — not colocated under the protocol repos. Ironclad-backed secrets are **not** a separate `secrets-backend-os` project.

---

## 1. Recipes (prefer these)

Like Fernet / `AESGCM` — AEAD with safe defaults. **Do not** roll your own CBC+HMAC.

```lisp
(use-package :stack-crypto)
(use-package :stack-secrets)

(let* ((key (generate-key))   ; 32 octets
       (pt (babel:string-to-octets "payload" :encoding :utf-8))
       (blob (seal pt :key key)))
  (babel:octets-to-string (unseal blob :key key) :encoding :utf-8))
```

Wrong key / tampered blob → `crypto-authentication-error` (fail closed).

Sign / verify (Ed25519, RSA-PSS, ECDSA P-256; RS256 PKCS#1 only when you ask).
KATs: RFC 8032 + Wycheproof excerpt in `crypto-backend-ironclad`; JWT interop vs PyJWT in `cl-stack-jwt`:

```lisp
(multiple-value-bind (sk pk) (generate-key-pair :ed25519)
  (let ((sig (sign #(1 2 3) :algorithm :ed25519 :key sk)))
    (verify #(1 2 3) sig :algorithm :ed25519 :key pk)))
```

Associated data (authenticated, not encrypted):

```lisp
(seal pt :key key :aad (babel:string-to-octets "tenant=1" :encoding :utf-8))
```

---

## 2. Digests & HMAC

```lisp
(digest (babel:string-to-octets "abc" :encoding :utf-8) :algorithm :sha256)
(hmac key data :algorithm :sha256)

;; Incremental (large streams)
(let ((h (make-hasher *crypto-backend* :sha256)))
  (update! h chunk1)
  (update! h chunk2)
  (finalize h))
```

---

## 3. Secrets (tokens / compare / passwords)

```lisp
(token-bytes 32)
(token-hex 32)
(token-urlsafe 32)
(uuid :version :v4)

(constant-time-equal mac1 mac2)

(let ((hash (hash-password "s3cret" :algorithm :argon2i)))
  (verify-password "s3cret" hash))   ; => T
```

Password algorithms wave-1: `:argon2i` (default), `:pbkdf2-sha256`.

---

## 4. What not to do

| Don't | Do |
|-------|----|
| `Cipher.getInstance("AES")` / bare ECB | `seal` / `:aes-gcm` |
| SHA-256 for passwords | `hash-password` |
| `equal` on MACs | `constant-time-equal` |
| Reuse GCM nonces | `seal` always generates a fresh nonce |

---

## See also

- Process spawn: [process.md](../capabilities/process.md) (not crypto)
- RPC over stdio: [rpc.md](../capabilities/rpc.md)
