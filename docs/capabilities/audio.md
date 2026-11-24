# audio-protocol (P2): PCM, WAV, mixing, MIDI rendering, decoding, DSP, voice processing

**Issues:** follow-ups in [Progress](#progress)
**Status:** AU0 [`audio-protocol`](https://github.com/egao1980/audio-protocol) 0.1.0 **contract**: [audio-protocol#1](https://github.com/egao1980/audio-protocol/pull/1) (draft). AU1 (FluidSynth): feasibility checked, [below](#au1-feasibility-libfluidsynth-over-cffi); no repo yet. AU2 and AU3: planned. AU4 and AU5: optional.
**Repos:** `audio-protocol` (nick `stack-audio`) · `audio-backend-fluidsynth` (AU1) · `audio-backend-ffmpeg` (AU2) · `audio-backend-world` and `audio-backend-signalsmith` (optional)
**Builds on:** [binary-protocol](binary-protocol.md) 0.1.1, `midi-protocol` 0.1.0 ([score.md](score.md), SC3), [process](process.md) and [compute-protocol](confinement.md) (ffmpeg out of process), `asdf-native` (the native overlays, as in [image.md](image.md))

**Batch** audio for the music stack:
- PCM buffers, WAV files, mixing and loops;
- rendering Standard MIDI Files to a mixdown or to stems, one per track or channel, through an engine: a reference tone synth in the protocol, a SoundFont synthesiser in a backend;
- decoding compressed uploads;
- a small DSP module for a transcription front end ([omr.md](omr.md), transcribe-protocol);
- later, optionally, voice analysis and resynthesis and pitch and time stretching.

Everything is a batch job: whole buffers in, fresh buffers out. There is no real-time audio I/O, no device access and no streaming.

The first consumer is the rehearsal set of [score.md](score.md) (SC4). score-backend-midi already writes one SMF per voice, with that voice brought forward. With AU0 and AU1 the same set becomes audio: render the score's stems once, then `mix` one practice file per voice with gains and pans, and `loop-region` a passage.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| RIFF/WAVE (Microsoft/IBM 1991), WAVEFORMATEX and WAVE_FORMAT_EXTENSIBLE | Chunk walk with odd-size padding; PCM 16/24-bit and IEEE float32; the `fact` chunk for non-PCM data; extensible fmt chunks with standard sub-format GUIDs | 8-bit and 32-bit PCM, float64, A-law, μ-law, ADPCM, RF64/BW64 (> 4 GiB) |
| Python `wave` (stdlib) and soundfile 0.12.1 over libsndfile 1.2.0 | **Test oracles**, out of process (`uv run --with soundfile==0.12.1`): fixtures, and a live cross-read of what we write | libsndfile itself (LGPL native; we read WAV in Lisp) |
| libsndfile and SoX conventions | Codes scale by 2^(bits−1) on read | libsndfile's 32767 scale on write (we use 32768 both ways, so files round-trip) |
| DAW mixers (constant-power pan, mute and solo) | The −3 dB sine pan law for mono sources, balance for stereo sources, mute winning over solo | Automation, buses, sends, plugins |
| libsamplerate, the Julius O. Smith bandlimited-interpolation notes | A windowed-sinc kernel at exact positions, tabulated per phase | Variable ratios, SIMD |
| FluidSynth 2.6 (LGPL-2.1) | AU1: SF2 synthesis, the sample-timer MIDI player, audio groups for per-channel stems | Its drivers, shell, network server and LADSPA |
| Autotalent, Zita-AT1, x42-autotune, MXTune (GPL) | Study only: they are real-time LV2/JACK tools | Code (license policy) |

No permissive, maintained CL library covers WAV with extensible formats, mixing and a MIDI render protocol (survey 2026-11). CL MIDI libraries are prior art in [score.md](score.md).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Buffer** | `pcm-buffer`: sample rate (an integer), channel count, frame count and an **interleaved `(simple-array single-float (*))`**, nominally −1…1. Read-only slots. No function modifies a buffer it is given. Buffers compare with `equalp`. | A 16-bit or 24-bit code c gives c / 2^(bits−1), and float32 is itself, so every supported encoding is exact in a single-float. A file read and written back in its own encoding is lossless, while gains, pans, sums and resampling get floating point without an intermediate integer clip. Interleaved is how WAV stores it and how a synth writes it. Doubles would double the memory for no gain at these word lengths. |
| **Finite samples** | Buffers hold finite samples. `read-wav` signals on a NaN or infinite float32 sample (restart `use-value`), and `write-wav` refuses one (`audio-encode-error`). | A NaN in audio is always a bug upstream. SBCL traps comparisons with it. |
| **Time** | Seconds are exact rationals where they can be. `(seconds-to-frame s rate)` = floor(s·rate + ½), rounded once. MIDI times come from midi-protocol's exact `ticks-to-seconds`. | Onsets don't drift, and the same tick lands on the same frame in every stem |
| **WAV in Lisp** | `read-wav` reads chunks up to `data` and **nothing after it**. LIST/INFO, `fact`, `PEAK`, `JUNK`, `bext`, `cue` and the rest are skipped, odd sizes padded. Six fmt checks run in order, WAVE_FORMAT_EXTENSIBLE (standard GUIDs) included. The RIFF size is not checked. Errors carry byte offsets, and every proper prefix of a file fails at its own length or at its data chunk. Restarts: `use-partial-data` for a truncated data chunk, `use-value` for a non-finite sample. `write-wav` writes plain tags only: the 44-byte PCM header that Python's `wave` and libsndfile write, or an 18-byte fmt chunk plus `fact` for float32. | Lenient with streaming writers; byte for byte with the two most common writers; the decoders of AU2 emit extensible files for more than 2 channels |
| **Byte I/O** | Through binary-protocol **0.1.1** (fixed-width fields, 16-bit codes and float32; 0.1.1 decodes IEEE specials without trapping). 24-bit codes are its gap #3, and `unpack-from`'s per-call scan is #4. | The stack's one byte layer. Its gaps are fixed there, not copied here. |
| **Encoding** | PCM code = round(x·2^(bits−1)), halves to even, clamped. 1.0 writes the top code and is not "clipped". One `samples-clipped` warning (count, peak) per write when \|x\| > 1. | Read-then-write keeps every code. Warnings are for real overs only. |
| **Pan law** | `pan-gains pan channels`. **Mono source**: the sine law, left = sin((1−p)·π/4), right = sin((1+p)·π/4). That is constant power, −3.01 dB per side at the centre, and exactly (1, 0) and (0, 1) at the ends. **Stereo source**: balance, left = min(1, 1−p), right = min(1, 1+p), unity at the centre. | The convention of most mixers. A centred mono stem sits at the level a stereo stem has at its balance centre. |
| **Mix** | `mix inputs &key gains pans mute solo master clip channels`. Inputs are buffers or stems. Gains are in dB (`db-to-gain` = 10^(dB/20)). The sum is a double-float in a stated order, rounded once. The longest input sets the length, muted inputs included. Heard = not muted and (no solo, or soloed), so mute wins. Clip policies are `:clip` (clamp, one warning), `:scale` (peak to 1) and `:none`. A sample rate or layout mismatch is `audio-mismatch-error`, with restarts `skip-input` and `use-value`. | A rehearsal mix is one `mix` call over stems. The mute and solo rule is a one-line, obviously total predicate, which [logic.md](logic.md) leaves to plain code. |
| **Loops** | `loop-region buffer start end &key count fade gap` plays frames start…end−1 *count* times, with *gap* frames of silence between plays and a linear fade over *fade* frames in and out of each play | Practice loops; exact copies when fade is 0 |
| **Resampling (in AU0)** | `resample buffer rate`: a Blackman-windowed sinc with 16 zero crossings a side, cutoff 0.95 of the lower Nyquist, evaluated at exact rational positions (output frame j at input j·r⁻¹). A polyphase table is allowed within 1e-5 of the formula. The promise: flat to 0.1 dB well inside the passband, and more than 60 dB down past the transition band (44.1 → 16 kHz: 6.3 to 8.9 kHz). | The transcription front end needs 16 kHz input. One documented quality is enough; a mastering-grade converter is not the point. |
| **Engines** | `audio-engine` class. Generic functions `render-midi engine smf &key sample-rate soundfont channels tail` → a buffer, and `render-stems … by` → stems (`:track` or `:channel`). The protocol's `:around` methods do the work every backend would repeat: SMF designators go through `read-smf`, arguments are type-checked, there is a render limit (`*max-render-seconds*`, `audio-limit-exceeded` with `continue`), and results are checked. **Every render of one SMF at one rate and tail has `render-frames` frames.** | Backends write primary methods only, and stems always line up for `mix` |
| **Stems** | The default `render-stems` renders each stem from a **filtered SMF**: every non-channel event kept (tempo, meta, sysex), plus the channel events of one track or one channel, with absolute times kept. Names come from the track's first track-name event, else "Track i"; channel stems are named "Channel c+1". A backend may override this with a one-pass render (FluidSynth audio groups) as long as the stems are the same. | Stems equal what you'd hear with the others muted; score-backend-midi writes one track and one channel per voice |
| **Reference engine** | `reference-engine` (`:sine` / `:square`, an amplitude): one tone per note at the equal-tempered frequency, velocity-scaled. No envelope. Notes of one channel and key end first in, first out. Every other event is ignored. | The protocol and its consumers can be tested without a SoundFont. The tests check a C major scale by onsets, zero crossings, Goertzel and exact values. |
| **SoundFont synthesis (AU1)** | libfluidsynth **2.6.x** over CFFI (asdf-native overlay), with `osal=cpp11`, no GLib, every driver off, built with `zig cc` for the four overlay targets. LGPL-2.1 native, so it ships as an overlay plus `NOTICE`, dynamically linked; the Lisp stays MIT. | Feasibility below: all four targets built, and SBCL ran it with traps on |
| **SoundFont** | **FluidR3_GM** (MIT; Frank Wen, Toby Smithe), 148,398,306 bytes. **Never vendored**: fetched on first use from a pinned URL, checked against its SHA-256, and cached. AU1's own tests use a tiny SF2 that the test suite **writes itself**, so CI downloads nothing. GeneralUser GS (custom permissive license, sample provenance uncertain by the author's own account) is a user-supplied option, not a default. | MIT is on the [allowlist](../LICENSE-POLICY.md); a custom license is not |
| **Decoding (AU2)** | `decode-audio source &key format` / `encode-audio buffer format`. WAV stays in Lisp. MP3/M4A/AAC/Opus/WebM go through **ffmpeg out of process**: in a container (compute-backend-podman, R4g-2) where available, else a host ffmpeg confined by compute-protocol (Seatbelt / Landlock, network off, the work directory only). Batch only, with size and duration limits. | Hostile uploads never meet an in-process decoder; ffmpeg's licence never touches the image |
| **DSP (AU3)** | A `stack-audio/dsp` module: radix-2 complex and real FFT, Hann/Hamming/Blackman windows, frames and hops, RMS, peak, `normalize`, and an STFT. It is what transcribe-protocol's pYIN backend needs. If a permissive, SBCL-clean CL FFT library exists, it is imported instead (to check in AU3). | The transcription front end; FFT is not in AU0 |
| **Licenses** | GPL tools (Autotalent, Zita-AT1, x42-autotune, MXTune) are study only | License policy |

---

## Repo layout

| Repo / system | Role |
|---------------|------|
| `audio-protocol` | The model, WAV, `pan-gains`, `mix`, `loop-region`, `resample`, the engine protocol and `reference-engine` (AU0); `stack-audio/dsp` (AU3); `decode-audio` / `encode-audio` generic functions (AU2) |
| `audio-backend-fluidsynth` | AU1: `fluidsynth-engine` (`render-midi`, a one-pass `render-stems`), the libfluidsynth overlay for linux-amd64, linux-arm64, darwin-arm64 and windows-amd64, the SoundFont fetcher |
| `audio-backend-ffmpeg` | AU2: an `audio-codec` running ffmpeg out of process through compute-protocol |
| `audio-backend-world`, `audio-backend-signalsmith` | Optional (AU4, AU5): voice analysis and resynthesis (WORLD, modified BSD), and pitch and time stretching (Signalsmith Stretch, MIT, behind a small C shim) |

---

## Protocol surface (AU0)

```lisp
;; model (given in the contract)
(defstruct pcm-buffer sample-rate channels frames samples)  ; samples: interleaved single-floats
(defun make-pcm-buffer (&key sample-rate channels frames samples))
(defun pcm-buffer-duration (buffer))          (defun sample-ref (buffer frame channel))
(defun pcm-channel (buffer channel))           (defun pcm-from-channels (channels &key sample-rate))
(defun seconds-to-frame (seconds rate))        (defun db-to-gain (db))  (defun note-frequency (key))
(defstruct stem name buffer track channel)

;; WAV
(defun read-wav (source))                     ; → buffer, encoding (:pcm16 :pcm24 :float32)
(defun write-wav (buffer destination &key (encoding :pcm16) (if-exists :supersede)))

;; mixing
(defun pan-gains (pan input-channels))        ; → left, right
(defun mix (inputs &key gains pans mute solo (master 0) (clip :clip) (channels 2)))
(defun loop-region (buffer start end &key (count 2) (fade 0) (gap 0)))
(defun resample (buffer sample-rate))

;; engines
(defclass audio-engine () ())
(defgeneric render-midi (engine smf &key sample-rate soundfont channels tail))   ; → buffer
(defgeneric render-stems (engine smf &key sample-rate soundfont channels tail by)) ; → stems
(defun smf-duration (smf))  (defun render-frames (smf sample-rate &optional tail))
(defvar *max-render-seconds* 3600)
(defclass reference-engine (audio-engine) (waveform amplitude))
```

Later slices add `(defgeneric codec-decode (codec source &key format))`, `codec-encode` and the conveniences `decode-audio` and `encode-audio` (AU2), and the `stack-audio/dsp` functions (AU3).

### Conditions

```text
audio-error (error)                         reason
├── audio-format-error (+ parse-error)      offset — restarts use-partial-data, use-value
│   └── wav-unsupported-encoding            format-tag, bits
├── audio-encode-error                      index
├── audio-mismatch-error                    index — restarts skip-input, use-value
├── audio-limit-exceeded                    limit, value — restart continue (renders)
└── audio-engine-error                      engine
    └── audio-backend-unavailable           no method, no native library, no SoundFont
audio-warning (warning)                     reason
├── samples-clipped                         count, peak
└── wav-format-warning                      offset (a partial frame)
```

AU2 signals `audio-format-error` for undecodable input, and lets compute-protocol's own conditions (`sandbox-denied`, `confinement-unavailable`) through with their restarts. Backends define no parallel tree.

---

## Slices

### AU0: the protocol (audio-protocol 0.1.0)

**Given:** package and exports, conditions and restart functions, `pcm-buffer`, `stem` and the time and gain helpers. **Stubbed:** `read-wav`, `write-wav`, `pan-gains`, `mix`, `loop-region`, `resample`, `smf-duration`, `render-frames`, the engine `:around` methods, the default `render-stems`, and the reference engine. **Fixtures:** 10 WAV files written by Python's `wave` and soundfile 0.12.1 from a committed generator: PCM16, PCM24 (one with an odd data size), float32 with `fact`/`PEAK`, LIST/INFO, and three WAVE_FORMAT_EXTENSIBLE. **Tests:**
- WAV:
  - every fixture read code for code, and the plain PCM ones written back byte for byte;
  - layouts, chunks before and after data, 23 malformed inputs with offsets, 13 unsupported encodings, every proper prefix, and the restarts;
  - a live cross-read where soundfile and `wave` read 36 files we wrote (skipped without `uv`).
- Mixing: the pan law, sums, gains, a mute and solo table, lengths, clip policies, mismatches.
- Loops and resampling: loop layouts and fades; the resampler against its formula, plus passband, stopband, DC and channels.
- The reference engine on a C major scale: onsets, zero crossings, Goertzel, exact values.
- Stems: each equals the render of its filtered SMF, and they sum to the mixdown.

### AU1: FluidSynth (audio-backend-fluidsynth 0.1.0)

**Stubbed:** `fluidsynth-engine` with `render-midi`, a one-pass `render-stems` through audio groups, the SoundFont fetcher, and log capture. **Fixtures:** a tiny SF2 the suite writes itself (one sine sample, one melodic preset and a drum preset), and the SC4 rehearsal SMFs. **Tests:**
- `render-frames` lengths.
- Onsets and pitches of the scale SMF, which must agree with the reference engine within an envelope tolerance.
- One-pass stems equal the default filtered-SMF stems within float tolerance.
- A missing SoundFont or library → `audio-backend-unavailable`.
- No float trap on any target, and no thread left behind.
- An opt-in FluidR3_GM listening render (nightly, cached by SHA-256).

### AU2: decoding (audio-backend-ffmpeg 0.1.0)

**Stubbed:** `codec-decode` / `codec-encode` running ffmpeg in a container or confined on the host, with `-nostdin`, network off, and input and output files in a private work directory. ffmpeg writes a seekable WAV that `read-wav` reads. Also format probing, and limits on duration, size and channels. **Tests:**
- Decoding of short MP3, M4A/AAC, Opus and WebM files that ffmpeg made from our own WAVs, within a tolerance.
- Hostile inputs (truncated, a wrong extension, huge declared durations) → `audio-format-error` or `audio-limit-exceeded`, never a hang.
- No network: the sandbox's own denial case.
- Skipped where no container runtime or confinement backend is available.

### AU3: DSP for transcription (audio-protocol 0.2.0)

**Stubbed:** `stack-audio/dsp`: FFT and real FFT (radix 2), windows, framing, STFT, RMS, peak and `normalize`. **Tests:**
- FFT against a direct DFT, and Parseval's theorem.
- Window sums, and the frame count rule.
- STFT peaks of the reference engine's notes.
- A 44.1 → 16 kHz → pYIN-ready pipeline over a rendered melody.

### Later, optional: WORLD and Signalsmith (AU4, AU5)

`analyze-voice` (f0, spectral envelope, aperiodicity) and `resynthesize` through WORLD (modified BSD, CFFI). `pitch-shift` and `time-stretch` through Signalsmith Stretch (MIT, header-only C++ behind a C shim). Same native pattern as AU1. Both start only when a consumer asks, and each gets its own feasibility note first.

---

## AU1 feasibility: libfluidsynth over CFFI

Checked 2026-11-24 against FluidSynth **v2.6.3** (2026-11-22, LGPL-2.1, library soname 3). Probe builds were throwaway work in a scratch directory; nothing was committed.

**Verdict: feasible as a zig-built overlay on all four targets, with no system library.**

**Build.** GLib is gone: 2.5.0 added `osal=cpp11` and 2.6.0 removed GLib and libinstpatch (#1799), so a minimal build needs only C and C++ compilers, threads, libm and the header-only gcem (Apache-2.0). FindGCEM downloads it at configure time from a pinned commit and hash, so vendor it for offline builds. The CMake probe used:

```text
-DBUILD_SHARED_LIBS=1 -Dosal=cpp11 -DCMAKE_BUILD_TYPE=Release
-Denable-{alsa,aufile,dbus,ipv6,jack,ladspa,libsndfile,midishare,network,oss,dsound,wasapi,
          waveout,winmidi,sdl3,pulseaudio,pipewire,readline,openmp,threads,signalsmith,
          systemd,coreaudio,coremidi,framework,native-dls}=0
CC/CXX = zig cc / zig c++ -target <triple>   (zig 0.17.1, the version the stb natives use)
```

| Target | zig triple | Result | Runtime dependencies |
|--------|------------|--------|----------------------|
| darwin-arm64 | `aarch64-macos` | `libfluidsynth.3.6.3.dylib`, 0.95 MB | `libSystem` only |
| linux-amd64 | `x86_64-linux-gnu.2.31` | `libfluidsynth.so.3.6.3` | libc, libm, libpthread, libdl; GLIBC_2.29 at most |
| linux-arm64 | `aarch64-linux-gnu.2.31` | `libfluidsynth.so.3.6.3` | the same; GLIBC_2.29 at most |
| windows-amd64 | `x86_64-windows-gnu` | `libfluidsynth-3.dll`, 392 exports | KERNEL32 and the UCRT (`api-ms-win-crt-*`) |

- **libc++ is linked statically** by zig, so add the libc++ licence (Apache-2.0 with LLVM exception) to the NOTICE next to LGPL-2.1 and gcem's.
- **Windows needs one wrapper.** CMake's MinGW rules archive the version resource into `objects.a`, and a `.res` file in an archive is "unknown file type" to lld-link. Use `CMAKE_RC_COMPILER` = `zig rc /:output-format coff /:target x64`, which emits a COFF object. Nothing else was patched.
- **No system library is needed.** A system library would be allowed by the policy (dynamic, overlay plus NOTICE), but today's distributions lag: Ubuntu 22.04 ships 2.2.5 and 24.04 ships 2.3.4, both GLib-era. Homebrew and MSYS2 ship 2.6.3. A pinned zig build gives one version everywhere.
- **The build follows image-backend-stb:** a `scripts/build-fluidsynth.sh` per target, the reusable natives workflow, and `lib/<os>-<arch>/`. FluidSynth itself is fetched by tag and SHA-256, never vendored.

**C API** (`include/fluidsynth/*.h`):
- Settings: `new_fluid_settings`, then `fluid_settings_setnum` / `setint` / `setstr` for `synth.sample-rate`, `synth.gain` (default 0.2), `synth.audio-groups`, `synth.audio-channels`, `synth.effects-groups`, `synth.reverb.active`, `synth.chorus.active`, `synth.cpu-cores` (keep 1) and `player.timing-source` (`sample`, the default).
- Synth: `new_fluid_synth`, `fluid_synth_sfload (synth, path, reset)` → a SoundFont id, or −1 (→ `audio-backend-unavailable`).
- Player: `new_fluid_player`, `fluid_player_add_mem` (the SMF bytes from `write-smf`, so no temporary file), `fluid_player_play`, and `fluid_player_get_status` (READY 0, PLAYING 1, STOPPING 2, DONE 3). Never call `fluid_player_join` with the sample timer: it waits for a render that only the caller performs.
- Render: `int fluid_synth_process (synth, len, nfx, float *fx[], nout, float *out[])`, called in 64-frame blocks while the player is PLAYING. Out buffers are **added to**, so zero them each block. MIDI channel c goes to stereo pair c mod `audio-groups`, so with 16 groups one pass yields the 16 channel stems. Point each group's 4 fx buffers at its own pair to keep reverb and chorus per stem. `fluid_synth_write_float` writes pair 0 only.
- Not used: `new_fluid_file_renderer` (raw s16 only without libsndfile, and it can't split stems).
- Logs: `fluid_set_log_function (level, fn, data)` per level. The probe printed "Ignoring unrecognized meta event" warnings to stderr, so AU1 routes them into Lisp warnings (or drops them) through a CFFI callback. The table is process-global and unlocked: set it once, at load.
- Teardown: `delete_fluid_player`, `delete_fluid_synth`, `delete_fluid_settings`, in that order.
- Length: the player keeps PLAYING until no voice sounds, plus a 2 s grace, so it renders the tails. AU1 then cuts or pads to `render-frames`, which the protocol requires.
- Mapping by-track stems onto groups needs one channel per track, which score-backend-midi gives. Other SMFs fall back to the default filtered render.

**Threads.**
- With `synth.cpu-cores` 1 (the default), `enable-threads=0` and the sample timer, every callback, logging included, runs on the calling thread. The probe confirmed it: one SBCL thread after rendering.
- `cpu-cores` N > 1 would start N−1 mixer threads. Dynamic sample loading starts none.
- `fluid_synth_sfunload` can start a 100 ms timer thread when a loader blocks the unload, so unload only at engine teardown.
- `synth.threadsafe-api` (default 1) is a recursive mutex. It is harmless, but one engine object should still render on one thread at a time; the backend holds its own lock.

**Float traps.**
- FluidSynth sets no FTZ/DAZ or MXCSR. Its reverbs add a 1e-8 DC offset and its IIR filters flush history below 1e-20 against denormals. Upstream CI runs `make check` with `enable-trap-on-fpe` (divide-by-zero, overflow and invalid unmasked, the set SBCL traps) on Linux x64 and arm64.
- The probe drove the darwin-arm64 build from SBCL 2.6.9 through `sb-alien` with **the default traps on**: midi-protocol's `type1-ensemble.mid` fixture (9.9 s rendered, grace included), reverb and chorus on, 16 audio groups. No trap fired, and the rendered energy per group matched a run with every trap masked, exactly. Energy appeared in groups 1, 2 and 10 only, the channels the fixture plays notes on.
- Known trap issues: 2.6.0 added a divide-by-zero in interpolation at low sample rates (fixed in 2.6.3, #1917), and an OS/2 x87 NaN in the IIR filter was papered over with fast-math (#1574).
- **Decision:** wrap every rendering foreign call in `sb-int:with-float-traps-masked (:overflow :invalid :divide-by-zero :inexact)`, as image-backend-stb does around its resize, and keep the trap-free run as a test on every target.

**SoundFont distribution.**

| Bank | License | Size | Source and pin |
|------|---------|------|----------------|
| FluidR3_GM.sf2 (default) | MIT (Debian `fluid-soundfont` copyright: Frank Wen, Toby Smithe) | 148,398,306 bytes | `fluid-soundfont_3.1.orig.tar.gz` from the Debian pool: 134,835,922 bytes, SHA-256 `2621acaa1c78e4abdb24bdd163230cc577e61276936d6aa6e3180582142f0343` (checked against the `.dsc`). The `.sf2` inside: SHA-256 `74594e8f4250680adf590507a306655a299935343583256f3b722c48a1bc1cb0` (recorded 2026-11-24; AU1 re-checks it). snapshot.debian.org is the fallback URL. |
| GeneralUser GS 2.0.3 (opt-in) | Custom, permissive (use, modify and repackage; no attribution clause); sample provenance not guaranteed by the author | 32,319,396 bytes | Its GitHub repository at a pinned commit (meant for automated packaging; the author asks that his site's download links not be hot-linked) |
| The test SF2 | MIT (written by the suite) | a few KB | Generated |
| TimGM6mb | GPL-2 | — | **Rejected** |
| VintageDreamsWaves-v2 (FluidSynth's test bank) | Freeware, no modification | — | **Rejected** (the probe used it locally only) |

The fetcher downloads to the user cache directory, checks SHA-256 before first use, and never ships a bank inside an OCI layer. It goes through the stack's HTTP client (`http-backend-async`) and pathlib, with restarts `use-value` (a local path) and `retry`. A bank the user names (`:soundfont`) is used as given.

**Risks to watch in AU1.**
- zig's libc++ `std::thread` and `std::filesystem` on windows-gnu compiled, but only the darwin build was run. The CI matrix must render on all four targets.
- Without libsndfile, SF3 (Vorbis) banks are refused. That is fine, since FluidR3_GM is SF2.
- Each FluidSynth minor bump re-checks the trap-free test and the export list.

---

## Progress

| Slice | Package | State |
|-------|---------|-------|
| AU0 | audio-protocol 0.1.0 | **contract**: [audio-protocol#1](https://github.com/egao1980/audio-protocol/pull/1) (draft). On the stubs, 357 tests: 344 fail, 13 pass (the given model). An independent reference implementation passes all 1000 assertions. |
| AU1 | audio-backend-fluidsynth | feasibility checked (above); repo not created |
| AU2, AU3 | — | planned |

### Decisions made in the AU0 contract

| Decision | Choice |
|----------|--------|
| **Codes scale by 2^(bits−1) both ways** | libsndfile writes with 32767; the live test compares codes and never asks libsndfile to convert |
| **float32 files are written WAVEFORMATEX-style** | An 18-byte fmt chunk plus `fact`. libsndfile writes 16 bytes plus `PEAK`, so float fixtures compare by value |
| **No extensible output** | Extensible fmt chunks are read, never written. More than 2 channels are written with tag 1, which `wave`, libsndfile and ffmpeg all read |
| **Resampling moved into AU0** | One documented quality. The outline had it in the DSP module |
| **The engine protocol is generic functions with `:around` checks** | Instead of the outline's `synth-render-midi` with a `stems` flag; stems have their own generic function and a default |

### Follow-ups

- [binary-protocol#3](https://github.com/egao1980/binary-protocol/issues/3): 24-bit integers, used by PCM24 (and midi-protocol's tempo).
- [binary-protocol#4](https://github.com/egao1980/binary-protocol/issues/4): `unpack-from` scans the whole buffer per call, so the WAV codec unpacks fresh blocks.

---

## Open questions

- Opus/Ogg encoding for downloads: through ffmpeg (sandbox), or a libopus overlay?
- Stems at several tempos: re-render with FluidSynth or `time-stretch`, decided by measured quality.
- Whether AU1's per-stem reverb (16 effects groups) is worth its cost over one shared reverb on the mixdown.
- Quality limits of resynthesis over large shifts (more than an octave), to be measured with listening tests (AU4).

## Non-goals

Real-time audio I/O, device ports, streaming, plugin hosting (LV2/VST), DAW-style editing, speech recognition, mastering-grade sample-rate conversion.
