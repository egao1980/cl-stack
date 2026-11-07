# Image libraries survey: lessons for `image-protocol`

**Target:** [docs/capabilities/image.md](../capabilities/image.md), the draft brief (P2)
**Date:** 2026-11-07
**Method:** vendor docs, GitHub API (last-commit dates, open issues), and source greps of shallow clones of the CL libraries and `stb_image.h` v2.30. Anything marked **(unverified)** comes from memory or secondary sources and was not checked against primary docs or code.

---

## Executive summary

1. **The native backend's C dependency is unpatched upstream.** `stb_image.h` was last changed on 2024-05-31 (v2.30). The eight GitHub Security Lab reports from October 2023 (GHSL-2023-145 to -151 and -165, CVE-2023-45661 to -45667 and -45675) are still **open** in `nothings/stb`, and their fix PRs were closed without being merged. Fedora and Debian ship their own patches. So `image-backend-stb` has to vendor a pinned stb, apply the distro patches, compile out the formats it does not need, and run the OSS-Fuzz `stbi_read_fuzzer` in its own CI. stb says it is meant for trusted input. Treat it that way unless the brief adds limits on top.
2. **The pure-CL backend is not memory-safe as shipped.** `cl-jpeg` compiles its whole codec with `(safety 0)`. `pngload` unfilters in `(safety 0)`. `3bz` had out-of-bounds writes (issue #16, 2023) and an infinite loop on truncated input (fixed 2026-06). On SBCL, `(sb-ext:restrict-compiler-policy 'safety 1)` puts a floor under those declarations without patching the libraries. The brief should make that the untrusted-input build profile and fuzz both backends.
3. **Add limits as a first-class part of the protocol** (Pillow `MAX_IMAGE_PIXELS`, sharp `limitInputPixels`, Rust `image::Limits`, Skia `fMaxDecodeMemory`, Go "call DecodeConfig first"). That means a header-only `probe-image`, checks before any pixel allocation, a frame limit, an input-byte limit, and a typed `image-limit-exceeded` condition. Every surveyed library that skipped limits later added them under CVE pressure.
4. **Pick the backend by explicit priority, not load order.** Go, Skia and Java ImageIO all regret or document ordering pitfalls. "Most recently loaded wins" depends on ASDF traversal order. Use `(format, operation) → priority` plus a user preference list. Do not fall back silently after a decode error.
5. **The protocol, not the backends, should do every pixel conversion** (16→8 bit, gray luma, alpha). stb uses `>> 8` for 16→8 and `(77R+150G+29B)>>8` for gray. cl-jpeg returns **BGR** order and uses a 1–64 quality scale. Backends should return native layouts and the protocol should normalise them, or parity tests between the backends will never be exact.
6. **Metadata in wave 1: read, don't apply.** Extract the EXIF orientation (1–8) and the raw ICC bytes, return them in an `image-info`, and offer `apply-orientation`. This is the default in Pillow, Rust `image`, sharp and Skia. stb parses neither, so the protocol needs its own small EXIF-orientation parser to keep the backends in agreement.
7. **Write our own PNG decoder for the Lisp backend** over `compression-protocol` (chipz is already imported), rather than importing `png-read` (unmaintained since 2017, about 3x slower than pngload) or `pngload` (heavy dependencies: cffi, mmap, static-vectors, 3bz, zpb-exif, swap-bytes, parse-float; `safety 0`; no APNG). A decoder we own can enforce limits from IHDR, decode APNG, and stay `safety`-clean. Import `zpng` for PNG encoding (small, BSD, salza2 is already imported, but it writes filter type 0 only). Import `cl-jpeg` with care (BGR order, `safety 0`, progressive decode added in 2026). Import `skippy` for GIF (it needs a compositor, and a quantiser for encoding).

---

## 1. Comparison of the general libraries

| Library | Language / model | Registry and detection | Limits (defaults) | Untrusted-input story | Animation model | Metadata defaults |
|---|---|---|---|---|---|---|
| [Pillow](https://pillow.readthedocs.io/en/stable/reference/Image.html) | Python + C; eager pixels, **lazy `open`** | Plugins via `register_open(id, factory, accept)`; `Image.open(fp, formats=[...])` restricts which plugins are tried | `MAX_IMAGE_PIXELS = 89,478,485`; warning above it, `DecompressionBombError` above 2x | Global `ImageFile.LOAD_TRUNCATED_IMAGES` flag (a footgun: process-wide) | `seek(n)` / `n_frames`; frames are not composited for some formats | EXIF orientation not applied (`ImageOps.exif_transpose` is separate); `draft()` uses JPEG DCT scaling |
| [libvips](https://www.libvips.org/API/current/) | C; **lazy, demand-driven, threaded pipeline** | Loader classes with `is_a` sniffers and priorities **(unverified: priority field)** | Loader-specific | `vips_block_untrusted_set` / `VIPS_BLOCK_UNTRUSTED` blocks operations tagged untrusted ([doc](https://www.libvips.org/API/current/func.block_untrusted_set.html)); `fail_on` (none/truncated/error/warning) | Animated images are a tall "toilet roll" strip + `page-height`, `delay` array, `loop` | `thumbnail` auto-rotates unless `no_rotate`; shrink-on-load → block shrink → lanczos3; `linear` off by default ([doc](https://www.libvips.org/API/current/ctor.Image.thumbnail.html)) |
| [sharp](https://sharp.pixelplumbing.com/api-constructor) | Node over libvips | Inherits libvips | `limitInputPixels = 268,402,689` (0x3FFF²); `unlimited: false` | `failOn: 'warning'`, recommended for untrusted input; `sequentialRead: true` | `animated: false`, `pages: 1` by default | `autoOrient: false`; **output strips all metadata by default** and converts to sRGB ([doc](https://sharp.pixelplumbing.com/api-output)) |
| ImageMagick / GraphicsMagick | C; huge coder set + external *delegates* | Magic sniffing, **can hand files to delegates** (Ghostscript, curl, ...) | `policy.xml` resource limits (width, height, area, memory, map, disk, time) | [ImageTragick](https://imagetragick.com/) CVE-2016-3714 (shell injection via delegates/MVG/MSL); mitigation is `policy.xml` coder denylists ([security policy](https://imagemagick.org/script/security-policy.php)); GraphicsMagick is in OSS-Fuzz **(unverified count)** | Multi-image lists | Many options |
| [stb_image](https://github.com/nothings/stb) | Single C header, `malloc`s its result | Tries each loader's `test` function in order; `STBI_ONLY_*` / `STBI_NO_*` compile out formats | `STBI_MAX_DIMENSIONS = 1<<24` per side; `stbi__mul2sizes_valid` overflow checks | Header says limits exist "to prevent denial-of-service attacks on untrusted data", but **GHSL 2023 issues are still open** upstream; [OSS-Fuzz project](https://github.com/google/oss-fuzz/tree/master/projects/stb) exists | `stbi_load_gif_from_memory`: **all frames composited into one buffer**, `delays` in ms (source: `g->delay = 10 * get16le`) | None: no EXIF, no ICC, no gAMA |
| [Rust `image` 0.25](https://docs.rs/image/latest/image/) | Rust; `DynamicImage` enum (L8, LA8, RGB8, RGBA8, L16, LA16, RGB16, RGBA16, RGB32F, RGBA32F) | `ImageReader::with_guessed_format`; [`hooks::register_decoding_hook`](https://docs.rs/image/latest/image/hooks/index.html) + [`register_format_detection_hook(ext, signature, mask)`](https://docs.rs/image/latest/image/hooks/fn.register_format_detection_hook.html) | [`Limits`](https://docs.rs/image/latest/image/struct.Limits.html): `max_alloc = 512 MiB` by default, width/height unset; `reserve`/`free` accounting | Fuzzed with cargo-fuzz **(unverified scope)** | `AnimationDecoder` → `Frames` of composited RGBA + delay | [`ImageDecoder`](https://docs.rs/image/latest/image/trait.ImageDecoder.html) exposes `icc_profile`, `exif_metadata`, `orientation`, `xmp`, `iptc`; orientation not applied (`apply_orientation`) |
| [Go `image`](https://pkg.go.dev/image) | Go; `image.Image` interface (`ColorModel`, `Bounds`, `At`) + concrete `RGBA` (premultiplied), `NRGBA` (straight), `Gray`, `Gray16`, `YCbCr`, `Paletted`, `CMYK` with `Pix`/`Stride`/`Rect` | `image.RegisterFormat(name, magic, decode, decodeConfig)`, `?` wildcard in magic; registered by blank import | None built in; package doc warns of resource exhaustion and says to call `DecodeConfig` first | `x/image` TIFF/WebP CVEs over the years **(unverified list)** | `image/gif.GIF{Image, Delay (1/100 s), Disposal, LoopCount}` raw, **not composited** | None |
| Java ImageIO | Java; `BufferedImage` with many `TYPE_*` layouts | `IIORegistry` of `ImageReaderSpi` with `canDecodeInput(stream)`, suffixes, MIME types; `ServiceRegistry.setOrdering` for priority | None | `ImageIO.read` returns **null** for an unknown format (anti-pattern); disk cache via `setUseCache` | `getNumImages(allowSearch)`, metadata trees | `IIOMetadata` trees; `ImageReadParam` source region and subsampling |
| Skia [`SkCodec`](https://github.com/google/skia/blob/main/include/codec/SkCodec.h) | C++; **caller-allocated destination + `rowBytes`** | `SkCodecs::Register` (not thread-safe, so register at startup) | `Options::fMaxDecodeMemory` | Fuzzed in OSS-Fuzz / Chrome **(unverified details)**; `Result` enum separates `kIncompleteInput` (partial image produced) from `kErrorInInput` | `FrameInfo{fRequiredFrame, fDuration ms, fDisposalMethod, fBlend, fAlphaType, fFrameRect}`, `getRepetitionCount` | `getOrigin()` (EXIF), `getICCProfile()`; `getScaledDimensions` for DCT downscale; incremental decode |

---

## 2. Topic recommendations

Each item says **adopt**, **adapt** or **avoid** and names the library it comes from.

### 2.1 Pixel / buffer representation and conversions

- **Adopt: interleaved, row-major, top-left origin, straight (non-premultiplied) alpha** as the canonical layout. This is how PNG, Pillow `RGBA`, Go `NRGBA` and Rust `Rgba8` store pixels, and it matches `terminal-image`. Go's `image.RGBA` is premultiplied, and mixing the two conventions is a classic bug source. Say "straight alpha" in the brief.
- **Adopt (stb):** request each backend's native channel count (`req_comp = 0`), then convert in the protocol. stb's own conversions are approximations: 16→8 is `(v >> 8)` (source line 1200) and gray is `(77R+150G+29B)>>8` (line 1805). cl-jpeg returns **B,G,R** order ([README](https://github.com/sharplispers/cl-jpeg)). If every backend leaves conversion to the protocol, lossless formats decode bit-identically on both backends.
- **Adapt (Rust `DynamicImage`):** keep 8-bit in wave 1, but add a `depth` slot now (`8`, reserved `16`, `:float`) with `pixels` typed `(simple-array (unsigned-byte 8) (*))` for depth 8. Wave 2 can then add `(unsigned-byte 16)` or `single-float` vectors without breaking the struct. Define the 16→8 rule as rounding, `(round (* v 255) 65535)`, rather than truncation. Note that stb HDR decode tone-maps with gamma 2.2 and scale 1 when loaded as 8-bit (from the header). The brief lists HDR as decodable, so it must state this.
- **Adopt (Pillow `L` = ITU-R 601-2):** BT.601 luma as in the brief, done in the protocol with integer rounding. **(Unverified:** Rust `image` uses BT.709 coefficients for `to_luma`.) Pick one and document it.
- **Avoid (Go `SubImage`, Java `BufferedImage` type zoo):** no shared-buffer views or stride in the core struct during wave 1. Views that alias memory confuse ownership. Introduce a separate `image-view` (with `stride` and `offset`) in the manipulation phase. stb_image_write's PNG writer and Skia's `rowBytes` already accept a stride, so views can be encoded without a copy later.
- **Adopt (stb, Go):** palette (indexed) images are expanded to RGB/RGBA at decode. Do not expose `:indexed` in wave 1. The exception is encode-side GIF, where a quantiser is needed (see 2.7).

### 2.2 Format detection and registry

- **Adopt (Go `RegisterFormat`, Rust detection hooks): masked magic signatures.** `sniff-format` should use a table of `(format offset signature mask)` that backends can extend, not a hard-coded `cond`. WebP needs a mask (`RIFF????WEBP`). AVIF and HEIC need the `ftyp` box at offset 4 plus brand matching. Minimum signatures: PNG `89 50 4E 47 0D 0A 1A 0A`; JPEG `FF D8 FF`; GIF `GIF87a`/`GIF89a`; BMP `BM`; PSD `8BPS`; HDR `#?RADIANCE`/`#?RGBE`; PNM `P1`–`P7`; TIFF `II*\0`/`MM\0*`; QOI `qoif`; ICO `00 00 01 00`; JXL `FF 0A` or the box form. Sniffing needs at least 12 bytes, more for `ftyp` brands.
- **Avoid (stb's TGA `test`): guessing formats that have no magic.** TGA (and raw PNM variants) should only be decoded with an explicit `:format :tga`. ImageMagick's history shows that sniffing which reaches a powerful coder is an attack vector.
- **Adapt (Pillow `formats=`, libvips untrusted block, ImageMagick `policy.xml`):** add `*enabled-formats*` (or `:formats` on `decode-image`) to restrict decoders. The default for decoding should be PNG, JPEG, GIF and BMP. PSD, HDR, PNM, TGA and PIC are opt-in, because they are rarely needed and stb's PSD/TGA/GIF loaders are where the GHSL bugs sit.
- **Avoid: "most recently loaded wins"** (the draft brief). Load order depends on ASDF dependency traversal. **Adopt (Java `ServiceRegistry.setOrdering`)** instead: `backend-formats` returns `(format operation priority)` entries, a `*backend-preference*` list overrides them, and ties break by registration order. Registering the same backend class twice (a reload) replaces the entry instead of duplicating it. Skia warns that `SkCodecs::Register` is not thread-safe, so guard the registry with a lock or document "register at load time only".
- **Avoid (Pillow's try-each-plugin on `open`; Java `ImageIO.read` → null): no silent fallback to another backend after a decode error.** A backend that rejects a file is a security-relevant signal. Offer a restart (`try-next-backend`) for callers who want fallback, and keep `use-value` on `image-unsupported-format`.
- **Adapt (Go: `:format` given):** trust `:format`, but if the format has magic bytes and they disagree, signal `image-format-mismatch` (a warning or a continuable error). Content-Type headers and file names both lie.

### 2.3 Safety: bombs, fuzzing, untrusted defaults, timeouts

- **Adopt (Rust `Limits`, Skia `fMaxDecodeMemory`, Pillow, sharp): `image-limits` struct + `*image-limits*` special + `:limits` keyword.** Fields:
  - `max-width` and `max-height` (default 16384 each, a suggested value)
  - `max-pixels` (default 2^28 ≈ 268M, matching sharp; Pillow's 89.5M is stricter)
  - `max-frames` (default 1000, suggested)
  - `max-bytes` for total decoded allocation, frames included (default 512 MiB, matching Rust)
  - `max-input-bytes` for stream sources (suggested 256 MiB)

  Provide `(make-image-limits :unlimited t)`, like Rust `no_limits()` and sharp `unlimited`.
- **Adopt (Go `DecodeConfig`): check limits before allocating.** Run the header probe (`stbi_info_from_memory`, the IHDR of our PNG decoder, the cl-jpeg SOF via the stream API, the skippy logical screen) first, then allocate. Go's docs warn that decoding "may allocate memory proportional to the width and height in the image header" before the pixel data is checked.
- **Watch out (stb GIF): `stbi_load_gif_from_memory` allocates every composited frame up front**, `w*h*4*frames` bytes, with no frame cap. The shim includes `stb_image.h` in the same translation unit, so it can call the internal `stbi__gif_load_next` frame by frame (it is `static`, but visible inside that TU), check the frame and byte budget each step, and copy each frame out. Treat this as a design suggestion that needs a prototype.
- **Adopt (stb patching):** vendor stb at a pinned commit, apply the Fedora/Debian GHSL patches ([CVE-2023-45661 et al.](https://cvefeed.io/vuln/detail/CVE-2023-45661); upstream issues [#1538](https://github.com/nothings/stb/issues/1538)–[#1552](https://github.com/nothings/stb/issues/1552) are open, PRs #1539–#1551 closed unmerged), and set the compile flags:
  - `STBI_NO_STDIO`, since Lisp reads the files
  - `STBI_ONLY_PNG/JPEG/GIF/BMP`, plus opt-in `STBI_ONLY_*` for the rest
  - a lower `STBI_MAX_DIMENSIONS`
  - `STBI_NO_FAILURE_STRINGS` off, but read `stbi_failure_reason()` on the same thread

  Older CVEs include [CVE-2021-28021, -37789, -42715 (HDR infinite loop), CVE-2022-28041, -28042](https://lwn.net/Articles/1060349/). That makes the patch set a fork with patches, which the workspace rules allow (it is already a native overlay).
- **Adopt (OSS-Fuzz):** run `stbi_read_fuzzer.c` ([OSS-Fuzz project](https://github.com/google/oss-fuzz/tree/master/projects/stb)) against the shim under ASan/UBSan in CI. Seed it with PngSuite and the GHSL PoCs.
- **New finding (CL): the pure backend is not safe by construction.** The evidence, from source greps:
  - `cl-jpeg/jpeg.lisp:95` defines `*optimize* '(optimize (safety 0) ... (speed 3))` and uses it in 40 places.
  - `pngload/src/decode.lisp` uses `(safety 0)` in 9 places in the unfilter and copy loops.
  - `3bz/util.lisp` and `checksums.lisp` use `(safety 0)`. 3bz [#16](https://github.com/3b/3bz/issues/16) reported out-of-bounds writes in `copy-block` (2023), and [#19](https://github.com/3b/3bz/issues/19) fixed an infinite loop on truncated input (2026-06).

  **Adopt:** an "untrusted" build profile for `image-backend-lisp` on SBCL that wraps the dependency loads in `(sb-ext:restrict-compiler-policy 'safety 1)`. That sets a floor that overrides local `(safety 0)` declarations, so the unmodified imports become bounds-checked (slower, but memory-safe). The decoders we write ourselves default to `(safety 1)`. Also fuzz the Lisp backend with a simple mutational harness: PngSuite seeds, byte flips, expecting `image-error` and never any other condition.
- **Avoid (in-process timeouts on FFI):** `sb-ext:with-timeout` or `bt:interrupt-thread` cannot safely interrupt C code, and stb has had infinite loops. Do not promise timeouts. **Adopt (browser/Chrome-style isolation, ImageMagick `time` limit as a concept):** the brief should say that callers decoding hostile input under a deadline (agent tools fetching URLs) should decode in a subprocess, for example via `agent-runtime` or `process`. The Lisp backend can check a deadline between rows or frames if a `:deadline` limit is set.
- **Adopt (sharp `failOn`, libvips `fail_on`; avoid Pillow's global `LOAD_TRUNCATED_IMAGES`):** handle truncated input per call, not with a global flag. Signal `image-truncated` (a subtype of `image-decode-error`) with a restart `use-partial-image` when the backend has a partial result. Pure-CL decoders can provide one; stb cannot, because it returns NULL.

### 2.4 Metadata: orientation, ICC, gamma

- **Adopt (Pillow, Rust `ImageDecoder::orientation`, Skia `getOrigin`, sharp `autoOrient: false`):** read orientation, don't apply it by default. Return `orientation` (1–8, NIL when absent) in `image-info` and on the image. Provide `apply-orientation` (the 8 flip/transpose cases are cheap and exact). Add a `:orient t` keyword for callers that want what browsers do, which agent tools reading phone photos usually do.
- **Adopt (in the protocol):** a minimal EXIF parser for the orientation tag only (TIFF header, IFD0, tag `0x0112`). It covers JPEG APP1 `Exif\0\0`, PNG `eXIf` and WebP `EXIF`. It belongs in the protocol, not in a backend, because stb parses no metadata and the result has to agree across backends. `zpb-exif` (BSD, last commit 2021) is an import alternative, but about 80 lines of our own code avoid the dependency.
- **Adapt (Rust `icc_profile`, Skia `getICCProfile`):** when a backend can extract them, return the raw ICC bytes (PNG `iCCP` decompressed, JPEG APP2 `ICC_PROFILE` chunks reassembled, WebP `ICCP`) as `icc-profile` octets, plus `gamma` from PNG `gAMA`. **Do not colour-manage in wave 1.** Assume sRGB and say so. **Avoid (sharp output):** don't strip and convert silently on encode. In wave 1 the encoder writes no metadata, and the brief should state that explicitly. png-read's README says it does not implement `iCCP`; pngload does parse `iCCP`, `gAMA`, `sRGB`, `cHRM` and `eXIf` (source grep).
- **Note:** [PNG Third Edition](https://www.w3.org/TR/png-3/) became a W3C Recommendation on 2025-06-24. It standardises APNG and adds `cICP` (H.273 colour signalling, HDR) and `mDCV`/`cLLI`. Reserve a `color-space` slot (`:srgb` by default) so `cICP` can be surfaced later.

### 2.5 Animation (GIF / APNG / WebP)

- **Adopt (stb, Rust `AnimationDecoder`, libvips): frames are fully composited canvases** at logical-screen size, straight-alpha RGBA, each with `delay-ms`. Disposal and blending are handled inside the decoder. This is the model every consumer can use. stb already composites GIF frames (dispose 2/3 handled; source around line 6807).
- **Avoid (Go `image/gif`, skippy): raw sub-rectangles with disposal codes as the public model.** skippy returns raw images with `left-position`, `disposal-method` and `delay-time`, so the Lisp backend must implement GIF compositing to match stb. That is a parity risk, so put a dedicated fixture set (disposal 1/2/3, transparency, local palettes) in the parity tests.
- **Adapt (Skia `FrameInfo`):** keep the raw fields optionally on `image-frame`. These are `frame-rect`, `disposal` (`:none :background :previous`) and `blend` (`:source :over`, from APNG `blend_op`), plus `loop-count` on the sequence (from the GIF NETSCAPE2.0 extension; APNG `acTL num_plays`; 0 means infinite). stb does not expose the loop count **(verified by absence in its API)**, so mark it NIL-able.
- **Delays:** GIF stores centiseconds and stb multiplies by 10 (line 6916). Keep the raw value, unclamped. Browsers clamp very small GIF delays (0 or about 10 ms) up to about 100 ms **(unverified: exact thresholds per browser)**. Offer an `effective-delay-ms` helper rather than clamping in the decoder.
- **APNG:** neither stb nor pngload decodes APNG frames (stb ignores `fcTL`/`fdAT`; pngload has no `acTL` and issue [#3](https://github.com/3b/pngload/issues/3) "add new chunks from v3" is open). The brief must say that `decode-frames` on APNG returns only the default image in wave 1, or that the native backend signals `image-unsupported-feature` when `acTL` is present. Our own Lisp PNG decoder could support APNG; that is an argument for writing it.
- **Adopt (Rust `Frames` iterator, libvips page access): a streaming `map-frames` / `do-frames`** next to the list-returning `decode-frames`, so a 1000-frame GIF need not be held in memory. Both respect `max-frames` and `max-bytes`.

### 2.6 Lazy, streaming and partial decoding; FFI memory

- **Adopt (Go `DecodeConfig`, Java `getWidth(0)`, Skia `getInfo`, Pillow lazy `open`): `probe-image` returns `image-info`** with format, width, height, channels, depth, `animated-p`, frame count if cheap, orientation and `icc-p`. It allocates no pixels. Backend sources: stb `stbi_info_from_memory` and `stbi_is_16_bit_from_memory`; pngload `:decode nil`; cl-jpeg `jpeg-file-dimensions` (file) or the descriptor/stream API; skippy `:synopsis` ([PR #8](https://github.com/xach/skippy/pull/8)). Kitty only needs dimensions and pixels, but agent tools will want "how big is this?" first.
- **Defer (Skia incremental decode, JPEG DCT scaling via Pillow `draft` / Skia `getScaledDimensions` / libvips shrink-on-load):** leave these out of wave 1, but reserve a `:scale` hint in `backend-decode`. Shrink-on-load is the main performance trick libvips and sharp use for thumbnails, and stb cannot do it.
- **FFI ownership (stb mallocs its result):** the shim returns a pointer. Lisp copies it into a fresh `(simple-array (unsigned-byte 8))` and calls `stbi_image_free` inside `unwind-protect`. One `memcpy` is negligible next to the decode. Pass the input octets with `cffi:with-pointer-to-vector-data`. **Pitfall (imago [#17](https://github.com/tokenrove/imago/issues/17)):** buffers passed to C must be shareable (`cffi:make-shareable-byte-vector` or static-vectors) on implementations other than SBCL. An alternative is `STBI_MALLOC` routed to a Lisp-provided allocator, but that is more complex and not recommended.
- **Thread safety (stb):** the non-`_thread` setters (`stbi_set_flip_vertically_on_load`, `stbi_set_unpremultiply_on_load`, `stbi_convert_iphone_png_to_rgb`) and stb_image_write's globals (`stbi_write_png_compression_level`, `stbi_write_force_png_filter`, `stbi_write_tga_with_rle`, `stbi_flip_vertically_on_write`) are process-wide. The shim must never call them at decode time. It sets the write globals once at init, or patches them into parameters. **Avoid** exposing per-call `:compression-level` for stb PNG without that patch. The brief already avoids the flip and unpremultiply flags; extend that to the write globals.
- **Kitty / libghostty hook:** confirm who frees the buffer returned by `GHOSTTY_SYS_OPT_DECODE_PNG`, and with which allocator, before implementing `terminal-backend-ghostty/images` **(unverified, not researched)**.

### 2.7 Encoding options

- **Adopt (Pillow `save(**params)`, Rust per-encoder constructors, sharp per-format option objects):** one common set of keys, validated per format.
  - `:quality` 1–100 (JPEG, WebP later)
  - `:compression-level` 0–9 (PNG)
  - `:subsampling` `:444 :422 :420` (JPEG)
  - `:progressive` (JPEG)
  - `:loop-count` and per-frame delays (GIF)

  Other keys go in `:backend-options` as a plist.
- **Avoid (Pillow silently ignores unknown keywords):** signal `image-unsupported-option` for a key the chosen backend cannot honour, for example `:progressive` on stb, which writes baseline only. Make it a warning by default and an error with `*strict-options*`.
- **Adopt protocol-level defaults so the backends agree.** JPEG `:quality 90` with `:subsampling :420` matches stb, which uses 90 when quality is 0 and subsamples when quality ≤ 90. sharp defaults to 80 and Pillow to 75 **(unverified for Pillow)**. PNG `:compression-level 6`, as in sharp and zlib. Map the values per backend. **cl-jpeg's `:q-factor` is a 1–64 scale with 64 as the default (no scaling of the Annex-K tables)**, not IJG quality, so the Lisp backend needs a quality→q-factor mapping or its own quantisation-table scaling (IJG formula). Parity tests for lossy output must compare with a tolerance (PSNR or max-delta), never bytes.
- **zpng** writes 8-bit only and always uses PNG filter type 0 (`+png-filtering+ 0`), so its output is larger than other encoders'. That is acceptable for terminal use. stb_image_write PNG is also "not optimal" by its own header.
- **GIF encode in the Lisp backend needs a palette quantiser** (median-cut or octree, optional dithering). skippy writes indexed images only. The brief lists "encode GIF" without saying this. Either defer GIF encoding or add the quantiser as an explicit task.

### 2.8 Manipulation API (later `image-ops`)

- **Adopt (libvips, sharp): Lanczos3 as the default downscale kernel**, with the kernel support scaled by the reduction factor. Fixed-support kernels such as OpenCV's `INTER_LINEAR` alias when downscaling **(unverified citation)**. For large reductions, **box-reduce by an integer factor first**, then Lanczos the rest: libvips "block shrink then lanczos3", Pillow `reducing_gap` (the `thumbnail` default is 2.0). Offer `:nearest :box :bilinear :bicubic :lanczos3`; Pillow's `resize` default is `BICUBIC`.
- **Adopt (libvips `linear`, sharp):** resize and composite on premultiplied alpha (to avoid dark fringes), then unpremultiply. Make sRGB→linear processing an option (`:linear t`). libvips defaults it off for speed; for correctness see Eric Brasseur's "Gamma error in picture scaling" **(classic reference, not re-fetched)**. Rust `image::imageops::resize` works on stored (gamma-encoded) values **(unverified)**.
- **Adopt (Pillow, imago): eager, functional operations** that return fresh images. Crop, rotate in 90° steps, flip and transpose should be exact and allocation-only. imago issue [#15](https://github.com/tokenrove/imago/issues/15) shows that naive general-angle rotation used for 90° is a performance trap. **Defer (libvips): a lazy pipeline.** It is a big design commitment, and the eager style can be wrapped later.
- **Thread safety:** no global state in the operations (the lesson from stb's flags). Pure functions over immutable inputs parallelise by row bands, for example with `lparallel`.
- **Composite:** the Porter-Duff `over` operator on premultiplied values, with an offset and clipping, as in Skia `SkBlendMode` and libvips `composite`.

### 2.9 Error taxonomy

Adapted from the Skia `SkCodec::Result` split, png-read's CRC restart, sharp's `failOn` and Go's `ErrFormat`. These are CLHS conditions per skill **cl-stack-conditions**.

```text
image-error (error)
├── image-unknown-format            ; sniff failed, no :format (Go ErrFormat; never return NIL like Java ImageIO)
├── image-unsupported-format        ; format known, no backend for operation — restarts use-value (backend), try-next-backend
├── image-unsupported-feature       ; e.g. APNG frames on stb, 12-bit / arithmetic JPEG (stb), CMYK on a backend lacking it
├── image-unsupported-option        ; encode key not honourable (warning by default, see 2.7)
├── image-limit-exceeded            ; slots: limit, value, actual — no default restart (handler may re-call with :limits)
├── image-decode-error              ; slots: format, backend, cause
│   ├── image-truncated             ; Skia kIncompleteInput — restart use-partial-image when available
│   └── image-corrupt               ; Skia kErrorInInput / CRC / bad Huffman etc.
├── image-encode-error              ; slots: format, backend, cause
└── image-native-unavailable        ; foreign library failed to load
image-warning (warning)
├── image-format-mismatch           ; :format disagrees with magic
└── image-crc-mismatch              ; png-read *crc-fail-behaviour* idea — restart continue
```

- **Adopt (png-read):** turn CRC failure into a restartable condition (png-read's `ignore-crc-failure`) instead of a global variable.
- **Adopt:** wrap foreign and library conditions with `:cause`, as the brief already does. Make sure *every* non-`image-error` condition escaping a backend counts as a bug in fuzz runs. The fuzz oracle is "only `image-error` subtypes escape".

---

## 3. Common Lisp libraries

Last-commit dates come from the GitHub commits API (default branch). "safety 0" comes from a source grep.

| Library | Repo / last commit | License | Pure CL? | Formats | Speed reputation | Dependencies | Known issues / notes |
|---|---|---|---|---|---|---|---|
| **opticl** | [slyrus/opticl](https://github.com/slyrus/opticl), 2022-02-07 | BSD (`:licence "BSD"`, COPYRIGHT) | Yes | PNG, JPEG, TIFF, GIF, PNM/PBM, TGA (via its deps) | Fast pixel ops with declarations (README: 6 ms per-pixel op, zero consing, SBCL) | alexandria, retrospectiff, zpng, **pngload** (png-read on clisp/abcl/clasp), cl-jpeg, skippy, opticl-core, cl-tga | 8 open issues: JPEG read bug [#44](https://github.com/slyrus/opticl/issues/44), gray+alpha conversion [#35](https://github.com/slyrus/opticl/issues/35); 3-D arrays `(h w c)`; tested on SBCL only. **Avoid** as a dependency; useful as reference glue code. |
| **imago** | [tokenrove/imago](https://github.com/tokenrove/imago), 2026-07-28 (maintained by V. Postnicov) | LLGPL | Mixed: own PNG, PNM, TGA readers + cl-jpeg; optional FFI `imago/jpeg-turbo`, `imago/libtiff`, `imago/libheif` | PNG, PNM, TGA, JPEG, TIFF, HEIC | Moderate (pixel-object 2-D arrays) | zlib (old pure-CL), cl-jpeg, alexandria, serapeum, array-operations, flexi-streams, ... | Active; README says the jpeg-turbo path is "much more reliable" than cl-jpeg; resize/rotate/compose exist. **Reference** for `image-ops`; LLGPL and pixel-object model make it a poor import. |
| **pngload** | [3b/pngload](https://github.com/3b/pngload), 2024-08-24 (original mfiano repo deleted) | MIT | Yes (mmap/cffi/static-vectors optional on some lisps) | PNG decode (1–16 bit, interlace, most ancillary chunks incl. iCCP, eXIf) | About 3x faster than png-read (README: 0.90 s vs 3.06 s, 4096² RGBA) | 3bz (alexandria, cffi, mmap, trivial-features, nibbles, babel), cffi, mmap, parse-float, static-vectors, swap-bytes, zpb-exif | `(safety 0)` in unfilter loops; no APNG ([#3](https://github.com/3b/pngload/issues/3)); `:decode nil` header probe; `load-vector` API. Heavy for a "pure" backend. |
| **png-read** | [Ramarren/png-read](https://github.com/Ramarren/png-read), 2017-08-15 | BSD-style (`.asd`) | Yes | PNG decode (all critical chunks, interlace) | Slowest of the group | iterate, chipz, babel (all already imported) | Unmaintained; no iCCP/cHRM/sPLT; README: loads PngSuite "but I did not check whether it does so correctly"; no `safety 0` found. |
| **cl-png** | [ljosa/cl-png](https://github.com/ljosa/cl-png), 2021-11-22 | LGPL-2.1 | **No**, CFFI over libpng | PNG (+ BMP, PNM helpers) | Fast (libpng) | cffi, cffi-grovel, system libpng | Needs a system libpng; LGPL. **Avoid** (we already have stb natively). |
| **zpng** | [xach/zpng](https://github.com/xach/zpng), 2015-03-12 | BSD | Yes | PNG encode: gray, gray-alpha, truecolor, truecolor-alpha, 8-bit | Adequate | salza2 (already imported) | Filter 0 only (larger files); 8-bit only; row/pixel-streamed APIs (`streamed-png`). Stable. **Import.** |
| **cl-jpeg** | [sharplispers/cl-jpeg](https://github.com/sharplispers/cl-jpeg), 2026-02-16 | BSD | Yes | JPEG baseline decode/encode; **progressive (SOF2) decode added 2026-02** ([#43](https://github.com/sharplispers/cl-jpeg/pull/43)); CMYK/YCCK helpers | Medium **(unverified benchmarks)** | none | **BGR output**; whole codec at `(safety 0)`; open PR [#44](https://github.com/sharplispers/cl-jpeg/pull/44) "Fix progressive JPEG decoding with restart intervals and odd sizes" (2026-10); issue [#41](https://github.com/sharplispers/cl-jpeg/issues/41) (in-memory encode) is still open, although a 2023-01 commit exported `encode-image-stream` for it; q-factor 1–64. **Import (pin after #44)**, under `restrict-compiler-policy`. |
| **skippy** | [xach/skippy](https://github.com/xach/skippy), 2017-10-27 | BSD | Yes | GIF87a/89a read/write, indexed, frames, disposal, delays, transparency | Fine | none | Open decompression failures [#2](https://github.com/xach/skippy/issues/2), [#6](https://github.com/xach/skippy/issues/6); no compositing; no quantiser. **Import** for GIF; write the compositor ourselves. |
| **retrospectiff** | [slyrus/retrospectiff](https://github.com/slyrus/retrospectiff), 2021-11-21 | BSD | Yes | TIFF read/write (subset) | Unknown | com.gigamonkeys.binary-data, flexi-streams, ieee-floats, cl-jpeg, deflate, **opticl-core** | Out of scope for wave 1; drags opticl-core. Later TIFF candidate. |
| **3bz** | [3b/3bz](https://github.com/3b/3bz), 2026-06-26 | MIT | Yes (cffi/mmap optional) | DEFLATE / zlib / gzip inflate | Fastest CL inflate | alexandria, cffi, mmap, trivial-features, nibbles, babel | OOB writes [#16](https://github.com/3b/3bz/issues/16) (fixed 2023), infinite loop [#19](https://github.com/3b/3bz/issues/19) (fixed 2026-06); `(safety 0)` in util/checksums. Candidate inflate backend for `compression-protocol` later. |
| **chipz** | imported already | BSD **(per Quicklisp, unverified here)** | Yes | inflate, bzip2 | Slower than 3bz | none | Already used by `compression-backend-chipz`. |
| **zpb-exif** | [xach/zpb-exif](https://github.com/xach/zpb-exif), 2021-01-17 | BSD **(unverified)** | Yes | EXIF parsing from JPEG | n/a | none | Possible import for orientation; our own minimal parser is preferred (2.4). |
| **jpeg-turbo** | [shamazmazum/jpeg-turbo](https://github.com/shamazmazum/jpeg-turbo), 2026-07-28 | BSD-2-Clause | No (CFFI over libturbojpeg) | JPEG both ways | Very fast | cffi, cffi-grovel, serapeum | Good model for a future `image-backend-turbojpeg` native overlay (Zig build like stb). |
| **cl-libheif** | [shamazmazum/cl-libheif](https://github.com/shamazmazum/cl-libheif), 2026-07-27 | **(unverified)** | No (CFFI) | HEIC/HEIF | — | cffi | Future HEIC backend reference. |
| **cl-sdl2-image**, **cl-soil** | [lispgames/cl-sdl2-image](https://github.com/lispgames/cl-sdl2-image) 2024; [cbaggers/cl-soil](https://github.com/cbaggers/cl-soil) 2018 | MIT / ? | No | Whatever SDL_image / SOIL support | — | SDL2 / SOIL | **Avoid**: system-library dependencies and game-oriented. |
| **image-info** | [xach/image-info](https://github.com/xach/image-info), 2011 | none stated | Yes | Header dimensions | — | — | Dead; idea only (`probe-image`). |

Not found: a maintained pure-CL **WebP**, **APNG**, **QOI** or **AVIF** decoder. opticl has an open QOI request [#45](https://github.com/slyrus/opticl/issues/45). Treat this as "not found by search", not "proven absent".

### Recommendation for `image-backend-lisp`

| Format | Decode | Encode | Why |
|---|---|---|---|
| PNG / APNG | **Write our own** (about 600–900 lines: chunks, CRC, unfilter, Adam7, palette/tRNS, 1–16 bit, APNG `acTL/fcTL/fdAT`) over `compression-protocol` `:zlib` (chipz, already imported; 3bz later) | **Import `zpng`** (wave 1); add adaptive filtering ourselves later if size matters | We control limits (IHDR checked before allocation, inflate output capped at the expected size, so we need a `:max-output` on `compression-protocol` decompress or our own guard), `(safety 1)`, APNG, iCCP/eXIf extraction, and no cffi/mmap/static-vectors in the "pure" backend. png-read is unmaintained and slow. pngload is fast but heavy, `safety 0`, and lacks APNG. Fallback if time-boxed: import **png-read** (deps already present). |
| JPEG | **Import `cl-jpeg`** (pin at or after the merge of #44), under `restrict-compiler-policy` | `cl-jpeg` with a quality→q-factor mapping | It is the only pure-CL JPEG codec, now with progressive decode. Swap BGR→RGB in the backend. |
| GIF | **Import `skippy`** + our own compositor | `skippy` + our own quantiser (or defer GIF encode) | Parity with stb's composited frames. |
| BMP | **Write our own** (uncompressed 24/32-bit + BI_BITFIELDS; RLE optional) | Write our own | Trivial, and it gives the Lisp backend a lossless second format to cross-check stb on. |

The new imports for `cl-stack-systems` are only `zpng`, `cl-jpeg` and `skippy`. salza2, chipz, iterate and babel are already present.

---

## 4. Concrete changes to the draft brief

1. **Prior-art table:** add sharp/libvips (limits, `failOn`, untrusted block, shrink-on-load), Go `image` (masked magic registry, `DecodeConfig`), Java ImageIO (SPI priority ordering), and Skia `SkCodec` (`Result` split, `FrameInfo`, caller buffers). Also record the stb security status: GHSL-2023 issues open upstream, we patch.
2. **Pixels decision:** say *straight alpha*. Add a `depth` slot (`8` in wave 1; `16`/`:float` reserved). Add `orientation`, `icc-profile`, `gamma` and `color-space` (`:srgb`) slots, or a `metadata` plist. Define 16→8 as rounded, done by the protocol, and gray as BT.601 with integer rounding. State that HDR decode tone-maps with gamma 2.2 (stb behaviour) or drop HDR from wave 1.
3. **Dispatch decision:** replace "most recently loaded wins" with per-entry **priority** + `*backend-preference*`. Make re-registration idempotent. No silent fallback after a decode error; add a `try-next-backend` restart.
4. **Format detection:** an extensible masked-signature table. Formats without magic (TGA) need an explicit `:format`. Add `*enabled-formats*` / `:formats`; the default decode set is PNG, JPEG, GIF and BMP, and PSD/HDR/PNM/TGA are opt-in. A `:format` that disagrees with the magic bytes gives `image-format-mismatch`.
5. **New "Limits" locked decision:** `image-limits` (max-width, max-height, max-pixels, max-frames, max-bytes, max-input-bytes), `*image-limits*`, `:limits`, conservative defaults, checked after the header probe and before allocation. Add `image-limit-exceeded`.
6. **New surface:** `probe-image` → `image-info` (no pixel allocation). `map-frames` streaming. `apply-orientation`, plus `:orient` on `decode-image` (default NIL). Add `loop-count`, and optionally `disposal`/`blend`/`frame-rect`, to frames. Say that frames are composited canvases.
7. **Encoding surface:** `encode-image image format &key quality compression-level subsampling progressive backend-options`, with protocol-level defaults (JPEG 90 / 4:2:0, PNG level 6) mapped per backend, and `image-unsupported-option`. State that no metadata is written in wave 1.
8. **Conditions:** replace the tree with the one in 2.9. Add `image-unsupported-feature`, `image-limit-exceeded`, `image-truncated` (restart `use-partial-image`), `image-corrupt`, `image-encode-error`, `image-unsupported-option`, `image-format-mismatch` (warning) and `image-crc-mismatch` (warning, restart `continue`).
9. **`image-backend-stb` row:** vendored pinned stb plus distro GHSL patches. `STBI_NO_STDIO`, `STBI_ONLY_*`, a lower `STBI_MAX_DIMENSIONS`. Never call the global setters at decode time; set the write globals once at init. Copy and free in `unwind-protect`. Frame-wise GIF through `stbi__gif_load_next` with a frame budget. ASan/UBSan fuzz job with `stbi_read_fuzzer`. APNG returns the default image only, or `image-unsupported-feature`.
10. **`image-backend-lisp` row:** our own PNG (+ APNG) and BMP codecs, imported `zpng`, `cl-jpeg` (BGR→RGB, quality→q-factor) and `skippy` (+ our compositor; GIF encode needs a quantiser or is deferred). Replace `png-read` with "own decoder over `compression-protocol`". Add an "untrusted" load profile using `sb-ext:restrict-compiler-policy 'safety 1` around the imports.
11. **Non-goals:** keep colour *management* out. Move "EXIF orientation / ICC" from non-goals to "read and expose, don't apply". Add "in-process timeouts: not offered; isolate hostile decodes in a subprocess".
12. **Implementation tasks:** add these tasks:
    - fuzz harnesses for both backends (oracle: only `image-error` escapes)
    - parity fixtures: PngSuite; GIF disposal/transparency; EXIF orientation 1–8 JPEGs; truncated files; bomb files such as a 50000×50000 PNG header and a zlib bomb
    - tolerance-based JPEG parity (PSNR)
    - an `compression-protocol` `:max-output` (or bounded inflate) prerequisite
    - checking libghostty's buffer ownership for `GHOSTTY_SYS_OPT_DECODE_PNG`
13. **Later `image-ops` note:** record the chosen defaults (Lanczos3, integer box pre-reduce, premultiplied processing, optional linear light, eager functional operations, no global state) so wave 1's struct does not block them.

---

## Sources

- stb: [repo](https://github.com/nothings/stb), [`stb_image.h` v2.30](https://raw.githubusercontent.com/nothings/stb/master/stb_image.h), [`stb_image_write.h` v1.16](https://raw.githubusercontent.com/nothings/stb/master/stb_image_write.h), [issues #1538–#1552 (GHSL-2023)](https://github.com/nothings/stb/issues/1538), [CVE-2023-45661](https://cvefeed.io/vuln/detail/CVE-2023-45661), [Fedora stb update](https://lists.fedoraproject.org/archives/list/package-announce@lists.fedoraproject.org/message/QVABVF4GEM6BYD5L4L64RCRSXUHY6LGN), [Debian DLA-4493-1 / LWN](https://lwn.net/Articles/1060349/), [Debian DLA-3305](https://www.debian.org/lts/security/2023/dla-3305), [OSS-Fuzz stb](https://github.com/google/oss-fuzz/tree/master/projects/stb)
- Pillow: [Image reference](https://pillow.readthedocs.io/en/stable/reference/Image.html)
- sharp: [constructor](https://sharp.pixelplumbing.com/api-constructor), [output](https://sharp.pixelplumbing.com/api-output)
- libvips: [block_untrusted_set](https://www.libvips.org/API/current/func.block_untrusted_set.html), [thumbnail](https://www.libvips.org/API/current/ctor.Image.thumbnail.html)
- ImageMagick: [ImageTragick](https://imagetragick.com/), [security policy](https://imagemagick.org/script/security-policy.php), [CVE-2016-3714 summary](https://cve.armis.com/cve-2016-3714), [USN-2990-1](https://osv.dev/vulnerability/USN-2990-1)
- Rust image: [Limits](https://docs.rs/image/latest/image/struct.Limits.html), [ImageDecoder](https://docs.rs/image/latest/image/trait.ImageDecoder.html), [hooks](https://docs.rs/image/latest/image/hooks/index.html), [register_format_detection_hook](https://docs.rs/image/latest/image/hooks/fn.register_format_detection_hook.html)
- Go: [image](https://pkg.go.dev/image)
- Skia: [SkCodec.h](https://github.com/google/skia/blob/main/include/codec/SkCodec.h)
- Java ImageIO: [javax.imageio](https://docs.oracle.com/en/java/javase/21/docs/api/java.desktop/javax/imageio/package-summary.html) **(described from knowledge; page not re-fetched)**
- PNG 3rd edition: [W3C TR](https://www.w3.org/TR/png-3/), [W3C news](https://www.w3.org/news/2025/portable-network-graphics-png-specification-third-edition-is-now-a-w3c-recommendation)
- CL: [opticl](https://github.com/slyrus/opticl), [imago](https://github.com/tokenrove/imago), [pngload](https://github.com/3b/pngload), [pngload mirror note](https://github.com/lisp-mirror/pngload), [png-read](https://github.com/Ramarren/png-read), [cl-png](https://github.com/ljosa/cl-png), [zpng](https://github.com/xach/zpng), [cl-jpeg](https://github.com/sharplispers/cl-jpeg), [skippy](https://github.com/xach/skippy), [retrospectiff](https://github.com/slyrus/retrospectiff), [3bz](https://github.com/3b/3bz), [zpb-exif](https://github.com/xach/zpb-exif), [jpeg-turbo](https://github.com/shamazmazum/jpeg-turbo), [cl-libheif](https://github.com/shamazmazum/cl-libheif), [cl-sdl2-image](https://github.com/lispgames/cl-sdl2-image), [cl-soil](https://github.com/cbaggers/cl-soil), [image-info](https://github.com/xach/image-info)
- SBCL: [`restrict-compiler-policy`](https://www.sbcl.org/manual/#Compiler-Policy) **(semantics from knowledge: sets a minimum for a quality that overrides local declarations; verify on the pinned SBCL)**
