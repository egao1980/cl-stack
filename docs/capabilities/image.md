# image-protocol (P2) — image decoding and encoding

**Issues:** [#275](https://github.com/egao1980/cl-stack/issues/275) · terminal [#264](https://github.com/egao1980/cl-stack/issues/264)
**Status:** brief **locked** — no code yet · research: [image-libraries.md](../research/image-libraries.md)

Decode PNG, JPEG, GIF, BMP and friends into pixels, and encode pixels back, behind one CLOS API over several backends at once. Each backend declares the formats it handles and with what priority. Inputs are untrusted by default: limits are checked before pixels are allocated, unusual formats must be enabled explicitly, and both backends are fuzzed.

First consumers:
- **Kitty graphics:** libghostty-vt asks its embedder for a PNG decoder (`GHOSTTY_SYS_OPT_DECODE_PNG`), and `terminal-backend-lisp` needs the same decoder for `f=100`.
- Agent tools reading screenshots and attachments
- `doc-extract-*`

---

## Prior art (intersection, not a clone)

Details and sources are in the [research notes](../research/image-libraries.md).

| Source | Took | Left |
|--------|------|------|
| stb_image / stb_image_write | One C codec set (PNG, JPEG, GIF with composited frames, BMP, TGA, PSD, HDR, PNM), cross-built like our other natives | Its process-wide flags. Its unpatched upstream: GHSL-2023 CVE-2023-45661…-45675 are still open, so **we vendor it with patches** |
| Pillow | `formats=` restriction; read-don't-apply orientation; save options validated per format | Global `LOAD_TRUNCATED_IMAGES`; silently ignored options |
| libvips / sharp | Pixel / byte limits; `failOn`-style truncation policy; an "untrusted" set of loaders | Lazy pipelines (wave 1 is eager) |
| Rust `image` | `Limits`; `DynamicImage` → `to_rgba8`; streaming frames | Generic pixel traits |
| Go `image` | Registry of masked magic signatures; `DecodeConfig` (probe before allocating) | Premultiplied `image.RGBA` as the default |
| Java ImageIO | Provider **priority ordering** | `read` returning NULL on failure |
| Skia `SkCodec` | The `Result` split (incomplete vs corrupt input); `FrameInfo` (rect, disposal, blend) | Incremental decoding (wave 1) |
| CL: zpng, cl-jpeg, skippy | Imported unmodified (`cl-stack-systems`) | opticl (heavy), imago (LLGPL), pngload (cffi/mmap/static-vectors, `safety 0`, no APNG), png-read (unmaintained) |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | CLOS protocol + several backends active at once | No one library does every format well |
| **Pixels** | `image`: `width` `height` `format` (`:gray :gray-alpha :rgb :rgba`) `depth` (`8` in wave 1; `16` / `:float` reserved) `pixels`. Pixels are a simple octet vector: interleaved, row-major, top-left first, no stride, **straight (non-premultiplied) alpha**. | The PNG / Pillow / Go `NRGBA` layout. It matches `terminal-protocol:terminal-image`, and the slot is ready for wider depths. |
| **Conversion in the protocol** | Backends return their native layout. The protocol does every conversion: 16→8 as `(round (* v 255) 65535)`, gray as BT.601 with integer rounding, palette expanded at decode, cl-jpeg's BGR→RGB. | Lossless formats decode **bit-identically** on both backends (stb's own `>>8` / approximate luma are not used) |
| **Metadata** | Read and expose, **don't apply**: `orientation` 1–8 (our own small EXIF reader: JPEG APP1, PNG `eXIf`), raw `icc-profile` octets, PNG `gamma`, `color-space` (`:srgb`). `apply-orientation`, plus `:orient t` on decode. No colour management. Encoders write no metadata in wave 1. | What Pillow / Rust / Skia / sharp do by default; stb parses no metadata |
| **Limits** | `image-limits`: `max-width` / `max-height` 16384, `max-pixels` 2²⁸, `max-frames` 1000, `max-bytes` 512 MiB (all frames), `max-input-bytes` 256 MiB. Set through `*image-limits*`, or per call with `:limits`; `(make-image-limits :unlimited t)` turns them off. Checked **after a header probe, before allocating**. | Decompression bombs; Rust / Skia / sharp / Pillow all have limits |
| **Enabled formats** | `*enabled-formats*` / `:formats`. The default decode set is `:png :jpeg :gif :bmp`. `:psd :hdr :pnm :tga` are opt-in. TGA (no magic) needs an explicit `:format`. | stb's GHSL bugs sit in its PSD / TGA / GIF / HDR loaders; ImageMagick's history |
| **Detection** | `sniff-format` uses a masked-signature table that backends can extend: PNG, JPEG, GIF, BMP, PSD, HDR, PNM, TIFF, QOI, ICO, WebP (`RIFF????WEBP`), AVIF / HEIC (`ftyp` brands), JXL. A `:format` that disagrees with the magic bytes signals the warning `image-format-mismatch`. | Content-Type headers and file names lie |
| **Dispatch** | `backend-formats` → `(format operation priority)` entries. `*backend-preference*` overrides priority; ties go to registration order. Re-registering a backend replaces its entry. **No silent fallback after a decode error**: `try-next-backend` and `use-value` are restarts. | Deterministic, and independent of ASDF load order |
| **Animation** | Frames are **composited canvases** at logical-screen size, each with `delay-ms` (raw, unclamped), `frame-rect`, `disposal` and `blend`. The sequence has a `loop-count` (NIL if unknown). `decode-frames` returns a list; `map-frames` streams. Both respect `max-frames` / `max-bytes`. | What stb, Rust and libvips give consumers |
| **Encoding** | `encode-image image format &key quality compression-level subsampling progressive backend-options`. The protocol sets the defaults (JPEG 90, 4:2:0; PNG level 6) and maps them per backend. A key the backend can't honour gives `image-unsupported-option` (a warning; an error under `*strict-options*`). | Backends agree on defaults; nothing is silently ignored |
| **Truncation** | Per call: `image-truncated` with the restart `use-partial-image` when the backend has a partial result | sharp `failOn`, not Pillow's global flag |
| **Timeouts** | None in-process: C decoders can't be interrupted safely. Callers decoding hostile input under a deadline do it in a subprocess (`process-protocol` / `agent-runtime`). | stb has had infinite loops |

---

## Repo layout

| Repo / system | Role |
|---------------|------|
| [`image-protocol`](https://github.com/egao1980/image-protocol) (`stack-image`) | Types, generics, limits, sniffing, conversion, EXIF orientation, dispatch, conditions |
| [`image-backend-stb`](https://github.com/egao1980/image-backend-stb) | Native. **Vendored, pinned stb with the Fedora / Debian GHSL patches.** A small C ABI built with `STBI_NO_STDIO`, `STBI_ONLY_PNG/JPEG/GIF/BMP` (the rest opt-in at runtime through `*enabled-formats*`) and a lower `STBI_MAX_DIMENSIONS`. Never calls stb's process-wide setters at decode time; the write globals are set once at init. Probes with `stbi_info_from_memory`. GIF is decoded frame by frame through `stbi__gif_load_next` with a frame and byte budget (to be prototyped). The result is copied into Lisp and freed in `unwind-protect`. APNG gives the default image plus `image-unsupported-feature` for frames. CI runs the OSS-Fuzz `stbi_read_fuzzer` under ASan / UBSan. Zig overlays: linux amd64/arm64, darwin arm64, windows amd64. |
| [`image-backend-lisp`](https://github.com/egao1980/image-backend-lisp) | Pure CL: **our own PNG + APNG and BMP codecs** over `compression-protocol` (needs a bounded inflate), imported `zpng` (PNG encode), `cl-jpeg` (JPEG, pinned after its PR #44; BGR→RGB; quality → q-factor), and `skippy` (GIF plus our own compositor). GIF *encode* waits for a quantiser. On SBCL the imports load under `(sb-ext:restrict-compiler-policy 'safety 1)`, because cl-jpeg compiles its codec at `safety 0`. |
| `terminal-backend-ghostty/images` | Registers `stack-image` as libghostty-vt's PNG decoder. The pixel buffer is allocated with `ghostty_alloc` and the allocator libghostty-vt passes in; libghostty-vt then owns and frees it (`sys.h`). |
| `terminal-backend-lisp` | Kitty `f=100` through `stack-image` when `image-protocol` is loaded |

---

## Protocol surface

```lisp
(defstruct image width height format depth pixels
           orientation icc-profile gamma (color-space :srgb))
(defstruct (image-frame (:include image)) delay-ms frame-rect disposal blend)
(defstruct image-sequence frames loop-count)
(defstruct image-info format width height pixel-format depth animated-p frame-count
           orientation icc-p)
(defstruct image-limits max-width max-height max-pixels max-frames max-bytes max-input-bytes)

(defvar *image-limits*) (defvar *enabled-formats*) (defvar *backend-preference*)
(defvar *strict-options* nil)

(defclass image-backend () ())
(defgeneric backend-formats (backend))                    ; → ((:png :decode 50) (:png :encode 50) …)
(defgeneric backend-probe (backend format octets))        ; → image-info, no pixels
(defgeneric backend-decode (backend format octets &key limits frames scale))
(defgeneric backend-encode (backend image format &key quality compression-level
                                     subsampling progressive backend-options))
(defun register-image-backend (backend))

(defun sniff-format (octets))
(defun probe-image (source &key format formats))
(defun decode-image (source &key format formats limits orient backend))   ; → image (first frame)
(defun decode-frames (source &key format formats limits backend))         ; → image-sequence
(defun map-frames (function source &key format formats limits backend))
(defun encode-image (image format &rest options &key backend &allow-other-keys)) ; → octets
(defun convert-image (image format))
(defun apply-orientation (image))
(defun supported-formats (&key (operation :decode)))
```

`source` is an octet vector, a pathname, or a binary input stream (read up to `max-input-bytes`).

### Conditions

```text
image-error (error)
├── image-unknown-format            ; sniffing failed and no :format given
├── image-unsupported-format        ; no backend for format+operation — restarts use-value (backend), try-next-backend
├── image-unsupported-feature       ; e.g. APNG frames on stb, arithmetic JPEG
├── image-unsupported-option        ; (also signalled as a warning; see Encoding)
├── image-limit-exceeded            ; slots: limit, allowed, actual
├── image-decode-error              ; slots: format, backend, cause
│   ├── image-truncated             ; restart use-partial-image when available
│   └── image-corrupt
├── image-encode-error
└── image-native-unavailable
image-warning (warning)
├── image-format-mismatch
└── image-crc-mismatch              ; restart continue
```

In fuzzing, any condition other than an `image-error` escaping a backend is a bug.

---

## Non-goals (wave 1)

- Editing (`image-ops` later). Its defaults are recorded now so the wave-1 struct doesn't block them: Lanczos3 with an integer box pre-reduce; premultiplied alpha during resize and composite; optional linear light; eager, functional operations; no global state; Porter-Duff `over`.
- Colour management; writing metadata
- WebP / AVIF / HEIC / TIFF / QOI decoding. They are sniffed, then reported as unsupported. Later native backends: libwebp, libavif, turbojpeg.
- In-process timeouts

---

## Implementation tasks

- [x] Brief lock — this doc
- [ ] `compression-protocol`: bounded inflate (`:max-output`)
- [ ] `image-protocol` + Rove: mock backend, sniffing, limits, conversions, EXIF orientation, dispatch / restarts
- [ ] `image-backend-stb`: vendored and patched stb, C ABI, Zig overlays, Rove, ASan/UBSan fuzz job
- [ ] `cl-stack-systems` imports: `zpng`, `cl-jpeg`, `skippy`
- [ ] `image-backend-lisp`: own PNG/APNG and BMP, cl-jpeg / skippy / zpng glue, safety-1 profile, Rove, mutational fuzz
- [ ] Parity fixtures for both backends: PngSuite, GIF disposal / transparency, EXIF orientation 1–8, truncated files, bombs (50000² PNG header, zlib bomb). JPEG compared by PSNR, never by bytes.
- [ ] `terminal-backend-ghostty/images` + parity `kitty-png` fixtures; `terminal-backend-lisp` Kitty `f=100`
- [ ] Cookbook `cookbooks/image.md`
