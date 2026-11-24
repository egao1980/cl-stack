# binary-protocol (P1)

**Status:** **shipped** — [`egao1980/binary-protocol`](https://github.com/egao1980/binary-protocol) OCI **0.1.1** (`stack-binary`). Pure Lisp, no deps.

Python [`struct`](https://docs.python.org/3/library/struct.html): `calcsize` / `pack` / `unpack` / `pack-into` / `unpack-from`.

Endian `<` `>` `!` `=` `@` — **standard** sizes, no C alignment. Codes: `x c b B ? h H i I l L q Q f d s`. Not `e` `n` `N` `P` `p`.

IEEE specials as in Python (0.1.1): `unpack` of `f` / `d` gives infinity and NaN instead of a float trap on SBCL (on other Lisps, `binary-unpack-error`), and `pack` of a NaN writes Python's quiet NaN (`7ff8000000000000` / `7fc00000`).

RFC 4648 / QP stay in [`encoding-protocol`](encoding-protocol.md).
