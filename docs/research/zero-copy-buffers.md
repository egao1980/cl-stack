# Zero-copy typed buffers for cl-stack: research report

**Date:** 2026-11-28. **Status:** research, no decision yet. Tracks [egao1980/arrow-protocol#8](https://github.com/egao1980/arrow-protocol/issues/8). Paths are relative to the cl-workspace checkout.

Scope: arrow-protocol#8 (typed storage plus the Arrow C Data Interface) and whether a stack-wide `buffer-protocol` is warranted. No code was changed. "Verified" means I checked it locally: SBCL 2.6.9 arm64, ECL 26.5.5, ABCL 1.9.2 on macOS. CCL is not installed here, so CCL claims come from source and documentation only.

## 0. Where the copies are today

| Site | What happens per value |
|---|---|
| `cl-stack-duckdb/src/decode.lisp` `decode-vector` | `cffi:mem-aref` per row into a boxed `simple-vector`. The validity bit is tested per row (`%valid-p`, `logbitp` over a `uint64` word). Strings go through `foreign-string-to-lisp`, blobs are copied byte by byte (`%blob`). |
| `cl-stack-duckdb/src/arrow.lisp` `result-to-arrow` | A second pass: `map 'vector #'%arrow-value` over the already boxed column, then `make-arrow-array` → `coerce … 'simple-vector`. That makes three materialisations per chunk. |
| `arrow-protocol/src/array.lisp` | `arrow-array` = `(type values)` with boxed values and `:null` sentinels. `validity-bitmap` and `array-null-count` rescan the whole vector each time they are called. |
| `arrow-protocol/src/ipc.lisp` write (`%append-buffers`, ~l.211–375) | Each fixed-width column is re-encoded value by value: `%write-i32le` / `%write-i64le`, and `%double-float-bits` through `sb-kernel` on SBCL or a temporary octet vector elsewhere. Then `%assemble-body` copies every chunk into one body vector with `replace`, `%encapsulate` copies it again, and `encode-ipc-stream` copies it a third time. |
| `ipc.lisp` read (`%decode-array`, ~l.577+) | `subseq` of each body buffer, then a per-value decode into `(make-array n)` (boxed). |
| `grpc-backend-http2/src/framing.lisp` | `unframe-message` / `unframe-next`: `coerce` to an octet vector, then `subseq` the payload. A second copy happens on concatenation (`replace`). |
| `cl-stack-zstd/src/api.lisp` | Input is pinned with `with-pointer-to-vector-data`, which is good. The output goes into `with-foreign-object` and is copied back to Lisp with a per-byte `mem-aref` loop (l.36, 56, 73). The streams (`streams.lisp`) keep `foreign-alloc` fin/fout buffers and copy per byte (l.75, 88). |
| `cl-stack-snappy/src/api.lisp` l.32 | Same per-byte `mem-aref` copy-out. |
| `event-backend-libuv` | Uses `uv_poll` readiness only (`register-io`, backend.lisp l.276–289). There is no `uv_read_start` / `uv_buf_t` path yet, so libuv never owns read buffers today. |
| `http2/core/buffer-pool.lisp` | Lock-free, size-classed pool of Lisp octet buffers (≤16, ≤1024, ≤16384). This is already a "buffer protocol" in miniature, but Lisp-heap only. |
| `audio-protocol` | Already uses specialized `double-float` / `single-float` vectors (`fft.lisp`, `mix.lisp`, `model.lisp`). This is the right model already. |
| `llm-backend-llama-cpp` | Embeddings arrive as lists or vectors through the `llama-cpp` binding and are `subseq`'d (`%slice-embedding`). The tensor path is not in scope yet. |

The quickest gains do not need foreign memory at all. Specialized vectors in `arrow-array`, plus bulk `memcpy` or `replace` instead of per-element `mem-aref` loops, remove most of the cost. Foreign-backed buffers matter only at true FFI boundaries: DuckDB Arrow export/import, codecs, and later the socket and llama.cpp paths.

## 1. Per implementation

### SBCL (primary)

**(a) Unboxed vectors.** Verified on 2.6.9: `upgraded-array-element-type` keeps `(unsigned-byte 2/4/7/8/16/32/63/64)`, `(signed-byte 8/16/32/64)`, `fixnum`, `single-float`, `double-float`, `(complex single-float)`, `(complex double-float)` and `bit`. That covers every Arrow fixed-width primitive. The physical layout of a `(simple-array T (*))` is a header (widetag + fixnum length, `sb-vm:vector-data-offset` words), followed by data packed little-endian on x86-64 and arm64. `bit` vectors are packed LSB-first within each word, which matches Arrow's bit numbering on little-endian hosts. That is an inference from the SBCL layout; test it against a golden bitmap before relying on `replace` across a sap.

**(b) Pinning.** `sb-sys:with-pinned-objects` plus `sb-sys:vector-sap` is what CFFI's `with-pointer-to-vector-data` expands to on SBCL (cffi-sbcl.lisp l.175–182). On arm64 it expands to `(let ((sb-vm::*pinned-objects* (list* x sb-vm::*pinned-objects*))) (declare (dynamic-extent …)) …)` (verified by macroexpansion). On x86-64 it keeps the object live on the control stack and relies on conservative stack scanning (from SBCL source knowledge; unverified here). Both forms are dynamic-extent by construction. There is no supported API for a long-lived pin: a pin ends when the scope ends. You could fake one by parking a thread inside `with-pinned-objects`, but that is a hack. Pinned objects also block compaction of the memory around them under gencgc (the default here: `:gencgc` is in the internal features). Many long pins mean fragmentation and slower GCs. The mark-region collector (Hayley Patton; build option since 2.3.8, arm64 since 2.4.1, stability fixes as late as 2.6.4) is "mostly non-moving", so pins are cheaper there. It is not the default build, though, so you cannot rely on it.

**(c) Arrays outside the GC heap.**
- `static-vectors` on SBCL `posix_memalign`s a block and writes a fake SBCL vector header (widetag + fixnumised length) in front of the data. It then makes a Lisp object with `sb-kernel:%make-lisp-obj` and the other-pointer lowtag (impl-sbcl.lisp). The GC ignores pointers outside its spaces, so the result is a genuine `simple-array` that `aref`, `replace` and `declare` all optimise. It must be freed with `free-static-vector`, and a dangling Lisp reference after that is a use-after-free. Alignment is 16 to 4096, power of two, on SBCL/unix only (constructor.lisp l.42–63), so **64-byte Arrow alignment is available on SBCL**.
- `sb-int:make-static-vector` (verified to exist) allocates in static space. It is never freed, so it suits only process-lifetime constant buffers.
- Wrapping *someone else's* foreign memory (for example a DuckDB `ArrowArray` buffer) as a Lisp array with the same trick is impossible without writing a header into the 16 bytes before the producer's data, which you do not own. Ruled out. `make-array-header` / `set-array-header` (in `sb-kernel`, verified present) can make a *non-simple* header displaced to a Lisp vector, but not to an arbitrary address. **On SBCL, imported foreign buffers must be accessed through SAP accessors** (`sb-sys:sap-ref-double`, `sap-ref-32`, or `cffi:mem-aref` with a constant type, which compiles to the same code). They are fast but not `aref`.

**(d) Finalizers.** `sb-ext:finalize object fn &key dont-save` runs on any thread (in 2.6.9 a dedicated `sb-impl::*finalizer-thread*`) in any dynamic scope. The closure must not close over the object, and errors become warnings (docstring, verified). Timing is GC-driven: a small Lisp wrapper around a large foreign buffer creates no GC pressure, so the buffer can live a long time, and the GC never learns about the foreign bytes.

### CCL

**(a)** Specialized ivectors exist for 8/16/32/64-bit signed and unsigned, single/double float and bit (from documentation and source; not verified locally).
**(b)** `ccl:with-pointer-to-ivector` (what CFFI uses, cffi-openmcl.lisp l.140) is undocumented. Per openmcl-devel it **suspends the GC for the extent of the body**. That is fine for a `memcpy` or a codec call. It is not acceptable around anything that blocks, such as a socket read or a long DuckDB call.
**(c)** `ccl:make-heap-ivector` returns `(values vector macptr size)`. The vector is a real ivector in malloc'd memory and is released with `ccl:dispose-heap-ivector`. This is what static-vectors uses on CCL (impl-clozure.lisp), and the CCL manual describes it. Alignment is not configurable (unverified: likely 8 or 16). Wrapping foreign memory not allocated this way is not possible, for the same header reason as on SBCL.
**(d)** Finalizers go through `ccl:terminate-when-unreachable`. trivial-garbage implements them as a weak-key table plus termination.

### ECL

**(a)** Verified on 26.5.5: `byte8/16/32/64`, `integer8/16/32/64`, `single-float`, `double-float`, `complex-single/double-float` and `bit` are all specialized. `fixnum` upgrades to `integer64`.
**(b)** Boehm GC is non-moving, so a Lisp array never moves. CFFI's `with-pointer-to-vector-data` is just `si:make-foreign-data-from-array` (cffi-ecl.lisp l.176). There is no pin cost, but liveness is the catch. Boehm scans foreign memory conservatively only if it is a registered root, so a Lisp vector referenced *only* from C can be collected. static-vectors on ECL is a plain `make-array`, and `free-static-vector` is a no-op (impl-ecl.lisp). For export you still need to hold a Lisp reference until `release`.
**(c)** **ECL can display foreign memory as a Lisp array.** Verified: `(make-array 2 :element-type 'double-float :displaced-to (ffi:allocate-foreign-object :double 2))` returns a `(vector double-float 2)`, and a write through `aref` shows up through `ffi:deref-array`. The array is non-simple (displaced), so `aref` costs one more indirection. A `si:allocate-foreign-data :void 16` source segfaulted on write, so wrap only typed foreign-data objects and treat this as internal API (`si:`).
**(d)** `ext:set-finalizer` / `ext:get-finalizer`. trivial-garbage chains them.

### ABCL

**(a)** Verified on 1.9.2: only `(unsigned-byte 8/16/32)` and `bit` specialize. `signed-byte 8/16/32`, `unsigned-byte 64`, `single-float` and `double-float` all upgrade to `T`, which means boxed Java objects. ABCL gets no unboxed float columns no matter what we do.
**(b)** There is no pinning, and JNA reaches the JVM heap only through copies. CFFI's ABCL `with-pointer-to-vector-data` **copies the vector into a foreign buffer, runs the body, and copies it back** (cffi-abcl.lisp l.358–370). It also looks the vector up in `*static-vector-pointer*` at *macroexpansion* time with the unevaluated form, so it probably always copies. That is an inference; unverified.
**(c)** `make-array … :nio-buffer` (feature `:nio`, verified) wraps a `java.nio.ByteBuffer`, and so a JNA `Memory`'s direct buffer, as a Lisp octet vector. This is real foreign-backed storage, and static-vectors uses it. Verified caveat: with `:element-type 'double-float` the `:nio-buffer` is **silently ignored** and you get a `SIMPLE-VECTOR`. Only ub8/16/32 work. Other types need a typed accessor layer over the `ByteBuffer` (`getDouble(index)`) or JNA `Pointer.getDouble`.
**(d)** `ext:finalize`, backed by JVM reference queues.

### Prior art

- LispWorks: `make-array … :allocation :static` and `fli:with-dynamic-lisp-array-pointer` (cffi-lispworks.lisp).
- Allegro: `:allocation :static-reclaimable` (a GC-reclaimed static array; cffi-allegro.lisp) and `excl:with-underlying-simple-vector`.

Allegro is the closest to the semantics we want: non-moving, freed by the GC, and directly `aref`-able.

## 2. Existing libraries

- **static-vectors** (sionescu): MIT, v1.9.3, last push 2024-06-24, 0 open issues, not archived. It is already a cl-stack-systems import (`cl-stack-systems/imports/static-vectors`), so using it needs no new third-party entry. Mechanisms per implementation are as in §1. The library gives you allocation only: no views, no refcounting, no wrapping of foreign memory. Treat it as a backend for one storage kind, not as the protocol.
- **CFFI**: `make-shareable-byte-vector` + `with-pointer-to-vector-data`. Pin-for-a-scope semantics on SBCL, CCL (with the GC suspended), ECL and LispWorks. On Allegro, LispWorks and ABCL it gives a static or copied buffer. Octets only by contract.
- **fast-io**: builds output buffers on static-vectors (fast-io.asd, src/io.lisp l.78). **nibbles**: endian-aware `ub32ref/le`-style accessors over octet vectors, Lisp-heap only. Both serve framing, not columnar data.
- **trivial-garbage**: a portable `finalize` / `cancel-finalization` wrapper over each implementation's native hook (trivial-garbage.lisp l.270–340).
- **Numeric arrays** (from memory; unverified in this session): numcl uses specialized Lisp arrays, displaced onto a flat base vector. magicl uses specialized Lisp vectors and pins (SBCL) or uses shareable vectors around BLAS/LAPACK calls. lla similarly pins where possible and copies otherwise. None of them wrap foreign memory as first-class storage, and all of them converge on "specialized Lisp vector, pin for the call".
- **CL Arrow**: `kat-co/cl-apache-arrow` wraps Arrow GLib through GObject Introspection, a C++ dependency, so it is unsuitable. I found no CL implementation of the C Data Interface. We would be first.

## 3. Arrow C Data and C Stream Interface

**Structs** (spec):

```c
struct ArrowSchema { const char* format; const char* name; const char* metadata;
  int64_t flags; int64_t n_children; struct ArrowSchema** children;
  struct ArrowSchema* dictionary; void (*release)(struct ArrowSchema*); void* private_data; };
struct ArrowArray { int64_t length; int64_t null_count; int64_t offset; int64_t n_buffers;
  int64_t n_children; const void** buffers; struct ArrowArray** children;
  struct ArrowArray* dictionary; void (*release)(struct ArrowArray*); void* private_data; };
struct ArrowArrayStream { int (*get_schema)(struct ArrowArrayStream*, struct ArrowSchema*);
  int (*get_next)(struct ArrowArrayStream*, struct ArrowArray*);
  const char* (*get_last_error)(struct ArrowArrayStream*);
  void (*release)(struct ArrowArrayStream*); void* private_data; };
```

All of these are plain pointers and `int64_t`s, so `cffi:defcstruct` binds them directly with no by-value structs. That matters: the DuckDB shim exists only because `duckdb_result` is passed by value.

**Ownership rules:**
- The consumer calls the *base* struct's `release` exactly once and never calls a child's.
- `release == NULL` marks a struct as released.
- The struct may be moved by bitwise copy, after which the source's `release` is set to NULL. So the producer must not store pointers into the struct itself.
- `private_data` belongs to the producer.
- `null_count` may be -1 (not yet computed).
- `offset` is in elements.
- A buffer may be NULL only for the validity bitmap when `null_count = 0`, or when its size is 0.
- Both sides SHOULD treat the data as immutable.
- Streams: end of stream is signalled by `get_next` returning a *released* array. `get_last_error` is valid only after an error and only until the next call. The stream is not thread-safe, so the consumer serialises calls.

**Alignment:** the C interface recommends alignment but does not require it ("Consumers MAY decide not to support unaligned memory"). The columnar format recommends 8- or 64-byte alignment and padding and prefers 64. IPC *requires* each body buffer to start at an 8-byte boundary and each message to be a multiple of 8 bytes. That is what `%pad8` / `%encapsulate` already do.

**Layout we must match byte for byte:**
- Validity bitmaps are LSB-first, 1 = valid, and may be omitted when `null_count` is 0.
- Booleans are bit-packed the same way.
- Fixed-width values are little-endian.
- utf8/binary use `length+1` int32 offsets (int64 for large types) followed by a data buffer, with offsets monotone even for null slots.
- Binary/Utf8 View uses 16-byte views: a 4-byte length, then either the inline bytes (≤12) or a 4-byte prefix, buffer index and offset.

DuckDB's internal `duckdb_string_t` (`%string-bytes` in decode.lisp) has exactly the View layout. DuckDB's Arrow export can produce either `utf8` or `string_view` depending on options. DuckDB validity is LSB-first in `uint64` words, which is the same bit order as Arrow.

**Import (DuckDB → Lisp).** The wrapper object holds:
- the `ArrowArray*`, copied (moved) into a Lisp-owned `foreign-alloc`'d struct so that DuckDB's stack copy can go;
- per-column buffer views: pointer, byte length, element type, element offset;
- a release thunk.

Lifetime is primarily scoped (`with-arrow-import`), with `release` in `unwind-protect`. A finalizer serves as a backstop, registered on the wrapper with a closure over the *foreign struct pointer only*, never over the wrapper itself. Because a finalizer can fire on any thread, `release` must be safe to call off-thread. DuckDB's is, as far as I know (unverified). An atomic flag guards against double release.

Children are moved out only when needed (the spec allows this, but the parent must then be released immediately). The simpler rule is that all column views share the parent's lifetime through a refcount on the parent.

If the consumer wants Lisp arrays that outlive the import, copy with one `memcpy` per buffer into a specialized vector: `with-pointer-to-vector-data` + `memcpy`, or `replace` from a static-vector. It is O(bytes), with no per-value work and no boxing.

**Export (Lisp → DuckDB).** `buffers[i]` must remain valid until the *consumer* calls `release`, at a time we do not control and possibly on a DuckDB worker thread. Scoped pinning therefore cannot back an export. The options are:
1. Storage that is already foreign or static (static-vectors, foreign buffers). Export is then zero-copy: `private_data` holds a handle id, and the `release` callback (`cffi:defcallback`) decrements the refcount in a global handle table.
2. One `memcpy` into a 64-byte-aligned foreign block on export.

Callbacks into Lisp from foreign threads work on SBCL (since 2.x, the thread is adopted), CCL and ECL with threads. On ABCL, JNA callbacks work but are slow. The `release` callback must not allocate heavily or signal: it should only push the handle id onto a lock-free queue, or decrement a refcount and `foreign-free`.

DuckDB entry points (cl-stack-duckdb `build/duckdb.h`, C API 1.5.6): **stable since 1.5.6** are `duckdb_to_arrow_schema`, `duckdb_data_chunk_to_arrow`, `duckdb_schema_from_arrow`, `duckdb_data_chunk_from_arrow` ("Data ownership is passed on to DuckDB's DataChunk") and `duckdb_destroy_arrow_converted_schema`. `duckdb_query_arrow*`, `duckdb_result_arrow_array`, `duckdb_arrow_scan` and `duckdb_arrow_array_scan` are **deprecated since 1.0** and compiled only with `DUCKDB_API_ALLOW_DEPRECATED`. Build on the 1.5.6 chunk-level API.

Note that `duckdb_data_chunk_to_arrow` produces the `ArrowArray` by converting a chunk. Whether it aliases the DuckDB vectors or copies them is not stated in the header. I suspect it copies some types, strings especially (unverified). So "zero-copy from DuckDB" means at most one copy, inside DuckDB's C++, instead of three boxed passes in Lisp.

## 4. A stack-wide `buffer-protocol`: recommendation

### Representation options

| Option | `aref`-able | Lifetime | Portability | Verdict |
|---|---|---|---|---|
| A. Specialized Lisp vector, pin on demand | yes, fastest | GC | SBCL/CCL/ECL good; ABCL floats boxed | **Default storage** |
| B. static-vectors (foreign-allocated Lisp vector) | yes | explicit free; dangling Lisp reference = UAF | SBCL fake header, CCL heap-ivector, ECL plain array, ABCL nio for ub8/16/32 only | **Exportable storage** |
| C. Foreign pointer + length + element type (+ release) | no: SAP / `mem-aref` accessors | refcount, scope, finalizer backstop | all (CFFI) | **Imported storage** |
| D. Fake headers over foreign memory | yes | n/a | unsafe on SBCL (header outside our block), workable only on ECL (displaced) | Reject, except an ECL optimisation |

You cannot get one representation that is both `aref`-able and able to wrap arbitrary foreign memory portably. So the protocol should be a **small struct with a storage kind**, not a Lisp array:

```lisp
(defstruct (buffer (:constructor %make-buffer))
  (kind    :lisp :type (member :lisp :static :foreign))
  (element-type '(unsigned-byte 8))  ; arrow-ish: :u8 :i32 :f64 :bit …
  (storage nil)        ; specialized simple-array (:lisp / :static) or NIL
  (pointer nil)        ; foreign pointer (:foreign; also cached for :static)
  (offset 0 :type fixnum)   ; in elements, Arrow-style
  (length 0 :type fixnum)
  (owner  nil))        ; refcounted owner: release fn + count + released flag
```

- **Views and slices:** `(buffer-slice buf start end)` gives a new header sharing `storage`/`pointer` and `owner`, and incrementing the owner's count. There is no copy. Arrow's own `offset` maps onto this directly, and gRPC payload slices (`subseq buf 5 (+ 5 n)` today) become views.
- **Accessors:** `buffer-ref` / `(setf buffer-ref)` are generic in name but specialised by macro. `with-buffer-accessor ((ref buf :f64)) …` expands into a type-dispatched loop with `aref` on a declared `(simple-array double-float (*))` for `:lisp`/`:static`, or `cffi:mem-aref ptr :double` for `:foreign`. Hot loops then pay one dispatch per buffer, not per element. Expose `buffer-to-vector` (a copy into a specialized vector, one `memcpy`) and `buffer-pointer` / `with-buffer-pointer` (a pin for `:lisp`, direct for the others).
- **Lifetime:**
  - `with-buffer` / `with-foreign-buffer` scopes are the primary model. They release on unwind, which fits CLHS 9-style conditions and keeps `unwind-protect` discipline.
  - A **refcount** is used only where ownership is shared: Arrow import (columns share the parent `ArrowArray`), slices, and export (DuckDB holds a reference until `release`). Use atomic incf/decf: `sb-ext:atomic-incf` on a struct slot of type `sb-ext:word`, and a lock elsewhere.
  - A **finalizer** on the owner is a backstop that logs a leak warning and releases. It is never the primary mechanism, because GC timing is unrelated to foreign memory pressure.
  - On release, `:foreign`/`:static` buffers set the pointer to NIL so later access signals a `buffer-released-error` (a typed condition with a `use-value` restart where meaningful) instead of crashing.
- **Aliasing and immutability:** buffers carry a `read-only` flag. Imported Arrow buffers are read-only (the spec says SHOULD be immutable), and exported ones become read-only on export. Mutating through `(setf buffer-ref)` checks the flag (one slot read), and `buffer-copy` produces a mutable copy. Do not try to enforce this for raw pointers.
- **Fallback:** `:lisp` is always available. Where a feature is missing, the protocol degrades instead of failing:
  - ABCL: `f64` storage is a boxed `simple-vector` or a ByteBuffer accessor; export copies into foreign memory.
  - CCL: `with-buffer-pointer` on `:lisp` suspends the GC, so blocking FFI calls must require `:static`. This is a declared capability, `(buffer-capability :pin-across-blocking-call)`.
  - Every backend runs the same Rove suite.
- **Pools:** fold http2's size-class pool idea in as `buffer-pool` (lock-free, size-classed, recycles `:static` buffers for socket and codec I/O). That avoids per-message `posix_memalign`/free and the static-vectors allocation cost (malloc + header write).

### Why this shape

It keeps the common path, Lisp-produced columns and audio/DSP, on plain specialized vectors that SBCL compiles tight. It confines foreign lifetime complexity to the three places that need it: Arrow import, export, and native codec/socket I/O. It is the same design Arrow C++/Rust use (a `Buffer` with a parent/owner refcount and slices), translated to CL storage realities.

The rejected options:
- static-vectors everywhere would give UAF risk to every consumer and needs explicit frees in pure-Lisp code.
- Fake headers are not maintainable across SBCL releases: they depend on `sb-vm` widetags, `%vector-widetag-and-n-bits` renames (static-vectors already carries both spellings) and the lowtag scheme.

Per the "own stack first" rule, this is a first-party protocol (`egao1980/buffer-protocol`). static-vectors and trivial-garbage are its only third-party dependencies, and both are already imported.

### What to measure before committing (Rove-adjacent bench harness in cl-stack-demos)

1. Decoding a 1M-row `DOUBLE` + `VARCHAR` DuckDB result: the current boxed path vs typed `memcpy` from `duckdb_vector_get_data` (no Arrow) vs `duckdb_data_chunk_to_arrow` + import views vs import + copy into a specialized vector. Measure time, bytes consed, and GC time.
2. `aref` on a declared specialized vector vs `mem-aref` on a SAP vs a `buffer-ref` generic dispatch, in a sum loop on SBCL, CCL and ECL. This decides how hard the accessor macro must work.
3. IPC write of a 1M-int64 column: per-value `%write-i64le` (today) vs `replace` from a `(signed-byte 64)` vector through a displaced octet view or `memcpy`.
4. `with-pinned-objects` cost and GC pause time with N concurrently pinned large vectors (gencgc, and mark-region if a build is available). `with-pointer-to-ivector` GC-suspension impact on CCL.
5. `make-static-vector`/`free` throughput vs `make-array` vs pooled reuse, for 4 KiB–1 MiB buffers (socket/codec sizes).
6. Finalizer backstop latency: how many leaked 1 MiB foreign buffers accumulate before SBCL finalizes them. This justifies "warn, don't rely on it".

## 5. Phased plan

**Phase 0: no new protocol yet (days).**
- Fix the per-byte copy loops in cl-stack-zstd (`api.lisp` l.36/56/73, `streams.lisp`) and cl-stack-snappy (`api.lisp` l.32). Use `memcpy` into a vector pinned with `with-pointer-to-vector-data`, or decompress straight into a pinned output vector.
- In grpc framing, return displaced views or `(values buf start end)` instead of `subseq`.

These are isolated, measurable, and need no design decision.

**Phase 1: typed storage in arrow-protocol (the core of #8).**
- Change `arrow-array` to `(type length null-count validity data offsets children)`, with `data` a specialized vector per fixed-width type, `validity` an octet vector (or `bit` vector), and utf8/binary as int32 offsets + an octet data vector.
- Keep `make-arrow-array` (boxed input → typed), `array-ref`, `array-null-p` and `arrow-array-values` (a boxed view built lazily) for compatibility. `null-count` is cached.
- IPC write becomes buffer `replace` with no per-value encoding on little-endian hosts. Add a `#+big-endian` byte-swap path and test it under ABCL, where floats stay boxed and the per-value path remains.
- Risk: every arrow-protocol consumer (parquet writer, `dremel.lisp`, schema-protocol-arrow, cl-stack-duckdb) reads `arrow-array-values`. Mitigation: keep that accessor working and migrate call sites incrementally.

**Phase 2: `buffer-protocol` v0 + C Data Interface import.**
- Create `egao1980/buffer-protocol` the same day (`create-first-party-repo.sh`) with the `:lisp` / `:static` / `:foreign` kinds, slices, scope + refcount + finalizer backstop, and conditions.
- arrow-protocol gains `arrow-protocol/c-data`: CFFI structs, `import-arrow-array` / `import-arrow-stream` producing arrays whose buffers are `:foreign` views, and `copy-arrow-array` to typed Lisp storage.
- cl-stack-duckdb gains a path over `duckdb_data_chunk_to_arrow` + `duckdb_to_arrow_schema`, replacing the three-pass boxed `result-to-arrow`.
- Risks:
  - DuckDB's exported `format` strings for its extensions (`string_view` `vu`, decimal `d:p,s`, timestamp tz `tsu:UTC`, unions, and maybe run-end encoding) need a format-string parser and mapping to existing type specs.
  - `release` threading.
  - The C API version floor (1.5.6), which is already pinned.

**Phase 3: export.**
- `export-arrow-array` from `:static` buffers (zero-copy) or `:lisp` buffers (one `memcpy` into a 64-byte-aligned foreign block). A `release` `defcallback` with a global handle table and atomic refcounts.
- Use it for `append-arrow-table` through `duckdb_data_chunk_from_arrow`, replacing both the row appender and the Parquet temp-file detour.
- Risks: callbacks from DuckDB worker threads (SBCL foreign-thread adoption, ECL's `mp` registration), and ABCL (copy only).

**Phase 4: I/O and messaging (later; design hinges on the libuv decision).**
- event-backend-libuv moves from `uv_poll` to `uv_read_start` with an `alloc_cb` that hands out `:static` buffers from a `buffer-pool`, so libuv reads straight into them.
- HTTP/2 frame payloads become slices of the read buffer.
- gRPC unframing slices again.
- protobuf `bytes` fields get an optional "view" decoding mode that returns `buffer` slices (a copy remains the default, because slices pin the whole read buffer: retention risk).
- TLS (cl-stack-ssl) decrypts into pooled buffers.
- The llama.cpp embeddings/tensors path returns `:foreign` `f32` views over `llama_get_embeddings`, which are valid until the next decode, so they are scoped. A copy is used when they must outlive the scope.

Risks for Phase 4:
- Slice retention can hold large buffers alive. Mitigate with a "compact if slice < 1/4 of parent" heuristic.
- Cross-thread release in the event loop.
- http2's existing pool would have to be unified, not duplicated.

**Cross-cutting risks:**
- UAF from `:static` buffers freed while a Lisp reference survives. Released buffers NIL their pointer, but a raw `storage` vector extracted earlier cannot be protected, so document "never retain `buffer-storage` of a `:static` buffer".
- SBCL internals used by static-vectors could change. It already copes with the `%vector-widetag-and-n-bits` rename, and it is pinned through the import.
- ABCL: the ceiling is copies plus boxed floats. Accept it and test it as the reference fallback.

## Sources

**Local files:**
- `arrow-protocol/src/array.lisp`, `src/table.lisp`, `src/ipc.lisp` (l.108–132, 211–383, 577–800), `README.md`
- `cl-stack-duckdb/src/decode.lisp`, `src/arrow.lisp`, `shim/cl_stack_duckdb_shim.c`, `build/duckdb.h` (l.2764–2860 Arrow module; 2860–3120 deprecated Arrow API; 9990/10016 vector data and validity), `README.md`
- `cl-stack-zstd/src/api.lisp`, `src/streams.lisp`; `cl-stack-snappy/src/api.lisp`; `grpc-backend-http2/src/framing.lisp`; `event-backend-libuv/src/backend.lisp`; `http2/core/buffer-pool.lisp`; `audio-protocol/src/{fft,mix,model}.lisp`; `llm-backend-llama-cpp/src/backend.lisp`
- `demiurge-parity/.cl-repository/static-vectors-1.9.3/src/{impl-sbcl,impl-clozure,impl-ecl,impl-abcl,constructor}.lisp`
- `demiurge-parity/.cl-repository/cffi-grovel-0.24.1/src/{cffi-sbcl,cffi-openmcl,cffi-ecl,cffi-abcl,cffi-lispworks,cffi-allegro}.lisp`
- `demiurge-parity/.cl-repository/trivial-garbage-0.21/trivial-garbage.lisp`; `fast-io-1.0/src/io.lisp`
- `cl-stack-systems/imports/static-vectors/qlfile`
- Local probes: `(local probe scripts, not committed)`

**GitHub:**
- egao1980/arrow-protocol#8 (`gh issue view 8 -R egao1980/arrow-protocol --comments`)
- https://github.com/sionescu/static-vectors (`gh api`: MIT, pushed 2024-06-24, v1.9.3)

**Web:**
- https://arrow.apache.org/docs/format/CDataInterface.html
- https://arrow.apache.org/docs/format/CStreamInterface.html
- https://arrow.apache.org/docs/format/Columnar.html
- https://zenodo.org/records/7816398 (Patton, parallel mark-region GC for SBCL, ELS 2023); https://groups.google.com/g/sbcl-devel/c/fWygXnj_8sk; https://groups.google.com/g/sbcl-announce/c/zl3OgJJumTc (2.3.8); https://sbcl.org/all-news.html
- https://ccl.clozure.com/manual/chapter13.11.html (heap ivectors); https://lists.clozure.com/pipermail/openmcl-devel/2017-February/011475.html and https://lists.clozure.com/pipermail/openmcl-devel/2005-January/001755.html (`with-pointer-to-ivector` suspends the GC)
- https://github.com/kat-co/cl-apache-arrow

**Unverified:**
- SBCL x86-64 pinning mechanism details and gencgc pin granularity.
- CCL element types and alignment.
- Whether `duckdb_data_chunk_to_arrow` aliases or copies.
- Whether DuckDB's `release` is thread-safe.
- The macroexpansion-time lookup in CFFI's ABCL `with-pointer-to-vector-data`.
- numcl, magicl and lla internals.
- SBCL `bit`-vector byte order equal to Arrow's on disk.
